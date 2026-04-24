defmodule Comcent.Schemas.CampaignCustomer do
  use Ecto.Schema
  import Ecto.Changeset
  alias Comcent.Types.Json

  @primary_key {:id, :string, autogenerate: false}
  @foreign_key_type :string
  schema "campaign_customers" do
    field(:first_name, :string, default: "")
    field(:last_name, :string, default: "")
    field(:phone_number, :string, default: "")
    field(:attributes, Json)
    field(:call_progress_status, :string, default: "NOT_SCHEDULED")
    field(:disposition, :string, default: "")
    field(:expiry_date, :utc_datetime)
    field(:scheduled_date, :utc_datetime)
    field(:member_id, :string, default: "")

    belongs_to(:campaign, Comcent.Schemas.Campaign, foreign_key: :campaign_id)

    timestamps(inserted_at: :created_at, updated_at: :updated_at)
  end

  def changeset(campaign_customer, attrs) do
    campaign_customer
    |> cast(attrs, [
      :first_name,
      :last_name,
      :phone_number,
      :attributes,
      :call_progress_status,
      :disposition,
      :expiry_date,
      :scheduled_date,
      :member_id,
      :campaign_id
    ])
    |> validate_required([:phone_number, :campaign_id])
  end
end
