defmodule Comcent.Schemas.NumberChannel do
  @moduledoc """
  Per-(number, channel) binding.

  One number carries several channels over different transports: voice rides
  the Elastic SIP Trunk while SMS rides an HTTPS webhook on the same number
  (confirmed against a live account). WhatsApp is not a property of the number at all —
  it needs a Sender registration against a WhatsApp Business Account — which is
  why it gets its own row with `status: "pending_verification"` rather than a
  boolean somewhere.

  Only `voice` rows are written today. Other channels need no migration.
  """

  use Ecto.Schema
  import Ecto.Changeset
  alias Comcent.Types.Json

  @channels ~w(voice sms mms whatsapp rcs)
  @statuses ~w(active pending_verification unsupported disabled)
  @transports ~w(sip_trunk webhook messaging_service)

  def channels, do: @channels
  def statuses, do: @statuses
  def transports, do: @transports

  @primary_key {:id, :string, autogenerate: false}
  @foreign_key_type :string
  @derive {Jason.Encoder,
           only: [:id, :channel, :status, :transport, :config, :number_id, :org_id]}
  schema "number_channels" do
    field(:channel, :string)
    field(:status, :string, default: "active")
    field(:transport, :string)
    field(:config, Json, default: %{})

    belongs_to(:number, Comcent.Schemas.Number, foreign_key: :number_id)
    belongs_to(:org, Comcent.Schemas.Org, foreign_key: :org_id)

    timestamps(inserted_at: :created_at, updated_at: :updated_at)
  end

  def changeset(number_channel, attrs) do
    number_channel
    |> cast(attrs, [:channel, :status, :transport, :config, :number_id, :org_id])
    |> validate_required([:channel, :transport, :number_id, :org_id])
    |> validate_inclusion(:channel, @channels)
    |> validate_inclusion(:status, @statuses)
    |> validate_inclusion(:transport, @transports)
    |> unique_constraint([:number_id, :channel], name: :number_channels_number_channel_idx)
  end
end
