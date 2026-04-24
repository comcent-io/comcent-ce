defmodule Comcent.Schemas.CampaignScript do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :string, autogenerate: false}
  @foreign_key_type :string
  schema "campaign_scripts" do
    field(:name, :string)
    field(:script, :string)

    belongs_to(:org, Comcent.Schemas.Org, foreign_key: :org_id)
    has_many(:campaigns, Comcent.Schemas.Campaign, foreign_key: :campaign_script_id)

    timestamps(inserted_at: :created_at, updated_at: :updated_at)
  end

  def changeset(campaign_script, attrs) do
    campaign_script
    |> cast(attrs, [:id, :name, :script, :org_id])
    |> validate_required([:id, :name, :script, :org_id])
  end
end
