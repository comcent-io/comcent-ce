defmodule Comcent.Schemas.Promises do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :string, autogenerate: false}
  @foreign_key_type :string
  @derive {Jason.Encoder,
           only: [
             :id,
             :org_id,
             :call_story_id,
             :promise,
             :status,
             :due_date,
             :created_by,
             :assigned_to,
             :created_at,
             :updated_at
           ]}

  schema "promises" do
    field(:call_story_id, :string, default: "")
    field(:promise, :string)
    field(:status, :string, default: "OPEN")
    field(:due_date, :utc_datetime)
    field(:created_by, :string, default: "")
    field(:assigned_to, :string, default: "")
    field(:created_at, :utc_datetime)
    field(:updated_at, :utc_datetime)

    belongs_to(:org, Comcent.Schemas.Org, foreign_key: :org_id)
  end

  def changeset(promises, attrs) do
    promises
    |> cast(attrs, [
      :id,
      :call_story_id,
      :promise,
      :status,
      :due_date,
      :created_by,
      :assigned_to,
      :org_id,
      :created_at,
      :updated_at
    ])
    |> validate_required([:id, :promise, :status, :org_id])
    |> validate_inclusion(:status, ["OPEN", "CLOSED"])
    |> foreign_key_constraint(:org_id)
  end
end
