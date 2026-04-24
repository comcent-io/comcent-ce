defmodule Comcent.Schemas.OrgAuditLog do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :string, autogenerate: false}
  @foreign_key_type :string
  schema "org_audit_logs" do
    field(:type, Ecto.Enum,
      values: [
        :CALL_TALK_TIME,
        :CALL_TRANSCRIPTION,
        :CALL_SENTIMENT_ANALYSIS,
        :CALL_SUMMARY_ANALYSIS,
        :CALL_RECORDING_S3_FILE_SIZE,
        :VOICEBOT
      ]
    )

    field(:call_story_id, :string)
    field(:quantity, :float, default: 0.0)
    field(:cost, :integer, default: 0)
    field(:price, :integer, default: 0)

    belongs_to(:org, Comcent.Schemas.Org, foreign_key: :org_id)

    timestamps(inserted_at: :created_at, updated_at: false)
  end

  def changeset(org_audit_log, attrs) do
    org_audit_log
    |> cast(attrs, [:type, :org_id, :call_story_id, :quantity, :cost, :price])
    |> validate_required([:type, :org_id, :call_story_id])
    |> foreign_key_constraint(:org_id,
      name: "org_audit_logs_org_id_fkey",
      message: "Organization not found"
    )
  end
end
