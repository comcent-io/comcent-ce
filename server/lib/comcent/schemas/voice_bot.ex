defmodule Comcent.Schemas.VoiceBot do
  use Ecto.Schema
  import Ecto.Changeset
  @primary_key {:id, :string, autogenerate: false}
  @foreign_key_type :string
  @derive {Jason.Encoder,
           only: [
             :id,
             :name,
             :instructions,
             :not_to_do_instructions,
             :greeting_instructions,
             :mcp_servers,
             :api_key,
             :is_hangup,
             :is_enqueue,
             :queues,
             :pipeline,
             :org_id
           ]}
  schema "voice_bots" do
    field(:name, :string)
    field(:instructions, :string)
    field(:not_to_do_instructions, :string)
    field(:greeting_instructions, :string, default: "")
    # Stored as JSONB containing an array of objects like [%{"url" => "...", "token" => "..."}]
    field(:mcp_servers, {:array, :map}, default: [])
    field(:api_key, :string)
    field(:is_hangup, :boolean, default: false)
    field(:is_enqueue, :boolean, default: false)
    field(:queues, {:array, :string})
    field(:pipeline, :string)
    belongs_to(:org, Comcent.Schemas.Org, foreign_key: :org_id)
  end

  def changeset(voice_bot, attrs) do
    voice_bot
    |> cast(attrs, [
      :name,
      :instructions,
      :not_to_do_instructions,
      :greeting_instructions,
      :mcp_servers,
      :api_key,
      :is_hangup,
      :is_enqueue,
      :queues,
      :pipeline,
      :org_id
    ])
    |> put_default_mcp_servers()
    |> validate_required([
      :name,
      :instructions,
      :not_to_do_instructions,
      :mcp_servers,
      :api_key,
      :pipeline,
      :org_id
    ])
    |> validate_length(:name, min: 3)
    |> validate_length(:instructions, min: 3)
    |> validate_length(:not_to_do_instructions, min: 3)
  end

  defp put_default_mcp_servers(changeset) do
    case get_field(changeset, :mcp_servers) do
      nil -> put_change(changeset, :mcp_servers, [])
      _ -> changeset
    end
  end
end
