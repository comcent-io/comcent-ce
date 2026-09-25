defmodule Comcent.Repo.Migrations.AddPasswordReset do
  use Ecto.Migration

  # Password reset links carry a random token stored only as a SHA-256 hash,
  # cleared when used. password_changed_at lets session tokens issued before
  # a reset be rejected.
  def change do
    alter table(:users) do
      add(:password_reset_token_hash, :text)
      add(:password_reset_expires_at, :utc_datetime)
      add(:password_reset_sent_at, :utc_datetime)
      add(:password_changed_at, :utc_datetime)
    end

    create(unique_index(:users, [:password_reset_token_hash]))
  end
end
