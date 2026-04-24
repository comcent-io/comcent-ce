defmodule Comcent.Repo.OrgApiKey do
  import Ecto.Query
  alias Comcent.Repo
  alias Comcent.Schemas.{OrgApiKey, Org}

  def get_all_by_org(subdomain) do
    from(k in OrgApiKey,
      join: o in Org,
      on: k.org_id == o.id,
      where: o.subdomain == ^subdomain,
      select: k
    )
    |> Repo.all()
  end

  def get_by_api_key(api_key, subdomain) do
    from(k in OrgApiKey,
      join: o in Org,
      on: k.org_id == o.id,
      where: k.api_key == ^api_key and o.subdomain == ^subdomain
    )
    |> Repo.one()
  end
end
