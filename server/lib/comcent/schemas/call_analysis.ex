defmodule Comcent.Schemas.CallAnalysis do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :string, autogenerate: false}
  @foreign_key_type :string
  schema "call_analyses" do
    field(:provider, :string)
    field(:type, :string)
    field(:analysis_data, :map)

    belongs_to(:call_story, Comcent.Schemas.CallStory, foreign_key: :call_story_id)
  end

  def changeset(call_analysis, attrs) do
    call_analysis
    |> cast(attrs, [:provider, :type, :analysis_data, :call_story_id])
    |> validate_required([:provider, :type, :analysis_data, :call_story_id])
    |> foreign_key_constraint(:call_story_id,
      name: "call_analyses_call_story_id_fkey",
      message: "Call story not found"
    )
  end
end
