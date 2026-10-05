defmodule Comcent.Encrypted.Map do
  @moduledoc """
  Map field stored as BYTEA, encrypted when `Comcent.Vault` has a key.

  Used for `provider_connections.credentials`, whose shape differs by
  `auth_method`: an API-key connection carries the customer's key SID and
  secret, while other methods may carry nothing at all. A map keeps that
  open rather than forcing a column per credential shape.

  With a key the stored bytes are what `Cloak.Ecto.Map` writes: the JSON,
  encrypted by the vault. Without one they are the JSON itself. The two are
  told apart on load by the first byte -- JSON for a map starts with `{`,
  Cloak's ciphertext with a version byte -- so rows written before a key was
  added keep loading after it is.
  """

  use Ecto.Type

  require Logger

  alias Comcent.Vault

  @impl true
  def type, do: :binary

  @impl true
  def cast(nil), do: {:ok, nil}
  def cast(value) when is_map(value), do: {:ok, value}
  def cast(_), do: :error

  @impl true
  def dump(nil), do: {:ok, nil}

  def dump(value) when is_map(value) do
    json = Jason.encode!(value)
    {:ok, if(Vault.enabled?(), do: Vault.encrypt!(json), else: json)}
  end

  def dump(_), do: :error

  @impl true
  def load(nil), do: {:ok, nil}
  def load("{" <> _ = json), do: Jason.decode(json)

  def load(ciphertext) when is_binary(ciphertext) do
    if Vault.enabled?() do
      Jason.decode(Vault.decrypt!(ciphertext))
    else
      Logger.error(
        "Stored provider credentials are encrypted but PROVIDER_CREDENTIALS_KEY is not set. Set the key they were saved with, or reconnect the provider account."
      )

      :error
    end
  end
end
