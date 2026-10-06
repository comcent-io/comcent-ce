defmodule ComcentWeb.Internal.DirectoryControllerTest do
  @moduledoc """
  FreeSWITCH asks the directory for the member behind an agent's call; the
  user_context it gets back ("default") is what routes the call as an
  outbound call from an agent. The org is whatever comes before the SIP user
  root domain, however many labels that has.
  """

  # Not async: the SIP user root domain is application config.
  use ComcentWeb.ConnCase, async: false

  alias Comcent.ProviderFixtures
  alias Comcent.Repo
  alias Comcent.Schemas.{OrgMember, User}

  # Obviously fake: the plug only compares them to what it is given.
  @username "test-internal-user"
  @password "test-internal-password"

  setup %{conn: conn} do
    System.put_env("INTERNAL_API_USERNAME", @username)
    System.put_env("INTERNAL_API_PASSWORD", @password)
    original_root = Application.fetch_env!(:comcent, :sip_user_root_domain)

    on_exit(fn ->
      System.delete_env("INTERNAL_API_USERNAME")
      System.delete_env("INTERNAL_API_PASSWORD")
      Application.put_env(:comcent, :sip_user_root_domain, original_root)
    end)

    org = ProviderFixtures.org()

    user =
      Repo.insert!(%User{
        id: Ecto.UUID.generate(),
        name: "Mira Quintal",
        email: "mira.#{System.unique_integer([:positive])}@example.com"
      })

    Repo.insert!(%OrgMember{
      user_id: user.id,
      org_id: org.id,
      role: :MEMBER,
      username: "mira",
      sip_password: "not-a-real-password"
    })

    credentials = Base.encode64("#{@username}:#{@password}")
    {:ok, conn: put_req_header(conn, "authorization", "Basic #{credentials}"), org: org}
  end

  defp lookup(conn, domain) do
    conn
    |> post("/internal-api/xml-curl/directory", %{"user" => "mira", "domain" => domain})
    |> response(200)
  end

  test "finds the member under a root domain of two labels", ctx do
    Application.put_env(:comcent, :sip_user_root_domain, "sip.example.com")

    body = lookup(ctx.conn, "#{ctx.org.subdomain}.sip.example.com")

    assert body =~ "<user id='mira'>"
    assert body =~ "<variable name='user_context' value='default'/>"
  end

  test "finds the member under a root domain of one label", ctx do
    Application.put_env(:comcent, :sip_user_root_domain, "example.com")

    assert lookup(ctx.conn, "#{ctx.org.subdomain}.example.com") =~ "<user id='mira'>"
  end

  test "does not find anyone outside the root domain or under a deeper name", ctx do
    Application.put_env(:comcent, :sip_user_root_domain, "sip.example.com")

    assert lookup(ctx.conn, "#{ctx.org.subdomain}.example.com") =~ ~s(status="not found")
    assert lookup(ctx.conn, "x.#{ctx.org.subdomain}.sip.example.com") =~ ~s(status="not found")
  end
end
