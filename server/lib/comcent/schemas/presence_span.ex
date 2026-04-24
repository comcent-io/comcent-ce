defmodule Comcent.Schemas.PresenceSpan do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :string, autogenerate: false}
  @foreign_key_type :string
  schema "presence_spans" do
    field(:org_id, :string)
    field(:user_id, :string)
    field(:start_at, :utc_datetime)
    field(:end_at, :utc_datetime)
    field(:presence, :string)
    field(:created_at, :utc_datetime)
    field(:updated_at, :utc_datetime)
  end

  def changeset(presence_span, attrs) do
    presence_span
    |> cast(attrs, [
      :id,
      :org_id,
      :user_id,
      :start_at,
      :end_at,
      :presence,
      :created_at,
      :updated_at
    ])
    |> validate_required([:id, :org_id, :user_id, :start_at, :presence])
  end
end
