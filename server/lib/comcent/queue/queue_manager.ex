defmodule Comcent.QueueManager do
  @moduledoc """
  Thin facade over the queue actor system.

  Each queue is represented by a `Comcent.QueueScheduler` process. This
  module exposes the small surface the rest of the app actually needs:
  starting/stopping a queue's scheduler, enqueuing a call, and notifying
  it when the waiting customer's leg hangs up.

  Agent presence, reservation, dial outcome, and retry decisions live in
  `Comcent.Queue.AgentSession` — they are no longer routed through here.
  """

  alias Comcent.Repo
  alias Comcent.Schemas.Queue
  alias Comcent.Schemas.Org
  import Ecto.Query
  require Logger
  alias Comcent.QueueScheduler

  @doc """
  Start a scheduler process for every queue in the system. Called once at
  boot.
  """
  def start_queue_manager do
    query =
      from(q in Queue, join: o in Org, on: q.org_id == o.id, select: {q.id, q.name, o.subdomain})

    sip_domain = Application.fetch_env!(:comcent, :sip_domain)

    Repo.all(query)
    |> Enum.each(fn {queue_id, queue_name, subdomain} ->
      start_queue_manager_worker(queue_id, subdomain)
      Logger.info("Started queue scheduler for #{queue_name}@#{subdomain}.#{sip_domain}")
    end)

    Logger.info("\n=== Started queue scheduler processes ===\n")
  end

  def start_queue_manager_worker(queue_id, subdomain) do
    Horde.DynamicSupervisor.start_child(
      Comcent.DynamicSupervisor,
      {QueueScheduler, %{queue_id: queue_id, subdomain: subdomain}}
    )
  end

  def stop_queue_manager_worker(queue_id, subdomain) do
    sip_domain = Application.fetch_env!(:comcent, :sip_domain)

    case Horde.Registry.lookup(
           Comcent.Registry,
           "queue_scheduler_#{queue_id}@#{subdomain}.#{sip_domain}"
         ) do
      [{pid, _}] ->
        Horde.DynamicSupervisor.terminate_child(Comcent.DynamicSupervisor, pid)

      [] ->
        {:error, :not_found}
    end
  end

  def add_call_to_queue(call_details) do
    Logger.info(
      "Adding call #{call_details.call_id} to queue #{call_details.queue_name} for subdomain #{call_details.subdomain}"
    )

    QueueScheduler.add_waiting_call(
      QueueScheduler.via_tuple(call_details.queue_id, call_details.subdomain),
      call_details
    )
  end

  def call_hung_up(subdomain, queue_id, call_id, hung_up_at \\ nil) do
    case get_worker_pid(queue_id, subdomain) do
      nil -> {:error, :not_found}
      pid -> QueueScheduler.call_hung_up(pid, call_id, hung_up_at)
    end
  end

  def get_worker_pid(queue_id, subdomain) do
    sip_domain = Application.fetch_env!(:comcent, :sip_domain)

    case Horde.Registry.lookup(
           Comcent.Registry,
           "queue_scheduler_#{queue_id}@#{subdomain}.#{sip_domain}"
         ) do
      [{pid, _}] -> pid
      [] -> nil
    end
  end

  defmodule QueuedCallDetails do
    @derive {Jason.Encoder,
             only: [
               :subdomain,
               :queue_name,
               :queue_id,
               :call_id,
               :freeswitch_ip_address,
               :date_time,
               :to_user,
               :to_name,
               :from_user,
               :from_name,
               :comcent_context_id
             ]}
    defstruct [
      :subdomain,
      :queue_name,
      :queue_id,
      :call_id,
      :freeswitch_ip_address,
      :date_time,
      :to_user,
      :to_name,
      :from_user,
      :from_name,
      :comcent_context_id
    ]
  end
end
