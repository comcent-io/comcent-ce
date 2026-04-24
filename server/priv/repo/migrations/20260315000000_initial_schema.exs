defmodule Comcent.Repo.Migrations.InitialSchema do
  use Ecto.Migration

  def up do
    # Enable extensions
    execute "CREATE EXTENSION IF NOT EXISTS vector"

    # ---------------------------------------------------------------------------
    # users
    # ---------------------------------------------------------------------------
    execute """
    CREATE TABLE "users" (
      "id"              TEXT      NOT NULL,
      "name"            TEXT      NOT NULL,
      "email"           TEXT      NOT NULL,
      "password_hash"   TEXT,
      "is_email_verified" BOOLEAN   NOT NULL DEFAULT false,
      "verification_email_sent_at" TIMESTAMP,
      "verification_resend_count" INTEGER NOT NULL DEFAULT 0,
      "verification_resend_window_started_at" TIMESTAMP,
      "created_at"       TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
      "updated_at"       TIMESTAMP NOT NULL,
      "picture"         TEXT,
      "agreed_to_tos_at"   TIMESTAMP,
      "has_agreed_to_tos"  BOOLEAN   NOT NULL DEFAULT false,
      "is_super_admin"    BOOLEAN   NOT NULL DEFAULT false,
      CONSTRAINT "users_pkey" PRIMARY KEY ("id")
    )
    """

    execute """
    CREATE UNIQUE INDEX "users_email_key" ON "users"("email")
    """

    execute """
    CREATE TABLE "user_identities" (
      "id"               TEXT      NOT NULL,
      "user_id"          TEXT      NOT NULL,
      "provider"         TEXT      NOT NULL,
      "provider_user_id" TEXT      NOT NULL,
      "email"            TEXT,
      "name"             TEXT,
      "picture"          TEXT,
      "created_at"       TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
      "updated_at"       TIMESTAMP NOT NULL,
      CONSTRAINT "user_identities_pkey" PRIMARY KEY ("id")
    )
    """

    execute """
    ALTER TABLE "user_identities"
      ADD CONSTRAINT "user_identities_user_id_fkey"
      FOREIGN KEY ("user_id") REFERENCES "users"("id")
      ON DELETE CASCADE ON UPDATE CASCADE
    """

    execute """
    CREATE UNIQUE INDEX "user_identities_provider_provider_user_id_key"
    ON "user_identities"("provider", "provider_user_id")
    """

    execute """
    CREATE UNIQUE INDEX "user_identities_user_id_provider_key"
    ON "user_identities"("user_id", "provider")
    """

    # ---------------------------------------------------------------------------
    # orgs
    # ---------------------------------------------------------------------------
    execute """
    CREATE TABLE "orgs" (
      "id"                       TEXT      NOT NULL,
      "name"                     TEXT      NOT NULL,
      "subdomain"                TEXT      NOT NULL,
      "use_custom_domain"          BOOLEAN   NOT NULL,
      "custom_domain"             TEXT,
      "assign_ext_automatically"   BOOLEAN   NOT NULL,
      "auto_ext_start"             TEXT,
      "auto_ext_end"               TEXT,
      "is_active"                 BOOLEAN   NOT NULL DEFAULT true,
      "enable_sentiment_analysis"  BOOLEAN   NOT NULL DEFAULT true,
      "enable_summary"            BOOLEAN   NOT NULL DEFAULT true,
      "enable_transcription"      BOOLEAN   NOT NULL DEFAULT true,
      "alert_threshold_balance"    INTEGER   NOT NULL DEFAULT 5,
      "max_members"               INTEGER,
      "enable_call_recording"      BOOLEAN   NOT NULL DEFAULT true,
      "wallet_balance"            BIGINT    NOT NULL DEFAULT 0,
      "max_monthly_storage_used"    BIGINT    NOT NULL DEFAULT 0,
      "storage_used"              BIGINT    NOT NULL DEFAULT 0,
      "low_balance_alert_count"     INTEGER   NOT NULL DEFAULT 0,
      "low_balance_alert_triggered_at" TIMESTAMP,
      "enable_labels"             BOOLEAN   NOT NULL DEFAULT true,
      "labels"                   JSONB,
      "daily_summary_time"         TEXT,
      "daily_summary_time_zone"     TEXT      DEFAULT 'America/New_York',
      "enable_daily_summary"       BOOLEAN   NOT NULL DEFAULT true,
      "created_at"                TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
      "updated_at"                TIMESTAMP NOT NULL,
      CONSTRAINT "orgs_pkey" PRIMARY KEY ("id")
    )
    """

    execute """
    CREATE UNIQUE INDEX "orgs_subdomain_key" ON "orgs"("subdomain")
    """

    # ---------------------------------------------------------------------------
    # countries & states (integer serial PKs)
    # ---------------------------------------------------------------------------
    execute """
    CREATE TABLE "countries" (
      "id"    SERIAL NOT NULL,
      "code"  TEXT   NOT NULL,
      "name"  TEXT   NOT NULL,
      CONSTRAINT "countries_pkey" PRIMARY KEY ("id")
    )
    """

    execute """
    CREATE UNIQUE INDEX "countries_code_key" ON "countries"("code")
    """

    execute """
    CREATE TABLE "states" (
      "id"          SERIAL     NOT NULL,
      "name"        TEXT       NOT NULL,
      "country_code" VARCHAR(3) NOT NULL,
      CONSTRAINT "states_pkey" PRIMARY KEY ("id")
    )
    """

    execute """
    ALTER TABLE "states"
      ADD CONSTRAINT "states_country_code_fkey"
      FOREIGN KEY ("country_code") REFERENCES "countries"("code")
      ON DELETE RESTRICT ON UPDATE CASCADE
    """

    # ---------------------------------------------------------------------------
    # sip_trunks
    # ---------------------------------------------------------------------------
    execute """
    CREATE TABLE "sip_trunks" (
      "id"               TEXT      NOT NULL,
      "org_id"            TEXT      NOT NULL,
      "name"             TEXT      NOT NULL,
      "outbound_username" TEXT,
      "outbound_password" TEXT,
      "outbound_contact"  TEXT      NOT NULL,
      "inbound_ips"       TEXT[],
      "created_at"        TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
      "updated_at"        TIMESTAMP NOT NULL,
      CONSTRAINT "sip_trunks_pkey" PRIMARY KEY ("id")
    )
    """

    execute """
    ALTER TABLE "sip_trunks"
      ADD CONSTRAINT "sip_trunks_org_id_fkey"
      FOREIGN KEY ("org_id") REFERENCES "orgs"("id")
      ON DELETE RESTRICT ON UPDATE CASCADE
    """

    # ---------------------------------------------------------------------------
    # numbers
    # ---------------------------------------------------------------------------
    execute """
    CREATE TABLE "numbers" (
      "id"                      TEXT      NOT NULL,
      "name"                    TEXT      NOT NULL,
      "number"                  TEXT      NOT NULL,
      "allow_outbound_regex"      TEXT,
      "org_id"                   TEXT      NOT NULL,
      "sip_trunk_id"              TEXT      NOT NULL,
      "is_default_outbound_number" BOOLEAN   NOT NULL DEFAULT false,
      "inbound_flow_graph"        JSONB     NOT NULL,
      "created_at"               TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
      "updated_at"               TIMESTAMP NOT NULL,
      CONSTRAINT "numbers_pkey" PRIMARY KEY ("id")
    )
    """

    execute """
    CREATE UNIQUE INDEX "numbers_number_key" ON "numbers"("number")
    """

    execute """
    ALTER TABLE "numbers"
      ADD CONSTRAINT "numbers_org_id_fkey"
      FOREIGN KEY ("org_id") REFERENCES "orgs"("id")
      ON DELETE RESTRICT ON UPDATE CASCADE
    """

    execute """
    ALTER TABLE "numbers"
      ADD CONSTRAINT "numbers_sip_trunk_id_fkey"
      FOREIGN KEY ("sip_trunk_id") REFERENCES "sip_trunks"("id")
      ON DELETE RESTRICT ON UPDATE CASCADE
    """

    # ---------------------------------------------------------------------------
    # org_members (composite PK: org_id + user_id)
    # ---------------------------------------------------------------------------
    execute """
    CREATE TABLE "org_members" (
      "user_id"          TEXT              NOT NULL,
      "org_id"           TEXT              NOT NULL,
      "role"            TEXT              NOT NULL,
      "username"        TEXT              NOT NULL,
      "sip_password"     TEXT              NOT NULL,
      "extension_number" TEXT,
      "presence"        TEXT              NOT NULL DEFAULT 'Logged Out',
      "number_id"        TEXT,
      CONSTRAINT "org_members_pkey" PRIMARY KEY ("org_id", "user_id")
    )
    """

    execute """
    CREATE UNIQUE INDEX "org_members_org_id_username_key" ON "org_members"("org_id", username)
    """

    execute """
    ALTER TABLE "org_members"
      ADD CONSTRAINT "org_members_user_id_fkey"
      FOREIGN KEY ("user_id") REFERENCES "users"("id")
      ON DELETE RESTRICT ON UPDATE CASCADE
    """

    execute """
    ALTER TABLE "org_members"
      ADD CONSTRAINT "org_members_org_id_fkey"
      FOREIGN KEY ("org_id") REFERENCES "orgs"("id")
      ON DELETE RESTRICT ON UPDATE CASCADE
    """

    execute """
    ALTER TABLE "org_members"
      ADD CONSTRAINT "org_members_number_id_fkey"
      FOREIGN KEY ("number_id") REFERENCES "numbers"("id")
      ON DELETE SET NULL ON UPDATE CASCADE
    """

    # ---------------------------------------------------------------------------
    # queues
    # ---------------------------------------------------------------------------
    execute """
    CREATE TABLE "queues" (
      "id"              TEXT      NOT NULL,
      "name"            TEXT      NOT NULL,
      "extension"       TEXT,
      "org_id"           TEXT      NOT NULL,
      "created_at"       TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
      "updated_at"       TIMESTAMP NOT NULL,
      "max_no_answers"    INTEGER   NOT NULL DEFAULT 2,
      "wrap_up_time"      INTEGER   NOT NULL DEFAULT 30,
      "reject_delay_time" INTEGER   NOT NULL DEFAULT 30,
      CONSTRAINT "queues_pkey" PRIMARY KEY ("id")
    )
    """

    execute """
    CREATE UNIQUE INDEX "queues_org_id_name_key" ON "queues"("org_id", name)
    """

    execute """
    ALTER TABLE "queues"
      ADD CONSTRAINT "queues_org_id_fkey"
      FOREIGN KEY ("org_id") REFERENCES "orgs"("id")
      ON DELETE RESTRICT ON UPDATE CASCADE
    """

    # ---------------------------------------------------------------------------
    # queue_memberships (composite PK: queue_id + org_id + user_id)
    # ---------------------------------------------------------------------------
    execute """
    CREATE TABLE "queue_memberships" (
      "queue_id"  TEXT      NOT NULL,
      "org_id"     TEXT      NOT NULL,
      "user_id"    TEXT      NOT NULL,
      "created_at" TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
      "updated_at" TIMESTAMP NOT NULL,
      CONSTRAINT "queue_memberships_pkey" PRIMARY KEY ("queue_id", "org_id", "user_id")
    )
    """

    execute """
    ALTER TABLE "queue_memberships"
      ADD CONSTRAINT "queue_memberships_queue_id_fkey"
      FOREIGN KEY ("queue_id") REFERENCES "queues"("id")
      ON DELETE RESTRICT ON UPDATE CASCADE
    """

    execute """
    ALTER TABLE "queue_memberships"
      ADD CONSTRAINT "queue_memberships_org_id_user_id_fkey"
      FOREIGN KEY ("org_id", "user_id") REFERENCES "org_members"("org_id", "user_id")
      ON DELETE RESTRICT ON UPDATE CASCADE
    """

    # ---------------------------------------------------------------------------
    # member_api_keys (composite PK: org_id + user_id + api_key)
    # ---------------------------------------------------------------------------
    execute """
    CREATE TABLE "member_api_keys" (
      "org_id"     TEXT      NOT NULL,
      "user_id"    TEXT      NOT NULL,
      "api_key"    TEXT      NOT NULL,
      "name"      TEXT      NOT NULL,
      "created_at" TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
      "updated_at" TIMESTAMP NOT NULL,
      CONSTRAINT "member_api_keys_pkey" PRIMARY KEY ("org_id", "user_id", "api_key")
    )
    """

    execute """
    CREATE UNIQUE INDEX "member_api_keys_api_key_key" ON "member_api_keys"("api_key")
    """

    execute """
    ALTER TABLE "member_api_keys"
      ADD CONSTRAINT "member_api_keys_org_id_user_id_fkey"
      FOREIGN KEY ("org_id", "user_id") REFERENCES "org_members"("org_id", "user_id")
      ON DELETE RESTRICT ON UPDATE CASCADE
    """

    # ---------------------------------------------------------------------------
    # org_api_keys (PK is the api_key text field)
    # ---------------------------------------------------------------------------
    execute """
    CREATE TABLE "org_api_keys" (
      "api_key"    TEXT      NOT NULL,
      "name"      TEXT      NOT NULL,
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

    # ---------------------------------------------------------------------------
    # org_invites
    # ---------------------------------------------------------------------------
    execute """
    CREATE TABLE "org_invites" (
      "id"        TEXT             NOT NULL,
      "org_id"     TEXT             NOT NULL,
      "email"     TEXT             NOT NULL,
      "role"      TEXT             NOT NULL,
      "invite_email_sent_at" TIMESTAMP,
      "invite_resend_count" INTEGER NOT NULL DEFAULT 0,
      "invite_resend_window_started_at" TIMESTAMP,
      "created_at" TIMESTAMP        NOT NULL DEFAULT CURRENT_TIMESTAMP,
      "updated_at" TIMESTAMP        NOT NULL,
      "status"    TEXT             NOT NULL DEFAULT 'PENDING',
      CONSTRAINT "org_invites_pkey" PRIMARY KEY ("id")
    )
    """

    execute """
    ALTER TABLE "org_invites"
      ADD CONSTRAINT "org_invites_org_id_fkey"
      FOREIGN KEY ("org_id") REFERENCES "orgs"("id")
      ON DELETE RESTRICT ON UPDATE CASCADE
    """

    # ---------------------------------------------------------------------------
    # org_webhooks
    # ---------------------------------------------------------------------------
    execute """
    CREATE TABLE "org_webhooks" (
      "id"         TEXT      NOT NULL,
      "webhook_url" TEXT      NOT NULL,
      "events"     TEXT[],
      "name"       TEXT      NOT NULL,
      "auth_token"  TEXT      NOT NULL,
      "org_id"      TEXT      NOT NULL,
      "created_at"  TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
      "updated_at"  TIMESTAMP NOT NULL,
      CONSTRAINT "org_webhooks_pkey" PRIMARY KEY ("id")
    )
    """

    execute """
    ALTER TABLE "org_webhooks"
      ADD CONSTRAINT "org_webhooks_org_id_fkey"
      FOREIGN KEY ("org_id") REFERENCES "orgs"("id")
      ON DELETE RESTRICT ON UPDATE CASCADE
    """

    # ---------------------------------------------------------------------------
    # org_billing_addresses
    # ---------------------------------------------------------------------------
    execute """
    CREATE TABLE "org_billing_addresses" (
      "id"         TEXT NOT NULL,
      "username"   TEXT NOT NULL,
      "city"       TEXT NOT NULL,
      "line_1"      TEXT NOT NULL,
      "country"    TEXT NOT NULL,
      "postal_code" TEXT NOT NULL,
      "state"      TEXT NOT NULL,
      "org_id"      TEXT NOT NULL,
      CONSTRAINT "org_billing_addresses_pkey" PRIMARY KEY ("id")
    )
    """

    execute """
    ALTER TABLE "org_billing_addresses"
      ADD CONSTRAINT "org_billing_addresses_org_id_fkey"
      FOREIGN KEY ("org_id") REFERENCES "orgs"("id")
      ON DELETE RESTRICT ON UPDATE CASCADE
    """

    # ---------------------------------------------------------------------------
    # org_audit_logs
    # ---------------------------------------------------------------------------
    execute """
    CREATE TABLE "org_audit_logs" (
      "id"          TEXT             NOT NULL,
      "type"        TEXT             NOT NULL,
      "org_id"       TEXT             NOT NULL,
      "call_story_id" TEXT             NOT NULL,
      "quantity"    DOUBLE PRECISION NOT NULL DEFAULT 0,
      "created_at"   TIMESTAMP        NOT NULL DEFAULT CURRENT_TIMESTAMP,
      "cost"        BIGINT           NOT NULL DEFAULT 0,
      "price"       BIGINT           NOT NULL DEFAULT 0,
      CONSTRAINT "org_audit_logs_pkey" PRIMARY KEY ("id")
    )
    """

    execute """
    CREATE INDEX "org_audit_logs_org_id_type_idx" ON "org_audit_logs"("org_id", type)
    """

    execute """
    ALTER TABLE "org_audit_logs"
      ADD CONSTRAINT "org_audit_logs_org_id_fkey"
      FOREIGN KEY ("org_id") REFERENCES "orgs"("id")
      ON DELETE RESTRICT ON UPDATE CASCADE
    """

    # ---------------------------------------------------------------------------
    # transactions
    # ---------------------------------------------------------------------------
    execute """
    CREATE TABLE "transactions" (
      "id"             TEXT             NOT NULL,
      "amount"         DOUBLE PRECISION NOT NULL DEFAULT 0,
      "date"           TIMESTAMP        NOT NULL DEFAULT CURRENT_TIMESTAMP,
      "description"    TEXT,
      "created_at"      TIMESTAMP        NOT NULL DEFAULT CURRENT_TIMESTAMP,
      "updated_at"      TIMESTAMP        NOT NULL,
      "org_id"          TEXT             NOT NULL,
      "customer_email"  TEXT             NOT NULL DEFAULT '',
      "payment_gateway" TEXT             NOT NULL DEFAULT '',
      "order_id"        TEXT             NOT NULL DEFAULT '',
      CONSTRAINT "transactions_pkey" PRIMARY KEY ("id")
    )
    """

    execute """
    ALTER TABLE "transactions"
      ADD CONSTRAINT "transactions_org_id_fkey"
      FOREIGN KEY ("org_id") REFERENCES "orgs"("id")
      ON DELETE RESTRICT ON UPDATE CASCADE
    """

    # ---------------------------------------------------------------------------
    # compliance_tasks
    # ---------------------------------------------------------------------------
    execute """
    CREATE TABLE "compliance_tasks" (
      "id"        TEXT      NOT NULL,
      "type"      TEXT      NOT NULL DEFAULT 'DELETE',
      "status"    TEXT      NOT NULL DEFAULT 'PENDING',
      "org_id"     TEXT      NOT NULL,
      "created_at" TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
      "updated_at" TIMESTAMP NOT NULL,
      "data"      JSONB     NOT NULL,
      CONSTRAINT "compliance_tasks_pkey" PRIMARY KEY ("id")
    )
    """

    execute """
    ALTER TABLE "compliance_tasks"
      ADD CONSTRAINT "compliance_tasks_org_id_fkey"
      FOREIGN KEY ("org_id") REFERENCES "orgs"("id")
      ON DELETE RESTRICT ON UPDATE CASCADE
    """

    # ---------------------------------------------------------------------------
    # voice_bots
    # ---------------------------------------------------------------------------
    execute """
    CREATE TABLE "voice_bots" (
      "id"                   TEXT               NOT NULL,
      "org_id"                TEXT               NOT NULL,
      "name"                 TEXT               NOT NULL,
      "instructions"         TEXT               NOT NULL,
      "is_hangup"             BOOLEAN            NOT NULL DEFAULT false,
      "is_enqueue"            BOOLEAN            NOT NULL DEFAULT false,
      "queues"               TEXT[],
      "api_key"               TEXT               NOT NULL,
      "not_to_do_instructions"  TEXT               NOT NULL,
      "greeting_instructions" TEXT               NOT NULL DEFAULT '',
      "mcp_servers"           JSONB              NOT NULL DEFAULT '[]',
      "pipeline"             TEXT               NOT NULL,
      CONSTRAINT "voice_bots_pkey" PRIMARY KEY ("id")
    )
    """

    execute """
    ALTER TABLE "voice_bots"
      ADD CONSTRAINT "voice_bots_org_id_fkey"
      FOREIGN KEY ("org_id") REFERENCES "orgs"("id")
      ON DELETE RESTRICT ON UPDATE CASCADE
    """

    # ---------------------------------------------------------------------------
    # campaign_groups
    # ---------------------------------------------------------------------------
    execute """
    CREATE TABLE "campaign_groups" (
      "id"        TEXT      NOT NULL,
      "org_id"     TEXT      NOT NULL,
      "name"      TEXT      NOT NULL,
      "created_at" TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
      "updated_at" TIMESTAMP NOT NULL,
      CONSTRAINT "campaign_groups_pkey" PRIMARY KEY ("id")
    )
    """

    execute """
    ALTER TABLE "campaign_groups"
      ADD CONSTRAINT "campaign_groups_org_id_fkey"
      FOREIGN KEY ("org_id") REFERENCES "orgs"("id")
      ON DELETE RESTRICT ON UPDATE CASCADE
    """

    # ---------------------------------------------------------------------------
    # campaign_scripts
    # ---------------------------------------------------------------------------
    execute """
    CREATE TABLE "campaign_scripts" (
      "id"        TEXT      NOT NULL,
      "org_id"     TEXT      NOT NULL,
      "name"      TEXT      NOT NULL,
      "created_at" TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
      "updated_at" TIMESTAMP NOT NULL,
      "script"    TEXT      NOT NULL,
      CONSTRAINT "campaign_scripts_pkey" PRIMARY KEY ("id")
    )
    """

    execute """
    ALTER TABLE "campaign_scripts"
      ADD CONSTRAINT "campaign_scripts_org_id_fkey"
      FOREIGN KEY ("org_id") REFERENCES "orgs"("id")
      ON DELETE RESTRICT ON UPDATE CASCADE
    """

    # ---------------------------------------------------------------------------
    # campaign_customer_mappings
    # ---------------------------------------------------------------------------
    execute """
    CREATE TABLE "campaign_customer_mappings" (
      "id"       TEXT  NOT NULL,
      "name"     TEXT  NOT NULL DEFAULT '',
      "mappings" JSONB NOT NULL,
      "org_id"    TEXT  NOT NULL,
      CONSTRAINT "campaign_customer_mappings_pkey" PRIMARY KEY ("id")
    )
    """

    execute """
    ALTER TABLE "campaign_customer_mappings"
      ADD CONSTRAINT "campaign_customer_mappings_org_id_fkey"
      FOREIGN KEY ("org_id") REFERENCES "orgs"("id")
      ON DELETE RESTRICT ON UPDATE CASCADE
    """

    # ---------------------------------------------------------------------------
    # campaigns
    # ---------------------------------------------------------------------------
    execute """
    CREATE TABLE "campaigns" (
      "id"               TEXT      NOT NULL,
      "campaign_group_id"  TEXT      NOT NULL,
      "name"             TEXT      NOT NULL,
      "created_at"        TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
      "updated_at"        TIMESTAMP NOT NULL,
      "start_date"        TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
      "end_date"          TIMESTAMP,
      "campaign_script_id" TEXT,
      "number_id"         TEXT      NOT NULL,
      "filters"          JSONB,
      CONSTRAINT "campaigns_pkey" PRIMARY KEY ("id")
    )
    """

    execute """
    ALTER TABLE "campaigns"
      ADD CONSTRAINT "campaigns_campaign_group_id_fkey"
      FOREIGN KEY ("campaign_group_id") REFERENCES "campaign_groups"("id")
      ON DELETE RESTRICT ON UPDATE CASCADE
    """

    execute """
    ALTER TABLE "campaigns"
      ADD CONSTRAINT "campaigns_campaign_script_id_fkey"
      FOREIGN KEY ("campaign_script_id") REFERENCES "campaign_scripts"("id")
      ON DELETE SET NULL ON UPDATE CASCADE
    """

    execute """
    ALTER TABLE "campaigns"
      ADD CONSTRAINT "campaigns_number_id_fkey"
      FOREIGN KEY ("number_id") REFERENCES "numbers"("id")
      ON DELETE RESTRICT ON UPDATE CASCADE
    """

    # ---------------------------------------------------------------------------
    # campaign_customers
    # ---------------------------------------------------------------------------
    execute """
    CREATE TABLE "campaign_customers" (
      "id"                 TEXT      NOT NULL,
      "campaign_id"        TEXT      NOT NULL,
      "first_name"          TEXT      NOT NULL DEFAULT '',
      "last_name"           TEXT      NOT NULL DEFAULT '',
      "phone_number"        TEXT      NOT NULL DEFAULT '',
      "attributes"         JSONB,
      "created_at"          TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
      "updated_at"          TIMESTAMP NOT NULL,
      "call_progress_status" TEXT      NOT NULL DEFAULT 'NOT_SCHEDULED',
      "disposition"        TEXT      NOT NULL DEFAULT '',
      "expiry_date"        TIMESTAMP,
      "member_id"           TEXT      NOT NULL DEFAULT '',
      "scheduled_date"      TIMESTAMP,
      CONSTRAINT "campaign_customers_pkey" PRIMARY KEY ("id")
    )
    """

    execute """
    ALTER TABLE "campaign_customers"
      ADD CONSTRAINT "campaign_customers_campaign_id_fkey"
      FOREIGN KEY ("campaign_id") REFERENCES "campaigns"("id")
      ON DELETE CASCADE ON UPDATE CASCADE
    """

    # ---------------------------------------------------------------------------
    # call_stories
    # ---------------------------------------------------------------------------
    execute """
    CREATE TABLE "call_stories" (
      "id"                  TEXT      NOT NULL,
      "org_id"               TEXT      NOT NULL,
      "start_at"             TIMESTAMP NOT NULL,
      "end_at"               TIMESTAMP,
      "callee"              TEXT      NOT NULL,
      "caller"              TEXT      NOT NULL,
      "direction"           TEXT      NOT NULL,
      "outbound_caller_id"    TEXT,
      "hangup_party"         TEXT,
      "is_transcribed"       BOOLEAN   NOT NULL DEFAULT false,
      "is_summarized"        BOOLEAN   NOT NULL DEFAULT false,
      "is_anonymized"        BOOLEAN   NOT NULL DEFAULT false,
      "is_sentiment_analyzed" BOOLEAN   NOT NULL DEFAULT false,
      "is_labeled"           BOOLEAN   NOT NULL DEFAULT false,
      "labels"              JSONB     NOT NULL DEFAULT '[]',
      CONSTRAINT "call_stories_pkey" PRIMARY KEY ("id")
    )
    """

    execute """
    CREATE INDEX "call_stories_labels_idx" ON "call_stories"(labels)
    """

    execute """
    ALTER TABLE "call_stories"
      ADD CONSTRAINT "call_stories_org_id_fkey"
      FOREIGN KEY ("org_id") REFERENCES "orgs"("id")
      ON DELETE RESTRICT ON UPDATE CASCADE
    """

    # ---------------------------------------------------------------------------
    # call_spans
    # ---------------------------------------------------------------------------
    execute """
    CREATE TABLE "call_spans" (
      "id"           TEXT      NOT NULL,
      "type"         TEXT      NOT NULL,
      "call_story_id"  TEXT      NOT NULL,
      "start_at"      TIMESTAMP NOT NULL,
      "end_at"        TIMESTAMP,
      "current_party" TEXT      NOT NULL,
      "channel_id"    TEXT      NOT NULL DEFAULT 'unknown',
      "metadata"     JSONB,
      CONSTRAINT "call_spans_pkey" PRIMARY KEY ("id")
    )
    """

    execute """
    ALTER TABLE "call_spans"
      ADD CONSTRAINT "call_spans_call_story_id_fkey"
      FOREIGN KEY ("call_story_id") REFERENCES "call_stories"("id")
      ON DELETE CASCADE ON UPDATE CASCADE
    """

    # ---------------------------------------------------------------------------
    # call_transcripts
    # ---------------------------------------------------------------------------
    execute """
    CREATE TABLE "call_transcripts" (
      "call_story_id"     TEXT  NOT NULL,
      "recording_span_id" TEXT  NOT NULL,
      "current_party"    TEXT  NOT NULL,
      "provider"        TEXT  NOT NULL,
      "transcript_data"  JSONB NOT NULL,
      "id"              TEXT  NOT NULL,
      CONSTRAINT "call_transcripts_pkey" PRIMARY KEY ("id")
    )
    """

    execute """
    ALTER TABLE "call_transcripts"
      ADD CONSTRAINT "call_transcripts_call_story_id_fkey"
      FOREIGN KEY ("call_story_id") REFERENCES "call_stories"("id")
      ON DELETE CASCADE ON UPDATE CASCADE
    """

    # ---------------------------------------------------------------------------
    # call_analyses
    # ---------------------------------------------------------------------------
    execute """
    CREATE TABLE "call_analyses" (
      "id"           TEXT  NOT NULL,
      "call_story_id"  TEXT  NOT NULL,
      "provider"     TEXT  NOT NULL,
      "type"         TEXT  NOT NULL,
      "analysis_data" JSONB NOT NULL,
      CONSTRAINT "call_analyses_pkey" PRIMARY KEY ("id")
    )
    """

    execute """
    ALTER TABLE "call_analyses"
      ADD CONSTRAINT "call_analyses_call_story_id_fkey"
      FOREIGN KEY ("call_story_id") REFERENCES "call_stories"("id")
      ON DELETE CASCADE ON UPDATE CASCADE
    """

    # ---------------------------------------------------------------------------
    # call_search_vectors (pgvector embeddings)
    # ---------------------------------------------------------------------------
    execute """
    CREATE TABLE "call_search_vectors" (
      "id"          TEXT         NOT NULL,
      "call_story_id" TEXT         NOT NULL,
      "embeddings"  vector(1536) NOT NULL,
      CONSTRAINT "call_search_vectors_pkey" PRIMARY KEY ("id")
    )
    """

    execute """
    ALTER TABLE "call_search_vectors"
      ADD CONSTRAINT "call_search_vectors_call_story_id_fkey"
      FOREIGN KEY ("call_story_id") REFERENCES "call_stories"("id")
      ON DELETE CASCADE ON UPDATE CASCADE
    """

    # ---------------------------------------------------------------------------
    # presence_spans
    # ---------------------------------------------------------------------------
    execute """
    CREATE TABLE "presence_spans" (
      "id"        TEXT      NOT NULL,
      "org_id"     TEXT      NOT NULL,
      "user_id"    TEXT      NOT NULL,
      "start_at"   TIMESTAMP NOT NULL,
      "end_at"     TIMESTAMP,
      "presence"  TEXT      NOT NULL,
      "created_at" TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
      "updated_at" TIMESTAMP NOT NULL,
      CONSTRAINT "presence_spans_pkey" PRIMARY KEY ("id")
    )
    """

    execute """
    ALTER TABLE "presence_spans"
      ADD CONSTRAINT "presence_spans_org_id_user_id_fkey"
      FOREIGN KEY ("org_id", "user_id") REFERENCES "org_members"("org_id", "user_id")
      ON DELETE RESTRICT ON UPDATE CASCADE
    """

    # ---------------------------------------------------------------------------
    # promises
    # ---------------------------------------------------------------------------
    execute """
    CREATE TABLE "promises" (
      "id"          TEXT            NOT NULL,
      "org_id"       TEXT            NOT NULL DEFAULT '',
      "promise"     TEXT            NOT NULL,
      "status"      TEXT            NOT NULL DEFAULT 'OPEN',
      "assigned_to"  TEXT            NOT NULL DEFAULT '',
      "created_at"   TIMESTAMP       NOT NULL DEFAULT CURRENT_TIMESTAMP,
      "updated_at"   TIMESTAMP       NOT NULL,
      "created_by"   TEXT            NOT NULL DEFAULT '',
      "due_date"     TIMESTAMP,
      "call_story_id" TEXT            NOT NULL DEFAULT '',
      CONSTRAINT "promises_pkey" PRIMARY KEY ("id")
    )
    """

    execute """
    ALTER TABLE "promises"
      ADD CONSTRAINT "promises_org_id_fkey"
      FOREIGN KEY ("org_id") REFERENCES "orgs"("id")
      ON DELETE RESTRICT ON UPDATE CASCADE
    """

    # ---------------------------------------------------------------------------
    # promise_audit_logs
    # ---------------------------------------------------------------------------
    execute """
    CREATE TABLE "promise_audit_logs" (
      "id"        TEXT                  NOT NULL,
      "promise_id" TEXT                  NOT NULL,
      "type"      TEXT                  NOT NULL,
      "old_value"  TEXT                  NOT NULL,
      "new_value"  TEXT                  NOT NULL,
      "org_id"     TEXT                  NOT NULL,
      "created_at" TIMESTAMP             NOT NULL DEFAULT CURRENT_TIMESTAMP,
      "updated_at" TIMESTAMP             NOT NULL,
      CONSTRAINT "promise_audit_logs_pkey" PRIMARY KEY ("id")
    )
    """

    execute """
    ALTER TABLE "promise_audit_logs"
      ADD CONSTRAINT "promise_audit_logs_org_id_fkey"
      FOREIGN KEY ("org_id") REFERENCES "orgs"("id")
      ON DELETE RESTRICT ON UPDATE CASCADE
    """

    # ---------------------------------------------------------------------------
    # daily_summaries
    # ---------------------------------------------------------------------------
    execute """
    CREATE TABLE "daily_summaries" (
      "id"                   TEXT      NOT NULL,
      "org_id"                TEXT      NOT NULL,
      "date"                 TIMESTAMP NOT NULL,
      "executive_summary"     TEXT      NOT NULL,
      "total_promises_closed"  INTEGER   NOT NULL DEFAULT 0,
      "total_promises_created" INTEGER   NOT NULL DEFAULT 0,
      CONSTRAINT "daily_summaries_pkey" PRIMARY KEY ("id")
    )
    """

    execute """
    ALTER TABLE "daily_summaries"
      ADD CONSTRAINT "daily_summaries_org_id_fkey"
      FOREIGN KEY ("org_id") REFERENCES "orgs"("id")
      ON DELETE RESTRICT ON UPDATE CASCADE
    """
  end

  def down do
    # Drop tables in reverse dependency order
    execute "DROP TABLE IF EXISTS \"daily_summaries\""
    execute "DROP TABLE IF EXISTS \"promise_audit_logs\""
    execute "DROP TABLE IF EXISTS \"promises\""
    execute "DROP TABLE IF EXISTS \"presence_spans\""
    execute "DROP TABLE IF EXISTS \"call_search_vectors\""
    execute "DROP TABLE IF EXISTS \"call_analyses\""
    execute "DROP TABLE IF EXISTS \"call_transcripts\""
    execute "DROP TABLE IF EXISTS \"call_spans\""
    execute "DROP TABLE IF EXISTS \"call_stories\""
    execute "DROP TABLE IF EXISTS \"campaign_customers\""
    execute "DROP TABLE IF EXISTS \"campaigns\""
    execute "DROP TABLE IF EXISTS \"campaign_customer_mappings\""
    execute "DROP TABLE IF EXISTS \"campaign_scripts\""
    execute "DROP TABLE IF EXISTS \"campaign_groups\""
    execute "DROP TABLE IF EXISTS \"voice_bots\""
    execute "DROP TABLE IF EXISTS \"compliance_tasks\""
    execute "DROP TABLE IF EXISTS \"transactions\""
    execute "DROP TABLE IF EXISTS \"org_audit_logs\""
    execute "DROP TABLE IF EXISTS \"org_billing_addresses\""
    execute "DROP TABLE IF EXISTS \"org_webhooks\""
    execute "DROP TABLE IF EXISTS \"org_invites\""
    execute "DROP TABLE IF EXISTS \"org_api_keys\""
    execute "DROP TABLE IF EXISTS \"member_api_keys\""
    execute "DROP TABLE IF EXISTS \"queue_memberships\""
    execute "DROP TABLE IF EXISTS \"queues\""
    execute "DROP TABLE IF EXISTS \"org_members\""
    execute "DROP TABLE IF EXISTS \"numbers\""
    execute "DROP TABLE IF EXISTS \"sip_trunks\""
    execute "DROP TABLE IF EXISTS \"states\""
    execute "DROP TABLE IF EXISTS \"countries\""
    execute "DROP TABLE IF EXISTS \"user_identities\""
    execute "DROP TABLE IF EXISTS \"orgs\""
    execute "DROP TABLE IF EXISTS \"users\""

    execute "DROP EXTENSION IF EXISTS vector"
  end
end
