defmodule ComcentWeb.NumberController do
  use ComcentWeb, :controller
  require Logger

  alias Comcent.Repo
  alias Comcent.Repo.{Number, Org}
  alias Comcent.Schemas.Number, as: NumberSchema

  def get_numbers(conn, params) do
    subdomain = conn.assigns[:subdomain]
    Logger.info("Getting numbers for org #{subdomain}")

    page = String.to_integer(params["page"] || "1")

    items_per_page =
      case Integer.parse(params["items_per_page"] || "10") do
        {n, _} when n in [5, 10, 20, 50] -> n
        _ -> 10
      end

    if params["page"] do
      result = Number.get_numbers_paginated(subdomain, page, items_per_page)
      total_pages = ceil(result.total_count / items_per_page)

      conn
      |> put_status(:ok)
      |> json(%{
        numbers: result.numbers,
        total_count: result.total_count,
        total_pages: total_pages,
        current_page: page,
        items_per_page: items_per_page
      })
    else
      numbers = Number.get_numbers_by_org(subdomain)
      conn |> put_status(:ok) |> json(%{numbers: numbers})
    end
  end

  def set_default(conn, %{"id" => id}) do
    subdomain = conn.assigns[:subdomain]
    Logger.info("Setting default number #{id} for org #{subdomain}")

    case Number.get_by_id(id, subdomain) do
      nil ->
        conn |> put_status(:not_found) |> json(%{error: "Number not found"})

      number ->
        Number.clear_default_for_org(subdomain)

        case Repo.update(NumberSchema.changeset(number, %{"is_default_outbound_number" => true})) do
          {:ok, _} ->
            conn |> put_status(:ok) |> json(%{success: true})

          {:error, changeset} ->
            Logger.error("Failed to set default number: #{inspect(changeset.errors)}")

            conn
            |> put_status(:internal_server_error)
            |> json(%{error: "Failed to set default number"})
        end
    end
  end

  def create(conn, params) do
    subdomain = conn.assigns[:subdomain]
    Logger.info("Creating number for org #{subdomain}")

    case Org.get_org_by_subdomain(subdomain) do
      nil ->
        conn |> put_status(:not_found) |> json(%{error: "Organization not found"})

      org ->
        case Number.get_by_number(params["number"]) do
          %NumberSchema{} ->
            conn |> put_status(:bad_request) |> json(%{error: "Number already exists"})

          nil ->
            case Repo.get(Comcent.Schemas.SipTrunk, params["sip_trunk_id"]) do
              nil ->
                conn |> put_status(:not_found) |> json(%{error: "Sip trunk not found"})

              _sip_trunk ->
                attrs = %{
                  "name" => params["name"],
                  "number" => params["number"],
                  "allow_outbound_regex" => params["allow_outbound_regex"],
                  "inbound_flow_graph" => params["inbound_flow_graph"],
                  "org_id" => org.id,
                  "sip_trunk_id" => params["sip_trunk_id"]
                }

                new_number = %NumberSchema{id: Ecto.UUID.generate()}

                case Repo.insert(NumberSchema.changeset(new_number, attrs)) do
                  {:ok, number} ->
                    Logger.info("Number created successfully for org #{subdomain}")
                    number = Repo.preload(number, :sip_trunk)
                    conn |> put_status(:ok) |> json(number)

                  {:error, changeset} ->
                    Logger.error("Failed to create number: #{inspect(changeset.errors)}")

                    conn
                    |> put_status(:unprocessable_entity)
                    |> json(%{error: format_errors(changeset)})
                end
            end
        end
    end
  end

  def update(conn, %{"id" => id} = params) do
    subdomain = conn.assigns[:subdomain]
    Logger.info("Updating number #{id} for org #{subdomain}")

    case Number.get_by_id(id, subdomain) do
      nil ->
        conn |> put_status(:not_found) |> json(%{error: "Number not found"})

      number ->
        case Number.get_by_number(params["number"]) do
          %NumberSchema{id: existing_id} when existing_id != id ->
            conn |> put_status(:bad_request) |> json(%{error: "Number already exists"})

          _ ->
            case Repo.get(Comcent.Schemas.SipTrunk, params["sip_trunk_id"]) do
              nil ->
                conn |> put_status(:not_found) |> json(%{error: "SipTrunk not found"})

              _sip_trunk ->
                attrs =
                  Map.take(params, [
                    "name",
                    "number",
                    "allow_outbound_regex",
                    "inbound_flow_graph",
                    "sip_trunk_id"
                  ])

                case Repo.update(NumberSchema.changeset(number, attrs)) do
                  {:ok, updated} ->
                    Logger.info("Number #{id} updated successfully")
                    updated = Repo.preload(updated, :sip_trunk)
                    conn |> put_status(:ok) |> json(updated)

                  {:error, changeset} ->
                    Logger.error("Failed to update number: #{inspect(changeset.errors)}")

                    conn
                    |> put_status(:unprocessable_entity)
                    |> json(%{error: format_errors(changeset)})
                end
            end
        end
    end
  end

  def delete(conn, %{"id" => id}) do
    subdomain = conn.assigns[:subdomain]
    Logger.info("Deleting number #{id} for org #{subdomain}")

    case Number.get_by_id(id, subdomain) do
      nil ->
        conn |> put_status(:not_found) |> json(%{error: "Number not found"})

      number ->
        campaigns = Number.get_campaigns_for_number(id)

        if length(campaigns) > 0 do
          campaign_names = Enum.map(campaigns, & &1.name)

          conn
          |> put_status(:conflict)
          |> json(%{
            error:
              "Cannot delete number as it is used in campaigns #{Enum.join(campaign_names, ", ")}"
          })
        else
          case Repo.delete(number) do
            {:ok, _} ->
              Logger.info("Number #{id} deleted successfully")

              conn
              |> put_status(:ok)
              |> json(%{message: "Number with id #{id} deleted successfully"})

            {:error, changeset} ->
              Logger.error("Failed to delete number: #{inspect(changeset.errors)}")

              conn
              |> put_status(:internal_server_error)
              |> json(%{error: "Failed to delete number"})
          end
        end
    end
  end

  defp format_errors(changeset) do
    Enum.map(changeset.errors, fn {field, {message, _}} -> "#{field}: #{message}" end)
    |> Enum.join(", ")
  end
end
