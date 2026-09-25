defmodule Comcent.Repo.Migrations.AddEmailVerificationToken do
  use Ecto.Migration

  # Email-verification links used to be JWTs that stayed valid for 24 hours
  # after use. They are now random tokens stored only as a SHA-256 hash, and
  # cleared when used or replaced by a resend.
  def change do
    alter table(:users) do
      add(:email_verification_token_hash, :text)
      add(:email_verification_expires_at, :utc_datetime)
    end

    create(unique_index(:users, [:email_verification_token_hash]))
  end
end
