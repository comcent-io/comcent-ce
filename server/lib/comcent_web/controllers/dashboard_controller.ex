defmodule ComcentWeb.DashboardController do
  use ComcentWeb, :controller
  require Logger
  alias Comcent.Call.LiveCalls
  alias Comcent.Repo
  alias Comcent.Schemas.Org

  def get_live_calls(conn, %{"subdomain" => subdomain}) do
    with {:ok, _org} <- get_org_by_subdomain(subdomain) do
      json(conn, %{live_calls: LiveCalls.list(subdomain)})
    else
      {:error, :org_not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Organization not found"})

      {:error, reason} ->
        Logger.error("Error getting live calls: #{inspect(reason)}")

        conn
        |> put_status(:internal_server_error)
        |> json(%{error: "Internal server error"})
    end
  end

  # Private functions

  defp get_org_by_subdomain(subdomain) do
    case Repo.get_by(Org, subdomain: subdomain) do
      nil -> {:error, :org_not_found}
      org -> {:ok, org}
    end
  end
end
