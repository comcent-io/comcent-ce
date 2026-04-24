defmodule Comcent.Queue.AgentSessionTest do
  use Comcent.DataCase

  import Mock

  alias Comcent.Queue.AgentSession
  alias Comcent.Queue.QueuedCall
  alias Comcent.QueueManager.QueuedCallDetails

  @member %{
    user_id: "user-1",
    username: "agent1",
    subdomain: "acme",
    presence: "Available"
  }

  setup do
    QueuedCall.stop("call-1")
    stop_session(@member)

    on_exit(fn ->
      QueuedCall.stop("call-1")
      stop_session(@member)
    end)

    :ok
  end

  defp stop_session(member) do
    case Horde.Registry.lookup(
           Comcent.Registry,
           "agent_session_#{member.subdomain}_#{member.user_id}"
         ) do
      [{pid, _}] -> GenServer.stop(pid, :normal)
      [] -> :ok
    end
  end

  defp presence_agent_get(agent), do: Agent.get(agent, & &1)
  defp presence_agent_set(agent, value), do: Agent.update(agent, fn _ -> value end)

  defp seed_queued_call do
    call = %QueuedCallDetails{
      call_id: "call-1",
      comcent_context_id: "call-1",
      subdomain: "acme",
      queue_id: "queue-1",
      queue_name: "sales",
      from_user: "+15551234567",
      from_name: "Caller",
      to_user: "4000",
      to_name: "Sales",
      freeswitch_ip_address: "127.0.0.1",
      date_time: DateTime.utc_now()
    }

    {:ok, _} = QueuedCall.start(call)
  end

  describe "attempt/3" do
    test "reserves the agent, flips presence to Reserved, and starts a dialer" do
      parent = self()
      {:ok, presence} = Agent.start_link(fn -> "Available" end)

      with_mocks([
        {Comcent.Repo.OrgMember, [:passthrough],
         [
           get_current_presence: fn "acme", "user-1" -> presence_agent_get(presence) end,
           update_member_presence: fn _, _, _ -> :ok end,
           update_member_presence_to_on_call: fn "acme", "user-1" ->
             presence_agent_set(presence, "On Call")
             :ok
           end,
           update_member_presence_if_busy: fn _, _, _ -> :ok end,
           update_member_presence_if_wrap_up: fn _, _, _ -> :ok end,
           force_member_logged_out: fn _, _ -> :ok end
         ]},
        {Comcent.Repo.Queue, [:passthrough],
         [
           get_queue_by_id: fn "queue-1", "acme" ->
             %{reject_delay_time: 0, wrap_up_time: 0, max_no_answers: 3}
           end
         ]},
        {Comcent.CallSession, [],
         append_story_event: fn _id, _entry -> :ok end,
         append_story_span: fn _id, _span -> :ok end},
        {Comcent.Queue.AgentSession.Dialer, [],
         start_link: fn attempt ->
           send(parent, {:dialer_started, attempt})
           {:ok, spawn(fn -> Process.sleep(:infinity) end)}
         end,
         cancel: fn pid, _reason ->
           if Process.alive?(pid), do: Process.exit(pid, :kill)
           :ok
         end}
      ]) do
        seed_queued_call()

        assert {:ok, reservation_id} = AgentSession.attempt(@member, "queue-1", "call-1")
        assert is_binary(reservation_id)

        assert_receive {:dialer_started, attempt}
        assert attempt.reservation_id == reservation_id
        assert attempt.member_username == "agent1"
        assert attempt.call_id == "call-1"

        state = AgentSession.get_state(@member)
        assert state.presence == "Reserved"
        assert state.reservation.id == reservation_id
        assert state.reservation.call_id == "call-1"

        assert {:error, _} = AgentSession.attempt(@member, "queue-1", "call-1")
      end
    end

    test "refuses attempt when presence is not Available" do
      {:ok, presence} = Agent.start_link(fn -> "On Call" end)

      with_mocks([
        {Comcent.Repo.OrgMember, [:passthrough],
         [
           get_current_presence: fn "acme", "user-1" -> presence_agent_get(presence) end,
           update_member_presence: fn _, _, _ -> :ok end,
           update_member_presence_to_on_call: fn _, _ -> :ok end,
           update_member_presence_if_busy: fn _, _, _ -> :ok end,
           update_member_presence_if_wrap_up: fn _, _, _ -> :ok end
         ]},
        {Comcent.Repo.Queue, [:passthrough],
         [
           get_queue_by_id: fn "queue-1", "acme" ->
             %{reject_delay_time: 0, wrap_up_time: 0, max_no_answers: 0}
           end
         ]}
      ]) do
        assert {:error, {:presence, "On Call"}} =
                 AgentSession.attempt(@member, "queue-1", "call-1")
      end
    end
  end

  describe "dialer outcomes" do
    test "dialer_answered atomically flips presence to On Call and clears reservation" do
      parent = self()
      {:ok, presence} = Agent.start_link(fn -> "Available" end)

      with_mocks([
        {Comcent.Repo.OrgMember, [:passthrough],
         [
           get_current_presence: fn "acme", "user-1" -> presence_agent_get(presence) end,
           update_member_presence_to_on_call: fn "acme", "user-1" ->
             presence_agent_set(presence, "On Call")
             :ok
           end,
           update_member_presence: fn _, _, _ -> :ok end,
           update_member_presence_if_busy: fn _, _, _ -> :ok end,
           update_member_presence_if_wrap_up: fn _, _, _ -> :ok end,
           force_member_logged_out: fn _, _ -> :ok end
         ]},
        {Comcent.Repo.Queue, [:passthrough],
         [
           get_queue_by_id: fn "queue-1", "acme" ->
             %{reject_delay_time: 0, wrap_up_time: 0, max_no_answers: 0}
           end
         ]},
        {Comcent.CallSession, [],
         append_story_event: fn _id, _entry -> :ok end,
         append_story_span: fn _id, _span -> :ok end},
        {Comcent.Queue.AgentSession.Dialer, [],
         start_link: fn attempt ->
           send(parent, {:dialer_started, attempt})
           {:ok, spawn(fn -> Process.sleep(:infinity) end)}
         end,
         cancel: fn _pid, _ -> :ok end}
      ]) do
        seed_queued_call()

        {:ok, reservation_id} = AgentSession.attempt(@member, "queue-1", "call-1")
        assert_receive {:dialer_started, _}

        {:ok, session} = AgentSession.ensure_started(@member)
        send(session, {:dialer_answered, reservation_id, "member-uuid"})

        Process.sleep(50)

        state = AgentSession.get_state(@member)
        assert state.reservation == nil
        assert state.presence == "On Call"
        assert state.no_answer_counts["queue-1"] == 0
      end
    end

    test "dialer_failed increments no-answer count and forces logout at max" do
      parent = self()
      {:ok, presence} = Agent.start_link(fn -> "Available" end)

      with_mocks([
        {Comcent.Repo.OrgMember, [:passthrough],
         [
           get_current_presence: fn "acme", "user-1" -> presence_agent_get(presence) end,
           update_member_presence: fn _, _, p ->
             presence_agent_set(presence, p)
             :ok
           end,
           update_member_presence_if_busy: fn _, _, _ -> :ok end,
           update_member_presence_if_wrap_up: fn _, _, _ -> :ok end,
           update_member_presence_to_on_call: fn _, _ -> :ok end,
           force_member_logged_out: fn _, _ ->
             presence_agent_set(presence, "Logged Out")
             send(parent, :forced_logout)
             :ok
           end
         ]},
        {Comcent.Repo.Queue, [:passthrough],
         [
           get_queue_by_id: fn "queue-1", "acme" ->
             %{reject_delay_time: 0, wrap_up_time: 0, max_no_answers: 1}
           end
         ]},
        {Comcent.CallSession, [],
         append_story_event: fn _id, _entry -> :ok end,
         append_story_span: fn _id, _span -> :ok end},
        {Comcent.Queue.AgentSession.Dialer, [],
         start_link: fn _attempt -> {:ok, spawn(fn -> Process.sleep(:infinity) end)} end,
         cancel: fn _pid, _ -> :ok end}
      ]) do
        seed_queued_call()

        {:ok, reservation_id} = AgentSession.attempt(@member, "queue-1", "call-1")
        {:ok, session} = AgentSession.ensure_started(@member)

        send(session, {:dialer_failed, reservation_id, :member_rejected})

        assert_receive :forced_logout, 500

        state = AgentSession.get_state(@member)
        assert state.reservation == nil
        assert state.no_answer_counts["queue-1"] == 1
        assert state.presence == "Logged Out"
      end
    end
  end
end
