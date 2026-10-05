defmodule ComcentWeb.SipTrunkController do
  use ComcentWeb, :controller
  require Logger

  alias Comcent.Repo
  alias Comcent.Repo.{SipTrunk, Org}
  alias Comcent.Schemas.SipTrunk, as: SipTrunkSchema

  def get_sip_trunks(conn, _params) do
    subdomain = conn.assigns[:subdomain]
    Logger.info("Getting sip trunks for org #{subdomain}")
    sip_trunks = SipTrunk.get_all_by_org(subdomain)
    json(conn, %{sip_trunks: sip_trunks})
  end

  # The addresses a customer configures on their carrier's side of a trunk.
  # They come from this deployment's configuration because they differ per
  # install; a value that isn't configured comes back as nil so the page can
  # leave it out instead of showing an address that would get calls rejected.
  def get_settings(conn, _params) do
    json(conn, %{
      public_ip: present(Application.get_env(:comcent, :sbc)[:public_ip]),
      sip_host: present(Application.get_env(:comcent, :provisioning)[:sbc_sip_fqdn])
    })
  end

  def create(conn, params) do
    subdomain = conn.assigns[:subdomain]
    Logger.info("Creating sip trunk for org #{subdomain}")

    case Org.get_org_by_subdomain(subdomain) do
      nil ->
        conn |> put_status(:not_found) |> json(%{error: "Organization not found"})

      org ->
        attrs = %{
          "name" => params["name"],
          "outbound_contact" => params["outbound_contact"],
          "inbound_ips" => params["inbound_ips"],
          "outbound_username" => params["outbound_username"],
          "outbound_password" => params["outbound_password"],
          "org_id" => org.id
        }

        new_trunk = %SipTrunkSchema{id: Ecto.UUID.generate()}

        case Repo.insert(SipTrunkSchema.changeset(new_trunk, attrs)) do
          {:ok, sip_trunk} ->
            Logger.info("Sip trunk created successfully for org #{subdomain}")
            conn |> put_status(:ok) |> json(sip_trunk)

          {:error, changeset} ->
            Logger.error("Failed to create sip trunk: #{inspect(changeset.errors)}")

            conn
            |> put_status(:unprocessable_entity)
            |> json(%{error: format_errors(changeset)})
        end
    end
  end

  def update(conn, %{"id" => id} = params) do
    subdomain = conn.assigns[:subdomain]
    Logger.info("Updating sip trunk #{id} for org #{subdomain}")

    case SipTrunk.get_by_id(id, subdomain) do
      nil ->
        conn |> put_status(:not_found) |> json(%{error: "SipTrunk not found"})

      sip_trunk ->
        attrs =
          Map.take(params, [
            "name",
            "outbound_contact",
            "inbound_ips",
            "outbound_username",
            "outbound_password"
          ])

        case Repo.update(SipTrunkSchema.changeset(sip_trunk, attrs)) do
          {:ok, updated} ->
            Logger.info("Sip trunk #{id} updated successfully")
            conn |> put_status(:ok) |> json(updated)

          {:error, changeset} ->
            Logger.error("Failed to update sip trunk: #{inspect(changeset.errors)}")

            conn
            |> put_status(:unprocessable_entity)
            |> json(%{error: format_errors(changeset)})
        end
    end
  end

  def delete(conn, %{"id" => id}) do
    subdomain = conn.assigns[:subdomain]
    Logger.info("Deleting sip trunk #{id} for org #{subdomain}")

    case SipTrunk.get_by_id(id, subdomain) do
      nil ->
        conn |> put_status(:not_found) |> json(%{error: "SipTrunk not found"})

      %{provider_connection_id: connection_id} when not is_nil(connection_id) ->
        # This trunk mirrors a real SIP trunk in the customer's provider
        # account. Deleting the row here would leave that trunk in place, still
        # carrying their numbers, with nothing in Comcent pointing at it. The
        # connection is the thing to disconnect, and it lives on its own page.
        conn
        |> put_status(:conflict)
        |> json(%{
          error:
            "This SIP trunk is managed by a Twilio connection and cannot be deleted on its own.",
          detail:
            "Deleting it here would leave the real trunk in place in your Twilio account. Disconnect the Twilio connection instead, which restores your numbers to their original configuration.",
          provider_connection_id: connection_id
        })

      sip_trunk ->
        numbers = SipTrunk.get_numbers_for_trunk(id)

        if length(numbers) > 0 do
          number_values = Enum.map(numbers, & &1.number)

          conn
          |> put_status(:conflict)
          |> json(%{
            error:
              "Cannot delete #{sip_trunk.name} as it is used in numbers #{Enum.join(number_values, ", ")}"
          })
        else
          case Repo.delete(sip_trunk) do
            {:ok, _} ->
              Logger.info("Sip trunk #{id} deleted successfully")

              conn
              |> put_status(:ok)
              |> json(%{message: "Sip trunk with id #{id} deleted successfully"})

            {:error, changeset} ->
              Logger.error("Failed to delete sip trunk: #{inspect(changeset.errors)}")

              conn
              |> put_status(:internal_server_error)
              |> json(%{error: "Failed to delete sip trunk"})
          end
        end
    end
  end

  defp present(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp present(_), do: nil

  defp format_errors(changeset) do
    Enum.map(changeset.errors, fn {field, {message, _}} -> "#{field}: #{message}" end)
    |> Enum.join(", ")
  end
end
