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
