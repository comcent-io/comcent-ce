defmodule Comcent.Queue.QueuedCallTest do
  use Comcent.DataCase

  import Mock

  alias Comcent.Queue.QueuedCall
  alias Comcent.QueueManager.QueuedCallDetails

  setup do
    on_exit(fn -> QueuedCall.stop("queue-call-1") end)
    :ok
  end

  defp mocks(do: block) do
    with_mocks([
      {Comcent.CallSession, [], append_story_event: fn _id, _entry -> :ok end}
    ]) do
      block
    end
  end

  defp sample_call do
    %QueuedCallDetails{
      call_id: "queue-call-1",
      comcent_context_id: "queue-call-1",
      subdomain: "acme",
      queue_id: "queue-1",
      queue_name: "sales",
      from_user: "+15551234567"
    }
  end

  test "start emits QUEUE_ENQUEUED and returns a snapshot" do
    parent = self()

    with_mocks([
      {Comcent.CallSession, [],
       append_story_event: fn _id, entry ->
         send(parent, {:event, entry})
         :ok
       end}
    ]) do
      assert {:ok, snap} = QueuedCall.start(sample_call())
      assert snap.call_id == "queue-call-1"
      assert snap.attempting_to_connect == false

      assert_receive {:event, %{type: "QUEUE_ENQUEUED"}}
    end
  end

  test "begin_attempt flips attempting_to_connect and records reservation" do
    mocks do
      {:ok, _} = QueuedCall.start(sample_call())

      member = %{user_id: "user-1", username: "agent1"}

      assert {:ok, state} =
               QueuedCall.begin_attempt("queue-call-1", member, "res-1", 1)

      assert state.attempting_to_connect
      assert state.attempt_lock_id == "res-1"
      assert state.current_attempt_number == 1
      assert state.attempting_to_connect_to_member.username == "agent1"
    end
  end

  test "mark_failed emits QUEUE_ATTEMPT_FAILED and resets attempt state" do
    mocks do
      {:ok, _} = QueuedCall.start(sample_call())
      member = %{user_id: "user-1", username: "agent1"}
      {:ok, _} = QueuedCall.begin_attempt("queue-call-1", member, "res-1", 1)

      assert {:ok, state} = QueuedCall.mark_failed("queue-call-1", :no_answer)
      assert state.attempting_to_connect == false
      assert state.attempt_lock_id == nil
      assert state.previous_attempt_to_connect_to_member.user_id == "user-1"
    end
  end

  test "mark_timed_out emits QUEUE_ATTEMPT_TIMED_OUT and resets attempt state" do
    mocks do
      {:ok, _} = QueuedCall.start(sample_call())
      member = %{user_id: "user-1", username: "agent1"}
      {:ok, _} = QueuedCall.begin_attempt("queue-call-1", member, "res-1", 1)

      assert {:ok, state} = QueuedCall.mark_timed_out("queue-call-1")
      assert state.attempting_to_connect == false
      assert state.previous_attempt_to_connect_to_member.user_id == "user-1"
    end
  end

  test "mark_answered emits QUEUE_AGENT_ANSWERED without resetting state" do
    mocks do
      {:ok, _} = QueuedCall.start(sample_call())
      member = %{user_id: "user-1", username: "agent1"}
      {:ok, _} = QueuedCall.begin_attempt("queue-call-1", member, "res-1", 1)

      assert {:ok, state} = QueuedCall.mark_answered("queue-call-1")
      assert state.attempting_to_connect
      assert state.attempt_lock_id == "res-1"
    end
  end

  test "eligible_agents excludes previous attempt's agent unless no one else is left" do
    mocks do
      {:ok, _} = QueuedCall.start(sample_call())
      member = %{user_id: "user-1", username: "agent1"}
      {:ok, _} = QueuedCall.begin_attempt("queue-call-1", member, "res-1", 1)
      {:ok, _} = QueuedCall.mark_failed("queue-call-1", :no_answer)

      assert QueuedCall.eligible_agents("queue-call-1", ["user-1", "user-2"]) == ["user-2"]
      assert QueuedCall.eligible_agents("queue-call-1", ["user-1"]) == ["user-1"]
    end
  end
end
