defmodule Comcent.Schemas.CallSearchVector do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :string, autogenerate: false}
  @foreign_key_type :string
  schema "call_search_vectors" do
    # PostgreSQL vector type, native in Ecto
    field(:embeddings, Pgvector.Ecto.Vector)

    belongs_to(:call_story, Comcent.Schemas.CallStory, foreign_key: :call_story_id)
  end

  def changeset(call_search_vector, attrs) do
    call_search_vector
    |> cast(attrs, [
      :id,
      :embeddings,
      :call_story_id
    ])
    |> validate_required([
      :id,
      :embeddings,
      :call_story_id
    ])
    |> foreign_key_constraint(:call_story_id,
      name: "call_search_vectors_call_story_id_fkey",
      message: "Call story not found"
    )
  end
end
