defmodule Comcent.Repo.CallSearchVector do
  require Logger
  alias Comcent.Schemas.CallSearchVector
  alias Comcent.Repo

  @doc """
  Inserts an embedding for a given call_story_id into the CallSearchVector table.
  The embedding is encoded as a JSON string.
  """
  def insert_embedding(call_story_id, embedding) do
    changeset =
      CallSearchVector.changeset(%CallSearchVector{}, %{
        id: Ecto.UUID.generate(),
        embeddings: embedding,
        call_story_id: call_story_id
      })

    case Repo.insert(changeset) do
      {:ok, _} ->
        :ok

      {:error, err} ->
        Logger.error("Failed to insert CallSearchVector: #{inspect(err)}")
        :error
    end
  end
end
