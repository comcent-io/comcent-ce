defmodule Comcent.Auth.ProviderConfig do
  @default_scopes ["openid", "email", "profile"]

  def password_enabled? do
    auth_config()[:password_enabled] != false
  end

  def public_provider_configs do
    auth_config()
    |> Keyword.get(:oidc_providers, %{})
    |> Enum.map(fn {provider_id, provider_config} ->
      %{
        id: provider_id,
        label: Map.get(provider_config, "label", provider_id),
        type: "oidc"
      }
    end)
    |> Enum.sort_by(& &1.id)
  end

  def fetch_provider(provider_id) when is_binary(provider_id) do
    case auth_config()[:oidc_providers][provider_id] do
      nil -> {:error, :provider_not_found}
      config -> {:ok, normalize_provider(provider_id, config)}
    end
  end

  defp auth_config do
    Application.get_env(:comcent, :auth, password_enabled: true, oidc_providers: %{})
  end

  defp normalize_provider(provider_id, config) do
    %{
      id: provider_id,
      label: Map.get(config, "label", provider_id),
      issuer: Map.fetch!(config, "issuer"),
      client_id: Map.fetch!(config, "client_id"),
      client_secret: Map.fetch!(config, "client_secret"),
      scopes: Map.get(config, "scopes", @default_scopes)
    }
  end
end
