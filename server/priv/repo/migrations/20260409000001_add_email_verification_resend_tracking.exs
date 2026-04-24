defmodule Comcent.Repo.Migrations.AddEmailVerificationResendTracking do
  use Ecto.Migration

  def change do
    execute("""
    ALTER TABLE users
    ADD COLUMN IF NOT EXISTS verification_email_sent_at TIMESTAMP
    """)

    execute("""
    ALTER TABLE users
    ADD COLUMN IF NOT EXISTS verification_resend_count INTEGER NOT NULL DEFAULT 0
    """)

    execute("""
    ALTER TABLE users
    ADD COLUMN IF NOT EXISTS verification_resend_window_started_at TIMESTAMP
    """)
  end
end
