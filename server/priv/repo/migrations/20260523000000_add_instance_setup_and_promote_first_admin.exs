defmodule Comcent.Repo.Migrations.AddInstanceSetupAndPromoteFirstAdmin do
  use Ecto.Migration

  def up do
    execute("""
    CREATE TABLE IF NOT EXISTS "instance_setup" (
      "id"                  INTEGER   NOT NULL DEFAULT 1,
      "token"               TEXT,
      "generated_at"        TIMESTAMP,
      "consumed_at"         TIMESTAMP,
      "consumed_by_user_id" TEXT,
      "created_at"          TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
      "updated_at"          TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
      CONSTRAINT "instance_setup_pkey"        PRIMARY KEY ("id"),
      CONSTRAINT "instance_setup_singleton"   CHECK ("id" = 1),
      CONSTRAINT "instance_setup_user_fkey"   FOREIGN KEY ("consumed_by_user_id") REFERENCES "users"("id") ON DELETE SET NULL
    )
    """)

    # Upgrade safety: if any user exists but none is super_admin, promote the
    # earliest-created user. This prevents an existing CE install from locking
    # itself out the moment the gated signup goes live.
    execute("""
    UPDATE "users"
    SET "is_super_admin" = true,
        "updated_at"     = CURRENT_TIMESTAMP
    WHERE "id" = (
      SELECT "id"
      FROM "users"
      ORDER BY "created_at" ASC
      LIMIT 1
    )
    AND NOT EXISTS (
      SELECT 1 FROM "users" WHERE "is_super_admin" = true
    )
    """)
  end

  def down do
    execute("DROP TABLE IF EXISTS \"instance_setup\"")
  end
end
