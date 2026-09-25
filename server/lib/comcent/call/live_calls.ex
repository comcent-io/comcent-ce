defmodule Comcent.Call.LiveCalls do
  @moduledoc """
  The Live Calls dashboard: the rows it loads, and the real-time updates it
  receives on the org's `live_calls:<subdomain>` channel.

  Each row lives in the call's own `Comcent.CallSession.Registry` entry, so
  `list/1` is exactly the calls whose process is alive, across the cluster. A
  row can't outlive its call even if a hang-up path never broadcasts
  `call_ended`; the broadcasts are notifications for pages already open.

  `broadcast/3` with `call_started`/`call_ended` writes the caller's registry
  entry, so it must be called from inside the call process.
  """

  alias Comcent.CallSession.Registry

  def broadcast(subdomain, action, call_data) do
    case action do
      "call_started" -> store(subdomain, call_data)
      "call_ended" -> Registry.clear_live_call(call_data.call_story_id)
    end

    Phoenix.PubSub.broadcast(
      Comcent.PubSub,
      "live_calls:#{subdomain}",
      {:live_call_update,
       %{
         subdomain: subdomain,
         action: action,
         call_data: call_data
       }}
    )
  end

  def list(nil), do: []
  def list(subdomain), do: Registry.live_calls_for_subdomain(subdomain)

  defp store(nil, _), do: :ok

  defp store(subdomain, call_data) do
    Registry.put_live_call(call_data.call_story_id, subdomain, call_data)
  end
end
