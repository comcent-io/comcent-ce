defmodule Comcent.Schemas.SipTrunk do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :string, autogenerate: false}
  @foreign_key_type :string
  @derive {Jason.Encoder,
           only: [
             :id,
             :name,
             :outbound_username,
             :outbound_password,
             :outbound_contact,
             :inbound_ips,
             :org_id
           ]}
  schema "sip_trunks" do
    field(:name, :string)
    field(:outbound_username, :string)
    field(:outbound_password, :string)
    field(:outbound_contact, :string)
    field(:inbound_ips, {:array, :string})

    belongs_to(:org, Comcent.Schemas.Org, foreign_key: :org_id)
    has_many(:numbers, Comcent.Schemas.Number, foreign_key: :sip_trunk_id)

    timestamps(inserted_at: :created_at, updated_at: :updated_at)
  end

  def changeset(sip_trunk, attrs) do
    sip_trunk
    |> cast(attrs, [
      :name,
      :outbound_username,
      :outbound_password,
      :outbound_contact,
      :inbound_ips,
      :org_id
    ])
    |> validate_required([:name, :outbound_contact, :inbound_ips, :org_id])
  end
end
