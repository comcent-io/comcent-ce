# CE-only stub. The real Comcent.Plans lives in EE. CE has a single implicit
# "unlimited" plan with zero prices and zero costs. Do NOT sync this file to EE.
# Keys mirror every access point in new_call_story_processor.ex so that
# `mix compile --warnings-as-errors` does not flag unknown-key type violations.
defmodule Comcent.Plans do
  @moduledoc false
  def active do
    %{
      prices: %{
        transcription: 0,
        sentiment: 0,
        sentiment_analysis: 0,
        summary: 0,
        voice_bot: 0,
        call: 0
      },
      costs: %{
        transcription: 0,
        audio_intelligence_input: 0,
        audio_intelligence_output: 0
      }
    }
  end
end
