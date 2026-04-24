defmodule ComcentWeb.Internal.MemberController do
  use ComcentWeb, :controller
  require Logger

  alias Comcent.Repo.OrgMember

  def update_presence(
        conn,
        %{"subdomain" => subdomain, "action" => action, "username" => username} = params
      ) do
    Logger.info(
      "Received POST request to /internal/user/presence with params: #{inspect(params)}"
    )

    case OrgMember.get_user_id_by_username_and_subdomain(username, subdomain) do
      nil ->
        Logger.error("User not found")

        conn
        |> put_status(:not_found)
        |> text("User not found")

      user_id ->
        case action do
          "unregistered" -> OrgMember.update_member_presence(subdomain, user_id, "Logged Out")
          _ -> OrgMember.revert_member_presence_from_logged_out(subdomain, username)
        end

        conn
        |> put_status(:ok)
        |> text("Presence updated")
    end
  end
end
