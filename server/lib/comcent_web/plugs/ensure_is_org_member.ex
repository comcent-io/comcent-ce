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
        not_org_member(conn)

      user ->
        assign(conn, :current_user, user)
    end
  end

  # This is called from SvelteKit's SSR `fetch`, which auto-follows redirects
  # server-to-server, so it can't be a browser-facing `redirect(to: "/org")`
  # here - that gets resolved against the API host and 404s. Return a
  # structured error and let the frontend decide to navigate the browser.
  defp not_org_member(conn) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(404, ~s({"error":"not_org_member"}))
    |> halt()
  end
end
