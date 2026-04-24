defmodule Comcent.Call.LiveCalls do
  @moduledoc """
  Cross-node projection of in-progress calls. Written from `Comcent.Call` on
  answer/end; read by the dashboard controller and the live-calls channel.

  This is the ONLY place the call subsystem still touches Redis: it's a
  projection for the web app, not authoritative call state.
  """

  require Logger
  alias Comcent.RedisClient

  @ttl_seconds 3600

  def broadcast(subdomain, action, call_data) do
    case action do
      "call_started" -> store(subdomain, call_data)
      "call_ended" -> remove(subdomain, call_data.call_story_id)
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

  def list(nil) do
    Logger.warning("Cannot get live calls from Redis: subdomain is nil")
    []
  end

  def list(subdomain) do
    case RedisClient.get(key(subdomain)) do
      {:ok, nil} ->
        []

      {:ok, json} ->
        case Jason.decode(json, keys: :atoms) do
          {:ok, calls} ->
            calls

          {:error, reason} ->
            Logger.error("Error decoding live calls JSON: #{inspect(reason)}")
            []
        end

      {:error, reason} ->
        Logger.error("Error getting live calls from Redis: #{inspect(reason)}")
        []
    end
  end

  defp store(nil, _), do: :ok

  defp store(subdomain, call_data) do
    updated =
      list(subdomain)
      |> Enum.reject(&(&1.call_story_id == call_data.call_story_id))
      |> Enum.concat([call_data])

    with {:ok, encoded} <- Jason.encode(updated) do
      RedisClient.setex(key(subdomain), encoded, @ttl_seconds)
    else
      reason ->
        Logger.error("Error storing live calls in Redis: #{inspect(reason)}")
    end
  end

  defp remove(nil, _), do: :ok

  defp remove(subdomain, call_story_id) do
    updated = Enum.reject(list(subdomain), &(&1.call_story_id == call_story_id))

    if Enum.empty?(updated) do
      RedisClient.del(key(subdomain))
    else
      with {:ok, encoded} <- Jason.encode(updated) do
        RedisClient.setex(key(subdomain), encoded, @ttl_seconds)
      else
        reason -> Logger.error("Error removing live call from Redis: #{inspect(reason)}")
      end
    end
  end

  defp key(subdomain), do: "live_calls:#{subdomain}"
end
