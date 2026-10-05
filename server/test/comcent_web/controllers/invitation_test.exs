defmodule ComcentWeb.InvitationTest do
  @moduledoc """
  Opening and accepting an invitation to an org.
  """

  # Not async: swaps SIGNING_KEY.
  use ComcentWeb.ConnCase, async: false

  import Ecto.Query

  alias Comcent.{Auth, ProviderFixtures, Repo}
  alias Comcent.Schemas.{OrgInvite, OrgMember, User}

  setup do
    previous = System.get_env("SIGNING_KEY")
    System.put_env("SIGNING_KEY", "test-signing-key")

    on_exit(fn ->
      if previous,
        do: System.put_env("SIGNING_KEY", previous),
        else: System.delete_env("SIGNING_KEY")
    end)

    org = ProviderFixtures.org()
    invitee = user("dana.#{System.unique_integer([:positive])}@example.com")

    invite =
      Repo.insert!(%OrgInvite{
        id: Ecto.UUID.generate(),
        org_id: org.id,
        email: invitee.email,
        role: "MEMBER",
        status: "PENDING"
      })

    {:ok, org: org, invitee: invitee, invite: invite}
  end

  test "the invitee sees the org, with its subdomain, and a suggested username", ctx do
    assert %{
             "invitation" => %{
               "id" => id,
               "role" => "MEMBER",
               "org" => %{"name" => "Acme", "subdomain" => subdomain}
             },
             "suggestedUsername" => "dana." <> _
           } = ctx |> as(ctx.invitee) |> get(path(ctx)) |> json_response(200)

    assert id == ctx.invite.id
    assert subdomain == ctx.org.subdomain
  end

  test "someone else can't open it", ctx do
    other = user("other.#{System.unique_integer([:positive])}@example.com")

    assert %{"error" => "Invalid invitation."} =
             ctx |> as(other) |> get(path(ctx)) |> json_response(404)
  end

  test "accepting joins the org with that username, once", ctx do
    assert %{"success" => true} =
             ctx
             |> as(ctx.invitee)
             |> post(path(ctx) <> "/accept", %{"username" => "dana"})
             |> json_response(200)

    assert %OrgMember{username: "dana", role: :MEMBER} =
             Repo.one!(
               from(m in OrgMember,
                 where: m.org_id == ^ctx.org.id and m.user_id == ^ctx.invitee.id
               )
             )

    assert Repo.get!(OrgInvite, ctx.invite.id).status == "ACCEPTED"

    # Accepted, it can't be opened again.
    assert ctx |> as(ctx.invitee) |> get(path(ctx)) |> json_response(404)
  end

  test "a username already used in the org is refused", ctx do
    taken = user("taken.#{System.unique_integer([:positive])}@example.com")

    Repo.insert!(%OrgMember{
      user_id: taken.id,
      org_id: ctx.org.id,
      role: :MEMBER,
      username: "dana",
      sip_password: "secret"
    })

    assert %{"error" => "Username dana already taken for this org"} =
             ctx
             |> as(ctx.invitee)
             |> post(path(ctx) <> "/accept", %{"username" => "dana"})
             |> json_response(400)
  end

  defp path(ctx), do: "/api/v2/user/invitations/#{ctx.invite.id}"

  defp as(ctx, user),
    do:
      put_req_header(
        ctx.conn,
        "authorization",
        "Bearer #{Auth.sign_session_token(user, "password")}"
      )

  defp user(email) do
    Repo.insert!(%User{
      id: Ecto.UUID.generate(),
      name: "Dana Scully",
      email: email,
      is_email_verified: true
    })
  end
end
