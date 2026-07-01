defmodule Comcent.Schemas.InstanceSetup do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :integer, autogenerate: false}
  schema "instance_setup" do
    field(:token, :string)
    field(:generated_at, :utc_datetime)
    field(:consumed_at, :utc_datetime)
    field(:consumed_by_user_id, :string)

    timestamps(inserted_at: :created_at, updated_at: :updated_at)
  end

  def changeset(row, attrs) do
    row
    |> cast(attrs, [:id, :token, :generated_at, :consumed_at, :consumed_by_user_id])
    |> validate_required([:id])
  end
end
