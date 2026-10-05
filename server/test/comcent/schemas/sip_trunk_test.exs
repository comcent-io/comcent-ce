defmodule Comcent.Schemas.SipTrunkTest do
  use ExUnit.Case, async: true

  alias Comcent.Schemas.SipTrunk

  @valid %{
    "name" => "Carrier",
    "outbound_contact" => "sip.example.com",
    "inbound_ips" => ["203.0.113.0/24"],
    "org_id" => "org"
  }

  defp changeset(outbound_contact) do
    SipTrunk.changeset(%SipTrunk{}, Map.put(@valid, "outbound_contact", outbound_contact))
  end

  test "stores the outbound contact without the sip: prefix" do
    changeset = changeset(" sip:sip.example.com:5080 ")

    assert changeset.valid?
    assert Ecto.Changeset.get_change(changeset, :outbound_contact) == "sip.example.com:5080"
  end

  test "accepts a bare host and a host:port" do
    assert Ecto.Changeset.get_change(changeset("sip.example.com"), :outbound_contact) ==
             "sip.example.com"

    assert Ecto.Changeset.get_change(changeset("203.0.113.10:5080"), :outbound_contact) ==
             "203.0.113.10:5080"
  end

  test "rejects an outbound contact that cannot be dialled" do
    changeset = changeset("sips:sip.example.com")

    refute changeset.valid?
    assert {message, []} = changeset.errors[:outbound_contact]
    assert message =~ "TLS"
  end

  test "an update that leaves the outbound contact alone keeps the stored value" do
    existing = %SipTrunk{
      name: "Carrier",
      outbound_contact: "legacy.example.com",
      inbound_ips: ["203.0.113.0/24"],
      org_id: "org"
    }

    changeset = SipTrunk.changeset(existing, %{"name" => "Renamed"})

    assert changeset.valid?
    assert Ecto.Changeset.get_field(changeset, :outbound_contact) == "legacy.example.com"
  end

  test "still requires an outbound contact" do
    changeset = changeset("")

    refute changeset.valid?
    assert {"can't be blank", _} = changeset.errors[:outbound_contact]
  end
end
