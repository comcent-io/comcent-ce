defmodule Comcent.Schemas.Queue do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :string, autogenerate: false}
  @foreign_key_type :string
  @derive {Jason.Encoder,
           only: [
             :id,
             :name,
             :extension,
             :wrap_up_time,
             :reject_delay_time,
             :max_no_answers,
             :org_id,
             :created_at,
             :updated_at
           ]}
  schema "queues" do
    field(:name, :string)
    field(:extension, :string)
    field(:wrap_up_time, :integer)
    field(:reject_delay_time, :integer)
    field(:max_no_answers, :integer)
    field(:created_at, :utc_datetime)
    field(:updated_at, :utc_datetime)

    belongs_to(:org, Comcent.Schemas.Org, type: :string, foreign_key: :org_id)
    has_many(:queue_memberships, Comcent.Schemas.QueueMembership, foreign_key: :queue_id)
    has_many(:members, through: [:queue_memberships, :user])
  end

  def changeset(queue, attrs) do
    now = DateTime.utc_now()

    attrs =
      Map.merge(attrs, %{
        "created_at" => now,
        "updated_at" => now
      })

    queue
    |> cast(attrs, [
      :id,
      :name,
      :extension,
      :org_id,
      :created_at,
      :updated_at,
      :wrap_up_time,
      :max_no_answers,
      :reject_delay_time
    ])
    |> validate_required([:id, :name, :org_id])
    |> validate_length(:name, min: 3, message: "must be at least 3 characters long")
    |> validate_format(:name, ~r/^[A-Za-z][A-Za-z0-9_.]*$/,
      message:
        "must start with a letter and can only contain letters, numbers, dots, and underscores"
    )
    |> validate_format(:extension, ~r/^(\d{2,5})?$/, message: "must be between 2 and 5 digits")
    |> unique_constraint([:org_id, :name], name: :queues_org_id_name_index)
    |> foreign_key_constraint(:org_id)
  end
end
