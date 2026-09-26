defmodule ComcentWeb.ApiKeysRemovedTest do
  # Organization and member API keys were never accepted by any plug, so the
  # feature was removed. These guard against it being half-restored: routes
  # that hand out keys the API won't take, or the plain-text key tables.
  use Comcent.DataCase, async: true

  @removed_routes [
    {"GET", "/api/v2/acme/settings/api-keys"},
    {"POST", "/api/v2/acme/settings/api-keys"},
    {"DELETE", "/api/v2/acme/settings/api-keys/some-key"},
    {"POST", "/api/v2/acme/me/api-keys"},
    {"DELETE", "/api/v2/acme/me/api-keys/some-key"}
  ]

  test "the API key routes no longer exist" do
    # A neighbouring settings route still resolves, so :error below means
    # "not routed" rather than "wrong path shape".
    assert %{} =
             Phoenix.Router.route_info(
               ComcentWeb.Router,
               "GET",
               "/api/v2/acme/settings/webhooks",
               "localhost"
             )

    for {method, path} <- @removed_routes do
      assert Phoenix.Router.route_info(ComcentWeb.Router, method, path, "localhost") == :error,
             "#{method} #{path} is still routed"
    end
  end

  test "the API key tables are dropped" do
    %{rows: rows} =
      Comcent.Repo.query!("""
      SELECT table_name FROM information_schema.tables
      WHERE table_schema = 'public' AND table_name IN ('org_api_keys', 'member_api_keys')
      """)

    assert rows == []
  end
end
