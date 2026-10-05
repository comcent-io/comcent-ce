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
  import Ecto.Query

  alias Comcent.{Clock, Repo}
  alias Comcent.Repo.Org, as: OrgRepo
  alias Comcent.Schemas.OrgMember

  @new_call_story "NEW_CALL_STORY"
  @presence_update "PRESENCE_UPDATE"

  # Maps each event type we send to the settings-UI event names that subscribe
  # to it. "Call Update Event" (CALL_UPDATE) is the only call-related choice
  # the UI offers, so it is the subscription for NEW_CALL_STORY.
  @subscriptions %{
    @new_call_story => ["CALL_UPDATE"],
    @presence_update => ["PRESENCE_UPDATE"]
  }

  @doc """
  Pushes a webhook notification for a new call story to every webhook of the
  org that is subscribed to it.
  """
  def push_to_webhook(call_story, vcon) do
    deliver(call_story.org, @new_call_story, vcon)
  end

  @doc """
  Sends a PRESENCE_UPDATE for a member whose presence just changed, without
  making the caller wait. Nothing is sent when the presence didn't actually
  change. (`config :comcent, :webhook_mode, :inline` runs it in the caller,
  for tests.)
  """
  def after_presence_change(subdomain, user_id, previous_presence, presence)

  def after_presence_change(_subdomain, _user_id, same, same), do: :ok

  def after_presence_change(subdomain, user_id, previous_presence, presence) do
    args = [subdomain, user_id, previous_presence, presence, Clock.now()]

    case Application.get_env(:comcent, :webhook_mode, :async) do
      :inline ->
        apply(__MODULE__, :push_presence_update, args)

      :async ->
        Task.Supervisor.start_child(
          Comcent.TaskSupervisor,
          __MODULE__,
          :push_presence_update,
          args
        )
    end

    :ok
  end

  @doc """
  Pushes a PRESENCE_UPDATE for the member `user_id` of the org `subdomain`
  to every webhook of the org that is subscribed to it.
  """
  def push_presence_update(subdomain, user_id, previous_presence, presence, changed_at) do
    case OrgRepo.get_org_by_subdomain(subdomain) do
      nil ->
        Logger.error("Org not found for subdomain #{subdomain}, presence update not sent")
        :error

      org ->
        member =
          Repo.one!(
            from(m in OrgMember,
              where: m.org_id == ^org.id and m.user_id == ^user_id,
              preload: :user
            )
          )

        deliver(Repo.preload(org, :webhooks), @presence_update, %{
          subdomain: subdomain,
          user_id: user_id,
          username: member.username,
          email: member.user.email,
          name: member.user.name,
          presence: presence,
          previous_presence: previous_presence,
          changed_at: changed_at
        })
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

  # Posts `data` as an `event_type` event to every webhook of `org` that is
  # subscribed to it.
  defp deliver(org, event_type, data) do
    webhooks =
      (org.webhooks || [])
      |> Enum.filter(&subscribed?(&1, event_type))

    if Enum.empty?(webhooks) do
      Logger.info("No webhooks subscribed to #{event_type} for subdomain #{org.subdomain}")

      :ok
    else
      body = %{"type" => event_type, "data" => data}

      webhooks
      |> Enum.map(fn webhook ->
        Task.async(fn ->
          push_to_single_webhook(webhook, body)
        end)
      end)
      |> Enum.map(&Task.await(&1, 30_000))
    end
  end

  defp push_to_single_webhook(webhook, body) do
    headers = [
      {"Content-Type", "application/json"},
      {"X-Api-Token", webhook.auth_token}
    ]

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
