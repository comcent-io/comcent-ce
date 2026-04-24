defmodule ComcentWeb.Plugs.OrgApiKeyAuth do
  import Plug.Conn
  alias Comcent.Repo.OrgApiKey

  def init(opts), do: opts

  def call(conn, _opts) do
    subdomain = conn.path_params["subdomain"]

    case get_req_header(conn, "x-api-key") do
      [api_key] ->
        case OrgApiKey.get_by_api_key(api_key, subdomain) do
          nil ->
            unauthorized(conn)

          key ->
            conn
            |> assign(:org_api_key, key)
            |> assign(:subdomain, subdomain)
        end

      _ ->
        unauthorized(conn)
    end
  end

  defp unauthorized(conn) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(401, "{\"error\":\"Invalid API key\"}")
    |> halt()
  end
end
