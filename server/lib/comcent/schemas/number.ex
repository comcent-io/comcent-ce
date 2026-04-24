defmodule Comcent.Schemas.Number do
  use Ecto.Schema
  import Ecto.Changeset
  alias Comcent.Types.Json

  @primary_key {:id, :string, autogenerate: false}
  @foreign_key_type :string
  @derive {Jason.Encoder,
           only: [
             :id,
             :name,
             :number,
             :allow_outbound_regex,
             :is_default_outbound_number,
             :inbound_flow_graph,
             :sip_trunk_id,
             :sip_trunk
           ]}
  schema "numbers" do
    field(:name, :string)
    field(:number, :string)
    field(:allow_outbound_regex, :string)
    field(:is_default_outbound_number, :boolean, default: false)
    field(:inbound_flow_graph, Json)

    belongs_to(:org, Comcent.Schemas.Org, foreign_key: :org_id)
    belongs_to(:sip_trunk, Comcent.Schemas.SipTrunk, foreign_key: :sip_trunk_id)
    has_many(:campaigns, Comcent.Schemas.Campaign, foreign_key: :number_id)

    timestamps(inserted_at: :created_at, updated_at: :updated_at)
  end

  def changeset(number, attrs) do
    number
    |> cast(attrs, [
      :name,
      :number,
      :allow_outbound_regex,
      :is_default_outbound_number,
      :inbound_flow_graph,
      :org_id,
      :sip_trunk_id
    ])
    |> validate_required([:name, :number, :org_id, :sip_trunk_id])
    |> unique_constraint(:number)
  end
end
