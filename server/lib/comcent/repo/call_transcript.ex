defmodule Comcent.Repo.CallTranscript do
  import Ecto.Query
  alias Comcent.Repo
  alias Comcent.Schemas.{CallTranscript, CallStory, Org}

  @doc """
  Gets all call transcripts for a particular organization by subdomain.

  ## Parameters
  - subdomain: The organization's subdomain

  ## Returns
  - List of JSON objects containing caller, callee, start_at, duration, and transcript
  """
  def get_transcripts_by_subdomain(subdomain) do
    # Calculate 24 hours ago from now
    twenty_four_hours_ago = DateTime.add(DateTime.utc_now(), -24 * 60 * 60, :second)

    transcripts =
      from(ct in CallTranscript,
        join: cs in CallStory,
        on: ct.call_story_id == cs.id,
        join: o in Org,
        on: cs.org_id == o.id,
        where: o.subdomain == ^subdomain,
        where: cs.start_at >= ^twenty_four_hours_ago,
        select: %{
          caller: cs.caller,
          callee: cs.callee,
          start_at: cs.start_at,
          end_at: cs.end_at,
          transcript_data: ct.transcript_data
        }
      )
      |> Repo.all()

    # Transform to JSON format with duration calculation
    Enum.map(transcripts, fn %{
                               caller: caller,
                               callee: callee,
                               start_at: start_at,
                               end_at: end_at,
                               transcript_data: transcript_data
                             } ->
      # Calculate duration in seconds
      duration =
        case {start_at, end_at} do
          {nil, _} -> 0
          {_, nil} -> 0
          {start, end_time} -> DateTime.diff(end_time, start, :second)
        end

      # Extract transcript text from transcript_data
      transcript =
        get_in(transcript_data, [
          "results",
          "channels",
          Access.at(0),
          "alternatives",
          Access.at(0),
          "transcript"
        ]) || ""

      %{
        caller: caller,
        callee: callee,
        start_at: start_at,
        duration: duration,
        transcript: transcript
      }
    end)
  end
end
