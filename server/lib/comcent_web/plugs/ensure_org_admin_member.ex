defmodule ComcentWeb.Plugs.EnsureOrgAdminMember do
  import Plug.Conn
  require Logger
  alias Comcent.Repo.User

  def init(opts), do: opts

  def call(conn, opts) do
    role = Keyword.fetch!(opts, :role)
    subdomain = conn.assigns[:subdomain]
    current_user = conn.assigns[:current_user]

    case User.find_user_and_org(current_user.email, subdomain) do
      nil ->
        conn
        |> put_status(:see_other)
        |> Phoenix.Controller.redirect(to: "/org")
        |> halt()

      user ->
        # Find the org member that matches the subdomain
        org_member =
          Enum.find(user.org_members, fn member ->
            member.org.subdomain == subdomain
          end)

        case org_member do
          nil ->
            conn
            |> put_status(:see_other)
            |> Phoenix.Controller.redirect(to: "/org")
            |> halt()

          org_member ->
            if org_member.role != role do
              conn
              |> put_status(:see_other)
              |> Phoenix.Controller.redirect(to: "/app/#{subdomain}")
              |> halt()
            else
              assign(conn, :current_user, user)
            end
        end
    end
  end
end
