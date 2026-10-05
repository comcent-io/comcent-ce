defmodule ComcentWeb.ProviderConnectionController do
  @moduledoc """
  Provider connections and number import.

  Admin-only: a connection carries credentials to the customer's billing-bearing
  provider account, and importing a number rewrites configuration in it.

  Credentials are never echoed back. Responses carry a four-character hint so an
  admin can tell two keys apart when rotating, and nothing more.
  """

  use ComcentWeb, :controller
  require Logger

  alias Comcent.Repo.{Org, ProviderConnection}
  alias Comcent.Repo.ProviderConnection, as: ProviderConnectionRepo
  alias Comcent.{ProviderConnections, ProviderDisconnect, ProviderNumbers, Provisioning}

  def index(conn, _params) do
    subdomain = conn.assigns[:subdomain]

    connections =
      subdomain
      |> ProviderConnections.list_for_org()
      |> Enum.map(&ProviderConnections.to_public/1)

    json(conn, %{provider_connections: connections})
  end

  def create(conn, params) do
    subdomain = conn.assigns[:subdomain]

    case Org.get_org_by_subdomain(subdomain) do
      nil ->
        conn |> put_status(:not_found) |> json(%{error: "Organization not found"})

      org ->
        case ProviderConnections.connect(org, params) do
          {:ok, connection} ->
            Logger.info("Connected provider account for org #{subdomain}")
            conn |> put_status(:created) |> json(ProviderConnections.to_public(connection))

          {:error, reason} ->
            respond_error(conn, reason)
        end
    end
  end

  @doc """
  Replaces stored credentials. Validated against the provider before saving, so
  a bad rotation cannot leave the connection worse than it was.
  """
  def rotate(conn, %{"id" => id} = params) do
    with_connection(conn, id, fn connection ->
      case ProviderConnections.rotate_credentials(connection, params) do
        {:ok, updated} -> json(conn, ProviderConnections.to_public(updated))
        {:error, reason} -> respond_error(conn, reason)
      end
    end)
  end

  def verify(conn, %{"id" => id}) do
    with_credentialed_connection(conn, id, fn connection ->
      case ProviderConnections.verify(connection) do
        {:ok, updated} -> json(conn, ProviderConnections.to_public(updated))
        {:error, reason} -> respond_error(conn, reason)
      end
    end)
  end

  @doc """
  Numbers in the connected account, fetched live.

  No cached inventory: one call to the provider, always accurate. Entries are
  annotated with whether they can be imported and why not, so the UI does not
  re-derive that logic.
  """
  def available_numbers(conn, %{"id" => id}) do
    with_credentialed_connection(conn, id, fn connection ->
      case ProviderNumbers.list_available(connection) do
        {:ok, numbers} -> json(conn, %{numbers: numbers})
        {:error, reason} -> respond_error(conn, reason)
      end
    end)
  end

  @doc """
  Imports selected numbers.

  Each number succeeds or fails on its own — one bad number must not sink the
  batch — so this always returns 200 with a per-number result the UI can render
  against the rows the user selected.
  """
  def import_numbers(conn, %{"id" => id} = params) do
    with_credentialed_connection(conn, id, fn connection ->
      sids = params["provider_sids"] || []
      confirm? = params["confirm_trunk_move"] == true

      results =
        Enum.map(sids, fn sid ->
          # Import records the number and snapshots its pre-Comcent config;
          # provisioning is what actually makes it route. Both must happen or
          # the customer is left with a number we claim to own and no path for
          # calls to reach it.
          case Provisioning.import_and_provision(connection, sid, confirm_trunk_move: confirm?) do
            {:ok, provisioned} ->
              %{
                provider_sid: sid,
                ok: true,
                e164: provisioned.number.number,
                number_id: provisioned.number.id,
                routing: "active"
              }

            {:error, reason} ->
              %{provider_sid: sid, ok: false, error: error_message(reason)}
          end
        end)

      json(conn, %{results: results})
    end)
  end

  @doc """
  What disconnecting would affect. Shown before the confirmation so the customer
  decides with the facts rather than discovering them afterwards.
  """
  def disconnect_preview(conn, %{"id" => id}) do
    with_credentialed_connection(conn, id, fn connection ->
      json(conn, ProviderDisconnect.preview(connection))
    end)
  end

  @doc """
  Disconnects. `mode` must be given explicitly — "release" restores the
  provider-side configuration and removes our rows, "keep" leaves the provider
  alone and deactivates ours. These are different intentions and guessing which
  one the customer meant would be the wrong kind of helpful.
  """
  def delete(conn, %{"id" => id} = params) do
    with_connection(conn, id, fn connection ->
      case params["mode"] do
        # Handing the numbers back means changing them in Twilio, which needs a
        # key we no longer hold once the connection is unmanaged.
        "release" when connection.status == "unmanaged" ->
          conn
          |> put_status(:conflict)
          |> json(%{
            error: "This connection has no API key, so its numbers cannot be handed back.",
            detail:
              "Add a key first. The original configuration of each number is still on file, so they can be restored exactly."
          })

        "release" ->
          do_disconnect(conn, connection, :release)

        "keep" when connection.status == "unmanaged" ->
          conn
          |> put_status(:ok)
          |> json(%{mode: "keep", numbers: 0, restored: 0, failed: [], already_unmanaged: true})

        "keep" ->
          do_disconnect(conn, connection, :keep)

        _ ->
          conn
          |> put_status(:bad_request)
          |> json(%{
            error:
              "mode must be \"release\" (restore provider config and remove) or \"keep\" (deactivate only)"
          })
      end
    end)
  end

  @doc """
  Re-reads imported numbers from the provider and reports drift.

  Runs inside the fetch we are already doing, so detecting drift costs no extra
  provider call beyond reading the numbers we manage.
  """
  def refresh_numbers(conn, %{"id" => id}) do
    with_credentialed_connection(conn, id, fn connection ->
      results =
        connection.id
        |> ProviderConnectionRepo.get_numbers()
        |> Enum.map(fn pn ->
          case ProviderNumbers.refresh(connection, pn) do
            {:ok, :unchanged} -> %{e164: pn.e164, state: "ok"}
            {:ok, :missing} -> %{e164: pn.e164, state: "missing"}
            {:ok, {:drifted, fields, _}} -> %{e164: pn.e164, state: "drifted", fields: fields}
            {:error, reason} -> %{e164: pn.e164, state: "error", error: error_message(reason)}
          end
        end)

      json(conn, %{numbers: results})
    end)
  end

  # Always succeeds: individual restore failures are reported inside the summary
  # rather than aborting, because refusing to disconnect over one number that
  # cannot be restored would trap the customer in the connection they are
  # trying to leave.
  defp do_disconnect(conn, connection, mode) do
    {:ok, summary} = ProviderDisconnect.disconnect(connection, mode)
    json(conn, summary)
  end

  # --- helpers -------------------------------------------------------------

  defp with_connection(conn, id, fun) do
    case ProviderConnection.get_by_id(id, conn.assigns[:subdomain]) do
      nil -> conn |> put_status(:not_found) |> json(%{error: "Provider connection not found"})
      connection -> fun.(connection)
    end
  end

  # An "unmanaged" connection holds no credentials by design: the customer asked
  # us to give the API key back. Anything that has to call the provider must
  # refuse here rather than reach the HTTP client with a nil password, which
  # raises rather than returning an error. Hiding the buttons is not enough --
  # the routes are still there.
  defp with_credentialed_connection(conn, id, fun) do
    with_connection(conn, id, fn
      %{status: "unmanaged"} ->
        conn
        |> put_status(:conflict)
        |> json(%{
          error: "This connection has no API key.",
          detail:
            "You asked Comcent to stop managing this Twilio account, so its key was deleted. Add a key to manage it again. Your numbers keep routing either way."
        })

      connection ->
        fun.(connection)
    end)
  end

  defp respond_error(conn, reason) do
    conn |> put_status(status_for(reason)) |> json(%{error: error_message(reason)})
  end

  defp status_for({:invalid_credentials, _}), do: :unauthorized
  defp status_for({:forbidden, _}), do: :forbidden
  defp status_for({:not_found, _}), do: :not_found
  defp status_for({:rate_limited, _}), do: :too_many_requests
  defp status_for({:transport_error, _}), do: :bad_gateway
  defp status_for({:validation, _}), do: :bad_request
  defp status_for({:trunk_conflict, _}), do: :conflict
  defp status_for({:not_voice_capable, _}), do: :unprocessable_entity
  # Actionable by the customer (detach the campaign), so not a 500.
  defp status_for({:numbers_in_use, _}), do: :conflict
  defp status_for({:disconnect_failed, _}), do: :internal_server_error
  defp status_for(%Ecto.Changeset{}), do: :unprocessable_entity
  defp status_for(_), do: :unprocessable_entity

  defp error_message({:invalid_credentials, _}),
    do: "Those credentials were rejected by the provider. Check the API key SID and secret."

  defp error_message({:transport_error, _}),
    do: "Could not reach the provider. This is a network problem, not a credential problem."

  defp error_message({:twilio_error, code, message}), do: "Provider error #{code}: #{message}"
  defp error_message({_tag, message}) when is_binary(message), do: message

  defp error_message(%Ecto.Changeset{} = changeset) do
    changeset.errors
    |> Enum.map(fn {field, {message, _}} -> "#{field}: #{message}" end)
    |> Enum.join(", ")
  end

  defp error_message(other), do: inspect(other)
end
