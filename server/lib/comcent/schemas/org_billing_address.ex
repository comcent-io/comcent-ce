defmodule Comcent.Schemas.OrgBillingAddress do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :string, autogenerate: false}
  @foreign_key_type :string
  schema "org_billing_addresses" do
    field(:username, :string)
    field(:line_1, :string)
    field(:city, :string)
    field(:state, :string)
    field(:country, :string)
    field(:postal_code, :string)

    belongs_to(:org, Comcent.Schemas.Org, foreign_key: :org_id)
  end

  def changeset(org_billing_address, attrs) do
    org_billing_address
    |> cast(attrs, [:username, :line_1, :city, :state, :country, :postal_code, :org_id])
    |> validate_required([:line_1, :city, :state, :country, :postal_code, :org_id])
  end
end
