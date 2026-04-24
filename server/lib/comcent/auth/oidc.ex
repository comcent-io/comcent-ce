defmodule Comcent.Auth.Oidc do
  alias Comcent.Auth
  alias Comcent.Auth.ProviderConfig

  def build_authorize_url(provider_id, redirect_uri) do
    with {:ok, provider} <- ProviderConfig.fetch_provider(provider_id),
         {:ok, discovery} <- discover(provider) do
      state =
        Auth.sign_state_token(%{
          "provider" => provider_id,
          "redirect_uri" => redirect_uri
        })

      query =
        URI.encode_query(%{
          "response_type" => "code",
          "client_id" => provider.client_id,
          "redirect_uri" => redirect_uri,
          "scope" => Enum.join(provider.scopes, " "),
          "state" => state
        })

      {:ok, "#{discovery["authorization_endpoint"]}?#{query}"}
    end
  end

  def exchange_code_for_user(provider_id, code, state, redirect_uri) do
    with {:ok, claims} <- Auth.verify_any_token(state),
         true <- claims["token_type"] == "oauth_state",
         true <- claims["provider"] == provider_id,
         true <- claims["redirect_uri"] == redirect_uri,
         {:ok, provider} <- ProviderConfig.fetch_provider(provider_id),
         {:ok, discovery} <- discover(provider),
         {:ok, token_response} <- fetch_token(provider, discovery, code, redirect_uri),
         {:ok, user_info} <- fetch_user_info(discovery, token_response["access_token"]) do
      {:ok,
       %{
         provider: provider_id,
         provider_user_id: user_info["sub"],
         email: user_info["email"],
         name: user_info["name"] || user_info["preferred_username"] || user_info["email"],
         picture: user_info["picture"],
         email_verified: user_info["email_verified"] == true
       }}
    else
      false -> {:error, :invalid_state}
      error -> error
    end
  end

  defp discover(provider) do
    issuer = String.trim_trailing(provider.issuer, "/")
    request_json("#{issuer}/.well-known/openid-configuration")
  end

  defp fetch_token(provider, discovery, code, redirect_uri) do
    body =
      URI.encode_query(%{
        "grant_type" => "authorization_code",
        "code" => code,
        "redirect_uri" => redirect_uri,
        "client_id" => provider.client_id,
        "client_secret" => provider.client_secret
      })

    request_json(discovery["token_endpoint"],
      method: :post,
      headers: [{"content-type", "application/x-www-form-urlencoded"}],
      body: body
    )
  end

  defp fetch_user_info(discovery, access_token) do
    request_json(discovery["userinfo_endpoint"],
      headers: [{"authorization", "Bearer #{access_token}"}]
    )
  end

  defp request_json(url, options \\ []) do
    method = Keyword.get(options, :method, :get)
    headers = Keyword.get(options, :headers, [])
    body = Keyword.get(options, :body, "")

    response =
      case method do
        :get -> HTTPoison.get(url, headers)
        :post -> HTTPoison.post(url, body, headers)
      end

    with {:ok, %{status_code: status_code, body: response_body}} when status_code in 200..299 <-
           response,
         {:ok, decoded} <- Jason.decode(response_body) do
      {:ok, decoded}
    else
      {:ok, %{status_code: status_code, body: response_body}} ->
        {:error, {:http_error, status_code, response_body}}

      error ->
        {:error, error}
    end
  end
end
