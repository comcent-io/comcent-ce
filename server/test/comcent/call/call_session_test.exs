defmodule Comcent.CallSessionTest do
  use Comcent.DataCase

  alias Comcent.CallFixtures
  alias Comcent.CallSession.Registry

  setup do
    org = CallFixtures.org()
    call = CallFixtures.start_call(org.subdomain)
    on_exit(fn -> CallFixtures.stop_call(call) end)

    agent =
      "dana@#{org.subdomain}.#{Application.fetch_env!(:comcent, :sip_user_root_domain)}"

    %{org: org, call: call, agent: agent}
  end

  describe "an agent who doesn't take a ringing call" do
    # 480 from the SBC when no tab answered (NO_USER_RESPONSE), and 603 when
    # the agent pressed Decline (CALL_REJECTED).
    for cause <- ["NO_USER_RESPONSE", "CALL_REJECTED"] do
      test "is the call's hangup party (#{cause})", ctx do
        leg = CallFixtures.ring_agent(ctx.call, ctx.agent)
        CallFixtures.ringing_leg_ends(ctx.call, leg, unquote(cause))

        assert hangup_party(ctx.call) == ctx.agent
      end
    end

    test "is not the hangup party when the caller gave up first", ctx do
      leg = CallFixtures.ring_agent(ctx.call, ctx.agent)
      CallFixtures.ringing_leg_ends(ctx.call, leg, "ORIGINATOR_CANCEL")

      refute hangup_party(ctx.call) == ctx.agent
    end
  end

  defp hangup_party(call), do: :sys.get_state(Registry.whereis(call)).hangup_party
end
