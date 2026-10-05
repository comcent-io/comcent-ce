defmodule Comcent.Vault do
  @moduledoc """
  Cloak vault for provider credentials.

  Encrypts `provider_connections.credentials` at rest. A Method B connection
  holds the customer's Twilio API key secret, which is full account access — it
  can buy numbers and spend their money.

  The key comes from `PROVIDER_CREDENTIALS_KEY` (base64, 32 bytes) and is wired
  in `config/runtime.exs`. It is optional: a self-hosted install is often torn
  down and set up again, and a key lost on the way would make every stored
  credential undecryptable. Without one the credentials are stored unencrypted
  and a warning is logged at boot; see `Comcent.Encrypted.Map`.
  """

  use Cloak.Vault, otp_app: :comcent

  require Logger

  @impl GenServer
  def init(config) do
    ciphers =
      case key() do
        nil ->
          Logger.warning(
            "PROVIDER_CREDENTIALS_KEY is not set, so provider (Twilio) credentials are stored unencrypted in the database."
          )

          []

        key ->
          [default: {Cloak.Ciphers.AES.GCM, tag: "AES.GCM.V1", key: key, iv_length: 12}]
      end

    {:ok, Keyword.put(config, :ciphers, ciphers)}
  end

  @doc "Whether an encryption key is configured."
  def enabled?, do: key() != nil

  defp key do
    case Application.get_env(:comcent, __MODULE__)[:key] do
      empty when empty in [nil, ""] ->
        nil

      encoded when is_binary(encoded) ->
        case Base.decode64(encoded) do
          {:ok, key} when byte_size(key) == 32 ->
            key

          {:ok, key} ->
            raise "PROVIDER_CREDENTIALS_KEY must decode to 32 bytes, got #{byte_size(key)}"

          :error ->
            raise "PROVIDER_CREDENTIALS_KEY is not valid base64"
        end
    end
  end
end
