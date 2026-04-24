defmodule Comcent.Schemas.DailySummary do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :string, autogenerate: false}
  @foreign_key_type :string
  @derive {Jason.Encoder,
           only: [
             :id,
             :date,
             :executive_summary,
             :org_id,
             :total_promises_created,
             :total_promises_closed
           ]}
  schema "daily_summaries" do
    field(:date, :utc_datetime)
    field(:executive_summary, :string)
    field(:total_promises_created, :integer, default: 0)
    field(:total_promises_closed, :integer, default: 0)
    belongs_to(:org, Comcent.Schemas.Org, foreign_key: :org_id)
  end

  def changeset(daily_summary, attrs) do
    daily_summary
    |> cast(attrs, [
      :id,
      :date,
      :executive_summary,
      :org_id,
      :total_promises_created,
      :total_promises_closed
    ])
    |> validate_required([
      :id,
      :date,
      :executive_summary,
      :org_id,
      :total_promises_created,
      :total_promises_closed
    ])
    |> foreign_key_constraint(:org_id)
  end
end
