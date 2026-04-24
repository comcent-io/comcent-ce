defmodule Comcent.Search do
  @moduledoc """
  Module for handling search functionality.
  """

  require Logger

  def search_index_the_call_story(call_story, transcriptions) do
    parties = transcriptions |> Enum.map(& &1.current_party) |> Enum.uniq()

    with {:ok, transcript_text} <- Comcent.Transcript.create_transcript_text(call_story),
         true <- is_binary(transcript_text) do
      text_to_index = """
      From: #{call_story.caller}
      To: #{call_story.callee}
      Direction: #{call_story.direction}
      Parties: #{Enum.join(parties, ", ")}
      Transcript: #{transcript_text}
      """

      chunk_and_embed_transcriptions(call_story, text_to_index)
    else
      _ ->
        :ok
    end
  end

  # Chunks each transcription, generates embeddings, and stores them in CallSearchVector
  defp chunk_and_embed_transcriptions(call_story, transcript_text) do
    if transcript_text != "" do
      # Chunk the text using TextChunker
      opts = [
        chunk_size: 250,
        chunk_overlap: 50,
        format: :plaintext,
        strategy: TextChunker.Strategies.RecursiveChunk
      ]

      chunks =
        TextChunker.split(transcript_text, opts)

      Logger.info("######### Number of chunks: #{length(chunks)}")

      Enum.each(chunks, fn chunk ->
        # Get embedding from OpenAI (assume returns {:ok, embedding} or {:error, reason})
        case Comcent.OpenAI.embed_text(chunk.text) do
          {:ok, embedding} ->
            Comcent.Repo.CallSearchVector.insert_embedding(call_story.id, embedding)

          {:error, reason} ->
            Logger.error("OpenAI embedding failed: #{inspect(reason)}")
        end
      end)
    end

    :ok
  end
end
