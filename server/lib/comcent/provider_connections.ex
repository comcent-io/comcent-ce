defmodule Comcent.ProviderConnections do
  @moduledoc """
  Connecting a customer's telephony provider account.

  Credentials are validated against the provider before anything is stored, so
  a connection row never exists in a state we have not proven works.

  There is no periodic re-check: `verify/1` runs only when something asks it
  to, so a key revoked in the provider console keeps a green status until the
  next action touches it. Calls keep flowing regardless -- the trunk
  authenticates by SIP credentials, not by the API key -- so this costs
  management, not service.
  """

  require Logger

  alias Comcent.Repo
  alias Comcent.Repo.ProviderConnection, as: ProviderConnectionRepo
  alias Comcent.Schemas.ProviderConnection
  alias Comcent.Twilio

  @doc """
  Validates credentials with the provider, then stores the connection.

  Deliberately validates first: storing unverified credentials would leave a
  connection that looks healthy in the UI and fails at provisioning time.
  """
  def connect(org, attrs) do
    with :ok <- supported_provider(attrs["provider"]),
         {:ok, auth} <- build_auth(attrs),
         {:ok, account} <- Twilio.verify_credentials(auth) do
      insert_connection(org, attrs, account)
    end
  end

  @doc """
  Replaces the credentials on an existing connection.

  Customers regenerate provider keys as routine hygiene. Without this the
  connection breaks with no way to hand us the new key short of disconnecting
  and re-importing every number.
  """
  def rotate_credentials(%ProviderConnection{} = connection, attrs) do
    with {:ok, auth} <-
           build_auth(Map.put(attrs, "external_account_sid", connection.external_account_sid)),
         {:ok, _account} <- Twilio.verify_credentials(auth) do
      connection
      |> ProviderConnection.changeset(%{
        "credentials" => credentials_from(attrs),
        "status" => "active",
        "last_verified_at" => Comcent.Clock.naive_now()
      })
      |> Repo.update()
    end
  end

  @doc """
  Re-checks stored credentials and records the outcome.

  Only `invalid_credentials` is conclusive. A transport error means we could
  not reach the provider, which says nothing about the credentials, so the
  status is left alone rather than alarming the customer over our own network.
  """
  def verify(%ProviderConnection{} = connection) do
    case Twilio.verify_credentials(auth_for(connection)) do
      {:ok, _account} ->
        touch(connection, "active")

      {:error, {:invalid_credentials, _}} = error ->
        touch(connection, "invalid_credentials")
        error

      {:error, {:transport_error, reason}} = error ->
        Logger.warning(
          "Could not reach provider for connection #{connection.id}: #{inspect(reason)} — leaving status unchanged"
        )

        error

      {:error, _} = error ->
        error
    end
  end

  @doc """
  Basic-auth pair for a stored connection.

  API-key connections carry the whole secret. Other auth methods may carry only
  an account identifier, with the real secret held in our own config — hence
  the credentials map rather than a column per field.
  """
  def auth_for(%ProviderConnection{} = connection) do
    creds = connection.credentials || %{}

    %{
      auth_user: creds["api_key_sid"] || connection.external_account_sid,
      auth_pass: creds["api_key_secret"] || creds["auth_token"],
      account_sid: connection.external_account_sid
    }
  end

  @doc """
  Connection as the API should return it: credentials replaced with a hint.

  The schema already excludes `credentials` from its Jason.Encoder derivation;
  this exists so a caller can show *which* key is configured without the value.
  """
  def to_public(%ProviderConnection{} = connection) do
    connection
    |> Map.take([
      :id,
      :provider,
      :auth_method,
      :label,
      :external_account_sid,
      :status,
      :last_verified_at,
      :metadata,
      :org_id
    ])
    |> Map.put(:credentials_hint, credentials_hint(connection))
  end

  # --- internals -----------------------------------------------------------

  defp insert_connection(org, attrs, account) do
    metadata =
      %{
        "friendly_name" => account["friendly_name"],
        "account_status" => account["status"],
        "account_type" => account["type"]
      }
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)
      |> Map.new()

    %ProviderConnection{id: Ecto.UUID.generate()}
    |> ProviderConnection.changeset(%{
      "provider" => attrs["provider"] || "twilio",
      "auth_method" => attrs["auth_method"] || "api_key",
      "label" => attrs["label"] || account["friendly_name"] || "Twilio",
      "external_account_sid" => attrs["external_account_sid"],
      "credentials" => credentials_from(attrs),
      "status" => "active",
      "last_verified_at" => Comcent.Clock.naive_now(),
      "metadata" => metadata,
      "org_id" => org.id
    })
    |> Repo.insert()
  end

  # The schema permits "telnyx" so the column is ready for Telnyx, but every
  # call in this module and in Provisioning goes to Comcent.Twilio. Accepting
  # one would store a connection labelled Telnyx whose traffic all went to
  # api.twilio.com.
  defp supported_provider(provider) when provider in [nil, "twilio"], do: :ok

  defp supported_provider(provider),
    do: {:error, {:validation, "#{provider} connections are not supported yet"}}

  defp build_auth(attrs) do
    account_sid = attrs["external_account_sid"]
    creds = credentials_from(attrs)

    cond do
      is_nil(account_sid) or account_sid == "" ->
        {:error, {:validation, "external_account_sid is required"}}

      is_nil(creds["api_key_secret"]) or creds["api_key_secret"] == "" ->
        {:error, {:validation, "api_key_secret is required"}}

      true ->
        {:ok,
         %{
           auth_user: creds["api_key_sid"] || account_sid,
           auth_pass: creds["api_key_secret"],
           account_sid: account_sid
         }}
    end
  end

  defp credentials_from(attrs) do
    %{
      "api_key_sid" => attrs["api_key_sid"],
      "api_key_secret" => attrs["api_key_secret"]
    }
    |> Enum.reject(fn {_k, v} -> is_nil(v) or v == "" end)
    |> Map.new()
  end

  # Last four characters only. Enough to tell two keys apart when rotating,
  # useless to anyone who sees a response body or a screenshot.
  defp credentials_hint(%ProviderConnection{credentials: creds}) when is_map(creds) do
    case creds["api_key_sid"] do
      nil -> nil
      sid -> "…" <> String.slice(sid, -4, 4)
    end
  end

  defp credentials_hint(_), do: nil

  defp touch(connection, status) do
    connection
    |> ProviderConnection.changeset(%{
      "status" => status,
      "last_verified_at" => Comcent.Clock.naive_now()
    })
    |> Repo.update()
  end

  @doc false
  def list_for_org(subdomain), do: ProviderConnectionRepo.get_all_by_org(subdomain)
end
