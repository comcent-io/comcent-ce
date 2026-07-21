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
        not_org_member(conn)

      user ->
        # Find the org member that matches the subdomain
        org_member =
          Enum.find(user.org_members, fn member ->
            member.org.subdomain == subdomain
          end)

        case org_member do
          nil ->
            not_org_member(conn)

          org_member ->
            if org_member.role != role do
              insufficient_role(conn)
            else
              assign(conn, :current_user, user)
            end
        end
    end
  end

  # These are called from SvelteKit's SSR `fetch`, which auto-follows
  # redirects server-to-server, so they can't be browser-facing
  # `redirect(to: ...)` here - that gets resolved against the API host and
  # 404s. Return a structured error and let the frontend decide to navigate
  # the browser.
  defp not_org_member(conn) do
    json_error(conn, 404, "not_org_member")
  end

  defp insufficient_role(conn) do
    json_error(conn, 403, "insufficient_role")
  end

  defp json_error(conn, status, error) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, ~s({"error":"#{error}"}))
    |> halt()
  end
end
