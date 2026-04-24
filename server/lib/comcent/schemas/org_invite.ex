defmodule Comcent.Schemas.OrgInvite do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :string, autogenerate: false}
  @foreign_key_type :string
  schema "org_invites" do
    field(:email, :string)
    field(:role, :string)
    field(:status, :string)
    field(:invite_email_sent_at, :utc_datetime)
    field(:invite_resend_count, :integer, default: 0)
    field(:invite_resend_window_started_at, :utc_datetime)

    belongs_to(:org, Comcent.Schemas.Org, foreign_key: :org_id)

    timestamps(inserted_at: :created_at, updated_at: :updated_at)
  end

  def changeset(org_invite, attrs) do
    org_invite
    |> cast(attrs, [
      :email,
      :role,
      :status,
      :org_id,
      :invite_email_sent_at,
      :invite_resend_count,
      :invite_resend_window_started_at
    ])
    |> validate_required([:email, :role, :status, :org_id])
    |> unique_constraint([:email, :org_id])
  end
end
