defmodule Comcent.Queue.QueuedCall do
  @moduledoc """
  Per-queued-call runtime state.

  One process per customer waiting in a queue. Lives from `QUEUE_ENQUEUED`
  to the moment the customer is either connected to an agent or abandons
  the call.

  Responsibilities
    * Track whether an attempt is currently in flight and which agent it is
      targeting.
    * Emit `QUEUE_*` story events to the associated `CallSession` so the
      call story is complete end-to-end.
    * Remember the most recent attempt so the scheduler can avoid an
      immediate retry on the same agent (`eligible_agents/2`).
  """

  use GenServer, restart: :transient

  alias Comcent.CallSession
  alias Comcent.Queue.QueuedCall.Registry

  # Public API -----------------------------------------------------------------

  def start_link(call_details) do
    GenServer.start_link(__MODULE__, call_details, name: Registry.via(call_details.call_id))
  end

  def child_spec(call_details) do
    %{
      id: {__MODULE__, call_details.call_id},
      start: {__MODULE__, :start_link, [call_details]},
      restart: :transient,
      type: :worker
    }
  end

  def start(call_details) do
    {:ok, _pid} = Registry.start_call(call_details)
    snapshot(call_details.call_id)
  end

  def snapshot(call_id), do: safe_call(call_id, :snapshot, :ignore)

  def begin_attempt(call_id, member, reservation_id, expected_count \\ 1) do
    safe_call(call_id, {:begin_attempt, member, reservation_id, expected_count}, :ignore)
  end

  def mark_answered(call_id), do: safe_call(call_id, :mark_answered, :ignore)

  def mark_failed(call_id, reason), do: safe_call(call_id, {:mark_failed, reason}, :ignore)

  def mark_timed_out(call_id), do: safe_call(call_id, :mark_timed_out, :ignore)

  @doc """
  Returns the subset of `candidate_user_ids` that are eligible to be tried
  next. Currently excludes the agent of the most recent attempt so the same
  agent is not dialed twice back-to-back — if they are the only candidate,
  they remain eligible.
  """
  def eligible_agents(call_id, candidate_user_ids) do
    safe_call(call_id, {:eligible_agents, candidate_user_ids}, candidate_user_ids)
  end

  def stop(call_id) do
    case Registry.whereis(call_id) do
      nil -> :ok
      pid -> GenServer.stop(pid, :normal)
    end
  end

  # GenServer callbacks --------------------------------------------------------

  @impl true
  def init(call_details) do
    emit_event(call_details, "QUEUE_ENQUEUED", %{
      queue_id: call_details.queue_id,
      queue_name: call_details.queue_name
    })

    {:ok,
     call_details
     |> Map.put_new(:attempt_sequence, 0)
     |> Map.put_new(:current_attempt_number, nil)
     |> Map.put_new(:attempting_to_connect, false)
     |> Map.put_new(:attempting_to_connect_to_member, nil)
     |> Map.put_new(:previous_attempt_to_connect_to_member, nil)
     |> Map.put_new(:attempt_lock_id, nil)
     |> Map.put_new(:expected_member_channel_count, 0)}
  end

  @impl true
  def handle_call(:snapshot, _from, state), do: {:reply, {:ok, state}, state}

  def handle_call({:begin_attempt, member, reservation_id, expected_count}, _from, state) do
    attempt_number = (state.attempt_sequence || 0) + 1

    new_state =
      state
      |> Map.put(:attempting_to_connect, true)
      |> Map.put(:attempting_to_connect_to_member, member)
      |> Map.put(:expected_member_channel_count, expected_count)
      |> Map.put(:attempt_lock_id, reservation_id)
      |> Map.put(:attempt_sequence, attempt_number)
      |> Map.put(:current_attempt_number, attempt_number)

    emit_event(new_state, "QUEUE_ATTEMPT_STARTED", %{
      queue_id: new_state.queue_id,
      queue_name: new_state.queue_name,
      member_username: member.username,
      reservation_id: reservation_id,
      expected_channel_count: expected_count,
      attempt_number: attempt_number
    })

    {:reply, {:ok, new_state}, new_state}
  end

  def handle_call(:mark_answered, _from, state) do
    if state.attempting_to_connect and state.attempting_to_connect_to_member != nil do
      emit_event(state, "QUEUE_AGENT_ANSWERED", %{
        queue_id: state.queue_id,
        queue_name: state.queue_name,
        member_username: state.attempting_to_connect_to_member.username,
        reservation_id: state.attempt_lock_id,
        attempt_number: state.current_attempt_number
      })

      {:reply, {:ok, state}, state}
    else
      {:reply, :ignore, state}
    end
  end

  def handle_call({:mark_failed, reason}, _from, state) do
    if state.attempting_to_connect and state.attempting_to_connect_to_member != nil do
      emit_event(state, "QUEUE_ATTEMPT_FAILED", %{
        queue_id: state.queue_id,
        queue_name: state.queue_name,
        member_username: state.attempting_to_connect_to_member.username,
        reservation_id: state.attempt_lock_id,
        attempt_number: state.current_attempt_number,
        reason: inspect(reason)
      })

      {:reply, {:ok, reset_attempt_state(state)}, reset_attempt_state(state)}
    else
      {:reply, :ignore, state}
    end
  end

  def handle_call(:mark_timed_out, _from, state) do
    if state.attempting_to_connect and state.attempting_to_connect_to_member != nil do
      emit_event(state, "QUEUE_ATTEMPT_TIMED_OUT", %{
        queue_id: state.queue_id,
        queue_name: state.queue_name,
        member_username: state.attempting_to_connect_to_member.username,
        reservation_id: state.attempt_lock_id,
        attempt_number: state.current_attempt_number
      })

      {:reply, {:ok, reset_attempt_state(state)}, reset_attempt_state(state)}
    else
      {:reply, :ignore, state}
    end
  end

  def handle_call({:eligible_agents, candidates}, _from, state) do
    exclude = state.previous_attempt_to_connect_to_member

    filtered =
      if exclude == nil do
        candidates
      else
        case Enum.reject(candidates, fn id -> id == exclude.user_id end) do
          [] -> candidates
          others -> others
        end
      end

    {:reply, filtered, state}
  end

  # Internals ------------------------------------------------------------------

  defp reset_attempt_state(state) do
    state
    |> Map.put(:previous_attempt_to_connect_to_member, state.attempting_to_connect_to_member)
    |> Map.put(:attempting_to_connect, false)
    |> Map.put(:attempting_to_connect_to_member, nil)
    |> Map.put(:attempt_lock_id, nil)
    |> Map.put(:expected_member_channel_count, 0)
    |> Map.put(:current_attempt_number, nil)
  end

  defp emit_event(state, type, metadata) do
    CallSession.append_story_event(state.comcent_context_id, %{
      type: type,
      call_story_id: state.comcent_context_id,
      channel_id: state.call_id,
      occurred_at: DateTime.utc_now(),
      current_party: state.from_user,
      metadata: metadata
    })
  end

  defp safe_call(call_id, message, default) do
    GenServer.call(Registry.via(call_id), message)
  catch
    :exit, {:noproc, _} -> default
    :exit, {{:noproc, _}, _} -> default
  end
end
