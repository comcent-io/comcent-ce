defmodule Comcent.Schemas.ComplianceTask do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :string, autogenerate: false}
  @foreign_key_type :string
  schema "compliance_tasks" do
    field(:type, :string)
    field(:status, :string)
    field(:created_at, :utc_datetime)
    field(:updated_at, :utc_datetime)
    field(:data, :map)

    belongs_to(:org, Comcent.Schemas.Org, foreign_key: :org_id)
  end

  def changeset(compliance_task, attrs) do
    compliance_task
    |> cast(attrs, [
      :id,
      :type,
      :status,
      :created_at,
      :org_id,
      :updated_at,
      :data
    ])
    |> validate_required([:id, :type, :status, :org_id, :updated_at, :data])
  end
end
