defmodule ComcentWeb.Plugs.SessionCutoffTest do
  use ComcentWeb.ConnCase, async: false

  alias Comcent.Auth
  alias Comcent.Auth.PasswordReset
  alias Comcent.Repo
  alias Comcent.Schemas.User

  setup do
    previous = System.get_env("SIGNING_KEY")
    System.put_env("SIGNING_KEY", "test-signing-key")

    on_exit(fn ->
      if previous,
        do: System.put_env("SIGNING_KEY", previous),
        else: System.delete_env("SIGNING_KEY")
    end)

    {token, token_attrs} = PasswordReset.new_token()

    user =
      %User{id: Ecto.UUID.generate()}
      |> User.changeset(
        Map.merge(token_attrs, %{
          name: "Cutoff User",
          email: "cutoff.#{System.unique_integer([:positive])}@example.com",
          is_email_verified: true
        })
      )
      |> Repo.insert!()

    %{user: user, reset_token: token}
  end

  defp fetch_user_session(conn, session_token) do
    conn
    |> put_req_header("authorization", "Bearer #{session_token}")
    |> get("/api/v2/user/session")
  end

  test "a session from before a reset is rejected, even from the same second", %{
    conn: conn,
    user: user,
    reset_token: reset_token
  } do
    before_reset = Auth.sign_session_token(user, "password")
    assert fetch_user_session(conn, before_reset).status == 200

    {:ok, reset_user} = PasswordReset.reset(reset_token, "new-password-123")

    assert fetch_user_session(build_conn(), before_reset).status == 401

    after_reset = Auth.sign_session_token(reset_user, "password")
    assert fetch_user_session(build_conn(), after_reset).status == 200
  end

  test "a login after the reset gets a working session", %{
    user: user,
    reset_token: reset_token
  } do
    {:ok, _} = PasswordReset.reset(reset_token, "new-password-123")

    login_token = Auth.sign_session_token(Repo.get!(User, user.id), "password")
    assert fetch_user_session(build_conn(), login_token).status == 200
  end

  test "session_current?/2" do
    changed = ~U[2026-01-01 00:00:00Z]
    stamp = DateTime.to_unix(changed)

    assert Auth.session_current?(%{"pwd_at" => stamp}, %{password_changed_at: changed})
    refute Auth.session_current?(%{"pwd_at" => stamp - 1}, %{password_changed_at: changed})
    refute Auth.session_current?(%{}, %{password_changed_at: changed})
    assert Auth.session_current?(%{}, %{password_changed_at: nil})
  end
end
