defmodule ComcentWeb.Internal.MemberController do
  use ComcentWeb, :controller
  require Logger

  alias Comcent.Repo.OrgMember

  def update_presence(
        conn,
        %{"subdomain" => subdomain, "action" => action, "username" => username}
      ) do
    Logger.info("Presence update for #{username}@#{subdomain}: #{action}")

    case OrgMember.get_user_id_by_username_and_subdomain(username, subdomain) do
      nil ->
        Logger.error("User not found")

        conn
        |> put_status(:not_found)
        |> text("User not found")

      user_id ->
        case action do
          "unregistered" ->
            OrgMember.forget_presence_before_lapse(subdomain, user_id)
            OrgMember.update_member_presence(subdomain, user_id, "Logged Out")

          # The registration ran out without the client unregistering.
          "expired" ->
            OrgMember.log_out_until_registered(subdomain, user_id)

          _ ->
            with :not_lapsed <- OrgMember.restore_presence_after_lapse(subdomain, user_id) do
              OrgMember.revert_member_presence_from_logged_out(subdomain, username)
            end
        end

        conn
        |> put_status(:ok)
        |> text("Presence updated")
    end
  end
end
