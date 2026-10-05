defmodule Comcent.Schemas.ProviderConnection do
  @moduledoc """
  A connected provider account. An org may hold several.

  `credentials` is encrypted at rest and deliberately excluded from the
  Jason.Encoder derivation — the API returns masked values only, never the
  stored secret.
  """

  use Ecto.Schema
  import Ecto.Changeset
  alias Comcent.Types.Json

  @providers ~w(twilio telnyx)
  @auth_methods ~w(api_key connect_subaccount)
  # "unmanaged" means the customer asked us to stop managing the account: we
  # hold no credentials any more, but the trunk we built is still live in their
  # provider account and still carrying calls. It is not "disconnected" -- a
  # full disconnect deletes the row outright.
  @statuses ~w(active invalid_credentials revoked unmanaged)

  def providers, do: @providers
  def auth_methods, do: @auth_methods
  def statuses, do: @statuses

  @primary_key {:id, :string, autogenerate: false}
  @foreign_key_type :string
  @derive {Jason.Encoder,
           only: [
             :id,
             :provider,
             :auth_method,
             :label,
             :external_account_sid,
             :status,
             :last_verified_at,
             :metadata,
             :org_id
           ]}
  schema "provider_connections" do
    field(:provider, :string)
    field(:auth_method, :string)
    field(:label, :string)
    field(:external_account_sid, :string)
    field(:credentials, Comcent.Encrypted.Map)
    field(:status, :string, default: "active")
    field(:last_verified_at, :naive_datetime)
    field(:metadata, Json, default: %{})

    belongs_to(:org, Comcent.Schemas.Org, foreign_key: :org_id)

    has_many(:provider_numbers, Comcent.Schemas.ProviderNumber,
      foreign_key: :provider_connection_id
    )

    timestamps(inserted_at: :created_at, updated_at: :updated_at)
  end

  def changeset(provider_connection, attrs) do
    provider_connection
    |> cast(attrs, [
      :provider,
      :auth_method,
      :label,
      :external_account_sid,
      :credentials,
      :status,
      :last_verified_at,
      :metadata,
      :org_id
    ])
    |> validate_required([:provider, :auth_method, :label, :external_account_sid, :org_id])
    |> validate_inclusion(:provider, @providers)
    |> validate_inclusion(:auth_method, @auth_methods)
    |> validate_inclusion(:status, @statuses)
    |> unique_constraint([:org_id, :provider, :external_account_sid],
      name: :provider_connections_org_account_idx,
      message: "this provider account is already connected"
    )
  end
end
