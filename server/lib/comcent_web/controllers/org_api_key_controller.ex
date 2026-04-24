defmodule ComcentWeb.OrgApiKeyController do
  use ComcentWeb, :controller
  require Logger

  alias Comcent.Repo
  alias Comcent.Repo.{OrgApiKey, Org}
  alias Comcent.Schemas.OrgApiKey, as: OrgApiKeySchema

  def get_api_keys(conn, _params) do
    subdomain = conn.assigns[:subdomain]
    Logger.info("Getting API keys for org #{subdomain}")
    api_keys = OrgApiKey.get_all_by_org(subdomain)
    json(conn, %{api_keys: api_keys})
  end

  def create(conn, params) do
    subdomain = conn.assigns[:subdomain]
    Logger.info("Creating API key for org #{subdomain}")

    name = params["name"]

    if is_nil(name) or String.length(name) < 3 do
      conn
      |> put_status(:bad_request)
      |> json(%{error: "Name must be at least 3 characters"})
    else
      case Org.get_org_by_subdomain(subdomain) do
        nil ->
          conn |> put_status(:not_found) |> json(%{error: "Organization not found"})

        org ->
          api_key_value = :crypto.strong_rand_bytes(64) |> Base.encode16(case: :lower)

          attrs = %{
            "api_key" => api_key_value,
            "name" => name,
            "org_id" => org.id
          }

          new_api_key = %OrgApiKeySchema{}

          case Repo.insert(OrgApiKeySchema.changeset(new_api_key, attrs)) do
            {:ok, api_key} ->
              Logger.info("API key created successfully for org #{subdomain}")
              conn |> put_status(:ok) |> json(api_key)

            {:error, changeset} ->
              Logger.error("Failed to create API key: #{inspect(changeset.errors)}")

              conn
              |> put_status(:unprocessable_entity)
              |> json(%{error: format_errors(changeset)})
          end
      end
    end
  end

  def delete(conn, %{"api_key" => api_key}) do
    subdomain = conn.assigns[:subdomain]
    Logger.info("Deleting API key for org #{subdomain}")

    case OrgApiKey.get_by_api_key(api_key, subdomain) do
      nil ->
        conn |> put_status(:not_found) |> json(%{error: "API key not found"})

      key_record ->
        case Repo.delete(key_record) do
          {:ok, _} ->
            Logger.info("API key deleted successfully for org #{subdomain}")
            conn |> put_status(:ok) |> json(%{message: "API key deleted successfully"})

          {:error, changeset} ->
            Logger.error("Failed to delete API key: #{inspect(changeset.errors)}")

            conn
            |> put_status(:internal_server_error)
            |> json(%{error: "Failed to delete API key"})
        end
    end
  end

  defp format_errors(changeset) do
    Enum.map(changeset.errors, fn {field, {message, _}} -> "#{field}: #{message}" end)
    |> Enum.join(", ")
  end
end
