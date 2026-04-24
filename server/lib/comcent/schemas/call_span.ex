defmodule Comcent.Schemas.CallSpan do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :string, autogenerate: false}
  @foreign_key_type :string
  @derive {Jason.Encoder,
           only: [
             :id,
             :type,
             :channel_id,
             :start_at,
             :end_at,
             :current_party,
             :metadata,
             :call_story_id
           ]}
  schema "call_spans" do
    field(:type, :string)
    field(:channel_id, :string, default: "unknown")
    field(:start_at, :utc_datetime)
    field(:end_at, :utc_datetime)
    field(:current_party, :string)
    field(:metadata, :map)

    belongs_to(:call_story, Comcent.Schemas.CallStory, foreign_key: :call_story_id)
  end

  def changeset(call_span, attrs) do
    call_span
    |> cast(attrs, [
      :id,
      :type,
      :channel_id,
      :start_at,
      :end_at,
      :current_party,
      :metadata,
      :call_story_id
    ])
    |> validate_required([:id, :type, :start_at, :current_party, :call_story_id])
    |> foreign_key_constraint(:call_story_id,
      name: "call_spans_call_story_id_fkey",
      message: "Call story not found"
    )
  end
end
