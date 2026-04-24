defmodule ComcentWeb.OrgWebhookController do
  use ComcentWeb, :controller
  require Logger

  alias Comcent.Repo
  alias Comcent.Repo.{OrgWebhook, Org}
  alias Comcent.Schemas.OrgWebhook, as: OrgWebhookSchema

  def get_webhooks(conn, _params) do
    subdomain = conn.assigns[:subdomain]
    Logger.info("Getting webhooks for org #{subdomain}")
    webhooks = OrgWebhook.get_all_by_org(subdomain)
    json(conn, %{webhooks: webhooks})
  end

  def create(conn, params) do
    subdomain = conn.assigns[:subdomain]
    Logger.info("Creating webhook for org #{subdomain}")

    case Org.get_org_by_subdomain(subdomain) do
      nil ->
        conn |> put_status(:not_found) |> json(%{error: "Organization not found"})

      org ->
        events = build_events(params)
        auth_token = :crypto.strong_rand_bytes(64) |> Base.encode16(case: :lower)

        attrs = %{
          "webhook_url" => params["webhook_url"],
          "name" => params["name"],
          "events" => events,
          "auth_token" => auth_token,
          "org_id" => org.id
        }

        new_webhook = %OrgWebhookSchema{id: Ecto.UUID.generate()}

        case Repo.insert(OrgWebhookSchema.changeset(new_webhook, attrs)) do
          {:ok, webhook} ->
            Logger.info("Webhook created successfully for org #{subdomain}")
            conn |> put_status(:ok) |> json(webhook)

          {:error, changeset} ->
            Logger.error("Failed to create webhook: #{inspect(changeset.errors)}")

            conn
            |> put_status(:unprocessable_entity)
            |> json(%{error: format_errors(changeset)})
        end
    end
  end

  def update(conn, %{"id" => id} = params) do
    subdomain = conn.assigns[:subdomain]
    Logger.info("Updating webhook #{id} for org #{subdomain}")

    case OrgWebhook.get_by_id(id, subdomain) do
      nil ->
        conn |> put_status(:not_found) |> json(%{error: "Webhook not found"})

      webhook ->
        events = build_events(params)

        attrs = %{
          "webhook_url" => params["webhook_url"],
          "name" => params["name"],
          "events" => events
        }

        case Repo.update(OrgWebhookSchema.changeset(webhook, attrs)) do
          {:ok, updated} ->
            Logger.info("Webhook #{id} updated successfully")
            conn |> put_status(:ok) |> json(updated)

          {:error, changeset} ->
            Logger.error("Failed to update webhook: #{inspect(changeset.errors)}")

            conn
            |> put_status(:unprocessable_entity)
            |> json(%{error: format_errors(changeset)})
        end
    end
  end

  def delete(conn, %{"id" => id}) do
    subdomain = conn.assigns[:subdomain]
    Logger.info("Deleting webhook #{id} for org #{subdomain}")

    case OrgWebhook.get_by_id(id, subdomain) do
      nil ->
        conn |> put_status(:not_found) |> json(%{error: "Webhook not found"})

      webhook ->
        case Repo.delete(webhook) do
          {:ok, _} ->
            Logger.info("Webhook #{id} deleted successfully")

            conn
            |> put_status(:ok)
            |> json(%{message: "Webhook with id #{id} deleted successfully"})

          {:error, changeset} ->
            Logger.error("Failed to delete webhook: #{inspect(changeset.errors)}")

            conn
            |> put_status(:internal_server_error)
            |> json(%{error: "Failed to delete webhook"})
        end
    end
  end

  defp build_events(params) do
    []
    |> maybe_add_event(params["call_update"] == true, "CALL_UPDATE")
    |> maybe_add_event(params["presence_update"] == true, "PRESENCE_UPDATE")
  end

  defp maybe_add_event(events, true, event), do: events ++ [event]
  defp maybe_add_event(events, false, _event), do: events

  defp format_errors(changeset) do
    Enum.map(changeset.errors, fn {_field, {message, _}} -> message end)
    |> Enum.join(", ")
  end
end
