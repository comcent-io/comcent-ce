defmodule Comcent.AuthTest do
  use ExUnit.Case, async: false

  alias Comcent.Auth
  alias Comcent.Auth.SessionToken

  setup do
    previous = System.get_env("SIGNING_KEY")
    System.put_env("SIGNING_KEY", "test-signing-key")

    on_exit(fn ->
      if previous,
        do: System.put_env("SIGNING_KEY", previous),
        else: System.delete_env("SIGNING_KEY")
    end)

    user = %{id: "user-1", email: "user@example.com", name: "User", picture: nil}
    user = Map.put(user, :is_email_verified, true)
    %{user: user}
  end

  describe "authenticate_with_jwt/1" do
    test "accepts a session token", %{user: user} do
      token = Auth.sign_session_token(user, "password")

      assert {:ok, %{email: "user@example.com"}} = Auth.authenticate_with_jwt(token)
    end

    test "rejects a token of another type", %{user: user} do
      token =
        SessionToken.sign(%{
          "sub" => user.id,
          "email" => user.email,
          "token_type" => "email_verification"
        })

      assert {:error, :invalid_token} = Auth.authenticate_with_jwt(token)
    end

    test "rejects a token with no type" do
      token = SessionToken.sign(%{"sub" => "user-1", "email" => "user@example.com"})

      assert {:error, :invalid_token} = Auth.authenticate_with_jwt(token)
    end
  end
end
