defmodule Comcent.Schemas.UserIdentity do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :string, autogenerate: false}
  @foreign_key_type :string
  schema "user_identities" do
    field(:provider, :string)
    field(:provider_user_id, :string)
    field(:email, :string)
    field(:name, :string)
    field(:picture, :string)

    belongs_to(:user, Comcent.Schemas.User, foreign_key: :user_id)

    timestamps(inserted_at: :created_at, updated_at: :updated_at)
  end

  def changeset(identity, attrs) do
    identity
    |> cast(attrs, [:provider, :provider_user_id, :email, :name, :picture, :user_id])
    |> validate_required([:provider, :provider_user_id, :user_id])
    |> unique_constraint([:provider, :provider_user_id],
      name: "user_identities_provider_provider_user_id_key"
    )
    |> unique_constraint([:user_id, :provider], name: "user_identities_user_id_provider_key")
  end
end
