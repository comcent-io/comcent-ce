defmodule Comcent.Schemas.User do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :string, autogenerate: false}
  @foreign_key_type :string
  schema "users" do
    field(:name, :string)
    field(:email, :string)
    field(:password_hash, :string)
    field(:is_email_verified, :boolean, default: false)
    field(:verification_email_sent_at, :utc_datetime)
    field(:verification_resend_count, :integer, default: 0)
    field(:verification_resend_window_started_at, :utc_datetime)
    field(:picture, :string)
    field(:has_agreed_to_tos, :boolean, default: false)
    field(:is_super_admin, :boolean, default: false)
    field(:agreed_to_tos_at, :utc_datetime)

    has_many(:identities, Comcent.Schemas.UserIdentity, foreign_key: :user_id)
    has_many(:org_members, Comcent.Schemas.OrgMember, foreign_key: :user_id)
    has_many(:orgs, through: [:org_members, :org])

    timestamps(inserted_at: :created_at, updated_at: :updated_at)
  end

  def changeset(user, attrs) do
    user
    |> cast(attrs, [
      :name,
      :email,
      :password_hash,
      :is_email_verified,
      :verification_email_sent_at,
      :verification_resend_count,
      :verification_resend_window_started_at,
      :picture,
      :has_agreed_to_tos,
      :is_super_admin,
      :agreed_to_tos_at
    ])
    |> validate_required([:name, :email])
    |> unique_constraint(:email)
  end
end
