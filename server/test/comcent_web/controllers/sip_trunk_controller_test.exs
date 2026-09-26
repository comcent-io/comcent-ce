defmodule ComcentWeb.SipTrunkControllerTest do
  # Not async: the tests change application config.
  use ComcentWeb.ConnCase, async: false

  alias Comcent.Auth
  alias Comcent.Repo
  alias Comcent.Schemas.{Org, OrgMember, User}

  setup do
    previous_signing_key = System.get_env("SIGNING_KEY")
    System.put_env("SIGNING_KEY", "test-signing-key")
    previous_sbc = Application.get_env(:comcent, :sbc)

    on_exit(fn ->
      if previous_signing_key,
        do: System.put_env("SIGNING_KEY", previous_signing_key),
        else: System.delete_env("SIGNING_KEY")

      Application.put_env(:comcent, :sbc, previous_sbc)
    end)

    org =
      %Org{id: Ecto.UUID.generate()}
      |> Ecto.Changeset.change(%{
        name: "Acme",
        subdomain: "acme-#{System.unique_integer([:positive])}",
        use_custom_domain: false,
        assign_ext_automatically: false
      })
      |> Repo.insert!()

    user =
      Repo.insert!(%User{
        id: Ecto.UUID.generate(),
        name: "Admin",
        email: "admin.#{System.unique_integer([:positive])}@example.com",
        is_email_verified: true
      })

    Repo.insert!(%OrgMember{
      user_id: user.id,
      org_id: org.id,
      role: :ADMIN,
      username: "admin#{System.unique_integer([:positive])}",
      sip_password: "secret"
    })

    %{org: org, token: Auth.sign_session_token(user, "password")}
  end

  defp put_public_ip(public_ip) do
    Application.put_env(
      :comcent,
      :sbc,
      Keyword.put(Application.get_env(:comcent, :sbc) || [], :public_ip, public_ip)
    )
  end

  defp get_settings(conn, org, token) do
    conn
    |> put_req_header("authorization", "Bearer #{token}")
    |> get("/api/v2/#{org.subdomain}/sip-trunks/settings")
  end

  test "returns the configured public SIP address", %{conn: conn, org: org, token: token} do
    put_public_ip("203.0.113.10")

    assert get_settings(conn, org, token) |> json_response(200) == %{"publicIp" => "203.0.113.10"}
  end

  test "returns nothing when the address is not configured", %{
    conn: conn,
    org: org,
    token: token
  } do
    put_public_ip(nil)
    assert get_settings(conn, org, token) |> json_response(200) == %{"publicIp" => nil}

    put_public_ip("  ")
    assert get_settings(conn, org, token) |> json_response(200) == %{"publicIp" => nil}
  end

  test "requires authentication", %{conn: conn, org: org} do
    assert conn |> get("/api/v2/#{org.subdomain}/sip-trunks/settings") |> json_response(401)
  end
end
