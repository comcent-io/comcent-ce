defmodule Comcent.Auth.EmailVerificationTest do
  use Comcent.DataCase, async: true

  alias Comcent.Auth.EmailVerification
  alias Comcent.Repo
  alias Comcent.Schemas.User

  defp insert_unverified_user(token_attrs) do
    %User{id: Ecto.UUID.generate()}
    |> User.changeset(
      Map.merge(token_attrs, %{
        name: "New User",
        email: "new.user.#{System.unique_integer([:positive])}@example.com",
        is_email_verified: false,
        verification_email_sent_at: DateTime.utc_now(),
        verification_resend_count: 1
      })
    )
    |> Repo.insert!()
  end

  test "verifies the user and clears the token" do
    {token, attrs} = EmailVerification.new_token()
    user = insert_unverified_user(attrs)

    assert {:ok, %User{id: id, is_email_verified: true}} = EmailVerification.verify(token)
    assert id == user.id

    reloaded = Repo.get!(User, user.id)
    assert reloaded.email_verification_token_hash == nil
    assert reloaded.email_verification_expires_at == nil
    assert reloaded.verification_resend_count == 0
  end

  test "a token works only once" do
    {token, attrs} = EmailVerification.new_token()
    insert_unverified_user(attrs)

    assert {:ok, _user} = EmailVerification.verify(token)
    assert {:error, :invalid_token} = EmailVerification.verify(token)
  end

  test "an expired token is rejected" do
    issued_at = DateTime.add(DateTime.utc_now(), -25 * 60 * 60, :second)
    {token, attrs} = EmailVerification.new_token(issued_at)
    user = insert_unverified_user(attrs)

    assert {:error, :token_expired} = EmailVerification.verify(token)
    refute Repo.get!(User, user.id).is_email_verified
  end

  test "a new token replaces the previous one" do
    {first_token, first_attrs} = EmailVerification.new_token()
    user = insert_unverified_user(first_attrs)

    {second_token, second_attrs} = EmailVerification.new_token()
    user |> User.changeset(second_attrs) |> Repo.update!()

    assert {:error, :invalid_token} = EmailVerification.verify(first_token)
    assert {:ok, _user} = EmailVerification.verify(second_token)
  end

  test "unknown and malformed tokens are rejected" do
    {_token, attrs} = EmailVerification.new_token()
    insert_unverified_user(attrs)

    assert {:error, :invalid_token} = EmailVerification.verify("not-a-real-token")
    assert {:error, :invalid_token} = EmailVerification.verify("")
    assert {:error, :invalid_token} = EmailVerification.verify(nil)
  end

  test "only the hash of the token is stored" do
    {token, attrs} = EmailVerification.new_token()
    user = insert_unverified_user(attrs)

    stored = Repo.get!(User, user.id).email_verification_token_hash
    assert stored != token
    assert stored == :crypto.hash(:sha256, token) |> Base.encode16(case: :lower)
  end
end
