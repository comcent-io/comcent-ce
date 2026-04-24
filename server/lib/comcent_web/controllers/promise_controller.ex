defmodule ComcentWeb.PromiseController do
  use ComcentWeb, :controller
  import Ecto.Query

  alias Comcent.Repo
  alias Comcent.Schemas.{Promises, PromiseAuditLog, Org, DailySummary}
  alias Comcent.Repo.DailySummary, as: DailySummaryRepo
  require Logger

  # Helper function to create audit log entry
  defp create_audit_log(promise_id, org_id, type, old_value, new_value) do
    audit_log_attrs = %{
      "id" => Ecto.UUID.generate(),
      "promise_id" => promise_id,
      "org_id" => org_id,
      "type" => type,
      "old_value" => old_value,
      "new_value" => new_value
    }

    %PromiseAuditLog{}
    |> PromiseAuditLog.changeset(audit_log_attrs)
    |> Repo.insert()
  end

  # Helper function to update daily summary with closed promises count
  defp update_daily_summary_closed_count(org_id, date, promises_closed_count) do
    case DailySummaryRepo.get_daily_summary_by_date_and_org_id(org_id, date) do
      nil ->
        Logger.debug("No daily summary found for today, skipping closed promise count update")

      daily_summary ->
        updated_count = (daily_summary.total_promises_closed || 0) + promises_closed_count

        DailySummary.changeset(daily_summary, %{
          total_promises_closed: updated_count
        })
        |> Repo.update!()

        Logger.info(
          "Updated daily summary #{daily_summary.id} with #{promises_closed_count} closed promises. New total: #{updated_count}"
        )
    end
  end

  def get_promises(conn, %{"subdomain" => subdomain} = _params) do
    Logger.info("Getting promises for org #{subdomain}")

    # Find the organization by subdomain
    org = Repo.get_by(Org, subdomain: subdomain)

    case org do
      nil ->
        Logger.error("Organization with subdomain #{subdomain} not found")

        conn
        |> put_status(:not_found)
        |> json(%{error: "Organization not found", code: "ORG_NOT_FOUND"})

      org ->
        # Get status filter from query params, default to OPEN if not provided
        # Extract multiple status values from query string using manual parsing
        status_values =
          conn.query_string
          |> String.split("&")
          |> Enum.filter(fn param -> String.starts_with?(param, "status=") end)
          |> Enum.map(fn param ->
            param |> String.split("=") |> Enum.at(1) |> URI.decode()
          end)
          |> Enum.filter(&(&1 != nil))

        # Process status values - ensure we get all selected statuses
        statuses =
          case status_values do
            # Default to OPEN if no status specified
            [] -> ["OPEN"]
            statuses_list -> statuses_list
          end

        # Get assigned_to filter from query params
        assigned_to_filter =
          conn.query_string
          |> String.split("&")
          |> Enum.find(fn param -> String.starts_with?(param, "assigned_to=") end)
          |> case do
            nil -> nil
            param -> param |> String.split("=") |> Enum.at(1) |> URI.decode()
          end

        # Build base query
        base_query =
          from(p in Promises,
            where: p.org_id == ^org.id,
            where: p.status in ^statuses,
            order_by: [desc: p.created_at]
          )

        # Apply assigned_to filter if present
        promises_query =
          case assigned_to_filter do
            nil -> base_query
            username -> from(p in base_query, where: p.assigned_to == ^username)
          end

        # Get promises for the org filtered by status and assigned_to
        promises = Repo.all(promises_query)

        # Calculate promise completion ratio (closed promises / total promises created today)
        today = Date.utc_today()
        today_start = DateTime.new!(today, ~T[00:00:00], "Etc/UTC")
        today_end = DateTime.new!(today, ~T[23:59:59], "Etc/UTC")

        # Get all promises created today
        promises_created_today =
          from(p in Promises,
            where: p.org_id == ^org.id,
            where: p.created_at >= ^today_start and p.created_at <= ^today_end
          )
          |> Repo.all()

        # Calculate ratio
        total_created_today = length(promises_created_today)
        closed_today = promises_created_today |> Enum.count(&(&1.status == "CLOSED"))

        completion_ratio =
          if total_created_today > 0, do: closed_today / total_created_today, else: 0.0

        response_promises = promises

        Logger.info("Retrieved #{length(promises)} promises for org #{subdomain}")

        Logger.info(
          "Today's completion ratio: #{closed_today}/#{total_created_today} = #{completion_ratio}"
        )

        json(conn, %{
          promises: response_promises,
          stats: %{
            completion_ratio: completion_ratio,
            total_created_today: total_created_today,
            closed_today: closed_today
          }
        })
    end
  end

  def close_promises(conn, %{"subdomain" => subdomain, "promise_ids" => promise_ids}) do
    Logger.info("Closing promises for org #{subdomain}: #{inspect(promise_ids)}")

    # Find the organization by subdomain
    org = Repo.get_by(Org, subdomain: subdomain)

    case org do
      nil ->
        Logger.error("Organization with subdomain #{subdomain} not found")

        conn
        |> put_status(:not_found)
        |> json(%{error: "Organization not found", code: "ORG_NOT_FOUND"})

      org ->
        # First, fetch the promises that will be closed
        promises_to_close =
          from(p in Promises,
            where: p.org_id == ^org.id,
            where: p.id in ^promise_ids,
            where: p.status == "OPEN"
          )
          |> Repo.all()

        # Update promises status to CLOSED
        {updated_count, _} =
          from(p in Promises,
            where: p.org_id == ^org.id,
            where: p.id in ^promise_ids,
            where: p.status == "OPEN"
          )
          |> Repo.update_all(set: [status: "CLOSED", updated_at: DateTime.utc_now()])

        # Create audit log entries for each closed promise
        Enum.each(promises_to_close, fn promise ->
          case create_audit_log(promise.id, org.id, :STATUS_CHANGED, "OPEN", "CLOSED") do
            {:ok, _audit_log} ->
              Logger.info("Created audit log for promise #{promise.id}")

            {:error, changeset} ->
              Logger.error(
                "Failed to create audit log for promise #{promise.id}: #{inspect(changeset.errors)}"
              )
          end
        end)

        # Update daily summary if it exists for today
        if updated_count > 0 do
          today_date = Date.utc_today()
          today_start = DateTime.new!(today_date, ~T[00:00:00], "Etc/UTC")
          update_daily_summary_closed_count(org.id, today_start, updated_count)
        end

        Logger.info("Closed #{updated_count} promises for org #{subdomain}")

        json(conn, %{closed: updated_count, message: "Promises closed successfully"})
    end
  end

  def update_assigned_to(conn, %{
        "subdomain" => subdomain,
        "promise_id" => promise_id,
        "assigned_to" => assigned_to
      }) do
    Logger.info(
      "Updating assigned_to for promise #{promise_id} in org #{subdomain} to #{assigned_to}"
    )

    # Find the organization by subdomain
    org = Repo.get_by(Org, subdomain: subdomain)

    case org do
      nil ->
        Logger.error("Organization with subdomain #{subdomain} not found")

        conn
        |> put_status(:not_found)
        |> json(%{error: "Organization not found", code: "ORG_NOT_FOUND"})

      org ->
        # Find the promise
        promise =
          from(p in Promises,
            where: p.id == ^promise_id,
            where: p.org_id == ^org.id
          )
          |> Repo.one()

        case promise do
          nil ->
            Logger.error("Promise #{promise_id} not found for org #{subdomain}")

            conn
            |> put_status(:not_found)
            |> json(%{error: "Promise not found", code: "PROMISE_NOT_FOUND"})

          promise ->
            # Store old value for audit log
            old_assigned_to = promise.assigned_to

            # Update the assigned_to field
            changeset =
              Promises.changeset(promise, %{
                assigned_to: assigned_to,
                updated_at: DateTime.utc_now()
              })

            case Repo.update(changeset) do
              {:ok, updated_promise} ->
                Logger.info("Successfully updated assigned_to for promise #{promise_id}")

                # Create audit log entry if the value changed
                if old_assigned_to != assigned_to do
                  case create_audit_log(
                         promise.id,
                         org.id,
                         :ASSIGNED_TO_CHANGED,
                         old_assigned_to,
                         assigned_to
                       ) do
                    {:ok, _audit_log} ->
                      Logger.info(
                        "Created audit log for assigned_to change on promise #{promise_id}"
                      )

                    {:error, changeset} ->
                      Logger.error(
                        "Failed to create audit log for promise #{promise_id}: #{inspect(changeset.errors)}"
                      )
                  end
                end

                promise_map = %{
                  id: updated_promise.id,
                  org_id: updated_promise.org_id,
                  call_story_id: updated_promise.call_story_id,
                  promise: updated_promise.promise,
                  status: updated_promise.status,
                  due_date: updated_promise.due_date,
                  created_by: updated_promise.created_by,
                  assigned_to: updated_promise.assigned_to,
                  created_at: updated_promise.created_at,
                  updated_at: updated_promise.updated_at
                }

                response_promise = promise_map

                json(conn, %{
                  promise: response_promise,
                  message: "Promise assignment updated successfully"
                })

              {:error, changeset} ->
                Logger.error("Failed to update promise: #{inspect(changeset.errors)}")

                conn
                |> put_status(:bad_request)
                |> json(%{error: "Failed to update promise", code: "UPDATE_FAILED"})
            end
        end
    end
  end
end
