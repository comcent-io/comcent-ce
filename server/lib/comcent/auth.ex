defmodule Comcent.Auth do
  alias Comcent.Auth.SessionToken

  def authenticate_with_jwt(token) do
    with {:ok, claims} <- SessionToken.verify(token),
         email when is_binary(email) <- claims["email"] do
      {:ok, %{email: email, claims: claims}}
    else
      _ -> {:error, :invalid_token}
    end
  end

  def authenticate_with_cookie(conn) do
    conn = Plug.Conn.fetch_cookies(conn)

    case get_cookie(conn, "idToken") do
      nil -> {:error, :no_cookie}
      token -> authenticate_with_jwt(token)
    end
  end

  def get_cookie(conn, name) do
    conn.cookies[name]
  end

  def verify_any_token(token) do
    SessionToken.verify(token)
  end

  def sign_session_token(user, auth_provider) do
    SessionToken.sign(%{
      "sub" => user.id,
      "email" => user.email,
      "name" => user.name,
      "picture" => user.picture,
      "email_verified" => user.is_email_verified,
      "auth_provider" => auth_provider,
      "token_type" => "session"
    })
  end

  def sign_state_token(claims, expires_in_seconds \\ 600) do
    SessionToken.sign(Map.put(claims, "token_type", "oauth_state"), expires_in_seconds)
  end

  def sign_email_verification_token(user, expires_in_seconds \\ 24 * 60 * 60) do
    SessionToken.sign(
      %{
        "sub" => user.id,
        "email" => user.email,
        "token_type" => "email_verification"
      },
      expires_in_seconds
    )
  end
end
