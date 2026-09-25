defmodule Comcent.CallSession.Registry do
  @moduledoc """
  Cluster-wide uniqueness for per-call GenServers. Backed by Horde so a call
  process lives on exactly one node and is reachable from anywhere via its
  `call_story_id`.
  """

  @registry Comcent.Registry
  @supervisor Comcent.DynamicSupervisor

  @doc """
  Returns a `:via` tuple that registers/locates a call process by id.
  """
  def via(call_story_id) do
    {:via, Horde.Registry, {@registry, {:call, call_story_id}}}
  end

  @doc """
  Finds an existing call pid, or returns nil.
  """
  def whereis(call_story_id) do
    case Horde.Registry.lookup(@registry, {:call, call_story_id}) do
      [{pid, _}] -> pid
      [] -> nil
    end
  end

  @doc """
  Publishes the row the Live Calls dashboard shows for this call, replacing
  the previous one (a transfer answers a new leg on the same call).

  Horde only lets a process rewrite its own registration value, so this must
  be called from inside the call process. The row
  lives only as long as that process does, so a call that dies without a
  `call_ended` can't leave a stale row behind.
  """
  def put_live_call(call_story_id, subdomain, live_call)
      when is_binary(call_story_id) and is_binary(subdomain) and is_map(live_call) do
    update(call_story_id, &Map.merge(&1, %{subdomain: subdomain, live_call: live_call}))
  end

  @doc """
  Takes the call off the Live Calls dashboard while its process lives on
  (e.g. between the answered leg hanging up and the call story closing).
  Called from inside the call process.
  """
  def clear_live_call(call_story_id) when is_binary(call_story_id) do
    update(call_story_id, &Map.delete(&1, :live_call))
  end

  @doc """
  The Live Calls dashboard rows of every call up for `subdomain`, across the
  cluster, oldest first.
  """
  def live_calls_for_subdomain(subdomain) when is_binary(subdomain) do
    @registry
    |> Horde.Registry.select([{{{:call, :_}, :_, :"$1"}, [], [:"$1"]}])
    |> Enum.flat_map(fn
      %{subdomain: ^subdomain, live_call: live_call} -> [live_call]
      _ -> []
    end)
    # start_at is nil if FreeSWITCH sent no usable timestamp; those sort first.
    |> Enum.sort_by(fn %{start_at: start_at} ->
      if start_at, do: DateTime.to_unix(start_at, :microsecond), else: 0
    end)
  end

  defp update(call_story_id, fun) do
    case Horde.Registry.update_value(@registry, {:call, call_story_id}, fn value ->
           fun.(value || %{})
         end) do
      :error -> :error
      {_new, _old} -> :ok
    end
  end

  @doc """
  Starts (or finds) the per-call process.
  """
  def start_call(call_story_id) when is_binary(call_story_id) do
    case Horde.DynamicSupervisor.start_child(
           @supervisor,
           {Comcent.CallSession, call_story_id}
         ) do
      {:ok, pid} -> {:ok, pid}
      {:ok, pid, _} -> {:ok, pid}
      {:error, {:already_started, pid}} -> {:ok, pid}
      other -> other
    end
  end
end
