defmodule Comcent.WebhookPusherTest do
  # Not async: Mock replaces HTTPoison globally.
  use ExUnit.Case, async: false

  import Mock

  alias Comcent.Schemas.{Org, OrgWebhook}
  alias Comcent.WebhookPusher

  @vcon %{"uuid" => "vcon-1"}

  defp webhook(url, events) do
    %OrgWebhook{
      id: url,
      name: url,
      webhook_url: url,
      auth_token: "token-" <> url,
      events: events
    }
  end

  defp call_story(webhooks) do
    %{org: %Org{subdomain: "acme", webhooks: webhooks}}
  end

  # Runs push_to_webhook/2 with HTTPoison.post mocked and returns the URLs posted to.
  defp posted_urls(webhooks) do
    test_pid = self()

    with_mock HTTPoison,
      post: fn url, body, headers ->
        send(test_pid, {:posted, url, Jason.decode!(body), headers})
        {:ok, %HTTPoison.Response{status_code: 200, body: ""}}
      end do
      WebhookPusher.push_to_webhook(call_story(webhooks), @vcon)
    end

    collect_posts([])
  end

  defp collect_posts(acc) do
    receive do
      {:posted, url, body, _headers} ->
        assert body == %{"type" => "NEW_CALL_STORY", "data" => @vcon}
        collect_posts([url | acc])
    after
      0 -> Enum.sort(acc)
    end
  end

  test "a webhook subscribed to call updates receives the new call story" do
    assert posted_urls([webhook("https://a.example", ["CALL_UPDATE"])]) == ["https://a.example"]

    assert posted_urls([webhook("https://b.example", ["CALL_UPDATE", "PRESENCE_UPDATE"])]) ==
             ["https://b.example"]
  end

  test "a webhook subscribed only to other events does not receive the new call story" do
    assert posted_urls([webhook("https://a.example", ["PRESENCE_UPDATE"])]) == []
  end

  test "a webhook with no events stored keeps receiving everything" do
    assert posted_urls([
             webhook("https://nil.example", nil),
             webhook("https://empty.example", [])
           ]) == ["https://empty.example", "https://nil.example"]
  end

  test "only the subscribed webhooks of an org are posted to" do
    assert posted_urls([
             webhook("https://calls.example", ["CALL_UPDATE"]),
             webhook("https://presence.example", ["PRESENCE_UPDATE"]),
             webhook("https://legacy.example", nil)
           ]) == ["https://calls.example", "https://legacy.example"]
  end

  test "an org without webhooks posts nothing" do
    assert posted_urls([]) == []
  end
end
