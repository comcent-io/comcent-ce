defmodule Comcent.Schemas.CallStory do
  use Ecto.Schema
  import Ecto.Changeset
  alias Comcent.Types.Json

  @primary_key {:id, :string, autogenerate: false}
  @foreign_key_type :string
  @derive {Jason.Encoder,
           only: [
             :id,
             :start_at,
             :end_at,
             :caller,
             :callee,
             :outbound_caller_id,
             :direction,
             :is_transcribed,
             :is_summarized,
             :is_sentiment_analyzed,
             :is_anonymized,
             :labels,
             :is_labeled,
             :hangup_party,
             :org_id,
             :call_spans,
             :call_story_events
           ]}
  schema "call_stories" do
    field(:start_at, :utc_datetime)
    field(:end_at, :utc_datetime)
    field(:caller, :string)
    field(:callee, :string)
    field(:outbound_caller_id, :string)
    field(:direction, :string)
    field(:is_transcribed, :boolean, default: false)
    field(:is_summarized, :boolean, default: false)
    field(:is_sentiment_analyzed, :boolean, default: false)
    field(:is_anonymized, :boolean, default: false)
    field(:labels, Json)
    field(:is_labeled, :boolean, default: false)
    field(:hangup_party, :string)

    belongs_to(:org, Comcent.Schemas.Org, foreign_key: :org_id)

    has_many(:call_spans, Comcent.Schemas.CallSpan,
      on_delete: :delete_all,
      foreign_key: :call_story_id
    )

    has_many(:call_story_events, Comcent.Schemas.CallStoryEvent,
      on_delete: :delete_all,
      foreign_key: :call_story_id
    )

    has_many(:call_transcripts, Comcent.Schemas.CallTranscript,
      on_delete: :delete_all,
      foreign_key: :call_story_id
    )

    has_many(:call_analyses, Comcent.Schemas.CallAnalysis,
      on_delete: :delete_all,
      foreign_key: :call_story_id
    )

    has_many(:call_search_vectors, Comcent.Schemas.CallSearchVector,
      on_delete: :delete_all,
      foreign_key: :call_story_id
    )
  end

  def changeset(call_story, attrs) do
    call_story
    |> cast(attrs, [
      :id,
      :start_at,
      :end_at,
      :caller,
      :callee,
      :outbound_caller_id,
      :direction,
      :is_transcribed,
      :is_summarized,
      :is_sentiment_analyzed,
      :is_anonymized,
      :labels,
      :is_labeled,
      :hangup_party,
      :org_id
    ])
    |> validate_required([:id, :start_at, :caller, :callee, :direction, :org_id])
    |> foreign_key_constraint(:org_id)
  end
end
