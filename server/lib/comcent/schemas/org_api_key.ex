defmodule Comcent.Schemas.OrgApiKey do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:api_key, :string, autogenerate: false}
  @foreign_key_type :string
  @derive {Jason.Encoder,
           only: [
             :api_key,
             :name,
             :org_id
           ]}
  schema "org_api_keys" do
    field(:name, :string)

    belongs_to(:org, Comcent.Schemas.Org, foreign_key: :org_id)

    timestamps(inserted_at: :created_at, updated_at: :updated_at)
  end

  def changeset(org_api_key, attrs) do
    org_api_key
    |> cast(attrs, [:api_key, :name, :org_id])
    |> validate_required([:api_key, :name, :org_id])
  end
end
