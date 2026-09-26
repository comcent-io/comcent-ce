defmodule Comcent.OutboundPatternTest do
  use ExUnit.Case, async: true

  alias Comcent.OutboundPattern

  @north_america "^\\+1[0-9]{10}$"

  describe "check/3" do
    test "allows a destination that matches" do
      assert OutboundPattern.check(@north_america, "+13478261234", "+14155550123") == :ok
    end

    test "refuses a destination that doesn't match" do
      assert OutboundPattern.check(@north_america, "+13478261234", "+442071234567") ==
               {:error, :destination_not_allowed}
    end

    test "nil, empty and blank patterns allow everything" do
      for pattern <- [nil, "", "  "] do
        assert OutboundPattern.check(pattern, "+13478261234", "+442071234567") == :ok
      end
    end

    test "an invalid pattern refuses rather than allowing" do
      assert OutboundPattern.check("^\\+1[0-9", "+13478261234", "+14155550123") ==
               {:error, :invalid_pattern}
    end

    test "matches what the carrier receives, not what was typed" do
      # An E.164 number sends E.164, whatever the caller typed.
      assert OutboundPattern.check(@north_america, "+13478261234", "14155550123") == :ok
      assert OutboundPattern.check(@north_america, "+13478261234", "(415) 555-0123") == :ok
    end

    test "a US 11-digit number is checked in both spellings" do
      assert OutboundPattern.match_targets("13478261234", "+14155550123") ==
               ["14155550123", "+14155550123"]

      assert OutboundPattern.check(@north_america, "13478261234", "+14155550123") == :ok
      assert OutboundPattern.check("^1[0-9]{10}$", "13478261234", "+14155550123") == :ok

      assert OutboundPattern.check(@north_america, "13478261234", "+442071234567") ==
               {:error, :destination_not_allowed}
    end
  end

  describe "validate/1" do
    test "accepts valid and empty patterns" do
      for pattern <- [@north_america, nil, ""] do
        assert OutboundPattern.validate(pattern) == :ok
      end
    end

    test "explains why an invalid pattern is rejected" do
      assert {:error, message} = OutboundPattern.validate("^\\+1[0-9")
      assert message =~ "is not a valid regular expression"
    end
  end
end
