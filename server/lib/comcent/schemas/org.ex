defmodule Comcent.Schemas.Org do
  use Ecto.Schema
  import Ecto.Changeset
  alias Comcent.Types.Json

  @primary_key {:id, :string, autogenerate: false}
  @foreign_key_type :string
  schema "orgs" do
    field(:name, :string)
    field(:subdomain, :string)
    field(:use_custom_domain, :boolean)
    field(:custom_domain, :string)
    field(:assign_ext_automatically, :boolean)
    field(:auto_ext_start, :string)
    field(:auto_ext_end, :string)
    field(:is_active, :boolean, default: true)
    field(:enable_transcription, :boolean, default: true)
    field(:enable_sentiment_analysis, :boolean, default: true)
    field(:enable_summary, :boolean, default: true)
    field(:enable_labels, :boolean, default: true)
    field(:labels, {:array, Json})
    field(:enable_call_recording, :boolean, default: true)
    field(:enable_daily_summary, :boolean, default: true)
    field(:daily_summary_time_zone, :string, default: "America/New_York")
    field(:daily_summary_time, :string)
    field(:max_members, :integer)
    field(:alert_threshold_balance, :integer, default: 5)
    field(:wallet_balance, :integer, default: 0)
    field(:storage_used, :integer, default: 0)
    field(:max_monthly_storage_used, :integer, default: 0)
    field(:low_balance_alert_triggered_at, :utc_datetime)
    field(:low_balance_alert_count, :integer, default: 0)

    has_many(:org_members, Comcent.Schemas.OrgMember, foreign_key: :org_id)
    has_many(:members, through: [:org_members, :user])
    has_many(:sip_trunks, Comcent.Schemas.SipTrunk, foreign_key: :org_id)
    has_many(:numbers, Comcent.Schemas.Number, foreign_key: :org_id)
    has_many(:queues, Comcent.Schemas.Queue, foreign_key: :org_id)
    has_many(:call_stories, Comcent.Schemas.CallStory, foreign_key: :org_id)
    has_many(:org_invites, Comcent.Schemas.OrgInvite, foreign_key: :org_id)
    has_many(:api_keys, Comcent.Schemas.OrgApiKey, foreign_key: :org_id)
    has_many(:webhooks, Comcent.Schemas.OrgWebhook, foreign_key: :org_id)
    has_many(:audit_logs, Comcent.Schemas.OrgAuditLog, foreign_key: :org_id)
    has_many(:billing_addresses, Comcent.Schemas.OrgBillingAddress, foreign_key: :org_id)
    has_many(:compliance_tasks, Comcent.Schemas.ComplianceTask, foreign_key: :org_id)
    has_many(:voice_bots, Comcent.Schemas.VoiceBot, foreign_key: :org_id)
    has_many(:campaign_groups, Comcent.Schemas.CampaignGroup, foreign_key: :org_id)

    has_many(:campaign_customer_mappings, Comcent.Schemas.CampaignCustomerMapping,
      foreign_key: :org_id
    )

    has_many(:campaign_scripts, Comcent.Schemas.CampaignScript, foreign_key: :org_id)
    has_many(:transactions, Comcent.Schemas.Transaction, foreign_key: :org_id)
    has_many(:promises, Comcent.Schemas.Promises, foreign_key: :org_id)
    has_many(:promise_audit_logs, Comcent.Schemas.PromiseAuditLog, foreign_key: :org_id)
    has_many(:daily_summaries, Comcent.Schemas.DailySummary, foreign_key: :org_id)

    timestamps(inserted_at: :created_at, updated_at: :updated_at)
  end

  def changeset(org, attrs) do
    org
    |> cast(attrs, [
      :name,
      :subdomain,
      :use_custom_domain,
      :custom_domain,
      :assign_ext_automatically,
      :auto_ext_start,
      :auto_ext_end,
      :is_active,
      :enable_transcription,
      :enable_sentiment_analysis,
      :enable_summary,
      :enable_labels,
      :labels,
      :enable_call_recording,
      :enable_daily_summary,
      :daily_summary_time_zone,
      :daily_summary_time,
      :max_members,
      :alert_threshold_balance,
      :wallet_balance,
      :storage_used,
      :max_monthly_storage_used,
      :low_balance_alert_triggered_at,
      :low_balance_alert_count
    ])
    |> validate_required([:name, :subdomain])
    |> unique_constraint(:subdomain)
    |> unique_constraint(:custom_domain)
  end
end
