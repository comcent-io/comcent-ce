defmodule Comcent.Repo.Migrations.AddAcceptedTermsVersion do
  use Ecto.Migration

  # Which TERMS_VERSION a user last accepted (Comcent.Terms), so publishing
  # new terms under a new version asks everyone to accept again. Users who
  # accepted before terms had versions are left null, which asks them again
  # too: what they accepted had placeholder links.
  def up do
    execute(~s|ALTER TABLE "users" ADD COLUMN IF NOT EXISTS "accepted_terms_version" TEXT|)
  end

  def down do
    execute(~s|ALTER TABLE "users" DROP COLUMN IF EXISTS "accepted_terms_version"|)
  end
end
