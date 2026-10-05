defmodule Comcent.Repo.Migrations.AddProviderConnections do
  @moduledoc """
  Provider connection data model.

  Provider-generic rather than Twilio-specific so Telnyx reuses these
  tables instead of forking a parallel stack.
  """

  use Ecto.Migration

  def up do
    # One row per connected provider account. An org may hold several.
    execute """
    CREATE TABLE IF NOT EXISTS "provider_connections" (
      "id"                    TEXT      NOT NULL,
      "org_id"                TEXT      NOT NULL,
      "provider"              TEXT      NOT NULL,
      "auth_method"           TEXT      NOT NULL,
      "label"                 TEXT      NOT NULL,
      "external_account_sid"  TEXT      NOT NULL,
      -- Encrypted by Comcent.Encrypted.Map. Null for auth methods whose only
      -- per-tenant value is the account SID.
      "credentials"           BYTEA,
      "status"                TEXT      NOT NULL DEFAULT 'active',
      "last_verified_at"      TIMESTAMP,
      "metadata"              JSONB     NOT NULL DEFAULT '{}',
      "created_at"            TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
      "updated_at"            TIMESTAMP NOT NULL,
      CONSTRAINT "provider_connections_pkey" PRIMARY KEY ("id")
    )
    """

    execute """
    ALTER TABLE "provider_connections"
      ADD CONSTRAINT "provider_connections_org_id_fkey"
      FOREIGN KEY ("org_id") REFERENCES "orgs"("id")
      ON DELETE RESTRICT ON UPDATE CASCADE
    """

    # The same provider account must not be connected twice to one org.
    execute """
    CREATE UNIQUE INDEX IF NOT EXISTS "provider_connections_org_account_idx"
      ON "provider_connections" ("org_id", "provider", "external_account_sid")
    """

    # Synced inventory of what exists in the provider account, including numbers
    # not yet imported, so the picker renders without a live API round-trip.
    execute """
    CREATE TABLE IF NOT EXISTS "provider_numbers" (
      "id"                      TEXT      NOT NULL,
      "provider_connection_id"  TEXT      NOT NULL,
      "org_id"                  TEXT      NOT NULL,
      "e164"                    TEXT      NOT NULL,
      "provider_sid"            TEXT      NOT NULL,
      "friendly_name"           TEXT,
      "capabilities"            JSONB     NOT NULL DEFAULT '{}',
      "provider_metadata"       JSONB     NOT NULL DEFAULT '{}',
      -- Snapshot of provider-side config taken BEFORE our first write. This is
      -- what makes disconnect non-destructive: trunk association silently
      -- clears voice_application_sid and detaching does not restore it.
      "original_config"         JSONB,
      "last_synced_at"          TIMESTAMP,
      "status"                  TEXT      NOT NULL DEFAULT 'available',
      "created_at"              TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
      "updated_at"              TIMESTAMP NOT NULL,
      CONSTRAINT "provider_numbers_pkey" PRIMARY KEY ("id")
    )
    """

    execute """
    ALTER TABLE "provider_numbers"
      ADD CONSTRAINT "provider_numbers_connection_id_fkey"
      FOREIGN KEY ("provider_connection_id") REFERENCES "provider_connections"("id")
      ON DELETE CASCADE ON UPDATE CASCADE
    """

    execute """
    ALTER TABLE "provider_numbers"
      ADD CONSTRAINT "provider_numbers_org_id_fkey"
      FOREIGN KEY ("org_id") REFERENCES "orgs"("id")
      ON DELETE RESTRICT ON UPDATE CASCADE
    """

    execute """
    CREATE UNIQUE INDEX IF NOT EXISTS "provider_numbers_connection_sid_idx"
      ON "provider_numbers" ("provider_connection_id", "provider_sid")
    """

    # Per-(number, channel) binding. Voice rides the SIP trunk while SMS rides
    # an HTTPS webhook on the same number, so a single sip_trunk_id column on
    # numbers cannot express the combination.
    execute """
    CREATE TABLE IF NOT EXISTS "number_channels" (
      "id"         TEXT      NOT NULL,
      "org_id"     TEXT      NOT NULL,
      "number_id"  TEXT      NOT NULL,
      "channel"    TEXT      NOT NULL,
      "status"     TEXT      NOT NULL DEFAULT 'active',
      "transport"  TEXT      NOT NULL,
      "config"     JSONB     NOT NULL DEFAULT '{}',
      "created_at" TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
      "updated_at" TIMESTAMP NOT NULL,
      CONSTRAINT "number_channels_pkey" PRIMARY KEY ("id")
    )
    """

    execute """
    ALTER TABLE "number_channels"
      ADD CONSTRAINT "number_channels_number_id_fkey"
      FOREIGN KEY ("number_id") REFERENCES "numbers"("id")
      ON DELETE CASCADE ON UPDATE CASCADE
    """

    execute """
    ALTER TABLE "number_channels"
      ADD CONSTRAINT "number_channels_org_id_fkey"
      FOREIGN KEY ("org_id") REFERENCES "orgs"("id")
      ON DELETE RESTRICT ON UPDATE CASCADE
    """

    execute """
    CREATE UNIQUE INDEX IF NOT EXISTS "number_channels_number_channel_idx"
      ON "number_channels" ("number_id", "channel")
    """

    # Null = manual/BYO SIP number, behaviour unchanged.
    execute """
    ALTER TABLE "numbers"
      ADD COLUMN IF NOT EXISTS "provider_number_id" TEXT
    """

    execute """
    ALTER TABLE "numbers"
      ADD CONSTRAINT "numbers_provider_number_id_fkey"
      FOREIGN KEY ("provider_number_id") REFERENCES "provider_numbers"("id")
      ON DELETE SET NULL ON UPDATE CASCADE
    """
  end

  def down do
    execute """
    ALTER TABLE "numbers" DROP CONSTRAINT IF EXISTS "numbers_provider_number_id_fkey"
    """

    execute """
    ALTER TABLE "numbers" DROP COLUMN IF EXISTS "provider_number_id"
    """

    execute """
    DROP TABLE IF EXISTS "number_channels"
    """

    execute """
    DROP TABLE IF EXISTS "provider_numbers"
    """

    execute """
    DROP TABLE IF EXISTS "provider_connections"
    """
  end
end
