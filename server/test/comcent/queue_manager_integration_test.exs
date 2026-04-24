defmodule Comcent.QueueManager.IntegrationTest do
  @moduledoc """
  End-to-end coverage for the actor-based queue path.

  Scenarios exercise `QueueScheduler`, `AgentSession`, and `QueuedCall`
  together with the `AgentSession.Dialer` stubbed, so we don't need a
  running FreeSWITCH.
  """

  use Comcent.DataCase

  import Mock

  alias Comcent.Queue.AgentSession
  alias Comcent.Queue.QueuedCall
  alias Comcent.QueueManager.QueuedCallDetails
  alias Comcent.QueueScheduler

  @subdomain "acme"
  @queue_id "queue-1"

  setup do
    on_exit(fn -> cleanup([@subdomain], ["user-1", "user-2"], ["call-1", "call-2"]) end)
    :ok
  end

  defp cleanup(subdomains, user_ids, call_ids) do
    for subdomain <- subdomains, user_id <- user_ids do
      case Horde.Registry.lookup(Comcent.Registry, "agent_session_#{subdomain}_#{user_id}") do
        [{pid, _}] -> GenServer.stop(pid, :normal)
        [] -> :ok
      end
    end

    for call_id <- call_ids, do: QueuedCall.stop(call_id)
    :ok
  end

  defp call(id),
    do: %QueuedCallDetails{
      call_id: id,
      comcent_context_id: id,
      subdomain: @subdomain,
      queue_id: @queue_id,
      queue_name: "sales",
      freeswitch_ip_address: "127.0.0.1",
      date_time: DateTime.utc_now(),
      to_user: "4000",
      to_name: "sales",
      from_user: "+15551234567",
      from_name: "Caller"
    }

  defp member(user_id),
    do: %{user_id: user_id, username: user_id, subdomain: @subdomain, presence: "Available"}

  defp wait_until(fun, timeout \\ 800, step \\ 20) do
    deadline = System.monotonic_time(:millisecond) + timeout

    loop = fn loop ->
      try do
        fun.()
      rescue
        ExUnit.AssertionError ->
          if System.monotonic_time(:millisecond) < deadline do
            Process.sleep(step)
            loop.(loop)
          else
            reraise ExUnit.AssertionError, __STACKTRACE__
          end
      end
    end

    loop.(loop)
  end

  defp run_with_mocks(user_ids, fun) do
    {:ok, presence} =
      Agent.start_link(fn -> Map.new(user_ids, fn id -> {id, "Available"} end) end)

    parent = self()

    with_mocks([
      {Comcent.Repo.OrgMember, [:passthrough],
       [
         get_current_presence: fn @subdomain, user_id ->
           Agent.get(presence, &Map.get(&1, user_id))
         end,
         get_member_by_user_id_and_queue: fn user_id, @subdomain, @queue_id ->
           if Enum.member?(user_ids, user_id) do
             %{user_id: user_id, username: user_id, subdomain: @subdomain, presence: "Available"}
           else
             nil
           end
         end,
         update_member_presence: fn @subdomain, user_id, v ->
           Agent.update(presence, &Map.put(&1, user_id, v))
           :ok
         end,
         update_member_presence_to_on_call: fn @subdomain, user_id ->
           Agent.update(presence, &Map.put(&1, user_id, "On Call"))
           :ok
         end,
         update_member_presence_if_busy: fn @subdomain, user_id, v ->
           Agent.update(presence, &Map.put(&1, user_id, v))
           :ok
         end,
         update_member_presence_if_wrap_up: fn @subdomain, user_id, v ->
           Agent.update(presence, &Map.put(&1, user_id, v))
           :ok
         end,
         force_member_logged_out: fn @subdomain, user_id ->
           Agent.update(presence, &Map.put(&1, user_id, "Logged Out"))
           :ok
         end,
         list_active_members: fn -> [] end
       ]},
      {Comcent.Repo.Queue, [:passthrough],
       [
         get_queue_by_id: fn @queue_id, @subdomain ->
           %{
             id: @queue_id,
             name: "sales",
             reject_delay_time: 0,
             wrap_up_time: 0,
             max_no_answers: 0
           }
         end,
         get_active_agents: fn @queue_id, @subdomain ->
           Enum.map(user_ids, fn id ->
             %{user_id: id, username: id, subdomain: @subdomain, presence: "Available"}
           end)
         end,
         get_total_agents_in_queue: fn @queue_id, @subdomain -> length(user_ids) end
       ]},
      {Comcent.CallSession, [],
       append_story_event: fn _id, entry ->
         send(parent, {:event, entry})
         :ok
       end,
       append_story_span: fn _id, span ->
         send(parent, {:span, span})
         :ok
       end},
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
      fun.()
    end
  end

  defp start_scheduler do
    {:ok, pid} =
      GenServer.start_link(
        QueueScheduler,
        %{queue_id: @queue_id, subdomain: @subdomain},
        name: QueueScheduler.via_tuple(@queue_id, @subdomain)
      )

    :sys.get_state(pid)
    pid
  end

  defp stop_scheduler(pid) do
    if Process.alive?(pid), do: GenServer.stop(pid, :normal)
  end

  test "scenario 1: seeded available agent picks up an enqueued call" do
    run_with_mocks(["user-1"], fn ->
      sched = start_scheduler()

      QueueScheduler.add_waiting_call(sched, call("call-1"))

      assert_receive {:dialer_started, attempt}, 500
      assert attempt.call_id == "call-1"

      {:ok, agent_pid} = AgentSession.ensure_started(member("user-1"))
      send(agent_pid, {:dialer_answered, attempt.reservation_id, "fs-uuid-1"})

      wait_until(fn ->
        state = QueueScheduler.get_state(sched)
        assert state.waiting == []
        assert map_size(state.in_flight) == 0
      end)

      stop_scheduler(sched)
    end)
  end

  test "scenario 2: no agents -> call waits; presence Available triggers match" do
    run_with_mocks([], fn ->
      sched = start_scheduler()

      QueueScheduler.add_waiting_call(sched, call("call-1"))

      state = QueueScheduler.get_state(sched)
      assert state.waiting == ["call-1"]
      assert map_size(state.in_flight) == 0

      # simulate admin adding an agent who is Available
      QueueScheduler.add_member(sched, member("user-1"))

      # membership check gates addition; since our mock returns the member,
      # they land in available and the match fires.
      assert_receive {:dialer_started, attempt}, 500
      assert attempt.call_id == "call-1"

      stop_scheduler(sched)
    end)
  end

  test "scenario 3: customer hangs up while attempt is in flight" do
    run_with_mocks(["user-1"], fn ->
      sched = start_scheduler()

      QueueScheduler.add_waiting_call(sched, call("call-1"))
      assert_receive {:dialer_started, _attempt}, 500

      QueueScheduler.call_hung_up(sched, "call-1")

      wait_until(fn ->
        state = QueueScheduler.get_state(sched)
        assert state.waiting == []
        assert map_size(state.in_flight) == 0
      end)

      stop_scheduler(sched)
    end)
  end
end
