defmodule Comcent.Schemas.OrgWebhook do
  use Ecto.Schema
  import Ecto.Changeset

  @url_regex ~r/^https?:\/\/[a-zA-Z0-9]/

  @primary_key {:id, :string, autogenerate: false}
  @foreign_key_type :string
  @derive {Jason.Encoder,
           only: [
             :id,
             :webhook_url,
             :events,
             :name,
             :auth_token,
             :org_id
           ]}
  schema "org_webhooks" do
    field(:webhook_url, :string)
    field(:events, {:array, :string})
    field(:name, :string)
    field(:auth_token, :string)

    belongs_to(:org, Comcent.Schemas.Org, foreign_key: :org_id)

    timestamps(inserted_at: :created_at, updated_at: :updated_at)
  end

  def changeset(org_webhook, attrs) do
    org_webhook
    |> cast(attrs, [:webhook_url, :events, :name, :auth_token, :org_id])
    |> validate_required([:webhook_url, :events, :name, :auth_token, :org_id])
    |> validate_length(:name, min: 3, message: "String must contain at least 3 character(s)")
    |> validate_format(:webhook_url, @url_regex, message: "Invalid Webhook URL format")
    |> validate_change(:webhook_url, fn :webhook_url, webhook_url ->
      case URI.parse(webhook_url) do
        %URI{scheme: scheme, host: host}
        when scheme in ["http", "https"] and is_binary(host) and host != "" ->
          []

        _ ->
          [webhook_url: "Invalid Webhook URL format"]
      end
    end)
    |> validate_change(:events, fn :events, events ->
      if is_list(events) and events != [] do
        []
      else
        [events: "Please select at least one event"]
      end
    end)
  end
end
