defmodule Comcent.Schemas.CampaignCustomerMapping do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :string, autogenerate: false}
  @foreign_key_type :string
  schema "campaign_customer_mappings" do
    field(:name, :string, default: "")
    field(:mappings, :map)

    belongs_to(:org, Comcent.Schemas.Org, foreign_key: :org_id)
  end

  def changeset(campaign_customer_mapping, attrs) do
    campaign_customer_mapping
    |> cast(attrs, [:id, :name, :mappings, :org_id])
    |> validate_required([:id, :name, :mappings, :org_id])
  end
end
