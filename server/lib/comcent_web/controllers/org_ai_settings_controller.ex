defmodule ComcentWeb.OrgAiSettingsController do
  use ComcentWeb, :controller
  alias Comcent.Repo.OrgAiSettings
  require Logger

  @doc """
  GET endpoint to retrieve AI settings for an organization.
  Requires user to be authenticated and be an ADMIN of the organization.
  """
  def get(conn, _params) do
    subdomain = conn.assigns[:subdomain]

    case OrgAiSettings.get_ai_settings(subdomain) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Organization not found"})

      ai_settings ->
        conn
        |> put_status(:ok)
        |> json(ai_settings)
    end
  end

  @doc """
  POST endpoint to update AI settings for an organization.
  Requires user to be authenticated and be an ADMIN of the organization.
  Validates that the required boolean fields are present.
  Accepts enable_daily_summary, daily_summary_time_zone, and daily_summary_time fields.
  """
  def update(conn, params) do
    subdomain = conn.assigns[:subdomain]

    with {:ok, validated_params} <- validate_ai_settings(params),
         {:ok, _org} <- OrgAiSettings.update_ai_settings(subdomain, validated_params) do
      conn
      |> put_status(:ok)
      |> json(%{message: "AI settings updated successfully"})
    else
      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Organization not found"})

      {:error, :validation_error, message} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: message})

      {:error, %Ecto.Changeset{} = changeset} ->
        errors = format_changeset_errors(changeset)

        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "Validation failed", details: errors})

      {:error, reason} ->
        Logger.error("Failed to update AI settings: #{inspect(reason)}")

        conn
        |> put_status(:internal_server_error)
        |> json(%{error: "Failed to update AI settings"})
    end
  end

  # Private helper functions

  defp validate_ai_settings(params) do
    with {:ok, enable_transcription} <- get_boolean_field(params, "enable_transcription"),
         {:ok, enable_sentiment} <- get_boolean_field(params, "enable_sentiment_analysis"),
         {:ok, enable_summary} <- get_boolean_field(params, "enable_summary"),
         {:ok, enable_labels} <- get_boolean_field(params, "enable_labels"),
         {:ok, enable_daily_summary} <- get_boolean_field(params, "enable_daily_summary") do
      {:ok,
       %{
         enable_transcription: enable_transcription,
         enable_sentiment_analysis: enable_sentiment,
         enable_summary: enable_summary,
         enable_labels: enable_labels,
         labels: Map.get(params, "labels"),
         enable_daily_summary: enable_daily_summary,
         daily_summary_time_zone: Map.get(params, "daily_summary_time_zone"),
         daily_summary_time: Map.get(params, "daily_summary_time")
       }}
    else
      {:error, message} -> {:error, :validation_error, message}
    end
  end

  defp get_boolean_field(params, field_name) do
    case Map.get(params, field_name) do
      nil ->
        {:error, "Field '#{field_name}' is required"}

      value when is_boolean(value) ->
        {:ok, value}

      _ ->
        {:error, "Field '#{field_name}' must be a boolean"}
    end
  end

  defp format_changeset_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
  end
end
