defmodule Comcent.SipDomain do
  @moduledoc """
  An org's SIP domain is `<subdomain>.<SIP user root domain>`, and the root
  domain can have any number of labels: `example.com` or `sip.example.com`.
  Code that needs the org from a SIP domain asks here rather than counting
  dots, which only worked for a two-label root domain.
  """

  @doc """
  The org subdomain of a SIP domain: `{:ok, "acme"}` for
  `"acme.sip.example.com"` when the root domain is `sip.example.com`;
  `:error` for any other domain, or one with dots before the root domain.
  """
  def subdomain(domain) when is_binary(domain) do
    suffix = "." <> Application.fetch_env!(:comcent, :sip_user_root_domain)

    with true <- String.ends_with?(domain, suffix),
         subdomain = String.replace_suffix(domain, suffix, ""),
         true <- subdomain != "" and not String.contains?(subdomain, ".") do
      {:ok, subdomain}
    else
      _ -> :error
    end
  end

  def subdomain(_), do: :error
end
