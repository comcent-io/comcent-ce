defmodule Comcent.Repo.Migrations.LinkSipTrunksToProviderConnections do
  @moduledoc """
  Records which provider connection created a SIP trunk.

  Two things needed this. Deleting such a trunk by hand leaves the real trunk
  behind in the provider account, so the UI has to know which trunks it must not
  offer to delete. And disconnect was finding its trunk by matching a name it
  had constructed — fragile if the label changes, and capable of matching a
  trunk the customer created themselves.

  Null means a manually configured trunk, which behaves exactly as before.
  """

  use Ecto.Migration

  def up do
    execute """
    ALTER TABLE "sip_trunks"
      ADD COLUMN IF NOT EXISTS "provider_connection_id" TEXT
    """

    execute """
    ALTER TABLE "sip_trunks"
      ADD CONSTRAINT "sip_trunks_provider_connection_id_fkey"
      FOREIGN KEY ("provider_connection_id") REFERENCES "provider_connections"("id")
      ON DELETE SET NULL ON UPDATE CASCADE
    """
  end

  def down do
    execute """
    ALTER TABLE "sip_trunks" DROP CONSTRAINT IF EXISTS "sip_trunks_provider_connection_id_fkey"
    """

    execute """
    ALTER TABLE "sip_trunks" DROP COLUMN IF EXISTS "provider_connection_id"
    """
  end
end
