defmodule Comcent.ProviderFixtures do
  @moduledoc """
  Rows for the Twilio provider-connection tests.

  Inserted through the real changesets rather than raw SQL, so a new required
  field breaks these loudly here instead of quietly diverging from what the
  application actually writes.
  """

  alias Comcent.Repo
  alias Comcent.Schemas.{Number, Org, ProviderConnection, ProviderNumber, SipTrunk}

  def org do
    %Org{id: Ecto.UUID.generate()}
    |> Ecto.Changeset.change(%{
      name: "Acme",
      subdomain: "acme-#{System.unique_integer([:positive])}",
      use_custom_domain: false,
      assign_ext_automatically: false
    })
    |> Repo.insert!()
  end

  @doc """
  A connected Twilio account. `metadata` carries the trunk we built, so pass
  `%{}` to model a connection that has never provisioned one.
  """
  def connection(org, attrs \\ %{}) do
    %ProviderConnection{id: Ecto.UUID.generate()}
    |> ProviderConnection.changeset(
      Map.merge(
        %{
          "provider" => "twilio",
          "auth_method" => "api_key",
          "label" => "Tw",
          "external_account_sid" => "AC#{System.unique_integer([:positive])}",
          "credentials" => %{"api_key_sid" => "SK123", "api_key_secret" => "shhh"},
          "status" => "active",
          "metadata" => %{},
          "org_id" => org.id
        },
        attrs
      )
    )
    |> Repo.insert!()
  end

  def sip_trunk(org, connection, attrs \\ %{}) do
    %SipTrunk{id: Ecto.UUID.generate()}
    |> SipTrunk.changeset(
      Map.merge(
        %{
          "name" => "Twilio Tw",
          "outbound_contact" => "x.pstn.twilio.com",
          "inbound_ips" => ["54.172.60.0/30"],
          "org_id" => org.id,
          "provider_connection_id" => connection.id
        },
        attrs
      )
    )
    |> Repo.insert!()
  end

  def provider_number(org, connection, attrs \\ %{}) do
    %ProviderNumber{id: Ecto.UUID.generate()}
    |> ProviderNumber.changeset(
      Map.merge(
        %{
          "provider_connection_id" => connection.id,
          "org_id" => org.id,
          "e164" => "+13478266412",
          "provider_sid" => "PN#{System.unique_integer([:positive])}",
          "original_config" => %{"trunk_sid" => "TKoriginal", "voice_url" => "https://old"},
          "status" => "imported"
        },
        attrs
      )
    )
    |> Repo.insert!()
  end

  def number(org, trunk, provider_number, attrs \\ %{}) do
    %Number{id: Ecto.UUID.generate()}
    |> Number.changeset(
      Map.merge(
        %{
          "name" => "Main",
          "number" => provider_number.e164,
          "org_id" => org.id,
          "sip_trunk_id" => trunk.id,
          "provider_number_id" => provider_number.id,
          "inbound_flow_graph" => %{"nodes" => %{}}
        },
        attrs
      )
    )
    |> Repo.insert!()
  end

  @doc """
  A Twilio `IncomingPhoneNumbers` payload, shaped the way the API returns it.

  Voice-capable and on no trunk by default, which is the importable case.
  """
  def twilio_number(attrs \\ %{}) do
    Map.merge(
      %{
        "sid" => "PN#{System.unique_integer([:positive])}",
        "phone_number" => "+13478266412",
        "friendly_name" => "(347) 826-6412",
        "capabilities" => %{"voice" => true, "sms" => true, "mms" => true},
        "trunk_sid" => nil,
        "voice_url" => "https://demo.twilio.com/welcome/voice/",
        "voice_method" => "POST"
      },
      attrs
    )
  end
end
