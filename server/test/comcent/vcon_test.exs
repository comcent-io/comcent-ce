defmodule Comcent.VConTest do
  use Comcent.DataCase, async: true

  alias Comcent.ProviderFixtures
  alias Comcent.Repo
  alias Comcent.Schemas.{CallAnalysis, CallSpan, CallStory, CallTranscript}
  alias Comcent.VCon

  @caller "+16505550188"
  @agent "maya@globex.comcent.io"
  @start ~U[2026-10-05 09:51:00Z]

  # A finished call once it has been transcribed (with sentiment) and
  # summarised.
  defp analysed_call do
    org = ProviderFixtures.org()
    id = Ecto.UUID.generate()

    Repo.insert!(%CallStory{
      id: id,
      org_id: org.id,
      caller: @caller,
      callee: "+14155550100",
      direction: "inbound",
      start_at: @start,
      end_at: DateTime.add(@start, 60)
    })

    span =
      Repo.insert!(%CallSpan{
        id: Ecto.UUID.generate(),
        call_story_id: id,
        current_party: @agent,
        type: "RECORDING",
        start_at: @start,
        end_at: DateTime.add(@start, 60),
        metadata: %{"direction" => "in", "file_name" => "#{id}-in.wav"}
      })

    Repo.insert!(%CallTranscript{
      id: Ecto.UUID.generate(),
      call_story_id: id,
      recording_span_id: span.id,
      current_party: @agent,
      provider: "DEEPGRAM",
      transcript_data: %{
        "results" => %{
          "channels" => [
            %{"alternatives" => [%{"words" => [%{"word" => "hello", "start" => 1.0}]}]}
          ],
          "sentiments" => %{"average" => %{"sentiment" => "positive", "sentiment_score" => 0.6}}
        }
      }
    })

    Repo.insert!(%CallAnalysis{
      id: Ecto.UUID.generate(),
      call_story_id: id,
      provider: "DEEPGRAM",
      type: "SUMMARY",
      analysis_data: %{
        "results" => %{"summary" => %{"text" => "The customer asked for a refund."}}
      }
    })

    Repo.get!(CallStory, id) |> Repo.preload([:org, :call_spans])
  end

  test "a transcribed call's vCon carries its transcript, sentiment and summary" do
    analysis = VCon.generate_vcon(analysed_call()).analysis

    assert Enum.map(analysis, & &1.type) |> Enum.sort() == ["sentiment", "summary", "transcript"]
    assert Enum.find(analysis, &(&1.type == "summary")).body == "The customer asked for a refund."
  end
end
