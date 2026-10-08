defmodule ComcentWeb.Internal.MemberControllerTest do
  @moduledoc """
  The SBC tells the server when a member's SIP registration comes and goes.
  A registration that runs out without the client unregistering ("expired",
  e.g. a throttled background tab) shows the member Logged Out until they
  register again, and then gives them back the presence they had.
  """

  use ComcentWeb.ConnCase, async: false

  alias Comcent.Repo
  alias Comcent.Repo.OrgMember, as: OrgMemberRepo
  alias Comcent.Schemas.{Org, OrgMember, User}

  # Obviously fake: the plug only compares them to what it is given.
  @username "test-internal-user"
  @password "test-internal-password"

  setup do
    System.put_env("INTERNAL_API_USERNAME", @username)
    System.put_env("INTERNAL_API_PASSWORD", @password)

    on_exit(fn ->
      System.delete_env("INTERNAL_API_USERNAME")
      System.delete_env("INTERNAL_API_PASSWORD")
    end)

    org =
      Repo.insert!(%Org{
        id: Ecto.UUID.generate(),
        name: "Acme",
        subdomain: "acme-#{System.unique_integer([:positive])}",
        use_custom_domain: false,
        assign_ext_automatically: false
      })

    user =
      Repo.insert!(%User{
        id: Ecto.UUID.generate(),
        name: "Tamsin Ardell",
        email: "tamsin.#{System.unique_integer([:positive])}@example.com",
        is_email_verified: true
      })

    Repo.insert!(%OrgMember{
      user_id: user.id,
      org_id: org.id,
      role: :MEMBER,
      username: "tamsin",
      sip_password: "secret",
      presence: "Available"
    })

    on_exit(fn -> OrgMemberRepo.forget_presence_before_lapse(org.subdomain, user.id) end)

    {:ok,
     authorization: "Basic " <> Base.encode64("#{@username}:#{@password}"),
     subdomain: org.subdomain,
     user_id: user.id}
  end

  defp sbc_says(ctx, action) do
    build_conn()
    |> put_req_header("authorization", ctx.authorization)
    |> post("/internal-api/user/presence", %{
      "subdomain" => ctx.subdomain,
      "action" => action,
      "username" => "tamsin"
    })
    |> response(200)
  end

  defp presence(ctx), do: OrgMemberRepo.get_current_presence(ctx.subdomain, ctx.user_id)

  defp set_presence(ctx, presence),
    do: OrgMemberRepo.update_member_presence(ctx.subdomain, ctx.user_id, presence)

  test "a lapsed registration shows Available as Logged Out until the member registers again",
       ctx do
    sbc_says(ctx, "expired")
    assert presence(ctx) == "Logged Out"

    sbc_says(ctx, "registered")
    assert presence(ctx) == "Available"
  end

  test "On Break comes back as On Break", ctx do
    set_presence(ctx, "On Break")

    sbc_says(ctx, "expired")
    assert presence(ctx) == "Logged Out"

    sbc_says(ctx, "registered")
    assert presence(ctx) == "On Break"
  end

  test "Wrap Up comes back as Available, which it would have become anyway", ctx do
    set_presence(ctx, "Wrap Up")

    sbc_says(ctx, "expired")
    sbc_says(ctx, "registered")

    assert presence(ctx) == "Available"
  end

  test "a member on a call is left to the call", ctx do
    set_presence(ctx, "On Call")

    sbc_says(ctx, "expired")
    assert presence(ctx) == "On Call"
  end

  test "a member who unregisters after the lapse stays Logged Out when they register", ctx do
    sbc_says(ctx, "expired")
    sbc_says(ctx, "unregistered")
    sbc_says(ctx, "registered")

    assert presence(ctx) == "Logged Out"
  end

  test "a member Logged Out by choice stays Logged Out", ctx do
    set_presence(ctx, "Logged Out")

    sbc_says(ctx, "expired")
    sbc_says(ctx, "registered")

    assert presence(ctx) == "Logged Out"
  end
end
