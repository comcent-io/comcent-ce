defmodule Comcent.Schemas.CallStoryEvent do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :string, autogenerate: false}
  @foreign_key_type :string
  @derive {Jason.Encoder,
           only: [
             :id,
             :type,
             :channel_id,
             :occurred_at,
             :current_party,
             :metadata,
             :call_story_id
           ]}
  schema "call_story_events" do
    field(:type, :string)
    field(:channel_id, :string, default: "unknown")
    field(:occurred_at, :utc_datetime_usec)
    field(:current_party, :string)
    field(:metadata, :map)

    belongs_to(:call_story, Comcent.Schemas.CallStory, foreign_key: :call_story_id)
  end

  def changeset(call_story_event, attrs) do
    call_story_event
    |> cast(attrs, [
      :id,
      :type,
      :channel_id,
      :occurred_at,
      :current_party,
      :metadata,
      :call_story_id
    ])
    |> validate_required([:id, :type, :occurred_at, :call_story_id])
    |> foreign_key_constraint(:call_story_id,
      name: "call_story_events_call_story_id_fkey",
      message: "Call story not found"
    )
  end
end
