defmodule Comcent.ProviderDisconnectTest do
  @moduledoc """
  Covers "stop managing this account" (`:keep`).

  The mode is easy to get wrong in the direction that matters: it must give up
  the credentials without disturbing anything the customer's calls depend on,
  and it must keep the row, because that row is the only record of the trunk we
  built and the only route back to each number's original configuration.
  """

  use Comcent.DataCase, async: false
  import Mock

  alias Comcent.{ProviderDisconnect, ProviderFixtures}
  alias Comcent.Schemas.Campaign
  alias Comcent.Schemas.{Number, ProviderConnection, ProviderNumber, SipTrunk}

  defp fixture do
    org = ProviderFixtures.org()

    connection =
      ProviderFixtures.connection(org, %{
        "metadata" => %{"trunk_sid" => "TK1", "credential_list_sid" => "CL1"}
      })

    trunk = ProviderFixtures.sip_trunk(org, connection)
    provider_number = ProviderFixtures.provider_number(org, connection)
    number = ProviderFixtures.number(org, trunk, provider_number)

    %{connection: connection, trunk: trunk, provider_number: provider_number, number: number}
  end

  describe "disconnect/2 with :keep" do
    test "gives up the credentials but keeps the connection row" do
      %{connection: connection} = fixture()

      {:ok, result} = ProviderDisconnect.disconnect(connection, :keep)
      assert result.mode == :keep

      reloaded = Repo.get(ProviderConnection, connection.id)

      # The row survives: it is the only place the trunk and credential list
      # SIDs are recorded, and deleting it would cascade the provider_numbers
      # that hold each number's original configuration.
      assert reloaded
      assert reloaded.status == "unmanaged"
      assert reloaded.metadata["trunk_sid"] == "TK1"

      # ...but we no longer hold a key to the customer's account.
      assert is_nil(reloaded.credentials)
    end

    test "leaves everything the calls depend on in place" do
      %{connection: connection, trunk: trunk, number: number, provider_number: pn} = fixture()

      {:ok, _} = ProviderDisconnect.disconnect(connection, :keep)

      # Routing is numbers -> sip_trunks, and both must survive untouched, or
      # the customer loses service for giving us back our own API key.
      assert Repo.get(Number, number.id).sip_trunk_id == trunk.id
      assert Repo.get(SipTrunk, trunk.id).provider_connection_id == connection.id

      # The restore snapshot is what makes handing the numbers back possible
      # later, once a key is supplied again.
      assert Repo.get(ProviderNumber, pn.id).original_config["trunk_sid"] == "TKoriginal"
    end

    test "a reconnect resumes the same connection rather than building a second one" do
      %{connection: connection, trunk: trunk} = fixture()

      {:ok, _} = ProviderDisconnect.disconnect(connection, :keep)

      # The unique index on (org, provider, account_sid) means a reconnect has
      # to come back through this row -- which is what stops a second trunk
      # being provisioned alongside the live one.
      assert [%SipTrunk{id: still_ours}] =
               Repo.all(from(t in SipTrunk, where: t.provider_connection_id == ^connection.id))

      assert still_ours == trunk.id
    end
  end

  describe "disconnect/2 with :release" do
    test "refuses before touching Twilio when a number is still used by a campaign" do
      %{connection: connection, number: number, trunk: trunk} = fixture()

      group =
        %Comcent.Schemas.CampaignGroup{id: Ecto.UUID.generate()}
        |> Ecto.Changeset.change(%{name: "Q4", org_id: connection.org_id})
        |> Repo.insert!()

      %Campaign{id: Ecto.UUID.generate()}
      |> Ecto.Changeset.change(%{
        name: "Winter promo",
        number_id: number.id,
        campaign_group_id: group.id
      })
      |> Repo.insert!()

      # No Twilio functions are stubbed: if the guard fails to stop us, the
      # first provider call raises and the test fails loudly rather than
      # silently tearing down a live trunk.
      assert {:error, {:numbers_in_use, message}} =
               ProviderDisconnect.disconnect(connection, :release)

      assert message =~ number.number

      # Nothing removed, because the delete would have failed against the
      # campaign FK after the trunk was already gone in Twilio.
      assert Repo.get(ProviderConnection, connection.id)
      assert Repo.get(SipTrunk, trunk.id)
      assert Repo.get(Number, number.id)
    end
  end

  describe "disconnect/2 with :release, success path" do
    test "removes every row once the provider side is restored" do
      %{connection: connection, trunk: trunk, number: number, provider_number: pn} = fixture()

      with_mock Comcent.Twilio,
        update_incoming_phone_number: fn _auth, sid, _params ->
          {:ok, %{"sid" => sid, "trunk_sid" => "TKoriginal"}}
        end,
        delete_trunk: fn _auth, _sid -> :ok end,
        delete_credential_list: fn _auth, _sid -> :ok end do
        {:ok, result} = ProviderDisconnect.disconnect(connection, :release)
        assert result.restored == 1
        assert result.failed == []
      end

      # All of it goes, in one transaction: a partial delete would leave rows
      # pointing at a trunk that no longer exists in Twilio.
      refute Repo.get(ProviderConnection, connection.id)
      refute Repo.get(SipTrunk, trunk.id)
      refute Repo.get(Number, number.id)
      refute Repo.get(ProviderNumber, pn.id)
    end
  end

  describe "restore read-back" do
    test "a number restored onto the wrong trunk is reported as failed" do
      %{connection: connection} = fixture()

      # Twilio answers 200 but leaves the number on our trunk instead of the
      # customer's. original_config says TKoriginal.
      with_mock Comcent.Twilio,
        update_incoming_phone_number: fn _auth, sid, _params ->
          {:ok, %{"sid" => sid, "trunk_sid" => "TKcomcent"}}
        end,
        delete_trunk: fn _auth, _sid -> :ok end,
        delete_credential_list: fn _auth, _sid -> :ok end do
        {:ok, result} = ProviderDisconnect.disconnect(connection, :release)

        assert result.restored == 0
        assert [%{ok: false, error: error}] = result.failed
        assert error =~ "TKcomcent"
        assert error =~ "TKoriginal"
      end
    end

    test "a number that was originally on no trunk restores to no trunk" do
      org = ProviderFixtures.org()
      connection = ProviderFixtures.connection(org)

      # Blank both sides: this is the case the "both blank" branch exists for.
      ProviderFixtures.provider_number(org, connection, %{
        "original_config" => %{"trunk_sid" => "", "voice_url" => "https://old"}
      })

      with_mock Comcent.Twilio,
        update_incoming_phone_number: fn _auth, sid, _params ->
          {:ok, %{"sid" => sid, "trunk_sid" => nil}}
        end,
        delete_trunk: fn _auth, _sid -> :ok end,
        delete_credential_list: fn _auth, _sid -> :ok end do
        {:ok, result} = ProviderDisconnect.disconnect(connection, :release)

        assert result.restored == 1
        assert result.failed == []
      end
    end
  end
end
