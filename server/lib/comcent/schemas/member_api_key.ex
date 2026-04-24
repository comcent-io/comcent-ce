defmodule Comcent.Schemas.MemberApiKey do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key false
  @foreign_key_type :string
  schema "member_api_keys" do
    field(:api_key, :string, primary_key: true)
    field(:name, :string)
    field(:org_id, :string, primary_key: true)
    field(:user_id, :string, primary_key: true)
    field(:created_at, :utc_datetime)
    field(:updated_at, :utc_datetime)
  end

  def changeset(member_api_key, attrs) do
    member_api_key
    |> cast(attrs, [:api_key, :name, :org_id, :user_id, :created_at, :updated_at])
    |> validate_required([:api_key, :name, :org_id, :user_id])
  end
end
