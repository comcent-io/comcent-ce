defmodule ComcentWeb.HealthController do
  use ComcentWeb, :controller

  def health(conn, _params) do
    conn
    |> put_status(:ok)
    |> text("okay")
  end
end
