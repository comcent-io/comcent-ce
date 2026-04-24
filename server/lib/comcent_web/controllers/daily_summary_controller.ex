defmodule ComcentWeb.DailySummaryController do
  use ComcentWeb, :controller
  alias Comcent.Repo.DailySummary
  require Logger

  def get_daily_summaries(conn, %{"subdomain" => subdomain}) do
    Logger.info("Fetching daily summaries for subdomain: #{subdomain}")

    daily_summaries = DailySummary.get_daily_summaries_by_subdomain(subdomain)

    daily_summaries_maps =
      Enum.map(daily_summaries, fn summary ->
        %{
          id: summary.id,
          date: summary.date,
          executive_summary: summary.executive_summary,
          org_id: summary.org_id,
          total_promises_created: summary.total_promises_created,
          total_promises_closed: summary.total_promises_closed
        }
      end)

    response_summaries = daily_summaries_maps

    json(conn, %{daily_summaries: response_summaries})
  end

  def get_sentiment_counts(conn, %{"subdomain" => subdomain, "date" => date}) do
    Logger.info("Fetching sentiment counts for subdomain: #{subdomain}, date: #{date}")

    case DailySummary.get_sentiment_counts_by_date(subdomain, date) do
      {:error, :invalid_date} ->
        conn
        |> put_status(:bad_request)
        |> json(%{
          error: "Invalid date format. Please use YYYY-MM-DD format",
          code: "INVALID_DATE_FORMAT"
        })

      sentiment_counts ->
        response_counts = sentiment_counts

        json(conn, %{sentiment_counts: response_counts})
    end
  end
end
