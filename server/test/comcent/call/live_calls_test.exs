defmodule Comcent.Call.LiveCallsTest do
  use Comcent.DataCase

  alias Comcent.Call.LiveCalls
  alias Comcent.CallFixtures
  alias Comcent.CallSession.Registry

  describe "list/1" do
    test "shows an answered call, and only to its own org" do
      acme = CallFixtures.subdomain()
      globex = CallFixtures.subdomain()
      call = CallFixtures.start_call(acme)
      on_exit(fn -> CallFixtures.stop_call(call) end)

      assert LiveCalls.list(acme) == []

      CallFixtures.answer(call, acme)

      assert [
               %{
                 call_story_id: ^call,
                 caller: "1001",
                 callee: "+13478266412",
                 direction: "inbound",
                 current_party: "1001",
                 start_at: %DateTime{}
               }
             ] = LiveCalls.list(acme)

      assert LiveCalls.list(globex) == []
    end

    test "drops the call on call_ended while its process lives on" do
      org = CallFixtures.subdomain()
      call = CallFixtures.start_call(org)
      on_exit(fn -> CallFixtures.stop_call(call) end)

      leg = CallFixtures.add_leg(call, org)
      CallFixtures.answer(call, org, leg)
      assert [%{call_story_id: ^call}] = LiveCalls.list(org)

      CallFixtures.hang_up(call, org, leg)

      assert Registry.whereis(call) != nil
      assert LiveCalls.list(org) == []
    end

    test "drops a call whose process dies without call_ended" do
      org = CallFixtures.subdomain()
      call = CallFixtures.start_call(org)
      CallFixtures.answer(call, org)
      assert [_] = LiveCalls.list(org)

      CallFixtures.stop_call(call)

      # Horde drops the registration when it sees the process die, which is a
      # message behind us.
      assert eventually(fn -> LiveCalls.list(org) == [] end)
    end

    test "keeps every call when many start at once" do
      org = CallFixtures.subdomain()

      calls =
        1..20
        |> Task.async_stream(fn _ ->
          call = CallFixtures.start_call(org)
          CallFixtures.answer(call, org)
          call
        end)
        |> Enum.map(fn {:ok, call} -> call end)

      on_exit(fn -> Enum.each(calls, &CallFixtures.stop_call/1) end)

      listed = LiveCalls.list(org)
      assert Enum.sort(Enum.map(listed, & &1.call_story_id)) == Enum.sort(calls)
    end

    test "is empty for a nil subdomain" do
      assert LiveCalls.list(nil) == []
    end
  end

  defp eventually(check, attempts \\ 50) do
    cond do
      check.() ->
        true

      attempts == 0 ->
        false

      true ->
        Process.sleep(10)
        eventually(check, attempts - 1)
    end
  end
end
