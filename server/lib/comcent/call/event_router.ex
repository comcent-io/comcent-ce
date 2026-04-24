defmodule Comcent.Call.EventRouter do
  @moduledoc """
  Decodes a FreeSWITCH/RabbitMQ event payload, classifies it, and routes it to
  the right per-call process (or handles it inline if it has no call context).

  The RabbitMQ consumer calls `handle_payload/1` for every delivery. The router
  never blocks on the call process beyond a cast.
  """

  require Logger

  alias Comcent.CallSession
  alias Comcent.KamailioRPC
  alias Comcent.RedisClient

  @spec handle_payload(binary()) :: :ok | {:error, term()}
  def handle_payload(payload) when is_binary(payload) do
    case Jason.decode(payload) do
      {:ok, body} ->
        handle_event(body)

      {:error, reason} = err ->
        Logger.error("Error decoding RabbitMQ payload: #{inspect(reason)}")
        err
    end
  end

  @spec handle_event(map()) :: :ok
  def handle_event(%{"Event-Name" => "CUSTOM", "Event-Subclass" => "comcent::heartbeat"} = body) do
    handle_heartbeat(body)
  end

  def handle_event(body) do
    # Side-channel: when the customer (inbound-root) channel destroys, tell
    # the queue scheduler *right now* — not whenever CallSession drains
    # its mailbox. Under stress CallSession can be 5+ s behind, long
    # enough for another queue attempt to kick off against a customer
    # that's already gone. Firing from EventRouter avoids that lag.
    notify_queue_on_customer_destroy(body)

    case classify(body) do
      {:route, id} ->
        CallSession.dispatch(id, body)
        :ok

      {:route_and_start, id} ->
        CallSession.start_and_dispatch(id, body)
        :ok

      :ignore ->
        Logger.info("Ignoring event #{inspect(body["Event-Name"])}")
        :ok

      :unroutable ->
        Logger.info("Unroutable event #{inspect(body["Event-Name"])}; missing call_story_id")

        :ok
    end
  end

  defp notify_queue_on_customer_destroy(%{"Event-Name" => "CHANNEL_DESTROY"} = body) do
    if inbound_root?(body) do
      call_id = body["Unique-ID"]

      case Comcent.Queue.QueuedCall.snapshot(call_id) do
        {:ok, %{queue_id: queue_id, subdomain: subdomain}}
        when is_binary(queue_id) and is_binary(subdomain) ->
          Comcent.QueueManager.call_hung_up(
            subdomain,
            queue_id,
            call_id,
            date_from_unix(body["Event-Date-Timestamp"])
          )

        _ ->
          :ok
      end
    end

    :ok
  end

  defp notify_queue_on_customer_destroy(_body), do: :ok

  defp date_from_unix(nil), do: DateTime.utc_now()

  defp date_from_unix(timestamp) when is_binary(timestamp) do
    case Integer.parse(timestamp) do
      {n, _} -> date_from_unix(n)
      :error -> DateTime.utc_now()
    end
  end

  defp date_from_unix(timestamp) when is_integer(timestamp) do
    case DateTime.from_unix(div(timestamp, 1_000_000)) do
      {:ok, dt} -> dt
      _ -> DateTime.utc_now()
    end
  end

  # Only CHANNEL_CREATE can legitimately start a fresh call process — inbound
  # root, or an outbound leg that carries an explicit comcent context id.
  # Every other event routes to an existing process or is dropped.
  defp classify(%{"Event-Name" => "CHANNEL_CREATE"} = body) do
    call_story_id = body["variable_comcent_context_id"] || body["Channel-Call-UUID"]

    cond do
      not (is_binary(call_story_id) and call_story_id != "") ->
        :unroutable

      inbound_root?(body) or body["variable_comcent_context_id"] != nil ->
        {:route_and_start, call_story_id}

      true ->
        {:route, call_story_id}
    end
  end

  defp classify(%{"Event-Name" => event} = body)
       when event in [
              "CHANNEL_ANSWER",
              "CHANNEL_DESTROY",
              "CHANNEL_HOLD",
              "CHANNEL_UNHOLD",
              "RECORD_START",
              "RECORD_STOP"
            ] do
    call_story_id = body["variable_comcent_context_id"] || body["Channel-Call-UUID"]

    if is_binary(call_story_id) and call_story_id != "" do
      {:route, call_story_id}
    else
      :unroutable
    end
  end

  defp classify(
         %{"Event-Name" => "CUSTOM", "Event-Subclass" => "comcent::s3UploadCompleted"} = body
       ) do
    case body["Call-Story-Id"] do
      id when is_binary(id) and id != "" -> {:route, id}
      _ -> :unroutable
    end
  end

  defp classify(_), do: :ignore

  defp inbound_root?(body) do
    body["Unique-ID"] == body["Channel-Call-UUID"] and body["Call-Direction"] == "inbound"
  end

  # ---------------------------------------------------------------------------
  # Heartbeat (not call-scoped)
  # ---------------------------------------------------------------------------

  defp handle_heartbeat(body) do
    Logger.info("HEARTBEAT event received")

    ip_address = body["SIP-Bind-IP"]
    host = body["FreeSWITCH-Hostname"]
    time = body["Event-Date-GMT"]

    save_freeswitch_to_redis(ip_address, host, time)

    unless KamailioRPC.is_ip_address_in_dispatcher(ip_address) do
      KamailioRPC.send_rpc_request_to_add_ip_address(ip_address)
    end

    :ok
  end

  defp save_freeswitch_to_redis(ip_address, host, time) do
    key = "fs.#{ip_address}"
    value = %{ip_address: ip_address, host: host, time: time}

    with {:ok, encoded} <- Jason.encode(value),
         {:ok, _} <- RedisClient.setex(key, encoded, 50) do
      :ok
    else
      error ->
        Logger.error("Failed to save FreeSWITCH details to Redis: #{inspect(error)}")
        :ok
    end
  end
end
