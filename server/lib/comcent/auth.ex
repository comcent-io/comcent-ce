defmodule Comcent.Auth do
  alias Comcent.Auth.SessionToken

  # Only session tokens authenticate a caller. Email-verification and OAuth
  # state tokens are signed with the same key and carry claims that look
  # similar, so the token type has to be checked here rather than trusted to
  # whoever forwarded the request.
  def authenticate_with_jwt(token) do
    with {:ok, claims} <- SessionToken.verify(token),
         "session" <- claims["token_type"],
         email when is_binary(email) <- claims["email"] do
      {:ok, %{email: email, claims: claims}}
    else
      _ -> {:error, :invalid_token}
    end
  end

  @doc """
  Whether a session token is still valid for its user. Session tokens carry
  the user's password-change stamp (`pwd_at`); a password reset moves the
  stamp, so every token issued before it stops matching, however close in
  time it was issued. Users who never reset have no stamp and nothing to
  match.
  """
  def session_current?(_claims, %{password_changed_at: nil}), do: true

  def session_current?(claims, %{password_changed_at: %DateTime{} = changed_at}) do
    claims["pwd_at"] == DateTime.to_unix(changed_at)
  end

  def session_current?(_claims, _user), do: false

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
    SessionToken.sign(
      %{
        "sub" => user.id,
        "email" => user.email,
        "name" => user.name,
        "picture" => user.picture,
        "email_verified" => user.is_email_verified,
        "auth_provider" => auth_provider,
        "token_type" => "session"
      }
      |> put_password_stamp(Map.get(user, :password_changed_at))
    )
  end

  defp put_password_stamp(claims, %DateTime{} = changed_at),
    do: Map.put(claims, "pwd_at", DateTime.to_unix(changed_at))

  defp put_password_stamp(claims, _changed_at), do: claims

  def sign_state_token(claims, expires_in_seconds \\ 600) do
    SessionToken.sign(Map.put(claims, "token_type", "oauth_state"), expires_in_seconds)
  end
end
