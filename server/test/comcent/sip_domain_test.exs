defmodule Comcent.SipDomainTest do
  # Not async: the SIP user root domain is application config.
  use ExUnit.Case, async: false

  alias Comcent.SipDomain

  setup do
    original = Application.fetch_env!(:comcent, :sip_user_root_domain)
    on_exit(fn -> Application.put_env(:comcent, :sip_user_root_domain, original) end)
  end

  test "the org is what comes before a root domain of any length" do
    Application.put_env(:comcent, :sip_user_root_domain, "sip.example.com")
    assert SipDomain.subdomain("acme.sip.example.com") == {:ok, "acme"}

    Application.put_env(:comcent, :sip_user_root_domain, "example.com")
    assert SipDomain.subdomain("acme.example.com") == {:ok, "acme"}
  end

  test "anything else is not an org's SIP domain" do
    Application.put_env(:comcent, :sip_user_root_domain, "sip.example.com")

    assert SipDomain.subdomain("acme.example.com") == :error
    assert SipDomain.subdomain("x.acme.sip.example.com") == :error
    assert SipDomain.subdomain("sip.example.com") == :error
    assert SipDomain.subdomain("acmesip.example.com") == :error
    assert SipDomain.subdomain(nil) == :error
  end
end
