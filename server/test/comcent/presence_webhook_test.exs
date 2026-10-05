defmodule Comcent.PresenceWebhookTest do
  @moduledoc """
  A member's presence change is sent as a PRESENCE_UPDATE event to the org's
  webhooks that subscribed to it. Driven through `Comcent.Repo.OrgMember`, the
  path every presence change takes (`config :comcent, :webhook_mode, :inline`
  keeps the delivery in the test process).
  """

  # Not async: Mock replaces HTTPoison globally.
  use Comcent.DataCase, async: false

  import Mock

  alias Comcent.ProviderFixtures
  alias Comcent.Repo.OrgMember, as: OrgMembers
  alias Comcent.Schemas.{OrgMember, OrgWebhook, User}

  setup do
    org = ProviderFixtures.org()

    user =
      Repo.insert!(%User{
        id: Ecto.UUID.generate(),
        name: "Mira Quintal",
        email: "mira.#{System.unique_integer([:positive])}@example.com",
        is_email_verified: true
      })

    member =
      Repo.insert!(%OrgMember{
        user_id: user.id,
        org_id: org.id,
        role: :MEMBER,
        username: "mira#{System.unique_integer([:positive])}",
        sip_password: "secret",
        presence: "Logged Out"
      })

    {:ok, org: org, user: user, member: member}
  end

  defp webhook(org, url, events) do
    Repo.insert!(%OrgWebhook{
      id: Ecto.UUID.generate(),
      org_id: org.id,
      name: url,
      webhook_url: url,
      auth_token: "token-" <> url,
      events: events
    })
  end

  # Changes the member's presence with HTTPoison.post mocked; returns what
  # was posted, as {url, decoded body, headers}, sorted by url.
  defp change_presence(ctx, presence) do
    test_pid = self()

    with_mock HTTPoison,
      post: fn url, body, headers ->
        send(test_pid, {:posted, url, Jason.decode!(body), headers})
        {:ok, %HTTPoison.Response{status_code: 200, body: ""}}
      end do
      assert :ok = OrgMembers.update_member_presence(ctx.org.subdomain, ctx.user.id, presence)
    end

    collect_posts([])
  end

  defp collect_posts(acc) do
    receive do
      {:posted, url, body, headers} -> collect_posts([{url, body, headers} | acc])
    after
      0 -> Enum.sort_by(acc, &elem(&1, 0))
    end
  end

  defp urls(posts), do: Enum.map(posts, &elem(&1, 0))

  test "a subscribed webhook receives the change, with who changed from what to what", ctx do
    webhook(ctx.org, "https://crm.example/hook", ["PRESENCE_UPDATE"])

    assert [{"https://crm.example/hook", body, headers}] = change_presence(ctx, "Available")

    assert {"X-Api-Token", "token-https://crm.example/hook"} in headers

    assert %{
             "type" => "PRESENCE_UPDATE",
             "data" => %{
               "subdomain" => subdomain,
               "user_id" => user_id,
               "username" => username,
               "email" => email,
               "name" => "Mira Quintal",
               "presence" => "Available",
               "previous_presence" => "Logged Out",
               "changed_at" => changed_at
             }
           } = body

    assert subdomain == ctx.org.subdomain
    assert user_id == ctx.user.id
    assert username == ctx.member.username
    assert email == ctx.user.email
    assert {:ok, _, 0} = DateTime.from_iso8601(changed_at)
  end

  test "a webhook subscribed only to call updates does not receive it", ctx do
    webhook(ctx.org, "https://calls.example", ["CALL_UPDATE"])
    webhook(ctx.org, "https://both.example", ["CALL_UPDATE", "PRESENCE_UPDATE"])

    assert urls(change_presence(ctx, "Available")) == ["https://both.example"]
  end

  test "a webhook with no events stored keeps receiving everything", ctx do
    webhook(ctx.org, "https://nil.example", nil)
    webhook(ctx.org, "https://empty.example", [])

    assert urls(change_presence(ctx, "Available")) == [
             "https://empty.example",
             "https://nil.example"
           ]
  end

  test "another org's webhooks are not posted to", ctx do
    other = ProviderFixtures.org()
    webhook(other, "https://other.example", ["PRESENCE_UPDATE"])

    assert change_presence(ctx, "Available") == []
  end

  test "setting the presence it already has sends nothing", ctx do
    webhook(ctx.org, "https://crm.example/hook", ["PRESENCE_UPDATE"])

    assert change_presence(ctx, "Logged Out") == []
  end

  test "a conditional change (Busy back to Available) is sent too", ctx do
    webhook(ctx.org, "https://crm.example/hook", ["PRESENCE_UPDATE"])
    change_presence(ctx, "Busy")

    test_pid = self()

    with_mock HTTPoison,
      post: fn url, body, _headers ->
        send(test_pid, {:posted, url, Jason.decode!(body)})
        {:ok, %HTTPoison.Response{status_code: 200, body: ""}}
      end do
      assert :ok =
               OrgMembers.update_member_presence_if_busy(
                 ctx.org.subdomain,
                 ctx.user.id,
                 "Available"
               )
    end

    assert_received {:posted, "https://crm.example/hook",
                     %{"data" => %{"previous_presence" => "Busy", "presence" => "Available"}}}
  end
end
