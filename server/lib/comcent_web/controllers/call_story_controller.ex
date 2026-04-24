defmodule ComcentWeb.CallStoryController do
  use ComcentWeb, :controller
  import Ecto.Query

  alias Comcent.Repo
  alias Comcent.Schemas.CallStory
  alias Comcent.Schemas.CallAnalysis
  alias Comcent.Schemas.CallSpan
  alias Comcent.Schemas.Org
  alias Comcent.Schemas.Promises
  alias Comcent.Transcript
  require Logger

  def get_transcript(conn, %{"call_story_id" => call_story_id, "subdomain" => subdomain}) do
    # Find call story with transcripts and spans for the specific org
    call_story =
      Repo.get_by(CallStory, id: call_story_id)
      |> Repo.preload([
        :call_transcripts,
        :call_spans,
        :call_story_events,
        org: []
      ])

    case call_story do
      nil ->
        Logger.error("Call story with id #{call_story_id} not found")

        conn
        |> put_status(:not_found)
        |> json(%{error: "Call story not found", code: "CALL_STORY_NOT_FOUND"})

      call_story ->
        # Verify the call story belongs to the correct org
        if call_story.org.subdomain != subdomain do
          Logger.error("Call story #{call_story_id} does not belong to org #{subdomain}")

          conn
          |> put_status(:not_found)
          |> json(%{error: "Call story not found", code: "CALL_STORY_NOT_FOUND"})
        else
          transcript_chat = Transcript.create_transcript_chat(call_story)
          json(conn, %{transcript_chat: transcript_chat})
        end
    end
  end

  def get_summary(conn, %{"call_story_id" => call_story_id, "subdomain" => subdomain}) do
    # Find call story to verify it belongs to the correct org
    call_story =
      Repo.get_by(CallStory, id: call_story_id)
      |> Repo.preload(org: [])

    case call_story do
      nil ->
        Logger.error("Call story with id #{call_story_id} not found")

        conn
        |> put_status(:not_found)
        |> json(%{error: "Call story not found", code: "CALL_STORY_NOT_FOUND"})

      call_story ->
        # Verify the call story belongs to the correct org
        if call_story.org.subdomain != subdomain do
          Logger.error("Call story #{call_story_id} does not belong to org #{subdomain}")

          conn
          |> put_status(:not_found)
          |> json(%{error: "Call story not found", code: "CALL_STORY_NOT_FOUND"})
        else
          # Find the summary analysis for this call story
          # Use Repo.all to handle multiple results and get the first one
          analyses =
            Repo.all(
              from analysis in CallAnalysis,
                where: analysis.call_story_id == ^call_story_id and analysis.type == "SUMMARY",
                limit: 1
            )

          # Extract summary text from analysis data, defaulting to empty string if not found
          summary_text =
            case analyses do
              [] ->
                ""

              [analysis | _] ->
                get_in(analysis.analysis_data, ["results", "summary", "text"]) || ""
            end

          json(conn, %{summary: summary_text})
        end
    end
  end

  def get_sentiment(conn, %{"call_story_id" => call_story_id, "subdomain" => subdomain}) do
    # Find call story to verify it belongs to the correct org
    call_story =
      Repo.get_by(CallStory, id: call_story_id)
      |> Repo.preload(org: [])

    case call_story do
      nil ->
        Logger.error("Call story with id #{call_story_id} not found")

        conn
        |> put_status(:not_found)
        |> json(%{error: "Call story not found", code: "CALL_STORY_NOT_FOUND"})

      call_story ->
        # Verify the call story belongs to the correct org
        if call_story.org.subdomain != subdomain do
          Logger.error("Call story #{call_story_id} does not belong to org #{subdomain}")

          conn
          |> put_status(:not_found)
          |> json(%{error: "Call story not found", code: "CALL_STORY_NOT_FOUND"})
        else
          # Find recording spans with direction "in" for this call story
          recording_spans =
            Repo.all(
              from span in CallSpan,
                where:
                  span.call_story_id == ^call_story_id and
                    span.type == "RECORDING" and
                    fragment("(?->>'direction') = ?", span.metadata, "in")
            )

          # Extract sentiment data from spans
          sentiment =
            recording_spans
            |> Enum.reduce(%{}, fn span, acc ->
              Map.put(acc, span.current_party, get_in(span.metadata, ["sentiment"]))
            end)

          json(conn, %{sentiment: sentiment})
        end
    end
  end

  def get_call_story(conn, %{"call_story_id" => call_story_id, "subdomain" => subdomain}) do
    Logger.info("Getting call story #{call_story_id} for org #{subdomain}")

    # Find the organization by subdomain
    org = Repo.get_by(Org, subdomain: subdomain)

    case org do
      nil ->
        Logger.error("Organization with subdomain #{subdomain} not found")

        conn
        |> put_status(:not_found)
        |> json(%{error: "Organization not found", code: "ORG_NOT_FOUND"})

      org ->
        # Find call story with call spans for the specific org
        call_story =
          from(cs in CallStory,
            where: cs.id == ^call_story_id and cs.org_id == ^org.id,
            preload: [:call_spans, :call_story_events]
          )
          |> Repo.one()

        case call_story do
          nil ->
            Logger.error("Call story with id #{call_story_id} not found for org #{subdomain}")

            conn
            |> put_status(:not_found)
            |> json(%{error: "Call story not found", code: "CALL_STORY_NOT_FOUND"})

          call_story ->
            # Check if transcribed, summarized, sentiment analyzed
            is_transcribed = call_story.is_transcribed || false
            is_summarized = call_story.is_summarized || false
            is_sentiment_analyzed = call_story.is_sentiment_analyzed || false

            # Get all promises for this call story
            promises =
              from(p in Promises,
                where: p.call_story_id == ^call_story_id,
                order_by: [asc: p.created_at]
              )
              |> Repo.all()

            call_story_map = %{
              id: call_story.id,
              caller: call_story.caller,
              callee: call_story.callee,
              direction: call_story.direction,
              start_at: call_story.start_at,
              end_at: call_story.end_at,
              org_id: call_story.org_id,
              is_transcribed: is_transcribed,
              is_summarized: is_summarized,
              is_sentiment_analyzed: is_sentiment_analyzed,
              call_spans: call_story.call_spans,
              call_story_events: call_story.call_story_events,
              promises: promises
            }

            Logger.info(
              "Retrieved call story #{call_story_id} with #{length(promises)} promises for org #{subdomain}"
            )

            json(conn, %{call_story: call_story_map})
        end
    end
  end

  def get_call_stories(conn, %{"subdomain" => subdomain} = params) do
    # Get pagination parameters from query params
    current_page = String.to_integer(params["page"] || "1")
    items_per_page = String.to_integer(params["items_per_page"] || "10")

    # Parse labels parameter - can be comma-separated string, JSON array, or already a list
    labels = parse_labels(params["labels"])

    Logger.info("Labels: #{inspect(labels)}")

    search_text =
      if params["search"] && String.trim(params["search"]) != "" do
        params["search"]
      else
        nil
      end

    # Validate items per page (allowed values: 5, 10, 20, 50)
    allowed_items_per_page = [5, 10, 20, 50]
    items_per_page = if items_per_page in allowed_items_per_page, do: items_per_page, else: 10

    # Find the organization by subdomain
    org = Repo.get_by(Org, subdomain: subdomain)

    case org do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Organization not found", code: "ORG_NOT_FOUND"})

      _org ->
        # Get total count for pagination with search filter
        total_count = Comcent.Repo.CallStory.get_call_stories_count(subdomain)

        # Get call stories with pagination, call spans, and search filter
        call_stories =
          Comcent.Repo.CallStory.list_call_stories(
            subdomain,
            items_per_page,
            current_page,
            search_text,
            labels
          )

        # Calculate total pages
        total_pages = Float.ceil(total_count / items_per_page) |> trunc()

        json(conn, %{
          call_stories: call_stories,
          total_pages: total_pages,
          current_page: current_page,
          items_per_page: items_per_page,
          total_count: total_count
        })
    end
  end

  # Private helper functions

  # Parse labels parameter from various formats
  defp parse_labels(nil), do: nil
  defp parse_labels(""), do: nil

  # Handle when labels is already a list (from Phoenix params)
  defp parse_labels(labels) when is_list(labels) do
    # Filter out empty strings and ensure all items are strings
    parsed =
      labels
      |> Enum.filter(fn label -> is_binary(label) && String.trim(label) != "" end)
      |> Enum.map(&String.trim/1)

    case parsed do
      [] -> nil
      list -> list
    end
  end

  # Handle comma-separated string: "urgent,follow-up,customer-complaint"
  defp parse_labels(labels) when is_binary(labels) do
    trimmed = String.trim(labels)

    cond do
      trimmed == "" ->
        nil

      # Check if it's a JSON array string
      String.starts_with?(trimmed, "[") ->
        case Jason.decode(trimmed) do
          {:ok, list} when is_list(list) -> parse_labels(list)
          _ -> nil
        end

      # Otherwise treat as comma-separated string
      true ->
        parsed =
          trimmed
          |> String.split(",")
          |> Enum.map(&String.trim/1)
          |> Enum.filter(&(&1 != ""))

        case parsed do
          [] -> nil
          list -> list
        end
    end
  end

  # Fallback for any other type
  defp parse_labels(_), do: nil
end
