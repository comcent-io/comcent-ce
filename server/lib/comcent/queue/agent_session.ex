defmodule Comcent.Queue.AgentSession do
  @moduledoc """
  One process per agent per org. Owns the agent's queue-side state:
  presence, reservation, no-answer counters, and (when active) the dialer
  process for the current attempt.

  Key invariants
    * Exactly one attempt in flight at any time. `reservation != nil` iff a
      dialer is running for this agent.
    * Presence transitions that matter to queue scheduling happen inside this
      process. Presence becomes `"Reserved"` the moment `attempt/3` succeeds
      and becomes `"On Call"` atomically with clearing the reservation when
      the dialer reports the member answered. No external code path can race
      between those two states.
    * Presence updates are authoritative here. `OrgMember.update_member_*`
      DB writes are performed from this process so other processes see them
      via the standard PubSub presence channel.

  Outbound messages to the QueueScheduler for this attempt are cast to the
  scheduler's via_tuple: `:agent_busy` (on attempt start or answered),
  `:agent_available` (on Available restoration and logout-cleanup), and
  `{:attempt_finished, call_id, outcome}` (so the scheduler can drop the
  call from in-flight and re-match if `:failed`).
  """

  use GenServer
  require Logger

  alias Comcent.Queue.AgentSession.Dialer
  alias Comcent.Queue.QueuedCall
  alias Comcent.Repo.OrgMember
  alias Comcent.Repo.Queue

  @supervisor Comcent.QueueDynamicSupervisor
  @dialer_safety_margin_ms 2_000

  # Public API -----------------------------------------------------------------

  def child_spec(%{subdomain: subdomain, user_id: user_id} = attrs) do
    %{
      id: "#{__MODULE__}_#{subdomain}_#{user_id}",
      start: {__MODULE__, :start_link, [attrs]}
    }
  end

  def start_link(%{subdomain: subdomain, user_id: user_id} = attrs) do
    case GenServer.start_link(__MODULE__, attrs, name: via_tuple(subdomain, user_id)) do
      {:ok, pid} -> {:ok, pid}
      {:error, {:already_started, _pid}} -> :ignore
    end
  end

  def via_tuple(subdomain, user_id) do
    {:via, Horde.Registry, {Comcent.Registry, "agent_session_#{subdomain}_#{user_id}"}}
  end

  def ensure_started(member) when is_map(member) do
    with {:ok, subdomain} <- fetch_member_attr(member, :subdomain),
         {:ok, user_id} <- fetch_member_attr(member, :user_id) do
      attrs =
        member
        |> normalize_member_attrs()
        |> Map.put(:subdomain, subdomain)
        |> Map.put(:user_id, user_id)

      do_ensure_started(attrs)
    end
  end

  def start_all_active_sessions do
    OrgMember.list_active_members()
    |> Enum.each(&ensure_started/1)
  end

  @doc """
  Ask this agent to attempt the given call. Synchronous. Returns `{:ok,
  reservation_id}` on success (dialer started; presence flipped to
  `"Reserved"`) or `{:error, :unavailable}` if the agent has an active
  reservation, is not `"Available"`, or the queued call has gone.
  """
  def attempt(member, queue_id, call_id) do
    with {:ok, pid} <- ensure_started(member) do
      GenServer.call(pid, {:attempt, queue_id, call_id})
    end
  end

  @doc """
  Cancel any in-flight attempt for this agent tied to `call_id`. Used by
  the QueueScheduler when the customer hangs up before being bridged.
  The dialer hangs up its member legs and the agent returns to whatever
  presence makes sense (Busy for reject_delay, or Available).
  """
  def cancel_attempt(member, call_id, reason) do
    with {:ok, pid} <- ensure_started(member) do
      GenServer.call(pid, {:cancel_attempt, call_id, reason})
    end
  end

  def release(member, reservation_id) do
    with {:ok, pid} <- ensure_started(member) do
      GenServer.call(pid, {:release, reservation_id})
    end
  end

  # Back-compat cast from CallSession. Idempotent: if presence is already
  # "On Call" (atomically flipped by the dialer-answered path), this is a
  # no-op.
  def queue_member_answered(subdomain, user_id) do
    with {:ok, member} <- member_ref(subdomain, user_id),
         {:ok, pid} <- ensure_started(member) do
      GenServer.cast(pid, :queue_member_answered)
    end
  end

  def queue_member_rejected(subdomain, user_id, queue_id) do
    with {:ok, member} <- member_ref(subdomain, user_id),
         {:ok, pid} <- ensure_started(member) do
      GenServer.cast(pid, {:queue_member_rejected, queue_id})
    end
  end

  def queue_member_call_ended(subdomain, user_id, queue_id) do
    with {:ok, member} <- member_ref(subdomain, user_id),
         {:ok, pid} <- ensure_started(member) do
      GenServer.cast(pid, {:queue_member_call_ended, queue_id})
    end
  end

  def get_state(member) do
    with {:ok, pid} <- ensure_started(member) do
      GenServer.call(pid, :get_state)
    end
  end

  # GenServer callbacks --------------------------------------------------------

  @impl true
  def init(attrs) do
    Process.flag(:trap_exit, true)

    {:ok,
     %{
       subdomain: attrs.subdomain,
       user_id: attrs.user_id,
       username: Map.get(attrs, :username),
       org_id: Map.get(attrs, :org_id),
       presence: Map.get(attrs, :presence),
       reservation: nil,
       dialer: nil,
       no_answer_counts: %{},
       restore_timer_ref: nil
     }}
  end

  @impl true
  def handle_call(:get_state, _from, state), do: {:reply, state, state}

  def handle_call({:attempt, queue_id, call_id}, _from, state) do
    presence = current_presence(state)
    state = %{state | presence: presence}

    cond do
      state.reservation != nil ->
        {:reply, {:error, :unavailable}, state}

      presence != "Available" ->
        {:reply, {:error, {:presence, presence}}, state}

      true ->
        case start_attempt(state, queue_id, call_id) do
          {:ok, reservation_id, new_state} ->
            {:reply, {:ok, reservation_id}, new_state}

          {:error, reason} ->
            {:reply, {:error, reason}, state}
        end
    end
  end

  def handle_call({:cancel_attempt, call_id, reason}, _from, state) do
    case state.reservation do
      %{call_id: ^call_id} = reservation ->
        # The Dialer GenServer is blocked inside a synchronous `api originate`
        # on its ESL connection; sending it `{:cancel, _}` just queues a
        # message that can't be processed (and its hupall would serialize
        # behind the pending originate reply on the same socket anyway).
        # Fire the hupall from an independent one-shot ESL connection so the
        # ringing agent leg is cancelled right now — FS will then return
        # `-ERR` to the blocked originate and the Dialer unwinds on its own.
        hupall_attempt_out_of_band(reservation)

        new_state =
          state
          |> stop_dialer(reason)
          |> clear_reservation()
          |> restore_presence_after_failure()

        {:reply, :ok, new_state}

      _ ->
        {:reply, :ok, state}
    end
  end

  def handle_call({:release, reservation_id}, _from, state) do
    case state.reservation do
      %{id: ^reservation_id} ->
        new_state =
          state
          |> stop_dialer(:released)
          |> clear_reservation()
          |> maybe_mark_available("released")

        {:reply, :ok, new_state}

      _ ->
        {:reply, :ok, state}
    end
  end

  @impl true
  def handle_cast(:queue_member_answered, state) do
    {:noreply, set_presence_on_call(state)}
  end

  def handle_cast({:queue_member_rejected, queue_id}, state) do
    # A forked-dial originate creates N member-leg channels. When one answers
    # and the others get cancelled, CallSession fires queue_member_rejected
    # for each losing leg. If we let it overwrite "On Call" → "Busy" and
    # then restore "Busy" → "Available" after reject_delay, the agent is
    # advertised as Available while actively on a call. Only honour the
    # reject transition when the agent isn't already on a call.
    if state.presence == "On Call" do
      {:noreply, state}
    else
      {:noreply,
       schedule_queue_presence_restore(
         state,
         queue_id,
         "Busy",
         &OrgMember.update_member_presence_if_busy/3,
         &(&1.reject_delay_time || 0)
       )}
    end
  end

  def handle_cast({:queue_member_call_ended, queue_id}, state) do
    # Only meaningful when the agent is currently on a call. If state is
    # already Available / Wrap Up / something else, ignore the late event.
    if state.presence == "On Call" do
      {:noreply,
       schedule_queue_presence_restore(
         state,
         queue_id,
         "Wrap Up",
         &OrgMember.update_member_presence_if_wrap_up/3,
         &(&1.wrap_up_time || 0)
       )}
    else
      {:noreply, state}
    end
  end

  @impl true
  def handle_info({:dialer_answered, reservation_id, member_uuid}, state) do
    case state.reservation do
      %{id: ^reservation_id} = reservation ->
        QueuedCall.mark_answered(reservation.call_id)
        append_queued_span(reservation.call_id)
        QueuedCall.stop(reservation.call_id)
        notify_scheduler(state, reservation, {:attempt_finished, reservation.call_id, :answered})

        new_state =
          state
          |> cancel_attempt_timer()
          |> clear_dialer_monitor()
          |> clear_reservation()
          |> reset_no_answer_count(reservation.queue_id)
          |> set_presence_on_call()

        _ = member_uuid
        {:noreply, new_state}

      _ ->
        Logger.info(
          "AgentSession #{state.subdomain}/#{state.user_id}: stale dialer_answered #{inspect(reservation_id)}"
        )

        {:noreply, state}
    end
  end

  def handle_info({:dialer_failed, reservation_id, reason}, state) do
    case state.reservation do
      %{id: ^reservation_id} = reservation ->
        QueuedCall.mark_failed(reservation.call_id, reason)

        {next_state, logged_out?} =
          state
          |> cancel_attempt_timer()
          |> clear_dialer_monitor()
          |> increment_no_answer(reservation.queue_id)
          |> maybe_force_logout(reservation.queue_id)

        next_state = clear_reservation(next_state)

        next_state =
          if logged_out? do
            %{next_state | presence: "Logged Out"}
          else
            restore_presence_after_failure(next_state)
          end

        notify_scheduler(state, reservation, {:attempt_finished, reservation.call_id, :failed})
        {:noreply, next_state}

      _ ->
        Logger.info(
          "AgentSession #{state.subdomain}/#{state.user_id}: stale dialer_failed #{inspect(reservation_id)} reason=#{inspect(reason)}"
        )

        {:noreply, state}
    end
  end

  def handle_info({:attempt_timeout, reservation_id}, state) do
    case state.reservation do
      %{id: ^reservation_id} = reservation ->
        QueuedCall.mark_timed_out(reservation.call_id)

        {next_state, logged_out?} =
          state
          |> stop_dialer(:attempt_timeout)
          |> cancel_attempt_timer()
          |> clear_dialer_monitor()
          |> increment_no_answer(reservation.queue_id)
          |> maybe_force_logout(reservation.queue_id)

        next_state = clear_reservation(next_state)

        next_state =
          if logged_out? do
            %{next_state | presence: "Logged Out"}
          else
            restore_presence_after_failure(next_state)
          end

        notify_scheduler(state, reservation, {:attempt_finished, reservation.call_id, :timed_out})
        {:noreply, next_state}

      _ ->
        {:noreply, state}
    end
  end

  def handle_info({:DOWN, ref, :process, _pid, reason}, %{dialer: %{ref: ref}} = state) do
    case state.reservation do
      %{id: reservation_id} ->
        send(self(), {:dialer_failed, reservation_id, {:dialer_crashed, reason}})
        {:noreply, %{state | dialer: nil}}

      _ ->
        {:noreply, %{state | dialer: nil}}
    end
  end

  def handle_info({:restore_presence, restore_fun, expected_presence}, state) do
    state = %{state | restore_timer_ref: nil}

    if current_presence(state) == expected_presence do
      restore_fun.(state.subdomain, state.user_id)
      {:noreply, %{state | presence: "Available"}}
    else
      {:noreply, %{state | presence: current_presence(state) || state.presence}}
    end
  end

  def handle_info({:EXIT, _pid, _reason}, state), do: {:noreply, state}

  def handle_info(_msg, state), do: {:noreply, state}

  # Internals: attempt lifecycle ----------------------------------------------

  defp start_attempt(state, queue_id, call_id) do
    case QueuedCall.snapshot(call_id) do
      {:ok, snap} ->
        timeout_ms = attempt_timeout_ms(queue_id, state.subdomain)

        attempt_params = %{
          owner: self(),
          reservation_id: reservation_id(),
          member_username: state.username,
          subdomain: state.subdomain,
          call_id: call_id,
          customer_uuid: snap.call_id,
          freeswitch_ip: snap.freeswitch_ip_address,
          from_user: snap.from_user,
          from_name: snap.from_name,
          to_user: snap.to_user,
          to_name: snap.to_name,
          comcent_context_id: snap.comcent_context_id,
          queue_id: queue_id,
          originate_timeout_ms: max(timeout_ms - @dialer_safety_margin_ms, 1_000)
        }

        case Dialer.start_link(attempt_params) do
          {:ok, dialer_pid} ->
            ref = Process.monitor(dialer_pid)

            timer =
              Process.send_after(
                self(),
                {:attempt_timeout, attempt_params.reservation_id},
                timeout_ms
              )

            reservation = %{
              id: attempt_params.reservation_id,
              queue_id: queue_id,
              call_id: call_id,
              freeswitch_ip: snap.freeswitch_ip_address
            }

            QueuedCall.begin_attempt(call_id, member_snapshot(state), reservation.id, 1)
            notify_scheduler(state, reservation, :agent_busy)

            new_state = %{
              state
              | reservation: reservation,
                dialer: %{pid: dialer_pid, ref: ref, timer: timer},
                presence: "Reserved"
            }

            {:ok, reservation.id, new_state}

          {:error, reason} ->
            Logger.error(
              "AgentSession #{state.subdomain}/#{state.user_id}: dialer start failed #{inspect(reason)}"
            )

            {:error, {:dialer_start_failed, reason}}
        end

      :ignore ->
        {:error, :call_not_found}
    end
  end

  defp stop_dialer(%{dialer: nil} = state, _reason), do: state

  defp stop_dialer(%{dialer: %{pid: pid}} = state, reason) do
    if Process.alive?(pid), do: Dialer.cancel(pid, reason)
    state
  end

  defp hupall_attempt_out_of_band(%{freeswitch_ip: fs_ip, call_id: call_id})
       when is_binary(fs_ip) and is_binary(call_id) do
    Task.Supervisor.start_child(Comcent.TaskSupervisor, fn ->
      cmd = "hupall NORMAL_CLEARING comcent_dialed_for_call_id #{call_id}"

      case SwitchX.Connection.Inbound.start_link(host: fs_ip, port: 8021) do
        {:ok, conn} ->
          try do
            with {:ok, "Accepted"} <- SwitchX.auth(conn, "ClueCon") do
              _ = SwitchX.api(conn, cmd)
            end
          after
            _ = SwitchX.close(conn)
          end

        _ ->
          :ok
      end
    end)

    :ok
  end

  defp hupall_attempt_out_of_band(_), do: :ok

  defp clear_dialer_monitor(%{dialer: nil} = state), do: state

  defp clear_dialer_monitor(%{dialer: %{ref: ref}} = state) do
    Process.demonitor(ref, [:flush])
    %{state | dialer: nil}
  end

  defp cancel_attempt_timer(%{dialer: %{timer: timer} = dialer} = state) when timer != nil do
    Process.cancel_timer(timer)
    %{state | dialer: %{dialer | timer: nil}}
  end

  defp cancel_attempt_timer(state), do: state

  defp clear_reservation(state), do: %{state | reservation: nil}

  defp reset_no_answer_count(state, queue_id) do
    %{state | no_answer_counts: Map.put(state.no_answer_counts, queue_id, 0)}
  end

  defp increment_no_answer(state, queue_id) do
    %{
      state
      | no_answer_counts: Map.update(state.no_answer_counts, queue_id, 1, &(&1 + 1))
    }
  end

  defp maybe_force_logout(state, queue_id) do
    queue = Queue.get_queue_by_id(queue_id, state.subdomain)
    max_no_answers = queue && queue.max_no_answers
    count = Map.get(state.no_answer_counts, queue_id, 0)

    if is_integer(max_no_answers) and max_no_answers > 0 and count >= max_no_answers do
      Logger.info(
        "AgentSession #{state.username || state.user_id}: reached max no-answers (#{max_no_answers}) on queue #{queue_id}, forcing Logged Out"
      )

      OrgMember.force_member_logged_out(state.subdomain, state.user_id)
      {state, true}
    else
      {state, false}
    end
  end

  defp set_presence_on_call(state) do
    case current_presence(state) do
      "Logged Out" ->
        %{state | presence: "Logged Out"}

      _ ->
        state = cancel_restore_timer(state)
        OrgMember.update_member_presence_to_on_call(state.subdomain, state.user_id)
        %{state | presence: "On Call"}
    end
  end

  defp restore_presence_after_failure(state) do
    case state.reservation do
      %{queue_id: queue_id} ->
        schedule_queue_presence_restore(
          state,
          queue_id,
          "Busy",
          &OrgMember.update_member_presence_if_busy/3,
          &(&1.reject_delay_time || 0)
        )

      _ ->
        maybe_mark_available(state, "attempt_complete")
    end
  end

  defp maybe_mark_available(state, _reason) do
    case current_presence(state) do
      "Logged Out" -> %{state | presence: "Logged Out"}
      "On Call" -> state
      "Busy" -> state
      "Wrap Up" -> state
      _other -> %{state | presence: "Available"}
    end
  end

  defp schedule_queue_presence_restore(state, queue_id, presence, restore_fun_member, delay_fun) do
    state = cancel_restore_timer(state)

    if current_presence(state) == "Logged Out" do
      %{state | presence: "Logged Out"}
    else
      OrgMember.update_member_presence(state.subdomain, state.user_id, presence)
      queue = Queue.get_queue_by_id(queue_id, state.subdomain)
      delay_ms = max(delay_fun.(queue) * 1_000, 0)

      timer_ref =
        Process.send_after(
          self(),
          {:restore_presence,
           fn subdomain, user_id -> restore_fun_member.(subdomain, user_id, "Available") end,
           presence},
          delay_ms
        )

      %{state | presence: presence, restore_timer_ref: timer_ref}
    end
  end

  defp cancel_restore_timer(%{restore_timer_ref: nil} = state), do: state

  defp cancel_restore_timer(%{restore_timer_ref: ref} = state) do
    Process.cancel_timer(ref)
    %{state | restore_timer_ref: nil}
  end

  defp attempt_timeout_ms(queue_id, subdomain) do
    # Whole-attempt budget: ring + answer + bridge. Must be generous enough
    # that a legitimate bridge isn't killed by a race between the answer
    # event and this timer. `@dialer_safety_margin_ms` below keeps the
    # dialer's originate_timeout strictly shorter than this.
    case Queue.get_queue_by_id(queue_id, subdomain) do
      %{reject_delay_time: delay} when is_integer(delay) ->
        max(10_000, delay * 1_000 + 8_000)

      _ ->
        10_000
    end
  end

  defp append_queued_span(call_id) do
    case QueuedCall.snapshot(call_id) do
      {:ok, %{comcent_context_id: ctx, date_time: started, from_user: party} = snap}
      when is_binary(ctx) ->
        Comcent.CallSession.append_story_span(ctx, %{
          type: "QUEUED",
          call_story_id: ctx,
          channel_id: snap.call_id,
          start_at: started,
          end_at: DateTime.utc_now(),
          current_party: party
        })

      _ ->
        :ok
    end
  end

  defp notify_scheduler(state, reservation, message) do
    scheduler = Comcent.QueueScheduler.via_tuple(reservation.queue_id, state.subdomain)

    payload =
      case message do
        :agent_busy ->
          {:agent_busy, state.user_id, reservation.call_id}

        :agent_available ->
          {:agent_available, state.user_id}

        {:attempt_finished, call_id, outcome} ->
          {:attempt_finished, state.user_id, call_id, outcome}
      end

    try do
      GenServer.cast(scheduler, payload)
    catch
      :exit, _ -> :ok
    end
  end

  defp member_snapshot(state) do
    %{
      subdomain: state.subdomain,
      user_id: state.user_id,
      username: state.username,
      org_id: state.org_id
    }
  end

  defp current_presence(state) do
    OrgMember.get_current_presence(state.subdomain, state.user_id) || state.presence
  end

  defp reservation_id do
    System.unique_integer([:positive, :monotonic]) |> Integer.to_string()
  end

  defp do_ensure_started(%{subdomain: subdomain, user_id: user_id} = member) do
    case Horde.DynamicSupervisor.start_child(
           @supervisor,
           {__MODULE__, Map.take(member, [:subdomain, :user_id, :username, :org_id, :presence])}
         ) do
      {:ok, pid} ->
        {:ok, pid}

      {:error, {:already_started, pid}} ->
        {:ok, pid}

      :ignore ->
        case Horde.Registry.lookup(Comcent.Registry, "agent_session_#{subdomain}_#{user_id}") do
          [{pid, _}] -> {:ok, pid}
          [] -> {:error, :not_found}
        end

      error ->
        error
    end
  end

  defp member_ref(subdomain, user_id) when is_binary(subdomain) and is_binary(user_id) do
    {:ok,
     %{
       subdomain: subdomain,
       user_id: user_id,
       presence: OrgMember.get_current_presence(subdomain, user_id)
     }}
  end

  defp normalize_member_attrs(member) do
    %{
      username: member_attr(member, :username),
      org_id: member_attr(member, :org_id),
      presence: member_attr(member, :presence)
    }
  end

  defp fetch_member_attr(member, key) do
    case member_attr(member, key) do
      nil -> {:error, {:missing_member_attr, key}}
      value -> {:ok, value}
    end
  end

  defp member_attr(member, key, default \\ nil) do
    Map.get(member, key, Map.get(member, Atom.to_string(key), default))
  end
end
