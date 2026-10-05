defmodule Comcent.ProvisioningTest do
  @moduledoc """
  Guards the invariant the import UI depends on: **one trunk per connection**,
  however many numbers are imported and however they are batched.

  This is not theoretical. The trunk SID is written onto the connection during
  the first import, and provisioning re-reads the connection to find it. A
  caller holding a stale struct, or two imports running concurrently, skips
  that read and builds a second trunk — which then quietly carries some of the
  customer's numbers with nothing pointing at it.

  The import page now sends one request per number to show progress, so this
  path runs once per number rather than once per batch.
  """

  use Comcent.DataCase, async: false
  import Mock

  alias Comcent.{ProviderFixtures, Provisioning}
  alias Comcent.Schemas.{ProviderConnection, SipTrunk}

  setup do
    previous = Application.get_env(:comcent, :provisioning)

    Application.put_env(:comcent, :provisioning,
      sbc_sip_fqdn: "sbc.example.com",
      twilio_signaling_cidrs: ["54.172.60.0/30"]
    )

    on_exit(fn -> Application.put_env(:comcent, :provisioning, previous) end)

    org = ProviderFixtures.org()
    {:ok, org: org, connection: ProviderFixtures.connection(org)}
  end

  # A small stateful fake: a number reports the trunk it is actually on, so it
  # is unattached when imported and attached once associated. A static stub
  # would trip the "already on another trunk" guard on its own read-back.
  defp twilio_stub(state) do
    [
      get_incoming_phone_number: fn _auth, sid ->
        attached? = Agent.get(state, &MapSet.member?(&1.associated, sid))

        {:ok,
         ProviderFixtures.twilio_number(%{
           "sid" => sid,
           # Distinct per sid: numbers are unique, and three imports of one
           # number would fail for a reason this test is not about.
           "phone_number" =>
             "+1555" <> String.slice(:erlang.phash2(sid) |> Integer.to_string(), 0, 7),
           "trunk_sid" => if(attached?, do: "TKcomcent", else: nil)
         })}
      end,
      associate_phone_number: fn _auth, _trunk, sid ->
        Agent.update(state, &%{&1 | associated: MapSet.put(&1.associated, sid)})
        {:ok, %{"sid" => sid}}
      end,
      create_trunk: fn _auth, friendly, domain ->
        Agent.update(
          state,
          &%{&1 | trunks: [friendly | &1.trunks], domains: [domain | &1.domains]}
        )

        {:ok, %{"sid" => "TKcomcent", "domain_name" => domain, "friendly_name" => friendly}}
      end,
      get_trunk: fn _auth, sid ->
        {:ok, %{"sid" => sid, "domain_name" => "already-built.pstn.twilio.com"}}
      end,
      create_origination_url: fn _auth, _sid, _opts -> {:ok, %{"sid" => "OU1"}} end,
      create_credential_list: fn _auth, _name -> {:ok, %{"sid" => "CL1"}} end,
      create_credential: fn _auth, _list, _user, _pass -> {:ok, %{"sid" => "CR1"}} end,
      attach_credential_list: fn _auth, _trunk, _list -> {:ok, %{"sid" => "CL1"}} end,
      update_incoming_phone_number: fn _auth, sid, params ->
        Agent.update(state, &%{&1 | restored: [sid | &1.restored]})
        # Restore detaches the number, so it comes back on no trunk.
        Agent.update(state, &%{&1 | associated: MapSet.delete(&1.associated, sid)})
        {:ok, ProviderFixtures.twilio_number(%{"sid" => sid, "trunk_sid" => params[:trunk_sid]})}
      end
    ]
  end

  defp new_state do
    {:ok, pid} =
      Agent.start_link(fn ->
        %{trunks: [], associated: MapSet.new(), restored: [], deleted: [], domains: []}
      end)

    pid
  end

  defp trunks_created(state), do: Agent.get(state, &length(&1.trunks))
  defp restored(state), do: Agent.get(state, & &1.restored)

  test "importing several numbers one request at a time builds exactly one trunk",
       %{org: org, connection: connection} do
    state = new_state()

    with_mock Comcent.Twilio, twilio_stub(state) do
      # Deliberately passing the *original* struct every time, which is what a
      # caller holding a connection from before the first import looks like.
      for sid <- ["PNaaa", "PNbbb", "PNccc"] do
        assert {:ok, _} = Provisioning.import_and_provision(connection, sid)
      end
    end

    assert trunks_created(state) == 1, "created more than one trunk in Twilio"

    trunks = Repo.all(from(t in SipTrunk, where: t.provider_connection_id == ^connection.id))
    assert length(trunks) == 1

    # And the trunk is recorded on the connection, which is what disconnect
    # later uses to tear it down.
    reloaded = Repo.get(ProviderConnection, connection.id)
    assert reloaded.metadata["trunk_sid"] == "TKcomcent"
    assert reloaded.metadata["credential_list_sid"] == "CL1"

    assert Repo.aggregate(from(n in Comcent.Schemas.Number, where: n.org_id == ^org.id), :count) ==
             3
  end

  test "a second import reuses the recorded trunk instead of creating one",
       %{connection: connection} do
    state = new_state()

    with_mock Comcent.Twilio, twilio_stub(state) do
      assert {:ok, _} = Provisioning.import_and_provision(connection, "PNfirst")

      # Reload, as a fresh request would: the trunk is now on the connection.
      reloaded = Repo.get(ProviderConnection, connection.id)
      assert {:ok, _} = Provisioning.import_and_provision(reloaded, "PNsecond")
    end

    assert trunks_created(state) == 1
  end

  describe "where Twilio is told to send inbound calls" do
    setup do
      previous = Application.get_env(:comcent, :sbc)
      on_exit(fn -> Application.put_env(:comcent, :sbc, previous) end)

      Application.put_env(:comcent, :provisioning,
        sbc_sip_fqdn: nil,
        twilio_signaling_cidrs: ["54.172.60.0/30"]
      )

      {:ok, sbc: previous}
    end

    defp origination_stub(state, test_pid) do
      Keyword.put(twilio_stub(state), :create_origination_url, fn _auth, _sid, opts ->
        send(test_pid, {:origination, opts[:sip_url]})
        {:ok, %{"sid" => "OU1"}}
      end)
    end

    test "the SBC's public IP when SBC_SIP_FQDN is not set", %{connection: connection, sbc: sbc} do
      Application.put_env(:comcent, :sbc, Keyword.put(sbc, :public_ip, "203.0.113.7"))

      with_mock Comcent.Twilio, origination_stub(new_state(), self()) do
        assert {:ok, _} = Provisioning.import_and_provision(connection, "PNaaa")
      end

      assert_received {:origination, "sip:203.0.113.7"}
    end

    test "nothing is created when neither address is set", %{connection: connection, sbc: sbc} do
      Application.put_env(:comcent, :sbc, Keyword.put(sbc, :public_ip, nil))
      state = new_state()

      with_mock Comcent.Twilio, origination_stub(state, self()) do
        assert {:error, {:configuration, message}} =
                 Provisioning.import_and_provision(connection, "PNaaa")

        assert message =~ "SBC_PUBLIC_IP"
      end

      assert trunks_created(state) == 0
    end
  end

  test "a trunk whose setup fails is deleted rather than orphaned",
       %{connection: connection} do
    state = new_state()

    # The trunk is created, then origination fails. Nothing in Comcent knows
    # the trunk exists at that point, so leaving it behind would put an
    # unidentifiable trunk in the customer's account -- one per retry.
    stub =
      Keyword.merge(twilio_stub(state),
        create_origination_url: fn _auth, _sid, _opts ->
          {:error, {:twilio_error, 20003, "Authentication Error"}}
        end,
        delete_trunk: fn _auth, sid ->
          Agent.update(state, &%{&1 | deleted: [sid | &1.deleted]})
          :ok
        end
      )

    with_mock Comcent.Twilio, stub do
      assert {:error, _} = Provisioning.import_and_provision(connection, "PNaaa")
    end

    assert Agent.get(state, & &1.deleted) == ["TKcomcent"]
  end

  test "a label with no usable characters still yields a valid trunk domain" do
    org = ProviderFixtures.org()
    connection = ProviderFixtures.connection(org, %{"label" => "!!!"})
    state = new_state()

    with_mock Comcent.Twilio, twilio_stub(state) do
      assert {:ok, _} = Provisioning.import_and_provision(connection, "PNaaa")
    end

    [domain] = Agent.get(state, & &1.domains)
    # A leading hyphen is an invalid DNS label, and Twilio rejects it with a
    # code the domain-collision retry does not handle.
    refute String.starts_with?(domain, "-")
    assert domain =~ ~r/^[a-z0-9][a-z0-9-]*\.pstn\.twilio\.com$/
  end

  test "provisioning failure rolls the import back rather than leaving a half-owned number",
       %{connection: connection} do
    state = new_state()

    stub =
      Keyword.put(twilio_stub(state), :create_trunk, fn _auth, _friendly, _domain ->
        {:error, {:twilio_error, 20003, "Authentication Error"}}
      end)

    with_mock Comcent.Twilio, stub do
      assert {:error, _} = Provisioning.import_and_provision(connection, "PNaaa")
    end

    # The rollback must put the number back before dropping the row that says
    # how it was configured, or a number already moved onto the Comcent trunk
    # is stranded with no way home.
    assert restored(state) == ["PNaaa"]

    # An imported number with no trunk is one we claim to own but cannot route,
    # and it would also block re-importing the same number.
    assert Repo.aggregate(Comcent.Schemas.ProviderNumber, :count) == 0
  end
end
