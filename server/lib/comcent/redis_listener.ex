defmodule Comcent.RedisListener do
  @moduledoc """
  Module to manage event processing in the system.
  """
  alias Comcent.{RedisClient, KamailioRPC}
  require Logger

  use GenServer

  def start_link(_) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @impl true
  def init(_) do
    Logger.info("Starting events listener")
    listen_for_expired_keys_in_redis()
    {:ok, %{}}
  end

  @impl true
  def handle_info({:redix_pubsub, _pid, _ref, :subscribed, %{channel: channel}}, state) do
    Logger.info("Successfully subscribed to Redis channel: #{channel}")
    {:noreply, state}
  end

  @impl true
  def handle_info(
        {:redix_pubsub, _pid, _ref, :message, %{channel: "__keyevent@0__:expired", payload: key}},
        state
      ) do
    handle_expired_key(key)
    {:noreply, state}
  end

  def handle_info(msg, state) do
    Logger.info("Received unexpected message in handle_info/2: #{inspect(msg)}")
    {:noreply, state}
  end

  defp listen_for_expired_keys_in_redis do
    case RedisClient.listen_for_expired_keys(&handle_expired_key/1) do
      {:ok, _} ->
        nil

      {:error, reason} ->
        Logger.error("Failed to setup key expiration listener: #{inspect(reason)}")
        nil
    end
  end

  defp handle_expired_key(key) do
    if String.starts_with?(key, "fs.") do
      Logger.info("Key #{key} has expired")
      ip_address = key |> String.split(".") |> Enum.drop(1) |> Enum.join(".")
      KamailioRPC.send_rpc_request_to_remove_ip_address(ip_address)
    end
  end
end
