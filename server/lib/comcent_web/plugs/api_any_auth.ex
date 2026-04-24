defmodule ComcentWeb.Plugs.ApiAnyAuth do
  import Plug.Conn
  require Logger
  import Ecto.Query
  alias Comcent.Auth

  def init(opts), do: opts

  def call(conn, _opts) do
    subdomain = conn.path_params["subdomain"]

    case authenticate_request(conn) do
      {:ok, claims_user} ->
        member = get_member(claims_user["email"] || claims_user[:email])

        if member do
          conn
          |> assign(:current_user, member)
          |> assign(:current_claims_user, claims_user)
          |> assign(:current_member, member)
          |> assign(:subdomain, subdomain)
        else
          unauthorized(conn)
        end

      {:error, reason} ->
        Logger.error("Authentication failed: #{inspect(reason)}")
        unauthorized(conn)
    end
  end

  defp authenticate_request(conn) do
    case get_req_header(conn, "authorization") do
      ["Bearer " <> token] ->
        Auth.verify_any_token(token)

      _ ->
        conn = Plug.Conn.fetch_cookies(conn)

        case Auth.get_cookie(conn, "idToken") do
          nil -> {:error, :no_cookie}
          token -> Auth.verify_any_token(token)
        end
    end
  end

  defp get_member(email) when is_binary(email) do
    query =
      from(u in Comcent.Schemas.User,
        where: u.email == ^email,
        select: u
      )

    Comcent.Repo.one(query)
  end

  defp get_member(_), do: nil

  defp unauthorized(conn) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(401, "{\"error\":\"Unauthorized\"}")
    |> halt()
  end
end
