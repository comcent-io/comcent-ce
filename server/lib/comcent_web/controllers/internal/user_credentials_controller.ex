defmodule ComcentWeb.Internal.UserCredentialsController do
  use ComcentWeb, :controller
  require Logger

  def create(conn, %{"domain" => domain, "username" => username} = params) do
    Logger.info("Received POST request to /internal/user/credentials")
    Logger.info("params: #{inspect(params)}")

    # Extract subdomain from domain
    sip_user_root_domain = Application.fetch_env!(:comcent, :sip_user_root_domain)
    [subdomain | _] = String.split(domain, ".#{sip_user_root_domain}")

    # Find the OrgMember based on username and org subdomain
    case find_org_member(subdomain, username) do
      %{sip_password: sip_password} when not is_nil(sip_password) ->
        conn
        |> put_status(:ok)
        |> json(%{p: sip_password})

      _ ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "User not found"})
    end
  end

  def create(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "Missing required parameters: domain and username"})
  end

  defp find_org_member(subdomain, username) do
    import Ecto.Query

    query =
      from(m in "org_members",
        join: o in "orgs",
        on: m.org_id == o.id,
        where: m.username == ^username and o.subdomain == ^subdomain,
        select: %{
          user_id: m.user_id,
          org_id: m.org_id,
          number_id: m.number_id,
          role: m.role,
          username: m.username,
          sip_password: m.sip_password,
          extension_number: m.extension_number,
          presence: m.presence
        }
      )

    Comcent.Repo.one(query)
  end
end
