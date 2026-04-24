defmodule Comcent.Repo.Migrations.BumpCallStoryEventsPrecision do
  use Ecto.Migration

  # Bump `call_story_events.occurred_at` from second-precision to
  # microsecond-precision so events that happen within the same second
  # (very common under stress — queue attempt started vs. failed vs. next
  # attempt started) sort deterministically by time alone. With the old
  # `timestamp(0)` column, equal-second events were tied and required
  # `metadata->>'attempt_number'` to reconstruct the real order.
  def change do
    alter table(:call_story_events) do
      modify(:occurred_at, :utc_datetime_usec, null: false, from: :utc_datetime)
    end
  end
end
