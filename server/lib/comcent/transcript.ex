defmodule Comcent.Transcript do
  @moduledoc """
  Module for handling transcript creation and formatting.
  """

  alias Comcent.Schemas.CallStory

  @type sentence :: %{
          current_party: String.t(),
          timestamp: integer(),
          text: String.t()
        }

  @type chat :: %{
          current_party: String.t(),
          start: number(),
          message: String.t()
        }

  @doc """
  Gets sorted sentences from call transcripts.
  """
  @spec get_sorted_sentences(CallStory.t()) :: [sentence()]
  def get_sorted_sentences(call_story) do
    sentences =
      Enum.flat_map(call_story.call_transcripts, fn transcript ->
        data = transcript.transcript_data

        related_call_span =
          Enum.find(call_story.call_spans, fn span ->
            metadata = span.metadata

            span.current_party == transcript.current_party &&
              span.type == "RECORDING" &&
              metadata["direction"] == "in"
          end)

        start_at = related_call_span && related_call_span.start_at

        channels = get_in(data, ["results", "channels"]) || []

        Enum.flat_map(channels, fn channel ->
          alternatives = channel["alternatives"] || []

          Enum.flat_map(alternatives, fn alternative ->
            words = alternative["words"] || []

            Enum.map(words, fn word ->
              timestamp =
                if start_at do
                  # Convert start_at to Unix timestamp if it's a DateTime
                  start_at_unix =
                    case start_at do
                      %DateTime{} -> DateTime.to_unix(start_at)
                      _ -> start_at
                    end

                  # Add the word's start time to the call start time
                  start_at_unix + trunc(word["start"])
                else
                  0
                end

              %{
                current_party: transcript.current_party,
                timestamp: timestamp,
                text: word["word"]
              }
            end)
          end)
        end)
      end)

    Enum.sort_by(sentences, & &1.timestamp)
  end

  @doc """
  Creates a formatted text transcript from call story.
  """
  @spec create_transcript_text(CallStory.t()) :: {:ok, String.t()}
  def create_transcript_text(call_story) do
    sorted_sentences = get_sorted_sentences(call_story)

    {final_transcript, _} =
      Enum.reduce(sorted_sentences, {"", ""}, fn sentence, {transcript, current_party} ->
        if current_party != sentence.current_party do
          new_transcript = transcript <> "\n\n#{sentence.current_party}:"
          {new_transcript, sentence.current_party}
        else
          {transcript <> " " <> sentence.text, current_party}
        end
      end)

    {:ok, String.trim(final_transcript)}
  end

  @doc """
  Creates a chat-style transcript from call story.
  """
  @spec create_transcript_chat(CallStory.t()) :: [chat()]
  def create_transcript_chat(call_story) do
    sorted_sentences = get_sorted_sentences(call_story)

    {transcript_messages, current_chat} =
      Enum.reduce(sorted_sentences, {[], nil}, fn sentence, {messages, current_chat} ->
        if current_chat == nil do
          new_chat = %{
            current_party: sentence.current_party,
            start: sentence.timestamp,
            message: sentence.text
          }

          {messages, new_chat}
        else
          if current_chat.current_party != sentence.current_party do
            new_chat = %{
              current_party: sentence.current_party,
              start: sentence.timestamp,
              message: sentence.text
            }

            {messages ++ [current_chat], new_chat}
          else
            updated_chat = %{
              current_chat
              | message: current_chat.message <> " " <> sentence.text
            }

            {messages, updated_chat}
          end
        end
      end)

    if current_chat do
      transcript_messages ++ [current_chat]
    else
      transcript_messages
    end
  end
end
