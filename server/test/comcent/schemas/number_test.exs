defmodule Comcent.Schemas.NumberTest do
  use ExUnit.Case, async: true

  alias Comcent.Schemas.Number

  @valid %{
    "name" => "Main",
    "number" => "+13478261234",
    "org_id" => "org",
    "sip_trunk_id" => "trunk"
  }

  test "saves a valid allowed outbound pattern" do
    changeset = Number.changeset(%Number{}, Map.put(@valid, "allow_outbound_regex", "^\\+1"))

    assert changeset.valid?
  end

  test "an empty allowed outbound pattern means unrestricted" do
    changeset = Number.changeset(%Number{}, Map.put(@valid, "allow_outbound_regex", ""))

    assert changeset.valid?
    assert Ecto.Changeset.get_field(changeset, :allow_outbound_regex) == nil
  end

  test "rejects an allowed outbound pattern that isn't a valid regex" do
    changeset = Number.changeset(%Number{}, Map.put(@valid, "allow_outbound_regex", "^\\+1[0-9"))

    refute changeset.valid?
    assert {message, []} = changeset.errors[:allow_outbound_regex]
    assert message =~ "is not a valid regular expression"
  end
end
