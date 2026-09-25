defmodule Comcent.Auth.PasswordReset do
  @moduledoc """
  Single-use tokens for password-reset links.

  The link carries a random token; only its SHA-256 hash is stored on the
  user. Resetting clears the hash in the same update that sets the new
  password, so a link works once, and a newer request overwrites the hash,
  so older links stop working.
  """

  import Ecto.Query

  alias Comcent.Auth.Password
  alias Comcent.Repo
  alias Comcent.Schemas.User

  @ttl_seconds 60 * 60
  @min_password_length 8

  def min_password_length, do: @min_password_length

  @doc """
  Returns a new raw token for the link and the user attributes that store it.
  """
  def new_token(now \\ DateTime.utc_now()) do
    token = :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)
    now = DateTime.truncate(now, :second)

    attrs = %{
      password_reset_token_hash: hash(token),
      password_reset_expires_at: DateTime.add(now, @ttl_seconds, :second),
      password_reset_sent_at: now
    }

    {token, attrs}
  end

  @doc """
  Sets a new password for the token's user and consumes the token. The email
  is marked verified too: following the link proves the user owns it.

  Returns `{:ok, user}`, `{:error, :token_expired}`, `{:error, :invalid_token}`
  or `{:error, :password_too_short}`. A short password leaves the token usable.
  """
  def reset(token, password, now \\ DateTime.utc_now())

  def reset(token, password, now) when is_binary(token) and token != "" do
    cond do
      not is_binary(password) or String.length(password) < @min_password_length ->
        {:error, :password_too_short}

      true ->
        token_hash = hash(token)

        case Repo.get_by(User, password_reset_token_hash: token_hash) do
          nil ->
            {:error, :invalid_token}

          %User{password_reset_expires_at: expires_at} = user ->
            if DateTime.compare(expires_at, now) == :gt do
              consume(user, token_hash, password, now)
            else
              {:error, :token_expired}
            end
        end
    end
  end

  def reset(_token, _password, _now), do: {:error, :invalid_token}

  # The hash is part of the WHERE clause so that two requests racing with the
  # same link cannot both succeed.
  defp consume(user, token_hash, password, now) do
    query =
      from(u in User,
        where: u.id == ^user.id and u.password_reset_token_hash == ^token_hash,
        select: u
      )

    case Repo.update_all(query,
           set: [
             password_hash: Password.hash(password),
             password_changed_at: DateTime.truncate(now, :second),
             is_email_verified: true,
             password_reset_token_hash: nil,
             password_reset_expires_at: nil,
             updated_at: NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)
           ]
         ) do
      {1, [user]} -> {:ok, user}
      _ -> {:error, :invalid_token}
    end
  end

  defp hash(token), do: :crypto.hash(:sha256, token) |> Base.encode16(case: :lower)
end
