defmodule Comcent.Schemas.Campaign do
  use Ecto.Schema
  import Ecto.Changeset
  alias Comcent.Types.Json

  @primary_key {:id, :string, autogenerate: false}
  @foreign_key_type :string
  schema "campaigns" do
    field(:name, :string)
    field(:start_date, :utc_datetime, default: DateTime.truncate(DateTime.utc_now(), :second))
    field(:end_date, :utc_datetime)
    field(:filters, Json)

    belongs_to(:campaign_group, Comcent.Schemas.CampaignGroup, foreign_key: :campaign_group_id)
    belongs_to(:campaign_script, Comcent.Schemas.CampaignScript, foreign_key: :campaign_script_id)
    belongs_to(:number, Comcent.Schemas.Number, foreign_key: :number_id)
    has_many(:campaign_customers, Comcent.Schemas.CampaignCustomer, foreign_key: :campaign_id)

    timestamps(inserted_at: :created_at, updated_at: :updated_at)
  end

  def changeset(campaign, attrs) do
    campaign
    |> cast(attrs, [
      :id,
      :name,
      :start_date,
      :end_date,
      :filters,
      :campaign_group_id,
      :campaign_script_id,
      :number_id
    ])
    |> validate_required([:name, :campaign_group_id, :number_id])
  end
end
