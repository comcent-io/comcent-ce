defmodule Comcent.Repo.OrgWebhook do
  import Ecto.Query
  alias Comcent.Repo
  alias Comcent.Schemas.{OrgWebhook, Org}

  def get_all_by_org(subdomain) do
    from(w in OrgWebhook,
      join: o in Org,
      on: w.org_id == o.id,
      where: o.subdomain == ^subdomain,
      select: w
    )
    |> Repo.all()
  end

  def get_by_id(id, subdomain) do
    from(w in OrgWebhook,
      join: o in Org,
      on: w.org_id == o.id,
      where: w.id == ^id and o.subdomain == ^subdomain
    )
    |> Repo.one()
  end
end
