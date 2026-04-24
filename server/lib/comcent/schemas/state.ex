defmodule Comcent.Schemas.State do
  use Ecto.Schema

  @primary_key {:id, :integer, autogenerate: false}
  @foreign_key_type :string
  schema "states" do
    field(:name, :string)
    field(:country_code, :string)

    belongs_to(:country, Comcent.Schemas.Country,
      foreign_key: :country_code,
      references: :code,
      define_field: false,
      type: :string
    )
  end
end
