defmodule ComcentWeb.Plugs.BasicAuth do
  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    if String.starts_with?(conn.request_path, "/internal-api/playback") ||
         conn.method == "OPTIONS" do
      conn
    else
      with ["Basic " <> encoded_credentials] <- get_req_header(conn, "authorization"),
           credentials = Base.decode64!(encoded_credentials),
           [username, password] <- String.split(credentials, ":") do
        check_credentials(conn, username, password)
      else
        _ -> unauthorized(conn)
      end
    end
  end

  defp check_credentials(conn, username, password) do
    if username == System.get_env("INTERNAL_API_USERNAME") &&
         password == System.get_env("INTERNAL_API_PASSWORD") do
      conn
    else
      unauthorized(conn)
    end
  end

  defp unauthorized(conn) do
    conn
    |> put_resp_header("www-authenticate", "Basic realm=\"Restricted Area\"")
    |> send_resp(401, "Unauthorized")
    |> halt()
  end
end
