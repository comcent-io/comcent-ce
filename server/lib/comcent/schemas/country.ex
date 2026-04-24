defmodule Comcent.Schemas.Country do
  use Ecto.Schema

  @primary_key {:id, :integer, autogenerate: false}
  @foreign_key_type :string
  schema "countries" do
    field(:code, :string)
    field(:name, :string)

    has_many(:states, Comcent.Schemas.State, foreign_key: :country_code, references: :code)
  end
end
