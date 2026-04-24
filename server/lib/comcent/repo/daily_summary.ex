defmodule Comcent.Repo.DailySummary do
  import Ecto.Query
  alias Comcent.Repo
  alias Comcent.Schemas.{DailySummary, Org, CallStory, CallSpan}

  @doc """
  Gets all daily summaries for an organization identified by its subdomain.

  Returns a list of `%Comcent.Schemas.DailySummary{}` ordered by `date` descending.
  """
  def get_daily_summaries_by_subdomain(subdomain) when is_binary(subdomain) do
    from(ds in DailySummary,
      join: o in Org,
      on: ds.org_id == o.id,
      where: o.subdomain == ^subdomain,
      order_by: [desc: ds.date],
      select: ds
    )
    |> Repo.all()
  end

  @doc """
  Gets a daily summary for a specific date and organization ID.

  Returns `%Comcent.Schemas.DailySummary{}` or `nil` if not found.
  """
  def get_daily_summary_by_date_and_org_id(org_id, date) do
    # Convert date to start of day datetime for comparison
    today_date = date |> DateTime.to_date()
    today_start = DateTime.new!(today_date, ~T[00:00:00], "Etc/UTC")

    from(ds in DailySummary,
      where: ds.org_id == ^org_id,
      where: fragment("DATE(?) = DATE(?)", ds.date, ^today_start),
      limit: 1
    )
    |> Repo.one()
  end

  @doc """
  Gets sentiment counts for a specific date and organization.

  Returns a map with counts of positive, negative, and neutral sentiments
  for the given date and subdomain.
  """
  def get_sentiment_counts_by_date(subdomain, date) when is_binary(subdomain) do
    case Date.from_iso8601(date) do
      {:ok, parsed_date} ->
        # Create start and end datetime for the given date
        start_datetime = DateTime.new!(parsed_date, ~T[00:00:00], "Etc/UTC")
        end_datetime = DateTime.new!(parsed_date, ~T[23:59:59], "Etc/UTC")

        # Query call spans with sentiment data for the specific date and organization
        recording_spans =
          from(cs in CallSpan,
            join: call_story in CallStory,
            on: cs.call_story_id == call_story.id,
            join: o in Org,
            on: call_story.org_id == o.id,
            where:
              o.subdomain == ^subdomain and
                cs.type == "RECORDING" and
                fragment("(?->>'direction') = ?", cs.metadata, "in") and
                cs.start_at >= ^start_datetime and
                cs.start_at <= ^end_datetime and
                not is_nil(fragment("?->>'sentiment'", cs.metadata))
          )
          |> Repo.all()

        # Count sentiments
        sentiment_counts =
          recording_spans
          |> Enum.reduce(%{positive: 0, negative: 0, neutral: 0}, fn span, acc ->
            sentiment = get_in(span.metadata, ["sentiment"])

            case sentiment do
              "positive" -> Map.update!(acc, :positive, &(&1 + 1))
              "negative" -> Map.update!(acc, :negative, &(&1 + 1))
              "neutral" -> Map.update!(acc, :neutral, &(&1 + 1))
              _ -> acc
            end
          end)

        sentiment_counts

      {:error, _} ->
        {:error, :invalid_date}
    end
  end
end
