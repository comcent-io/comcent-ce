defmodule ComcentWeb.QueueController do
  use ComcentWeb, :controller
  require Logger
  alias Comcent.Repo.Queue
  alias Comcent.Repo.Org
  alias Comcent.Repo.QueueMembership
  alias Comcent.GetQueueIds
  alias Comcent.Repo.OrgMember
  alias Comcent.QueueScheduler
  alias Comcent.QueueManager

  def create(conn, %{"subdomain" => subdomain} = params) do
    Logger.info("Creating queue")

    %{
      "name" => name,
      "extension" => extension
    } = params

    # Generate UUID for queue ID and create queue params
    queue_params =
      Map.merge(params, %{
        "id" => Ecto.UUID.generate()
      })

    # Wrap everything in a transaction
    case Comcent.Repo.transaction(fn ->
           # First get the org by subdomain
           case Org.get_org_by_subdomain(subdomain) do
             nil ->
               {:error, :org_not_found}

             org ->
               # Check existing name
               if Queue.get_queue_by_name_and_subdomain(name, subdomain) do
                 {:error, :name_conflict}
               else
                 # Check existing extension if provided
                 extension_exists =
                   if extension do
                     Queue.get_queue_id_by_extension_and_subdomain(extension, subdomain)
                   end

                 if extension_exists do
                   {:error, :extension_conflict}
                 else
                   # Create the queue with org's ID
                   Queue.create_queue(Map.put(queue_params, "org_id", org.id))
                 end
               end
           end
         end) do
      {:ok, {:ok, queue}} ->
        Logger.info("Queue created successfully for org #{subdomain}")

        # Start a worker process for this queue under DynamicSupervisor

        Comcent.QueueManager.start_queue_manager_worker(queue.id, subdomain)

        queue_address = "#{queue.id}@#{subdomain}.#{Application.fetch_env!(:comcent, :sip_domain)}"
        Logger.info("Started queue manager process for queue #{queue.name} at #{queue_address}")

        conn
        |> put_status(:ok)
        |> json(%{
          message: "Queue created successfully for org #{subdomain}",
          queue: queue
        })

      {:ok, {:error, :name_conflict}} ->
        Logger.error("Queue already exists with name #{name}")

        conn
        |> put_status(:conflict)
        |> json(%{
          error: "Queue already exists with name #{name}",
          code: "NAME_CONFLICT"
        })

      {:ok, {:error, :extension_conflict}} ->
        Logger.error("Queue with extension #{extension} already exists")

        conn
        |> put_status(:conflict)
        |> json(%{
          error: "Queue with extension #{extension} already exists",
          code: "EXTENSION_CONFLICT"
        })

      {:ok, {:error, :org_not_found}} ->
        Logger.error("Organization with subdomain #{subdomain} not found")

        conn
        |> put_status(:not_found)
        |> json(%{
          error: "Organization with subdomain #{subdomain} not found",
          code: "ORG_NOT_FOUND"
        })

      {:ok, {:error, changeset}} ->
        Logger.error("Invalid queue parameters: #{inspect(changeset.errors)}")

        # Transform changeset errors into a more user-friendly format
        formatted_errors =
          changeset.errors
          |> Enum.map(fn {field, {message, _}} ->
            %{
              field: field,
              message: message,
              code: "VALIDATION_ERROR"
            }
          end)

        conn
        |> put_status(:unprocessable_entity)
        |> json(%{
          error: "Invalid queue parameters",
          code: "VALIDATION_ERROR",
          details: formatted_errors
        })

      {:error, error} ->
        Logger.error("Failed to create queue: #{inspect(error)}")

        conn
        |> put_status(:internal_server_error)
        |> json(%{
          error: "Failed to create queue",
          code: "INTERNAL_ERROR"
        })
    end
  end

  def update(conn, %{"id" => id, "subdomain" => subdomain} = params) do
    Logger.info("Updating queue")

    name = params["name"]
    extension = params["extension"]
    wrap_up_time = params["wrap_up_time"]
    max_no_answers = params["max_no_answers"]
    reject_delay_time = params["reject_delay_time"]

    Comcent.Repo.transaction(fn ->
      case Queue.get_queue_by_id(id, subdomain) do
        nil ->
          Comcent.Repo.rollback(:queue_not_found)

        queue ->
          # Check if the name is already in use by a different queue
          if not is_nil(name) and name != "" do
            existing_queue = Queue.get_queue_by_name_and_subdomain(name, subdomain)

            if existing_queue && existing_queue.id != id do
              Comcent.Repo.rollback(:name_conflict)
            end
          end

          # Check if the extension is already in use by a different queue
          if not is_nil(extension) and extension != "" do
            existing_id =
              Queue.get_queue_id_by_extension_and_subdomain(extension, subdomain)

            case existing_id do
              nil -> :ok
              existing_id when existing_id == id -> :ok
              _ -> Comcent.Repo.rollback(:extension_conflict)
            end
          end

          # Update the queue with the new name and extension
          case Queue.update_queue(queue, %{
                 "name" => name,
                 "extension" => extension,
                 "wrap_up_time" => wrap_up_time,
                 "max_no_answers" => max_no_answers,
                 "reject_delay_time" => reject_delay_time
               }) do
            {:ok, updated_queue} -> updated_queue
            {:error, changeset} -> Comcent.Repo.rollback(changeset)
          end
      end
    end)
    |> case do
      {:ok, queue} ->
        Logger.info("Queue updated successfully")
        json(conn, %{message: "Queue updated successfully", queue: queue})

      {:error, :queue_not_found} ->
        Logger.error("Queue with id #{id} not found")

        conn
        |> put_status(:not_found)
        |> json(%{error: "Queue not found", code: "QUEUE_NOT_FOUND"})

      {:error, :name_conflict} ->
        Logger.error("Queue with name #{name} already exists")

        conn
        |> put_status(:conflict)
        |> json(%{
          error: "Queue with name #{name} already exists",
          code: "NAME_CONFLICT"
        })

      {:error, :extension_conflict} ->
        Logger.error("Queue with extension #{extension} already exists")

        conn
        |> put_status(:conflict)
        |> json(%{
          error: "Queue with extension #{extension} already exists",
          code: "EXTENSION_CONFLICT"
        })

      {:error, changeset} ->
        Logger.error("Invalid queue parameters: #{inspect(changeset.errors)}")

        formatted_errors =
          changeset.errors
          |> Enum.map(fn {field, {message, _}} ->
            %{
              field: field,
              message: message,
              code: "VALIDATION_ERROR"
            }
          end)

        conn
        |> put_status(:unprocessable_entity)
        |> json(%{
          error: "Invalid queue parameters",
          code: "VALIDATION_ERROR",
          details: formatted_errors
        })
    end
  end

  def get_queues(conn, %{"subdomain" => subdomain}) do
    Logger.info("Getting queues for org #{subdomain}")

    queues = Queue.get_queues_by_org(subdomain)
    json(conn, %{queues: queues})
  end

  def get_queue(conn, %{"id" => queue_id, "subdomain" => subdomain}) do
    Logger.info("Getting queue #{queue_id} for org #{subdomain}")

    queue = Queue.get_queue_with_members(queue_id, subdomain)
    Logger.info("Queue #{queue_id} for org #{subdomain}: #{inspect(queue)}")
    json(conn, %{queue_data: queue})
  end

  @spec delete(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def delete(conn, %{"id" => id, "subdomain" => subdomain}) do
    Logger.info("Deleting queue")

    Comcent.Repo.transaction(fn ->
      case Queue.get_queue_by_id(id, subdomain) do
        nil ->
          Comcent.Repo.rollback(:queue_not_found)

        queue ->
          # Check if the queue is used in any inbound flow graph
          queue_number_map = GetQueueIds.get_queue_ids_from_number_flow_graphs(subdomain)

          case Map.get(queue_number_map, queue.name) do
            nil ->
              :ok

            numbers ->
              numbers_str = Enum.join(numbers, ", ")

              error_msg =
                "Cannot delete #{queue.name} as it is used in inbound flow graph in numbers: #{numbers_str}"

              Logger.error(error_msg)
              Comcent.Repo.rollback({:queue_in_use, error_msg})
          end

          # Check if the queue is used in any voice bot
          voicebots = GetQueueIds.get_voicebots_with_queue(subdomain, queue.name)

          if length(voicebots) > 0 do
            error_msg =
              "Cannot delete #{queue.name} as it is used in voice bots: #{Enum.join(voicebots, ", ")}"

            Logger.error(error_msg)
            Comcent.Repo.rollback({:queue_in_use, error_msg})
          end

          # Stop a worker process for this queue under DynamicSupervisor
          queue_address = "#{queue.id}@#{subdomain}.#{Application.fetch_env!(:comcent, :sip_domain)}"

          case Comcent.QueueManager.stop_queue_manager_worker(queue.id, subdomain) do
            :ok ->
              Logger.info(
                "Terminated queue manager process for queue #{queue.name} at #{queue_address}"
              )

            {:error, :not_found} ->
              Logger.warning(
                "Queue manager process for queue #{queue.name}@#{subdomain}.#{Application.fetch_env!(:comcent, :sip_domain)} not found"
              )

            _ ->
              Logger.error(
                "Failed to stop queue manager process for queue #{queue.name}@#{subdomain}.#{Application.fetch_env!(:comcent, :sip_domain)}"
              )
          end

          QueueMembership.delete_queue_memberships(queue.id)
          Queue.delete_queue(queue)
      end
    end)
    |> case do
      {:ok, _} ->
        Logger.info("Queue deleted successfully")
        json(conn, %{message: "Queue deleted successfully"})

      {:error, {:queue_in_use, error_msg}} ->
        Logger.error(error_msg)

        conn
        |> put_status(:conflict)
        |> json(%{error: error_msg, code: "QUEUE_IN_USE"})

      {:error, :queue_not_found} ->
        Logger.error("Queue with id #{id} not found")

        conn
        |> put_status(:not_found)
        |> json(%{error: "Queue not found", code: "QUEUE_NOT_FOUND"})
    end
  end

  def get_queue_state(conn, %{"id" => id, "subdomain" => subdomain}) do
    Logger.info("Getting queue state for queue #{id} for org #{subdomain}")

    case QueueManager.get_worker_pid(id, subdomain) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Queue not found", code: "QUEUE_NOT_FOUND"})

      pid ->
        # Same shape as the `queue_dashboard_update` WebSocket payload, so
        # the REST-initial-load and the live subscription agree. The old
        # hand-rolled version referenced `state.members` / `state.queued_calls`
        # — fields from the pre-refactor scheduler — and threw `KeyError`,
        # which the dashboard displayed as "Data not found" until the first
        # broadcast happened to arrive.
        response_state =
          pid
          |> QueueScheduler.dashboard_payload()
          |> ComcentWeb.JsonCase.camel_case_keys()

        json(conn, %{state: response_state})
    end
  end

  def add_member(conn, %{"id" => id, "subdomain" => subdomain, "user_id" => user_id} = _params) do
    Logger.info("Adding user #{user_id} to queue #{id} for org #{subdomain}")

    with {:ok, queue} <- get_queue_by_id(id, subdomain),
         {:ok, _member} <- validate_org_membership(user_id, subdomain),
         {:ok, _} <- Queue.add_member_to_queue(%{org_id: queue.org_id, user_id: user_id}, id) do
      # Get the worker process and update its state
      case QueueManager.get_worker_pid(id, subdomain) do
        nil ->
          conn
          |> put_status(:not_found)
          |> json(%{error: "Queue not found", code: "QUEUE_NOT_FOUND"})

        pid ->
          # Get member details and add to worker
          case OrgMember.get_member_by_user_id_and_queue(user_id, subdomain, id) do
            nil ->
              conn
              |> put_status(:not_found)
              |> json(%{error: "Member not found", code: "MEMBER_NOT_FOUND"})

            member ->
              QueueScheduler.add_member(pid, member)
              QueueScheduler.refresh_total_agents(pid)
              json(conn, %{message: "Member added to queue successfully"})
          end
      end
    else
      {:error, :queue_not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Queue not found", code: "QUEUE_NOT_FOUND"})

      {:error, :not_org_member} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "User is not a member of this org", code: "NOT_ORG_MEMBER"})

      {:error, error} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: error, code: "ADD_MEMBER_ERROR"})
    end
  end

  def remove_member(conn, %{"id" => id, "subdomain" => subdomain, "member_id" => member_id}) do
    Logger.info("Removing member #{member_id} from queue #{id} for org #{subdomain}")

    case Queue.get_queue_by_id(id, subdomain) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Queue not found", code: "QUEUE_NOT_FOUND"})

      queue ->
        case Queue.remove_member_from_queue(id, member_id, queue.org_id) do
          {:ok, _} ->
            # Get the worker process and update its state
            case QueueManager.get_worker_pid(id, subdomain) do
              nil ->
                conn
                |> put_status(:not_found)
                |> json(%{error: "Queue not found", code: "QUEUE_NOT_FOUND"})

              pid ->
                QueueScheduler.remove_member(pid, member_id)
                QueueScheduler.refresh_total_agents(pid)
                json(conn, %{message: "Member removed from queue successfully"})
            end

          {:error, error} ->
            conn
            |> put_status(:unprocessable_entity)
            |> json(%{error: error, code: "REMOVE_MEMBER_ERROR"})
        end
    end
  end

  # Helper functions
  defp get_queue_by_id(id, subdomain) do
    case Queue.get_queue_by_id(id, subdomain) do
      nil -> {:error, :queue_not_found}
      queue -> {:ok, queue}
    end
  end

  defp validate_org_membership(user_id, subdomain) do
    case OrgMember.is_org_member(user_id, subdomain) do
      nil -> {:error, :not_org_member}
      member -> {:ok, member}
    end
  end
end
