defmodule Comcent.Twilio do
  @moduledoc """
  Twilio REST client.

  Per-request credentials, not global config: every call acts on a specific
  customer's connected account, so auth is passed in rather than read from
  application env the way `Comcent.Deepgram` does.

  Two hosts are in play and mixing them up is the classic mistake here:

    * `api.twilio.com/2010-04-01/Accounts/{sid}` — accounts, numbers, SIP
      credential lists
    * `trunking.twilio.com/v1` — Elastic SIP Trunks

  ## A 2xx does not mean the write took effect

  Verified three times against a live account:

    * `POST /Trunks` without `DomainName` returns 201 with `domain_name: null` —
      a trunk that can never route
    * associating a number already on another trunk returns 201 and silently
      steals it
    * setting `sms_url` on a number in a Messaging Service returns 200 and is
      ignored

  Callers must read back and assert the intended end state. This module returns
  what Twilio said; it does not claim the write worked.
  """

  require Logger

  @api_base "https://api.twilio.com/2010-04-01"
  @trunking_base "https://trunking.twilio.com/v1"
  @timeout 15_000
  @recv_timeout 30_000

  @typedoc """
  Basic-auth pair plus the account SID used in URL paths.

  For an API-key connection the auth user is the key SID and `account_sid` is
  the account it belongs to. For account credentials both are the account SID.
  """
  @type auth :: %{auth_user: String.t(), auth_pass: String.t(), account_sid: String.t()}

  @type error ::
          {:invalid_credentials, String.t()}
          | {:forbidden, String.t()}
          | {:not_found, String.t()}
          | {:rate_limited, String.t()}
          | {:twilio_error, integer(), String.t()}
          | {:transport_error, term()}

  # --- account -------------------------------------------------------------

  @doc """
  Fetches the account. Doubles as credential verification: cheap, authenticated,
  and it fails exactly when the credentials are wrong.
  """
  @spec get_account(auth) :: {:ok, map()} | {:error, error}
  def get_account(%{account_sid: sid} = auth) do
    get(auth, "#{@api_base}/Accounts/#{sid}.json")
  end

  @doc """
  Verifies credentials by exercising the permission we actually need.

  Deliberately does **not** probe `/Accounts`: a Standard API key — the type we
  ask customers to create — has no access to that endpoint, so verifying there
  would reject exactly the credentials we recommend. Listing phone numbers
  proves the key can do the job we will ask of it, which is the more useful
  assertion anyway.

  Account metadata (friendly name, type, status) is a nice-to-have used for
  labelling, so it is fetched separately and its absence is not a failure.
  """
  @spec verify_credentials(auth) :: {:ok, map()} | {:error, error}
  def verify_credentials(%{account_sid: sid} = auth) do
    case get(auth, "#{@api_base}/Accounts/#{sid}/IncomingPhoneNumbers.json?PageSize=1") do
      {:ok, _} -> {:ok, account_metadata(auth)}
      {:error, _} = error -> error
    end
  end

  # Best effort: works with account credentials, quietly skipped with a Standard
  # key. Never the reason a connection is rejected.
  defp account_metadata(%{account_sid: sid} = auth) do
    case get_account(auth) do
      {:ok, account} -> Map.take(account, ["sid", "friendly_name", "status", "type"])
      {:error, _} -> %{"sid" => sid}
    end
  end

  # --- phone numbers -------------------------------------------------------

  @doc """
  Lists incoming phone numbers, following pagination.

  Note the resource carries no `messaging_service_sid` field — Messaging Service
  membership is invisible from here and needs a separate traversal of
  `messaging.twilio.com/v1/Services`.
  """
  @spec list_incoming_phone_numbers(auth) :: {:ok, [map()]} | {:error, error}
  def list_incoming_phone_numbers(%{account_sid: sid} = auth) do
    paginate(auth, "#{@api_base}/Accounts/#{sid}/IncomingPhoneNumbers.json?PageSize=100",
      key: "incoming_phone_numbers"
    )
  end

  @spec get_incoming_phone_number(auth, String.t()) :: {:ok, map()} | {:error, error}
  def get_incoming_phone_number(%{account_sid: sid} = auth, phone_number_sid) do
    get(auth, "#{@api_base}/Accounts/#{sid}/IncomingPhoneNumbers/#{phone_number_sid}.json")
  end

  @spec update_incoming_phone_number(auth, String.t(), keyword() | map()) ::
          {:ok, map()} | {:error, error}
  def update_incoming_phone_number(%{account_sid: sid} = auth, phone_number_sid, params) do
    post(
      auth,
      "#{@api_base}/Accounts/#{sid}/IncomingPhoneNumbers/#{phone_number_sid}.json",
      params
    )
  end

  # --- trunking ------------------------------------------------------------

  @doc """
  Creates an Elastic SIP Trunk.

  `domain_name` is required in practice even though Twilio treats it as
  optional: omit it and the trunk comes back with `domain_name: null` and no
  termination URI, so nothing can route. It must also be globally unique —
  a collision returns `400 [21248]`, which callers should handle by
  regenerating the label rather than surfacing the error.
  """
  @spec create_trunk(auth, String.t(), String.t()) :: {:ok, map()} | {:error, error}
  def create_trunk(auth, friendly_name, domain_name) do
    post(auth, "#{@trunking_base}/Trunks",
      FriendlyName: friendly_name,
      DomainName: domain_name
    )
  end

  @spec get_trunk(auth, String.t()) :: {:ok, map()} | {:error, error}
  def get_trunk(auth, trunk_sid), do: get(auth, "#{@trunking_base}/Trunks/#{trunk_sid}")

  @spec delete_trunk(auth, String.t()) :: :ok | {:error, error}
  def delete_trunk(auth, trunk_sid), do: delete(auth, "#{@trunking_base}/Trunks/#{trunk_sid}")

  @doc """
  Adds an origination URL (Twilio -> our SBC). All five parameters are required
  by the API. The host may be an FQDN, so the SBC needs a stable public name
  but not a static IP.
  """
  @spec create_origination_url(auth, String.t(), keyword()) :: {:ok, map()} | {:error, error}
  def create_origination_url(auth, trunk_sid, opts) do
    post(auth, "#{@trunking_base}/Trunks/#{trunk_sid}/OriginationUrls",
      FriendlyName: Keyword.fetch!(opts, :friendly_name),
      SipUrl: Keyword.fetch!(opts, :sip_url),
      Priority: Keyword.get(opts, :priority, 10),
      Weight: Keyword.get(opts, :weight, 10),
      Enabled: Keyword.get(opts, :enabled, true)
    )
  end

  @doc "Creates a SIP credential list. Note: Account API, not the Trunking API."
  @spec create_credential_list(auth, String.t()) :: {:ok, map()} | {:error, error}
  def create_credential_list(%{account_sid: sid} = auth, friendly_name) do
    post(auth, "#{@api_base}/Accounts/#{sid}/SIP/CredentialLists.json",
      FriendlyName: friendly_name
    )
  end

  @spec create_credential(auth, String.t(), String.t(), String.t()) ::
          {:ok, map()} | {:error, error}
  def create_credential(%{account_sid: sid} = auth, credential_list_sid, username, password) do
    post(
      auth,
      "#{@api_base}/Accounts/#{sid}/SIP/CredentialLists/#{credential_list_sid}/Credentials.json",
      Username: username,
      Password: password
    )
  end

  @spec delete_credential_list(auth, String.t()) :: :ok | {:error, error}
  def delete_credential_list(%{account_sid: sid} = auth, credential_list_sid) do
    delete(auth, "#{@api_base}/Accounts/#{sid}/SIP/CredentialLists/#{credential_list_sid}.json")
  end

  @spec attach_credential_list(auth, String.t(), String.t()) :: {:ok, map()} | {:error, error}
  def attach_credential_list(auth, trunk_sid, credential_list_sid) do
    post(auth, "#{@trunking_base}/Trunks/#{trunk_sid}/CredentialLists",
      CredentialListSid: credential_list_sid
    )
  end

  @doc """
  Associates a phone number with a trunk.

  **Check the number's `trunk_sid` first.** Twilio accepts this for a number
  already on another trunk, returns 201, and silently moves it — breaking
  whatever that trunk was serving, with no error to catch.
  """
  @spec associate_phone_number(auth, String.t(), String.t()) :: {:ok, map()} | {:error, error}
  def associate_phone_number(auth, trunk_sid, phone_number_sid) do
    post(auth, "#{@trunking_base}/Trunks/#{trunk_sid}/PhoneNumbers",
      PhoneNumberSid: phone_number_sid
    )
  end

  @spec disassociate_phone_number(auth, String.t(), String.t()) :: :ok | {:error, error}
  def disassociate_phone_number(auth, trunk_sid, phone_number_sid) do
    delete(auth, "#{@trunking_base}/Trunks/#{trunk_sid}/PhoneNumbers/#{phone_number_sid}")
  end

  # --- webhook signature ---------------------------------------------------

  @doc """
  Validates an `X-Twilio-Signature` header.

  Twilio signs the full request URL concatenated with the POST parameters
  sorted by key, HMAC-SHA1 with the account's auth token, base64 encoded.

  Note this requires the **auth token**, not an API key secret — a connection
  authenticated with an API key cannot validate inbound webhooks this way.
  Comparison is constant-time.
  """
  @spec valid_signature?(String.t(), String.t(), map(), String.t()) :: boolean()
  def valid_signature?(signature, url, params, auth_token)
      when is_binary(signature) and is_binary(url) and is_map(params) and is_binary(auth_token) do
    payload =
      params
      |> Enum.sort_by(fn {k, _v} -> to_string(k) end)
      |> Enum.reduce(url, fn {k, v}, acc -> acc <> to_string(k) <> to_string(v) end)

    expected =
      :crypto.mac(:hmac, :sha, auth_token, payload)
      |> Base.encode64()

    Plug.Crypto.secure_compare(expected, signature)
  end

  def valid_signature?(_, _, _, _), do: false

  # --- transport -----------------------------------------------------------

  defp get(auth, url), do: request(auth, :get, url, "")

  defp post(auth, url, params) do
    request(auth, :post, url, URI.encode_query(normalize(params)))
  end

  defp delete(auth, url) do
    case request(auth, :delete, url, "") do
      {:ok, _} -> :ok
      {:error, _} = error -> error
    end
  end

  # Only nil is dropped. An empty string is meaningful to Twilio: it is how a
  # field is cleared, and how a number is detached from a trunk. Stripping it
  # would make "unset this" silently do nothing.
  defp normalize(params) do
    params
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Enum.map(fn {k, v} -> {to_string(k), to_string(v)} end)
  end

  defp paginate(auth, url, key: key), do: paginate(auth, url, key, [])

  defp paginate(auth, url, key, acc) do
    case get(auth, url) do
      {:ok, body} ->
        items = acc ++ Map.get(body, key, [])

        case body["next_page_uri"] do
          nil -> {:ok, items}
          "" -> {:ok, items}
          next -> paginate(auth, "https://api.twilio.com" <> next, key, items)
        end

      {:error, _} = error ->
        error
    end
  end

  defp request(%{auth_user: user, auth_pass: pass}, method, url, body) do
    headers =
      case method do
        :post -> [{"Content-Type", "application/x-www-form-urlencoded"}]
        _ -> []
      end

    options = [
      hackney: [basic_auth: {user, pass}],
      timeout: @timeout,
      recv_timeout: @recv_timeout
    ]

    case HTTPoison.request(method, url, body, headers, options) do
      {:ok, %HTTPoison.Response{status_code: status, body: raw}} when status in 200..299 ->
        {:ok, decode(raw)}

      {:ok, %HTTPoison.Response{status_code: status, body: raw}} ->
        {:error, classify(status, decode(raw))}

      {:error, %HTTPoison.Error{reason: reason}} ->
        Logger.error("Twilio request failed: #{inspect(reason)} (#{method} #{url})")
        {:error, {:transport_error, reason}}
    end
  end

  defp decode(""), do: %{}

  defp decode(raw) do
    case Jason.decode(raw) do
      {:ok, decoded} when is_map(decoded) -> decoded
      _ -> %{}
    end
  end

  # Twilio's own error codes are more useful than the HTTP status: 20003 is an
  # auth failure regardless of whether it arrives as 401 or 403.
  defp classify(status, body) do
    code = body["code"]
    message = body["message"] || body["detail"] || "Twilio request failed with status #{status}"

    case {status, code} do
      {_, 20003} -> {:invalid_credentials, message}
      {401, _} -> {:invalid_credentials, message}
      {403, _} -> {:forbidden, message}
      {404, _} -> {:not_found, message}
      {429, _} -> {:rate_limited, message}
      _ -> {:twilio_error, code || status, message}
    end
  end
end
