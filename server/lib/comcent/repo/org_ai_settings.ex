defmodule Comcent.Repo.OrgAiSettings do
  import Ecto.Query
  alias Comcent.Repo
  alias Comcent.Schemas.Org

  @doc """
  Get AI settings for an organization by subdomain.
  Returns a map with subdomain, enable_transcription, enable_sentiment_analysis, enable_summary, enable_labels, labels,
  enable_daily_summary, daily_summary_time_zone, and daily_summary_time.
  """
  def get_ai_settings(subdomain) do
    Repo.one(
      from(o in Org,
        where: o.subdomain == ^subdomain,
        select: %{
          subdomain: o.subdomain,
          enable_transcription: o.enable_transcription,
          enable_sentiment_analysis: o.enable_sentiment_analysis,
          enable_summary: o.enable_summary,
          enable_labels: o.enable_labels,
          labels: o.labels,
          enable_daily_summary: o.enable_daily_summary,
          daily_summary_time_zone: o.daily_summary_time_zone,
          daily_summary_time: o.daily_summary_time
        }
      )
    )
  end

  @doc """
  Update AI settings for an organization by subdomain.
  Accepts a map with enable_transcription, enable_sentiment_analysis, enable_summary, enable_labels, labels,
  enable_daily_summary, daily_summary_time_zone, and daily_summary_time fields.
  Returns {:ok, org} on success or {:error, changeset} on failure.
  """
  def update_ai_settings(subdomain, ai_settings) do
    case Repo.one(from(o in Org, where: o.subdomain == ^subdomain)) do
      nil ->
        {:error, :not_found}

      org ->
        org
        |> Org.changeset(%{
          enable_transcription: Map.get(ai_settings, :enable_transcription),
          enable_sentiment_analysis: Map.get(ai_settings, :enable_sentiment_analysis),
          enable_summary: Map.get(ai_settings, :enable_summary),
          enable_labels: Map.get(ai_settings, :enable_labels),
          labels: Map.get(ai_settings, :labels),
          enable_daily_summary: Map.get(ai_settings, :enable_daily_summary),
          daily_summary_time_zone: Map.get(ai_settings, :daily_summary_time_zone),
          daily_summary_time: Map.get(ai_settings, :daily_summary_time)
        })
        |> Repo.update()
    end
  end
end
