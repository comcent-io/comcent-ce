defmodule Comcent.Repo.Migrations.DropApiKeyTables do
  @moduledoc """
  Drops the organization and member API key tables.

  Admins could create organization API keys under Settings, and members could
  create their own on their profile page, but nothing ever checked either kind:
  no plug looked a key up, and the API accepts only session tokens. The keys
  looked like a working credential and weren't one, so the feature is removed
  rather than left half-built. If API-key auth is added later it will need its
  own design (hashed keys, scopes, last-used, revocation), not these tables,
  which stored the key in plain text.

  Any keys that exist are dropped with the tables. Nothing accepted them, so no
  integration can be relying on them.

  Voice bots have their own `api_key` column on `voice_bots`; that is unrelated
  and untouched.

  `down` recreates both tables empty, exactly as the initial schema made them.
  """

  use Ecto.Migration

  def up do
    execute ~s(DROP TABLE IF EXISTS "org_api_keys")
    execute ~s(DROP TABLE IF EXISTS "member_api_keys")
  end

  def down do
    execute """
    CREATE TABLE IF NOT EXISTS "member_api_keys" (
      "org_id"     TEXT      NOT NULL,
      "user_id"    TEXT      NOT NULL,
      "api_key"    TEXT      NOT NULL,
      "name"       TEXT      NOT NULL,
      "created_at" TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
      "updated_at" TIMESTAMP NOT NULL,
      CONSTRAINT "member_api_keys_pkey" PRIMARY KEY ("org_id", "user_id", "api_key")
    )
    """

    execute """
    CREATE UNIQUE INDEX IF NOT EXISTS "member_api_keys_api_key_key" ON "member_api_keys"("api_key")
    """

    execute """
    ALTER TABLE "member_api_keys"
      ADD CONSTRAINT "member_api_keys_org_id_user_id_fkey"
      FOREIGN KEY ("org_id", "user_id") REFERENCES "org_members"("org_id", "user_id")
      ON DELETE RESTRICT ON UPDATE CASCADE
    """

    execute """
    CREATE TABLE IF NOT EXISTS "org_api_keys" (
      "api_key"    TEXT      NOT NULL,
      "name"       TEXT      NOT NULL,
      "org_id"     TEXT      NOT NULL,
      "created_at" TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
      "updated_at" TIMESTAMP NOT NULL,
      CONSTRAINT "org_api_keys_pkey" PRIMARY KEY ("api_key")
    )
    """

    execute """
    ALTER TABLE "org_api_keys"
      ADD CONSTRAINT "org_api_keys_org_id_fkey"
      FOREIGN KEY ("org_id") REFERENCES "orgs"("id")
      ON DELETE RESTRICT ON UPDATE CASCADE
    """
  end
end
