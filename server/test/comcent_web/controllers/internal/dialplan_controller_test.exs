defmodule ComcentWeb.Internal.DialplanControllerTest do
  @moduledoc """
  The dialplan's handling of a number's allowed outbound pattern, which it
  enforces on every outbound call that leaves through that number's trunk.
  """

  use ComcentWeb.ConnCase

  import ExUnit.CaptureLog, only: [with_log: 1]

  alias Comcent.Repo
  alias Comcent.Schemas.{Number, Org, OrgMember, SipTrunk, User}

  # Obviously fake: the plug only compares them to what it is given.
  @username "test-internal-user"
  @password "test-internal-password"

  @north_america "^\\+1[0-9]{10}$"

  setup %{conn: conn} do
    System.put_env("INTERNAL_API_USERNAME", @username)
    System.put_env("INTERNAL_API_PASSWORD", @password)

    on_exit(fn ->
      System.delete_env("INTERNAL_API_USERNAME")
      System.delete_env("INTERNAL_API_PASSWORD")
    end)

    credentials = Base.encode64("#{@username}:#{@password}")
    {:ok, conn: put_req_header(conn, "authorization", "Basic #{credentials}")}
  end

  describe "a number's allowed outbound pattern" do
    test "lets through a destination that matches it", %{conn: conn} do
      org = org()
      number = number(org, allow_outbound_regex: @north_america)
      member = member(org)

      conn = outbound_call(conn, org, member, "+14155550123", number)

      assert response(conn, 200) =~ "sofia/internal/+14155550123@trunk.example.com"
    end

    test "refuses a destination that doesn't match it, and says so", %{conn: conn} do
      org = org()
      number = number(org, allow_outbound_regex: @north_america)
      member = member(org)

      conn = outbound_call(conn, org, member, "+442071234567", number)

      body = response(conn, 403)
      assert body =~ ~s(status="not allowed")
      assert body =~ "destination not allowed from this number"
      refute body =~ "bridge"
    end

    test "is matched against the destination as sent to the carrier", %{conn: conn} do
      org = org()
      number = number(org, allow_outbound_regex: @north_america)
      member = member(org)

      # Typed without the +, as a softphone user would; the trunk gets E.164.
      conn = outbound_call(conn, org, member, "14155550123", number)

      assert response(conn, 200) =~ "sofia/internal/+14155550123@trunk.example.com"
    end

    test "an E.164 pattern also works for a number stored as US 11-digit", %{conn: conn} do
      org = org()

      number =
        number(org,
          number: "1347826#{1000 + rem(unique(), 9000)}",
          allow_outbound_regex: @north_america
        )

      member = member(org)

      conn = outbound_call(conn, org, member, "+14155550123", number)

      # The carrier gets the US 11-digit form, same as before.
      assert response(conn, 200) =~ "sofia/internal/14155550123@trunk.example.com"
    end

    test "an empty or missing pattern leaves the number unrestricted", %{conn: conn} do
      org = org()
      member = member(org)

      for pattern <- [nil, "", "   "] do
        number = number(org, allow_outbound_regex: pattern)

        conn = outbound_call(conn, org, member, "+442071234567", number)

        assert response(conn, 200) =~ "sofia/internal/+442071234567@trunk.example.com"
      end
    end

    test "an invalid stored pattern refuses the call and logs an error", %{conn: conn} do
      org = org()
      # Saved before patterns were validated: inserted without the changeset.
      number = number(org, allow_outbound_regex: "^\\+1[0-9")
      member = member(org)

      {conn, logs} = with_log(fn -> outbound_call(conn, org, member, "+14155550123", number) end)

      assert response(conn, 403) =~ "number's allowed outbound pattern is invalid"
      assert logs =~ "[error]"
      assert logs =~ "is not a valid regular expression"
    end

    test "applies to the org's default outbound number", %{conn: conn} do
      org = org()

      _default =
        number(org, allow_outbound_regex: @north_america, is_default_outbound_number: true)

      member = member(org)

      refused = outbound_call(conn, org, member, "+442071234567")
      assert response(refused, 403) =~ "destination not allowed from this number"

      allowed = outbound_call(conn, org, member, "+14155550123")
      assert response(allowed, 200) =~ "sofia/internal/+14155550123@trunk.example.com"
    end

    test "applies to the member's own default number", %{conn: conn} do
      org = org()
      number = number(org, allow_outbound_regex: @north_america)
      member = member(org, number_id: number.id)

      conn = outbound_call(conn, org, member, "+442071234567")

      assert response(conn, 403) =~ "destination not allowed from this number"
    end

    test "applies to an inbound call redirected to an external number", %{conn: conn} do
      org = org()
      number = number(org, allow_outbound_regex: @north_america)

      conn =
        post(conn, "/internal-api/xml-curl/dialplan", %{
          "Caller-Context" => "public",
          "Hunt-RDNIS" => number.number,
          "Hunt-Destination-Number" => "+442071234567",
          "variable_sip_to_user" => number.number,
          "variable_sip_from_user" => "+13478266412",
          "variable_sip_from_host" => "carrier.test",
          "variable_uuid" => Ecto.UUID.generate()
        })

      assert response(conn, 403) =~ "destination not allowed from this number"
    end
  end

  defp org do
    Repo.insert!(%Org{
      id: Ecto.UUID.generate(),
      name: "Acme",
      subdomain: "acme-#{unique()}",
      use_custom_domain: false,
      assign_ext_automatically: false,
      is_active: true
    })
  end

  defp number(org, attrs) do
    trunk =
      Repo.insert!(%SipTrunk{
        id: Ecto.UUID.generate(),
        org_id: org.id,
        name: "Trunk",
        outbound_contact: "trunk.example.com"
      })

    defaults = [
      id: Ecto.UUID.generate(),
      name: "Main",
      number: "+1347826#{1000 + rem(unique(), 9000)}",
      org_id: org.id,
      sip_trunk_id: trunk.id,
      inbound_flow_graph: %{}
    ]

    Repo.insert!(struct!(Number, Keyword.merge(defaults, attrs)))
  end

  defp member(org, attrs \\ []) do
    user =
      Repo.insert!(%User{
        id: Ecto.UUID.generate(),
        name: "Agent",
        email: "agent-#{unique()}@example.com"
      })

    defaults = [
      user_id: user.id,
      org_id: org.id,
      role: :MEMBER,
      username: "agent#{unique()}",
      sip_password: "not-a-real-password"
    ]

    Repo.insert!(struct!(OrgMember, Keyword.merge(defaults, attrs)))
  end

  # An agent's call to an external number, as FreeSWITCH asks for it: the From
  # host is under the SIP user root domain, which is what marks it internal.
  # With no `number` the call carries no X-outbound-number header, so the
  # dialplan falls back to the member's and then the org's default number.
  defp outbound_call(conn, org, member, destination, number \\ nil) do
    root_domain = Application.fetch_env!(:comcent, :sip_user_root_domain)

    params = %{
      "Caller-Context" => "public",
      "Hunt-Destination-Number" => destination,
      "variable_sip_from_user" => member.username,
      "variable_sip_from_host" => "#{org.subdomain}.#{root_domain}",
      "variable_uuid" => Ecto.UUID.generate()
    }

    params =
      if number,
        do: Map.put(params, "variable_sip_h_X-outbound-number", number.number),
        else: params

    post(conn, "/internal-api/xml-curl/dialplan", params)
  end

  defp unique, do: System.unique_integer([:positive])
end
