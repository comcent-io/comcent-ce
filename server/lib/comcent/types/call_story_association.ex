defmodule Comcent.Types.CallStoryAssociation do
  @type t :: %__MODULE__{
          id: String.t(),
          start_at: DateTime.t(),
          end_at: DateTime.t() | nil,
          caller: String.t(),
          callee: String.t(),
          outbound_caller_id: String.t() | nil,
          direction: String.t(),
          is_transcribed: boolean(),
          is_summarized: boolean(),
          is_sentiment_analyzed: boolean(),
          is_anonymized: boolean(),
          hangup_party: String.t() | nil,
          org: %{
            id: String.t(),
            name: String.t(),
            subdomain: String.t(),
            use_custom_domain: boolean(),
            custom_domain: String.t() | nil,
            assign_ext_automatically: boolean(),
            auto_ext_start: String.t() | nil,
            auto_ext_end: String.t() | nil,
            is_active: boolean(),
            enable_transcription: boolean(),
            enable_sentiment_analysis: boolean(),
            enable_summary: boolean(),
            enable_call_recording: boolean(),
            max_members: integer() | nil,
            alert_threshold_balance: integer(),
            wallet_balance: integer(),
            storage_used: integer(),
            max_monthly_storage_used: integer(),
            webhooks:
              list(%{
                id: String.t(),
                url: String.t(),
                events: list(String.t()),
                is_active: boolean(),
                secret: String.t()
              })
          },
          call_spans:
            list(%{
              id: String.t(),
              type: String.t(),
              channel_id: String.t(),
              start_at: DateTime.t(),
              end_at: DateTime.t() | nil,
              current_party: String.t() | nil,
              metadata: map() | nil
            }),
          call_story_events:
            list(%{
              id: String.t(),
              type: String.t(),
              channel_id: String.t(),
              occurred_at: DateTime.t(),
              current_party: String.t() | nil,
              metadata: map() | nil
            })
        }

  defstruct [
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
    :hangup_party,
    :org,
    :call_spans,
    :call_story_events
  ]
end
