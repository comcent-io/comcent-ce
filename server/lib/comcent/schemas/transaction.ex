defmodule Comcent.Schemas.Transaction do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :string, autogenerate: false}
  @foreign_key_type :string
  schema "transactions" do
    field(:order_id, :string)
    field(:payment_gateway, :string)
    field(:customer_email, :string)
    field(:amount, :float)
    field(:date, :utc_datetime)
    field(:description, :string)

    belongs_to(:org, Comcent.Schemas.Org, foreign_key: :org_id)

    timestamps(inserted_at: :created_at, updated_at: :updated_at)
  end

  def changeset(transaction, attrs) do
    transaction
    |> cast(attrs, [
      :order_id,
      :payment_gateway,
      :customer_email,
      :amount,
      :date,
      :description,
      :org_id
    ])
    |> validate_required([:amount, :org_id])
  end
end
