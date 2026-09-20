defmodule Comcent.Queue.AgentSession.DialerTest do
  use ExUnit.Case, async: true

  alias Comcent.Queue.AgentSession.Dialer

  describe "attempt_key/2" do
    # A queued call is offered to agents one after another under one call id.
    # Cleanup of a finished attempt runs after the next attempt has started,
    # so the two must never share a key or the first kills the second's leg.
    test "differs between two attempts for the same call" do
      call_id = "aa44fe24-55b2-4f2a-84b2-06796d745c98"

      refute Dialer.attempt_key(call_id, "1") == Dialer.attempt_key(call_id, "2")
    end

    # Reservation ids come from System.unique_integer/1: unique per BEAM node
    # only. Two nodes sharing a FreeSWITCH will both hand out "1".
    test "differs between calls that happen to share a reservation id" do
      refute Dialer.attempt_key("call-a", "1") == Dialer.attempt_key("call-b", "1")
    end

    test "contains no whitespace, since hupall splits its arguments on it" do
      refute Dialer.attempt_key("aa44fe24-55b2-4f2a-84b2-06796d745c98", "17") =~ ~r/\s/
    end
  end
end
