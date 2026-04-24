defmodule Comcent.Schemas.CallTranscript do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :string, autogenerate: false}
  @foreign_key_type :string
  schema "call_transcripts" do
    field(:recording_span_id, :string)
    field(:current_party, :string)
    field(:provider, :string)
    field(:transcript_data, :map)

    belongs_to(:call_story, Comcent.Schemas.CallStory, foreign_key: :call_story_id)
  end

  def changeset(call_transcript, attrs) do
    call_transcript
    |> cast(attrs, [
      :recording_span_id,
      :current_party,
      :provider,
      :transcript_data,
      :call_story_id
    ])
    |> validate_required([
      :recording_span_id,
      :current_party,
      :provider,
      :transcript_data,
      :call_story_id
    ])
    |> foreign_key_constraint(:call_story_id,
      name: "call_transcripts_call_story_id_fkey",
      message: "Call story not found"
    )
  end
end
