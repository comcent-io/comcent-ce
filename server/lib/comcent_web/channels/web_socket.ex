defmodule ComcentWeb.WebSocket do
  use Phoenix.Socket
  alias Comcent.Repo.OrgMember

  ## Channels
  channel "presence:*", ComcentWeb.PresenceChannel
  channel "compliance:*", ComcentWeb.ComplianceChannel
  channel "queue_dashboard:*", ComcentWeb.QueueDashboardChannel
  channel "live_calls:*", ComcentWeb.LiveCallsChannel

  @impl true
  def connect(%{"token" => token, "subdomain" => subdomain}, socket, _connect_info) do
    case Comcent.Auth.authenticate_with_jwt(token) do
      {:ok, user} ->
        case OrgMember.get_member_by_email_and_subdomain(user.email, subdomain) do
          nil ->
            {:error, :unauthorized}

          member ->
            socket =
              socket
              |> assign(:current_user, user)
              |> assign(:subdomain, subdomain)
              |> assign(:current_member, member)

            {:ok, socket}
        end

      error ->
        {:error, error}
    end
  end

  @impl true
  def id(_socket), do: nil
end
