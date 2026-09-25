defmodule Comcent.Auth.EmailVerification do
  @moduledoc """
  Single-use tokens for email-verification links.

  The link carries a random token; only its SHA-256 hash is stored on the
  user. Verifying clears the hash, so a link works once, and issuing a new
  token (a resend) overwrites it, so older links stop working.
  """

  import Ecto.Query

  alias Comcent.Repo
  alias Comcent.Schemas.User

  @ttl_seconds 24 * 60 * 60

  @doc """
  Returns a new raw token for the link and the user attributes that store
  it. Callers save the attributes in the same transaction that sends the
  email.
  """
  def new_token(now \\ DateTime.utc_now()) do
    token = :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)

    attrs = %{
      email_verification_token_hash: hash(token),
      email_verification_expires_at:
        now |> DateTime.add(@ttl_seconds, :second) |> DateTime.truncate(:second)
    }

    {token, attrs}
  end

  @doc """
  Marks the token's user verified and consumes the token.

  Returns `{:ok, user}`, `{:error, :token_expired}` or `{:error, :invalid_token}`.
  """
  def verify(token, now \\ DateTime.utc_now())

  def verify(token, now) when is_binary(token) and token != "" do
    token_hash = hash(token)

    case Repo.get_by(User, email_verification_token_hash: token_hash) do
      nil ->
        {:error, :invalid_token}

      %User{email_verification_expires_at: expires_at} = user ->
        if DateTime.compare(expires_at, now) == :gt do
          consume(user, token_hash)
        else
          {:error, :token_expired}
        end
    end
  end

  def verify(_token, _now), do: {:error, :invalid_token}

  # The hash is part of the WHERE clause so that two requests racing with the
  # same link cannot both succeed.
  defp consume(user, token_hash) do
    query =
      from(u in User,
        where: u.id == ^user.id and u.email_verification_token_hash == ^token_hash,
        select: u
      )

    case Repo.update_all(query,
           set: [
             is_email_verified: true,
             email_verification_token_hash: nil,
             email_verification_expires_at: nil,
             verification_email_sent_at: nil,
             verification_resend_count: 0,
             verification_resend_window_started_at: nil,
             updated_at: NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)
           ]
         ) do
      {1, [user]} -> {:ok, user}
      _ -> {:error, :invalid_token}
    end
  end

  defp hash(token), do: :crypto.hash(:sha256, token) |> Base.encode16(case: :lower)
end
