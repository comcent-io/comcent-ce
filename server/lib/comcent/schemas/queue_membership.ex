defmodule Comcent.Schemas.QueueMembership do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key false
  @foreign_key_type :string
  schema "queue_memberships" do
    belongs_to(:queue, Comcent.Schemas.Queue, foreign_key: :queue_id, primary_key: true)
    belongs_to(:org, Comcent.Schemas.Org, foreign_key: :org_id, primary_key: true)
    belongs_to(:user, Comcent.Schemas.User, foreign_key: :user_id, primary_key: true)

    belongs_to(:member, Comcent.Schemas.OrgMember,
      foreign_key: :user_id,
      references: :user_id,
      define_field: false,
      where: [org_id: {:parent, :org_id}]
    )

    field(:created_at, :utc_datetime)
    field(:updated_at, :utc_datetime)
  end

  def changeset(queue_membership, attrs) do
    queue_membership
    |> cast(attrs, [:queue_id, :org_id, :user_id, :created_at, :updated_at])
    |> validate_required([:queue_id, :org_id, :user_id])
    |> foreign_key_constraint(:queue_id, name: :queue_memberships_queue_id_fkey)
    |> foreign_key_constraint(:org_id, name: :queue_memberships_org_id_fkey)
    |> foreign_key_constraint(:user_id, name: :queue_memberships_user_id_fkey)
  end
end
