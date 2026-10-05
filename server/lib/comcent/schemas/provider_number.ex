defmodule Comcent.Schemas.ProviderNumber do
  @moduledoc """
  Synced inventory of a number as it exists in the provider account,
  including numbers not yet imported into Comcent.

  `original_config` holds the provider-side configuration as it was *before*
  Comcent's first write. It is the only copy: associating a number with a
  Twilio trunk clears `voice_application_sid`, and detaching it later restores
  nothing (verified against a live account).
  """

  use Ecto.Schema
  import Ecto.Changeset
  alias Comcent.Types.Json

  # "missing" = released on the provider side but still referenced here. Rows
  # are marked, never deleted, so a number vanishing under a live queue
  # surfaces instead of disappearing.
  @statuses ~w(available imported missing)

  def statuses, do: @statuses

  @primary_key {:id, :string, autogenerate: false}
  @foreign_key_type :string
  @derive {Jason.Encoder,
           only: [
             :id,
             :e164,
             :provider_sid,
             :friendly_name,
             :capabilities,
             :provider_metadata,
             :last_synced_at,
             :status,
             :provider_connection_id,
             :org_id
           ]}
  schema "provider_numbers" do
    field(:e164, :string)
    field(:provider_sid, :string)
    field(:friendly_name, :string)
    field(:capabilities, Json, default: %{})
    field(:provider_metadata, Json, default: %{})
    field(:original_config, Json)
    field(:last_synced_at, :naive_datetime)
    field(:status, :string, default: "available")

    belongs_to(:provider_connection, Comcent.Schemas.ProviderConnection,
      foreign_key: :provider_connection_id
    )

    belongs_to(:org, Comcent.Schemas.Org, foreign_key: :org_id)
    has_one(:number, Comcent.Schemas.Number, foreign_key: :provider_number_id)

    timestamps(inserted_at: :created_at, updated_at: :updated_at)
  end

  def changeset(provider_number, attrs) do
    provider_number
    |> cast(attrs, [
      :e164,
      :provider_sid,
      :friendly_name,
      :capabilities,
      :provider_metadata,
      :original_config,
      :last_synced_at,
      :status,
      :provider_connection_id,
      :org_id
    ])
    |> validate_required([:e164, :provider_sid, :provider_connection_id, :org_id])
    |> validate_inclusion(:status, @statuses)
    |> unique_constraint([:provider_connection_id, :provider_sid],
      name: :provider_numbers_connection_sid_idx
    )
  end
end
