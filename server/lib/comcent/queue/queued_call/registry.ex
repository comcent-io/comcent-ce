defmodule Comcent.Queue.QueuedCall.Registry do
  @moduledoc false

  @registry Comcent.Registry
  @supervisor Comcent.QueueDynamicSupervisor

  def via(call_id) do
    {:via, Horde.Registry, {@registry, {:queued_call, call_id}}}
  end

  def whereis(call_id) do
    case Horde.Registry.lookup(@registry, {:queued_call, call_id}) do
      [{pid, _}] -> pid
      [] -> nil
    end
  end

  def start_call(call_details) do
    case Horde.DynamicSupervisor.start_child(
           @supervisor,
           {Comcent.Queue.QueuedCall, call_details}
         ) do
      {:ok, pid} -> {:ok, pid}
      {:ok, pid, _} -> {:ok, pid}
      {:error, {:already_started, pid}} -> {:ok, pid}
      other -> other
    end
  end
end
