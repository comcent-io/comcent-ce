defmodule Comcent.Schemas.OrgMember do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key false
  @foreign_key_type :string
  schema "org_members" do
    belongs_to(:user, Comcent.Schemas.User,
      foreign_key: :user_id,
      primary_key: true
    )

    belongs_to(:org, Comcent.Schemas.Org,
      foreign_key: :org_id,
      primary_key: true
    )

    belongs_to(:number, Comcent.Schemas.Number, foreign_key: :number_id, type: :string)

    field(:role, Ecto.Enum, values: [:ADMIN, :MEMBER])
    field(:username, :string)
    field(:sip_password, :string)
    field(:extension_number, :string)
    field(:presence, :string, default: "Logged Out")

    has_many(:queue_memberships, Comcent.Schemas.QueueMembership,
      foreign_key: :user_id,
      references: :user_id,
      where: [org_id: {:parent, :org_id}]
    )

    has_many(:queues, through: [:queue_memberships, :queue])

    # has_many(:api_keys, Comcent.Schemas.MemberApiKey,
    #   foreign_key: :user_id,
    #   references: :user_id,
    #   where: [org_id: {:parent, :org_id}]
    # )

    # has_many(:presence_spans, Comcent.Schemas.PresenceSpan,
    #   foreign_key: :user_id,
    #   references: :user_id,
    #   where: [org_id: {:parent, :org_id}]
    # )
  end

  def changeset(org_member, attrs) do
    org_member
    |> cast(attrs, [
      :user_id,
      :org_id,
      :number_id,
      :role,
      :username,
      :sip_password,
      :extension_number,
      :presence
    ])
    |> validate_required([:user_id, :org_id, :role, :username, :sip_password])
    |> unique_constraint([:org_id, :username], name: :org_members_org_id_username_index)
    |> foreign_key_constraint(:user_id)
    |> foreign_key_constraint(:org_id)
    |> foreign_key_constraint(:number_id)
  end
end
