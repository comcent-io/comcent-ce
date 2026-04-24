defmodule Comcent.Repo.Migrations.AddCallStoryEvents do
  use Ecto.Migration

  def change do
    create table(:call_story_events, primary_key: false) do
      add(:id, :text, primary_key: true)
      add(:type, :text, null: false)

      add(:call_story_id, references(:call_stories, type: :text, on_delete: :delete_all),
        null: false
      )

      add(:occurred_at, :utc_datetime, null: false)
      add(:current_party, :text)
      add(:channel_id, :text, null: false, default: "unknown")
      add(:metadata, :map)
    end
  end
end
