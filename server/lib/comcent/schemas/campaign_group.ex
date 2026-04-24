defmodule Comcent.Schemas.CampaignGroup do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :string, autogenerate: false}
  @foreign_key_type :string
  @derive {Jason.Encoder,
           only: [
             :id,
             :name,
             :org_id,
             :created_at,
             :updated_at
           ]}
  schema "campaign_groups" do
    field(:name, :string)

    belongs_to(:org, Comcent.Schemas.Org, foreign_key: :org_id)
    has_many(:campaigns, Comcent.Schemas.Campaign, foreign_key: :campaign_group_id)

    timestamps(inserted_at: :created_at, updated_at: :updated_at)
  end

  def changeset(campaign_group, attrs) do
    campaign_group
    |> cast(attrs, [:id, :name, :org_id])
    |> validate_required([:name, :org_id])
  end
end
