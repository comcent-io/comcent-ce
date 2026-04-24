defmodule Comcent.OpenAI do
  require Logger
  alias HTTPoison

  def embed_text(text) do
    openai_api_key = Application.get_env(:comcent, :openai)[:api_key]
    url = "https://api.openai.com/v1/embeddings"

    headers = [
      {"Content-Type", "application/json"},
      {"Authorization", "Bearer #{openai_api_key}"}
    ]

    body =
      Jason.encode!(%{
        "input" => text,
        "model" => "text-embedding-3-small"
      })

    case HTTPoison.post(url, body, headers) do
      {:ok, %HTTPoison.Response{status_code: 200, body: resp_body}} ->
        case Jason.decode(resp_body) do
          {:ok, %{"data" => [%{"embedding" => embedding} | _]}} ->
            {:ok, embedding}

          {:ok, %{"error" => error}} ->
            {:error, error}

          error ->
            {:error, error}
        end

      {:ok, %HTTPoison.Response{status_code: code, body: resp_body}} ->
        {:error, %{status: code, body: resp_body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Sends a chat completion request to OpenAI API
  """
  def chat_completion(messages, temperature \\ 0, model \\ "gpt-4o-mini") do
    openai_api_key = Application.get_env(:comcent, :openai)[:api_key]
    url = "https://api.openai.com/v1/chat/completions"

    headers = [
      {"Content-Type", "application/json"},
      {"Authorization", "Bearer #{openai_api_key}"}
    ]

    body =
      Jason.encode!(%{
        "model" => model,
        "messages" => messages,
        "temperature" => temperature
      })

    case HTTPoison.post(url, body, headers, timeout: 30_000, recv_timeout: 30_000) do
      {:ok, %HTTPoison.Response{status_code: 200, body: resp_body}} ->
        case Jason.decode(resp_body) do
          {:ok, %{"choices" => [%{"message" => %{"content" => content}} | _]}} ->
            {:ok, content}

          {:ok, %{"error" => error}} ->
            Logger.error("OpenAI API error: #{inspect(error)}")
            {:error, error}

          error ->
            Logger.error("Failed to decode OpenAI response: #{inspect(error)}")
            {:error, error}
        end

      {:ok, %HTTPoison.Response{status_code: code, body: resp_body}} ->
        Logger.error("OpenAI API error: Status #{code}, Body: #{inspect(resp_body)}")
        {:error, %{status: code, body: resp_body}}

      {:error, reason} ->
        Logger.error("HTTP request to OpenAI failed: #{inspect(reason)}")
        {:error, reason}
    end
  end
end
