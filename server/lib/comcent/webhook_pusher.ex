defmodule Comcent.WebhookPusher do
  @moduledoc """
  Module for pushing webhook notifications to configured endpoints.

  Each webhook stores the events its admin selected in the settings UI
  (`org_webhooks.events`). An event is only delivered to the webhooks that
  selected the matching setting. A webhook with no events stored (a `NULL` or
  empty column, which predates the "select at least one event" validation)
  keeps receiving every event, as it always did.
  """
  require Logger

  @new_call_story "NEW_CALL_STORY"

  # Maps each event type we send to the settings-UI event names that subscribe
  # to it. "Call Update Event" (CALL_UPDATE) is the only call-related choice
  # the UI offers, so it is the subscription for NEW_CALL_STORY.
  # PRESENCE_UPDATE is offered by the UI but not emitted yet.
  @subscriptions %{
    @new_call_story => ["CALL_UPDATE"]
  }

  @doc """
  Pushes a webhook notification for a new call story to every webhook of the
  org that is subscribed to it.
  """
  def push_to_webhook(call_story, vcon) do
    webhooks =
      (call_story.org.webhooks || [])
      |> Enum.filter(&subscribed?(&1, @new_call_story))

    if Enum.empty?(webhooks) do
      Logger.info(
        "No webhooks subscribed to #{@new_call_story} for subdomain #{call_story.org.subdomain}"
      )

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

  @doc """
  Whether `webhook` should receive events of `event_type`.
  """
  def subscribed?(%{events: events}, _event_type) when events in [nil, []], do: true

  def subscribed?(%{events: events}, event_type) when is_list(events) do
    subscribing_events = Map.get(@subscriptions, event_type, [event_type])
    Enum.any?(events, &(&1 in subscribing_events))
  end

  defp push_to_single_webhook(webhook, vcon) do
    headers = [
      {"Content-Type", "application/json"},
      {"X-Api-Token", webhook.auth_token}
    ]

    body = %{
      "type" => @new_call_story,
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
