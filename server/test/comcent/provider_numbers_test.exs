defmodule Comcent.ProviderNumbersTest do
  @moduledoc """
  Import behaviour, with Twilio stubbed.

  `:mock` replaces the module globally for the duration of the block, so these
  cannot run async.
  """

  use Comcent.DataCase, async: false
  import Mock

  alias Comcent.{ProviderFixtures, ProviderNumbers}
  alias Comcent.Schemas.ProviderNumber

  setup do
    org = ProviderFixtures.org()
    {:ok, org: org, connection: ProviderFixtures.connection(org)}
  end

  describe "import_number/3" do
    test "explains an already-imported number instead of leaking the constraint",
         %{connection: connection} do
      number = ProviderFixtures.twilio_number(%{"phone_number" => "+18149073153"})

      with_mock Comcent.Twilio, get_incoming_phone_number: fn _auth, _sid -> {:ok, number} end do
        assert {:ok, _} = ProviderNumbers.import_number(connection, number["sid"])

        # Second import of the same number trips the unique index. The customer
        # must not see "provider_connection_id: has already been taken".
        assert {:error, {:already_imported, message}} =
                 ProviderNumbers.import_number(connection, number["sid"])

        assert message =~ "+18149073153"
        assert message =~ "already been imported"
        refute message =~ "provider_connection_id"
      end
    end

    test "refuses a number that cannot take voice", %{connection: connection} do
      number =
        ProviderFixtures.twilio_number(%{
          "capabilities" => %{"voice" => false, "sms" => true}
        })

      with_mock Comcent.Twilio, get_incoming_phone_number: fn _auth, _sid -> {:ok, number} end do
        assert {:error, {:not_voice_capable, _}} =
                 ProviderNumbers.import_number(connection, number["sid"])
      end
    end

    test "refuses to steal a number off another trunk unless told to",
         %{connection: connection} do
      number = ProviderFixtures.twilio_number(%{"trunk_sid" => "TKsomeone-elses"})

      with_mock Comcent.Twilio, get_incoming_phone_number: fn _auth, _sid -> {:ok, number} end do
        # Twilio moves the number silently on association, so an unconfirmed
        # import must stop rather than quietly repoint whatever that trunk fed.
        assert {:error, {:trunk_conflict, message}} =
                 ProviderNumbers.import_number(connection, number["sid"])

        assert message =~ "TKsomeone-elses"
        assert Repo.aggregate(ProviderNumber, :count) == 0

        assert {:ok, _} =
                 ProviderNumbers.import_number(connection, number["sid"],
                   confirm_trunk_move: true
                 )
      end
    end

    test "refuses a provider we cannot actually drive", %{org: org} do
      # The column allows "telnyx" for later, but every call still goes to
      # Comcent.Twilio -- storing one would label a connection Telnyx while all
      # its traffic went to api.twilio.com.
      assert {:error, {:validation, message}} =
               Comcent.ProviderConnections.connect(org, %{
                 "provider" => "telnyx",
                 "external_account_sid" => "AC123",
                 "api_key_sid" => "SK1",
                 "api_key_secret" => "shh"
               })

      assert message =~ "telnyx"
    end

    test "records the original configuration so the number can be handed back",
         %{connection: connection} do
      number =
        ProviderFixtures.twilio_number(%{
          "trunk_sid" => "TKtheirs",
          "voice_url" => "https://their-app.example/voice"
        })

      with_mock Comcent.Twilio, get_incoming_phone_number: fn _auth, _sid -> {:ok, number} end do
        {:ok, imported} =
          ProviderNumbers.import_number(connection, number["sid"], confirm_trunk_move: true)

        # Without this snapshot, disconnect has nothing to restore to.
        assert imported.original_config["trunk_sid"] == "TKtheirs"
        assert imported.original_config["voice_url"] == "https://their-app.example/voice"
      end
    end
  end
end
