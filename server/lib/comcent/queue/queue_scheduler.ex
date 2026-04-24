defmodule Comcent.QueueScheduler do
  @moduledoc """
  One process per queue. Matches waiting calls to available agents.

  Deliberately thin. The scheduler does not know about FreeSWITCH, does not
  own dialers, and caches nothing about agent presence or call state —
  `Comcent.Queue.AgentSession` and `Comcent.Queue.QueuedCall` are the
  authoritative sources of truth for those things.

  State
    * `waiting`   — FIFO of `call_id`s waiting to be connected
    * `available` — ordered list (insertion order) of `user_id`s currently
      eligible to be dialed. Kept as a list rather than a set so that
      round-robin sweeps produce stable, fair agent ordering — iterating a
      MapSet would reorder by hash/alphabet and starve agents at the end.
    * `in_flight` — `%{user_id => call_id}` for active attempts
    * `last_assigned_user_id` — round-robin anchor

  Triggers (all of these cast `:try_match`)
    * `add_waiting_call/2` — a new customer joins the queue
    * `{:presence_update, ...}` arriving on PubSub with presence `"Available"`
    * `{:attempt_finished, _, _, :failed | :timed_out}` from AgentSession

  Scheduler <-> AgentSession conversation
    * Scheduler calls `AgentSession.attempt/3`. Returns `{:ok, _}` or
      `{:error, :unavailable}` synchronously.
    * AgentSession casts `{:agent_busy, user_id, call_id}` (redundant with
      the reply; serves as an audit trail), and
      `{:attempt_finished, user_id, call_id, outcome}` when the attempt
      resolves.
  """

  use GenServer
  require Logger

  alias Comcent.CallSession
  alias Comcent.Queue.AgentSession
  alias Comcent.Queue.QueuedCall
  alias Comcent.Repo.{Queue, OrgMember}
  alias Phoenix.PubSub

  # Public API -----------------------------------------------------------------

  def child_spec(%{queue_id: queue_id, subdomain: subdomain}) do
    %{
      id: "#{__MODULE__}_#{queue_id}@#{subdomain}",
      start: {__MODULE__, :start_link, [%{queue_id: queue_id, subdomain: subdomain}]}
    }
  end

  def start_link(%{queue_id: queue_id, subdomain: subdomain}) do
    case GenServer.start_link(
           __MODULE__,
           %{queue_id: queue_id, subdomain: subdomain},
           name: via_tuple(queue_id, subdomain),
           restart: :transient
         ) do
      {:ok, pid} -> {:ok, pid}
      {:error, {:already_started, _pid}} -> :ignore
    end
  end

  def via_tuple(queue_id, subdomain) do
    sip_domain = Application.fetch_env!(:comcent, :sip_domain)

    {:via, Horde.Registry,
     {Comcent.Registry, "queue_scheduler_#{queue_id}@#{subdomain}.#{sip_domain}"}}
  end

  def add_waiting_call(pid, call_details),
    do: GenServer.cast(pid, {:add_waiting_call, call_details})

  def call_hung_up(pid, call_id, hung_up_at \\ nil),
    do: GenServer.cast(pid, {:call_hung_up, call_id, hung_up_at})

  def add_member(pid, member), do: GenServer.cast(pid, {:add_member, member})

  def remove_member(pid, user_id), do: GenServer.cast(pid, {:remove_member, user_id})

  def refresh_total_agents(pid), do: GenServer.cast(pid, :refresh_total_agents)

  def get_state(pid), do: GenServer.call(pid, :get_state)

  @doc """
  Returns the dashboard payload — same shape the WebSocket broadcast uses,
  so the REST `/queues/:id/state` endpoint and the live subscription hand
  the frontend identical data. Built in this module so future state-shape
  changes stay in one place.
  """
  def dashboard_payload(pid), do: GenServer.call(pid, :dashboard_payload)

  # GenServer callbacks --------------------------------------------------------

  @impl true
  def init(%{queue_id: queue_id, subdomain: subdomain}) do
    Process.flag(:trap_exit, true)
    PubSub.subscribe(Comcent.PubSub, "presence:#{subdomain}")

    state = %{
      queue_id: queue_id,
      subdomain: subdomain,
      queue_name: nil,
      waiting: [],
      available: [],
      in_flight: %{},
      last_assigned_user_id: nil,
      total_agents: 0
    }

    {:ok, state, {:continue, :load_queue}}
  end

  @impl true
  def handle_continue(:load_queue, state) do
    queue = Queue.get_queue_by_id(state.queue_id, state.subdomain)

    available =
      queue_available_agents(state.queue_id, state.subdomain)
      |> Enum.reduce([], fn member, acc ->
        ensure_agent_session(member)
        put_available(acc, member.user_id)
      end)

    state = %{
      state
      | queue_name: queue && queue.name,
        available: available,
        total_agents: Queue.get_total_agents_in_queue(state.queue_id, state.subdomain)
    }

    broadcast_state(state)
    {:noreply, maybe_match(state)}
  end

  @impl true
  def handle_call(:get_state, _from, state), do: {:reply, state, state}

  def handle_call(:dashboard_payload, _from, state),
    do: {:reply, build_dashboard_payload(state), state}

  @impl true
  def handle_cast({:add_waiting_call, call_details}, state) do
    case QueuedCall.start(call_details) do
      {:ok, _snapshot} ->
        Logger.info(
          "Queue #{state.queue_name}@#{state.subdomain}: enqueued call #{call_details.call_id}"
        )

        state = %{state | waiting: state.waiting ++ [call_details.call_id]}
        broadcast_state(state)
        {:noreply, maybe_match(state)}

      other ->
        Logger.error("Failed to start QueuedCall #{call_details.call_id}: #{inspect(other)}")
        {:noreply, state}
    end
  end

  def handle_cast({:call_hung_up, call_id, hung_up_at}, state) do
    state = handle_call_hung_up(state, call_id, hung_up_at)
    {:noreply, state}
  end

  def handle_cast({:add_member, member}, state) do
    ensure_agent_session(member)
    presence = OrgMember.get_current_presence(state.subdomain, member.user_id) || member.presence

    state =
      if presence == "Available" and not Map.has_key?(state.in_flight, member.user_id) do
        %{state | available: put_available(state.available, member.user_id)}
      else
        state
      end

    state = refresh_total_agents_count(state)
    broadcast_state(state)
    {:noreply, maybe_match(state)}
  end

  def handle_cast({:remove_member, user_id}, state) do
    state = drop_agent(state, user_id, :removed_from_queue)
    state = refresh_total_agents_count(state)
    broadcast_state(state)
    {:noreply, state}
  end

  def handle_cast(:refresh_total_agents, state) do
    state = refresh_total_agents_count(state)
    broadcast_state(state)
    {:noreply, state}
  end

  def handle_cast({:agent_busy, _user_id, _call_id}, state), do: {:noreply, state}

  def handle_cast({:attempt_finished, user_id, call_id, outcome}, state) do
    state = %{state | in_flight: Map.delete(state.in_flight, user_id)}

    state =
      case outcome do
        :answered ->
          %{state | waiting: Enum.reject(state.waiting, &(&1 == call_id))}

        _ ->
          state
      end

    broadcast_state(state)

    # On failure, agent is Busy for reject_delay. When they return to
    # Available, presence PubSub will re-add them. Don't add them here.
    {:noreply, maybe_match(state)}
  end

  @impl true
  def handle_info({:presence_update, %{user_id: user_id, presence: presence}}, state) do
    state =
      case presence do
        "Available" ->
          handle_agent_available(state, user_id)

        "Logged Out" ->
          drop_agent(state, user_id, :logged_out)

        _ ->
          # Intermediate presence like "On Call"/"Busy"/"Wrap Up" must not
          # cancel an in-flight attempt — the AgentSession owns that
          # lifecycle. Just make sure the agent isn't sitting in `available`.
          %{state | available: List.delete(state.available, user_id)}
      end

    broadcast_state(state)
    {:noreply, maybe_match(state)}
  end

  def handle_info({:EXIT, _pid, _reason}, state), do: {:noreply, state}

  def handle_info(_msg, state), do: {:noreply, state}

  # Internals: matching --------------------------------------------------------

  defp maybe_match(state) do
    cond do
      state.waiting == [] -> state
      state.available == [] -> state
      true -> do_match(state)
    end
  end

  defp do_match(state) do
    case next_callable(state) do
      nil ->
        state

      call_id ->
        ordered = order_candidates(state.available, state.last_assigned_user_id)
        eligible = QueuedCall.eligible_agents(call_id, ordered)

        try_agents(state, call_id, eligible)
    end
  end

  defp try_agents(state, _call_id, []), do: state

  defp try_agents(state, call_id, [user_id | rest]) do
    member = %{subdomain: state.subdomain, user_id: user_id}

    case AgentSession.attempt(member, state.queue_id, call_id) do
      {:ok, _reservation_id} ->
        state = %{
          state
          | available: List.delete(state.available, user_id),
            in_flight: Map.put(state.in_flight, user_id, call_id),
            last_assigned_user_id: user_id
        }

        broadcast_state(state)
        maybe_match(state)

      {:error, _reason} ->
        state = %{state | available: List.delete(state.available, user_id)}
        try_agents(state, call_id, rest)
    end
  end

  defp put_available(available, user_id) do
    if Enum.member?(available, user_id), do: available, else: available ++ [user_id]
  end

  defp next_callable(state) do
    in_flight_calls = MapSet.new(Map.values(state.in_flight))
    Enum.find(state.waiting, fn call_id -> not MapSet.member?(in_flight_calls, call_id) end)
  end

  defp order_candidates(candidates, nil), do: candidates

  defp order_candidates(candidates, last_user_id) do
    case Enum.find_index(candidates, &(&1 == last_user_id)) do
      nil ->
        candidates

      idx when idx + 1 >= length(candidates) ->
        candidates

      idx ->
        Enum.slice(candidates, (idx + 1)..-1) ++ Enum.slice(candidates, 0..idx)
    end
  end

  # Internals: lifecycle helpers ----------------------------------------------

  defp handle_agent_available(state, user_id) do
    cond do
      Map.has_key?(state.in_flight, user_id) -> state
      Enum.member?(state.available, user_id) -> state
      not agent_belongs_to_queue?(state, user_id) -> state
      true -> %{state | available: put_available(state.available, user_id)}
    end
  end

  defp drop_agent(state, user_id, reason) do
    state = %{state | available: List.delete(state.available, user_id)}

    case Map.fetch(state.in_flight, user_id) do
      {:ok, call_id} ->
        AgentSession.cancel_attempt(
          %{subdomain: state.subdomain, user_id: user_id},
          call_id,
          reason
        )

        %{state | in_flight: Map.delete(state.in_flight, user_id)}

      :error ->
        state
    end
  end

  defp handle_call_hung_up(state, call_id, hung_up_at) do
    attempting_user_id =
      Enum.find_value(state.in_flight, fn {user_id, c} -> if c == call_id, do: user_id end)

    call_snapshot = QueuedCall.snapshot(call_id)

    # Close the RINGING span before stopping QueuedCall. Otherwise mark_failed
    # becomes a no-op (registry lookup returns :noproc) and the UI shows an
    # unterminated attempt on the ringing agent. This path is specifically
    # "customer hung up while an attempt was in flight" — the dialer's own
    # :dialer_failed arrives seconds later and finds a stale reservation, so
    # it can't write the event either.
    if attempting_user_id, do: QueuedCall.mark_failed(call_id, :customer_hung_up)

    QueuedCall.stop(call_id)

    append_queued_span(state, call_snapshot, hung_up_at || DateTime.utc_now())

    state =
      if attempting_user_id do
        AgentSession.cancel_attempt(
          %{subdomain: state.subdomain, user_id: attempting_user_id},
          call_id,
          :customer_hung_up
        )

        %{state | in_flight: Map.delete(state.in_flight, attempting_user_id)}
      else
        state
      end

    state = %{state | waiting: Enum.reject(state.waiting, &(&1 == call_id))}
    broadcast_state(state)
    state
  end

  defp append_queued_span(_state, :ignore, _end_at), do: :ok

  defp append_queued_span(_state, {:ok, snapshot}, end_at) do
    if is_binary(snapshot.comcent_context_id) do
      CallSession.append_story_span(snapshot.comcent_context_id, %{
        type: "QUEUED",
        call_story_id: snapshot.comcent_context_id,
        channel_id: snapshot.call_id,
        start_at: snapshot.date_time,
        end_at: end_at,
        current_party: snapshot.from_user
      })
    end

    :ok
  end

  defp refresh_total_agents_count(state) do
    %{state | total_agents: Queue.get_total_agents_in_queue(state.queue_id, state.subdomain)}
  end

  defp queue_available_agents(queue_id, subdomain) do
    if function_exported?(Queue, :get_active_agents, 2) do
      Queue.get_active_agents(queue_id, subdomain)
    else
      Queue.get_available_agents(queue_id, subdomain)
    end
  end

  defp ensure_agent_session(member) do
    case AgentSession.ensure_started(member) do
      {:ok, _} -> :ok
      _ -> :ok
    end
  end

  defp agent_belongs_to_queue?(state, user_id) do
    case OrgMember.get_member_by_user_id_and_queue(user_id, state.subdomain, state.queue_id) do
      nil -> false
      _ -> true
    end
  end

  # Dashboard broadcast --------------------------------------------------------

  defp broadcast_state(state) do
    PubSub.broadcast(
      Comcent.PubSub,
      "queue_dashboard:#{state.subdomain}:#{state.queue_id}",
      {:queue_dashboard_update, build_dashboard_payload(state)}
    )
  end

  defp build_dashboard_payload(state) do
    %{
      queue_id: state.queue_id,
      queue_name: state.queue_name,
      subdomain: state.subdomain,
      available_members: available_members_payload(state),
      waiting_calls: waiting_calls_payload(state),
      total_agents: state.total_agents
    }
  end

  # Only fields the dashboard actually consumes are exposed. Returning raw
  # Ecto schemas / GenServer state crashed Jason (it can't encode the
  # {microseconds, precision} tuple inside NaiveDateTime, or Ecto.Schema
  # internals), silently breaking the WebSocket channel so dashboards
  # never saw a single update.
  defp available_members_payload(state) do
    Enum.map(state.available, fn user_id ->
      case OrgMember.get_member_by_user_id_and_queue(user_id, state.subdomain, state.queue_id) do
        nil -> %{user_id: user_id, username: nil, presence: "Available"}
        member -> %{user_id: user_id, username: member.username, presence: "Available"}
      end
    end)
  end

  defp waiting_calls_payload(state) do
    Enum.flat_map(state.waiting, fn call_id ->
      case QueuedCall.snapshot(call_id) do
        {:ok, snap} -> [waiting_call_row(snap)]
        _ -> []
      end
    end)
  end

  defp waiting_call_row(snap) do
    %{
      from_user: Map.get(snap, :from_user),
      date_time: Map.get(snap, :date_time),
      attempting_to_connect: Map.get(snap, :attempting_to_connect, false),
      attempting_to_connect_to_member:
        case Map.get(snap, :attempting_to_connect_to_member) do
          nil -> nil
          member -> %{username: Map.get(member, :username)}
        end
    }
  end
end
