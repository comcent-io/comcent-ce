defmodule Comcent.Deepgram do
  @moduledoc """
  A client for interacting with the Deepgram API.
  """

  use HTTPoison.Base
  require Logger

  @base_url "https://api.deepgram.com/v1"
  @default_timeout 30_000
  # Receive timeout needs to be longer as Deepgram downloads and transcribes audio
  @default_recv_timeout 120_000

  def process_url(url) do
    @base_url <> url
  end

  def process_request_headers(headers) do
    headers
    |> Keyword.put(:"Content-Type", "application/json")
    |> Keyword.put(:Authorization, "Token " <> api_key())
  end

  @doc """
  Transcribes audio using Deepgram's API.

  ## Parameters
    - url: The URL of the audio file to transcribe
    - enable_sentiment: Whether to enable sentiment analysis

  ## Examples
      iex> Comcent.Deepgram.transcribe("https://example.com/audio.mp3", true)
      {:ok, %{"results" => %{"channels" => [%{"alternatives" => [%{"transcript" => "Hello world"}]}]}}}
  """
  def transcribe_url(url, enable_sentiment) do
    listen_url = if enable_sentiment, do: "/listen?sentiment=true", else: "/listen"

    body =
      %{
        url: url,
        language: "en",
        model: "general",
        punctuate: true
      }
      |> Jason.encode()
      |> case do
        {:ok, encoded} -> encoded
        {:error, _} -> "{}"
      end

    post(listen_url, body, [], timeout: @default_timeout, recv_timeout: @default_recv_timeout)
    |> handle_response()
  end

  defp handle_response({:ok, %{status_code: 200, body: body}}) when byte_size(body) > 0 do
    case Jason.decode(body) do
      {:ok, decoded} ->
        {:ok, decoded}

      {:error, error} ->
        Logger.error("Failed to decode Deepgram response: #{inspect(error)}")
        {:error, error}
    end
  end

  defp handle_response({:ok, %{status_code: 200, body: ""}}) do
    Logger.error("Received empty response from Deepgram API")
    {:error, :empty_response}
  end

  defp handle_response({:ok, %{status_code: status_code, body: body}}) do
    Logger.error("Deepgram API error: Status #{status_code}, Body: #{inspect(body)}")
    {:error, %{status_code: status_code, body: body}}
  end

  defp handle_response({:error, error}) do
    Logger.error("Deepgram API request failed: #{inspect(error)}")
    {:error, error}
  end

  defp api_key do
    Application.get_env(:comcent, :deepgram)[:api_key] ||
      raise "Deepgram API key not configured. Please set it in config.exs"
  end

  @doc """
  Generates a summary of the transcript text using Deepgram
  """
  def generate_summary(transcript_text) do
    body =
      %{
        text: transcript_text
      }
      |> Jason.encode()
      |> case do
        {:ok, encoded} ->
          encoded

        {:error, error} ->
          Logger.error("Failed to encode summary request: #{inspect(error)}")
          "{}"
      end

    post("/read?language=en&summarize=true", body, [],
      timeout: @default_timeout,
      recv_timeout: @default_recv_timeout
    )
    |> handle_response()
  end
end
