defmodule Comcent.OutboundContactTest do
  use ExUnit.Case, async: true

  alias Comcent.OutboundContact

  doctest Comcent.OutboundContact

  describe "normalize/1" do
    test "stores every accepted form as the bare host[:port]" do
      for {input, canonical} <- [
            {"sip.example.com", "sip.example.com"},
            {"sip.example.com:5080", "sip.example.com:5080"},
            {"sip:sip.example.com", "sip.example.com"},
            {"sip:sip.example.com:5080", "sip.example.com:5080"},
            {"SIP:sip.example.com:5080", "sip.example.com:5080"},
            {"www.something.com", "www.something.com"},
            {"203.0.113.10", "203.0.113.10"},
            {"203.0.113.10:5060", "203.0.113.10:5060"},
            {"sip:203.0.113.10:5080", "203.0.113.10:5080"},
            # Internal hosts, such as a container name, have a single label.
            {"sipp-uas:6351", "sipp-uas:6351"},
            {"x.pstn.twilio.com", "x.pstn.twilio.com"}
          ] do
        assert OutboundContact.normalize(input) == {:ok, canonical}, input
      end
    end

    test "trims surrounding whitespace" do
      assert OutboundContact.normalize("  sip:sip.example.com:5080\n") ==
               {:ok, "sip.example.com:5080"}
    end

    test "drops leading zeros from the port" do
      assert OutboundContact.normalize("sip.example.com:05080") == {:ok, "sip.example.com:5080"}
    end

    test "refuses what cannot be dialled" do
      for input <- [
            "",
            "   ",
            "sip.example .com",
            "sip:",
            ":5080",
            "sip:sip:sip.example.com",
            "http://sip.example.com",
            "http:sip.example.com",
            "sip.example.com:0",
            "sip.example.com:65536",
            "sip.example.com:abc",
            "sip.example.com:",
            "265.1.0.5",
            "1.0.5",
            "-example.com",
            "example-.com",
            "example..com",
            "exa!mple.com",
            "2001:db8::1",
            "[2001:db8::1]:5060",
            "sip:sip.example.com:5060:5061"
          ] do
        assert {:error, message} = OutboundContact.normalize(input), inspect(input)
        assert message =~ "host:port", inspect(input)
      end
    end

    test "explains why sips: and URI parameters are refused" do
      assert {:error, message} = OutboundContact.normalize("sips:sip.example.com:5061")
      assert message =~ "TLS"

      assert {:error, message} = OutboundContact.normalize("sip:sip.example.com;transport=tcp")
      assert message =~ ";transport=tcp"

      assert {:error, message} = OutboundContact.normalize("sip:trunk@sip.example.com")
      assert message =~ "user@"

      assert {:error, message} = OutboundContact.normalize("http://sip.example.com")
      assert message =~ "only the sip: scheme"
    end

    test "refuses a value that isn't a string" do
      assert {:error, _} = OutboundContact.normalize(5060)
    end
  end

  describe "dial_address/1" do
    test "reads both the canonical form and an older sip:-prefixed row" do
      assert OutboundContact.dial_address("sip.example.com:5080") == "sip.example.com:5080"
      assert OutboundContact.dial_address("sip:sip.example.com:5080") == "sip.example.com:5080"
      assert OutboundContact.dial_address(" sip.example.com ") == "sip.example.com"
      assert OutboundContact.dial_address(nil) == nil
    end
  end
end
