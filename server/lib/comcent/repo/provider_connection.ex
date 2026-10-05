defmodule Comcent.Repo.ProviderConnection do
  @moduledoc """
  Queries for provider connections.

  Everything is scoped by org subdomain rather than by id alone — a connection
  carries credentials to a customer's billing-bearing account, so an id from
  one org must never resolve for another.
  """

  import Ecto.Query

  alias Comcent.Repo
  alias Comcent.Schemas.{Org, ProviderConnection, ProviderNumber}

  def get_all_by_org(subdomain) do
    from(pc in ProviderConnection,
      join: o in Org,
      on: pc.org_id == o.id,
      where: o.subdomain == ^subdomain,
      order_by: [asc: pc.label],
      select: pc
    )
    |> Repo.all()
  end

  def get_by_id(id, subdomain) do
    from(pc in ProviderConnection,
      join: o in Org,
      on: pc.org_id == o.id,
      where: pc.id == ^id and o.subdomain == ^subdomain
    )
    |> Repo.one()
  end

  @doc """
  Provider SIDs of numbers this org has already imported from this connection.

  This is what makes a cached inventory unnecessary: the import picker fetches
  live from Twilio and uses this set to mark what is already taken, rather than
  diffing against a stored copy of the customer's whole account.
  """
  def imported_provider_sids(connection_id) do
    from(pn in ProviderNumber,
      where: pn.provider_connection_id == ^connection_id,
      select: pn.provider_sid
    )
    |> Repo.all()
    |> MapSet.new()
  end

  def get_numbers(connection_id) do
    from(pn in ProviderNumber,
      where: pn.provider_connection_id == ^connection_id,
      order_by: [asc: pn.e164],
      select: pn
    )
    |> Repo.all()
  end
end
