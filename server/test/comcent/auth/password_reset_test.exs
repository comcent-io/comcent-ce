defmodule Comcent.Auth.PasswordResetTest do
  use Comcent.DataCase, async: true

  alias Comcent.Auth.Password
  alias Comcent.Auth.PasswordReset
  alias Comcent.Repo
  alias Comcent.Schemas.User

  @old_password "old-password-123"
  @new_password "new-password-123"

  defp insert_user(token_attrs) do
    %User{id: Ecto.UUID.generate()}
    |> User.changeset(
      Map.merge(token_attrs, %{
        name: "Reset User",
        email: "reset.user.#{System.unique_integer([:positive])}@example.com",
        password_hash: Password.hash(@old_password),
        is_email_verified: false
      })
    )
    |> Repo.insert!()
  end

  test "sets the new password once and clears the token" do
    {token, attrs} = PasswordReset.new_token()
    user = insert_user(attrs)

    assert {:ok, %User{id: id}} = PasswordReset.reset(token, @new_password)
    assert id == user.id

    reloaded = Repo.get!(User, user.id)
    assert Password.verify(@new_password, reloaded.password_hash)
    refute Password.verify(@old_password, reloaded.password_hash)
    assert reloaded.is_email_verified
    assert %DateTime{} = reloaded.password_changed_at
    assert reloaded.password_reset_token_hash == nil

    assert {:error, :invalid_token} = PasswordReset.reset(token, "another-password-1")
  end

  test "an expired token is rejected and the password stays" do
    {token, attrs} = PasswordReset.new_token(DateTime.add(DateTime.utc_now(), -2 * 60 * 60))
    user = insert_user(attrs)

    assert {:error, :token_expired} = PasswordReset.reset(token, @new_password)
    assert Password.verify(@old_password, Repo.get!(User, user.id).password_hash)
  end

  test "a newer token replaces the previous one" do
    {first, first_attrs} = PasswordReset.new_token()
    user = insert_user(first_attrs)
    {second, second_attrs} = PasswordReset.new_token()
    user |> User.changeset(second_attrs) |> Repo.update!()

    assert {:error, :invalid_token} = PasswordReset.reset(first, @new_password)
    assert {:ok, _user} = PasswordReset.reset(second, @new_password)
  end

  test "a short password is rejected and the token stays usable" do
    {token, attrs} = PasswordReset.new_token()
    insert_user(attrs)

    assert {:error, :password_too_short} = PasswordReset.reset(token, "short")
    assert {:ok, _user} = PasswordReset.reset(token, @new_password)
  end

  test "unknown and malformed tokens are rejected" do
    {_token, attrs} = PasswordReset.new_token()
    insert_user(attrs)

    assert {:error, :invalid_token} = PasswordReset.reset("not-a-real-token", @new_password)
    assert {:error, :invalid_token} = PasswordReset.reset("", @new_password)
    assert {:error, :invalid_token} = PasswordReset.reset(nil, @new_password)
  end

  test "only the hash of the token is stored" do
    {token, attrs} = PasswordReset.new_token()
    user = insert_user(attrs)

    stored = Repo.get!(User, user.id).password_reset_token_hash
    assert stored != token
    assert stored == :crypto.hash(:sha256, token) |> Base.encode16(case: :lower)
  end
end
