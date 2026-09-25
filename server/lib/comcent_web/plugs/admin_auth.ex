defmodule ComcentWeb.Plugs.AdminAuth do
  import Plug.Conn
  require Logger
  import Ecto.Query
  alias Comcent.Auth
  alias Comcent.Repo
  alias Comcent.Schemas.User

  def init(opts), do: opts

  def call(conn, _opts) do
    case authenticate_request(conn) do
      {:ok, user} ->
        # Check if user has SUPER_ADMIN role in any organization
        if super_admin_with_current_session?(user) do
          conn
          |> assign(:current_user, user)
        else
          unauthorized(conn)
        end

      {:error, reason} ->
        Logger.error("Admin authentication failed: #{inspect(reason)}")
        login_required(conn)
    end
  end

  defp authenticate_request(conn) do
    case get_req_header(conn, "authorization") do
      ["Bearer " <> token] ->
        Auth.authenticate_with_jwt(token)

      _ ->
        Auth.authenticate_with_cookie(conn)
    end
  end

  defp super_admin_with_current_session?(%{email: email, claims: claims}) do
    query = from(u in User, where: u.email == ^email and u.is_super_admin == true)

    case Repo.one(query) do
      nil -> false
      super_admin -> Auth.session_current?(claims, super_admin)
    end
  end

  defp unauthorized(conn) do
    conn
    |> assign(:admin_layout, true)
    |> put_resp_content_type("text/html")
    |> put_status(401)
    |> Phoenix.Controller.render(ComcentWeb.AdminHTML, :unauthorized)
    |> halt()
  end

  defp login_required(conn) do
    conn
    |> assign(:admin_layout, true)
    |> put_resp_content_type("text/html")
    |> put_status(401)
    |> Phoenix.Controller.render(ComcentWeb.AdminHTML, :login_required)
    |> halt()
  end
end
