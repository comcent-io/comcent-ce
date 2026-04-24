defmodule ComcentWeb.Plugs.EnsureIsOrgMember do
  import Plug.Conn
  require Logger
  alias Comcent.Repo.User

  def init(opts), do: opts

  def call(conn, _opts) do
    subdomain = conn.assigns[:subdomain]
    current_user = conn.assigns[:current_user]

    case User.find_user_and_org(current_user.email, subdomain) do
      nil ->
        conn
        |> put_status(:see_other)
        |> Phoenix.Controller.redirect(to: "/org")
        |> halt()

      user ->
        assign(conn, :current_user, user)
    end
  end
end
