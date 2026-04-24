defmodule Comcent.WebhookPusher do
  @moduledoc """
  Module for pushing webhook notifications to configured endpoints.
  """
  require Logger

  @doc """
  Pushes a webhook notification for a new call story to all configured webhooks.
  """
  def push_to_webhook(call_story, vcon) do
    webhooks = call_story.org.webhooks || []

    if Enum.empty?(webhooks) do
      Logger.info("No webhooks found for subdomain #{call_story.org.subdomain}")
      :ok
    else
      webhooks
      |> Enum.map(fn webhook ->
        Task.async(fn ->
          push_to_single_webhook(webhook, vcon)
        end)
      end)
      |> Enum.map(&Task.await(&1, 30_000))
    end
  end

  defp push_to_single_webhook(webhook, vcon) do
    headers = [
      {"Content-Type", "application/json"},
      {"X-Api-Token", webhook.auth_token}
    ]

    body = %{
      "type" => "NEW_CALL_STORY",
      "data" => vcon
    }

    case Jason.encode(body) do
      {:ok, encoded_body} ->
        case HTTPoison.post(webhook.webhook_url, encoded_body, headers) do
          {:ok, _response} ->
            :ok

          {:error, error} ->
            Logger.error("Error sending webhook #{webhook.webhook_url}: #{inspect(error)}")
            :error
        end

      {:error, error} ->
        Logger.error("Error encoding webhook body: #{inspect(error)}")
        :error
    end
  end
end
