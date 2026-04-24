defmodule Comcent.Schemas.PromiseAuditLog do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :string, autogenerate: false}
  @foreign_key_type :string
  @derive {Jason.Encoder,
           only: [
             :id,
             :promise_id,
             :type,
             :old_value,
             :new_value,
             :org_id,
             :created_at,
             :updated_at
           ]}

  schema "promise_audit_logs" do
    field(:promise_id, :string)
    field(:type, Ecto.Enum, values: [:ASSIGNED_TO_CHANGED, :STATUS_CHANGED])
    field(:old_value, :string)
    field(:new_value, :string)
    field(:created_at, :utc_datetime)
    field(:updated_at, :utc_datetime)

    belongs_to(:org, Comcent.Schemas.Org, foreign_key: :org_id)
  end

  def changeset(promise_audit_log, attrs) do
    now = DateTime.utc_now()

    attrs =
      Map.merge(attrs, %{
        "created_at" => now,
        "updated_at" => now
      })

    promise_audit_log
    |> cast(attrs, [
      :id,
      :promise_id,
      :type,
      :old_value,
      :new_value,
      :org_id,
      :created_at,
      :updated_at
    ])
    |> validate_required([:id, :promise_id, :type, :old_value, :new_value, :org_id])
    |> validate_inclusion(:type, [:ASSIGNED_TO_CHANGED, :STATUS_CHANGED])
    |> foreign_key_constraint(:org_id)
    |> foreign_key_constraint(:promise_id)
  end
end
