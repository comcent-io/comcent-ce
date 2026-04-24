defmodule Comcent.Repo.Migrations.AddOrgInviteResendTracking do
  use Ecto.Migration

  def change do
    execute("""
    ALTER TABLE org_invites
    ADD COLUMN IF NOT EXISTS invite_email_sent_at TIMESTAMP
    """)

    execute("""
    ALTER TABLE org_invites
    ADD COLUMN IF NOT EXISTS invite_resend_count INTEGER NOT NULL DEFAULT 0
    """)

    execute("""
    ALTER TABLE org_invites
    ADD COLUMN IF NOT EXISTS invite_resend_window_started_at TIMESTAMP
    """)
  end
end
