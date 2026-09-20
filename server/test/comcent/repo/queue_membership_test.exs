defmodule Comcent.Repo.QueueMembershipTest do
  use Comcent.DataCase

  alias Comcent.Repo.Queue
  alias Comcent.Schemas.{Org, OrgMember, QueueMembership, User}
  alias Comcent.Schemas.Queue, as: QueueSchema

  setup do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    org =
      Repo.insert!(%Org{
        id: "org-1",
        name: "Org 1",
        subdomain: "org1",
        use_custom_domain: false,
        assign_ext_automatically: false,
        is_active: true,
        enable_transcription: false,
        enable_sentiment_analysis: false,
        enable_summary: false,
        enable_labels: false,
        enable_call_recording: false,
        enable_daily_summary: false,
        wallet_balance: 1_000,
        storage_used: 0,
        max_monthly_storage_used: 0
      })

    user = Repo.insert!(%User{id: "user-1", name: "Agent One", email: "agent.one@example.com"})

    Repo.insert!(%OrgMember{
      user_id: user.id,
      org_id: org.id,
      role: :MEMBER,
      username: "agentone",
      sip_password: "secret"
    })

    queue =
      Repo.insert!(%QueueSchema{
        id: "queue-1",
        name: "support",
        org_id: org.id,
        wrap_up_time: 30,
        reject_delay_time: 30,
        max_no_answers: 2,
        created_at: now,
        updated_at: now
      })

    %{org: org, user: user, queue: queue}
  end

  describe "add_member_to_queue/2" do
    test "adds a member", %{org: org, user: user, queue: queue} do
      assert {:ok, %QueueMembership{}} =
               Queue.add_member_to_queue(%{org_id: org.id, user_id: user.id}, queue.id)
    end

    # A double click on "Add to queue" sends the same request twice. The second
    # insert used to raise Ecto.ConstraintError on the primary key, which the
    # controller surfaced as a 500 "Internal Server Error" toast.
    test "reports a duplicate instead of raising", %{org: org, user: user, queue: queue} do
      attrs = %{org_id: org.id, user_id: user.id}

      assert {:ok, _} = Queue.add_member_to_queue(attrs, queue.id)
      assert {:error, :already_member} = Queue.add_member_to_queue(attrs, queue.id)
      assert Repo.aggregate(QueueMembership, :count) == 1
    end
  end
end
