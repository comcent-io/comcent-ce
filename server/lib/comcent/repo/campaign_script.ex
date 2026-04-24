defmodule Comcent.Repo.CampaignScript do
  import Ecto.Query

  alias Comcent.Repo
  alias Comcent.Schemas.{Campaign, CampaignScript, Org}

  @doc """
  List all campaign scripts scoped to an org subdomain.
  Mirrors the Prisma findMany with org.subdomain condition.
  """
  def get_all_campaign_scripts(subdomain) do
    from(cs in CampaignScript,
      join: o in Org,
      on: cs.org_id == o.id,
      where: o.subdomain == ^subdomain
    )
    |> Repo.all()
  end

  @doc """
  Fetch a single campaign script by ID scoped to an org subdomain.
  Mirrors the Prisma findUnique with org.subdomain condition.
  """
  def get_campaign_script_by_id(campaign_script_id, subdomain) do
    from(cs in CampaignScript,
      join: o in Org,
      on: cs.org_id == o.id,
      where: cs.id == ^campaign_script_id and o.subdomain == ^subdomain
    )
    |> Repo.one()
  end

  @doc """
  Fetch all campaigns linked to a given campaign script ID.
  Mirrors the Prisma findMany in extractCampaignsFromCampaignScript.ts.
  """
  def get_campaigns_by_campaign_script_id(campaign_script_id) do
    from(c in Campaign,
      where: c.campaign_script_id == ^campaign_script_id,
      select: %{name: c.name}
    )
    |> Repo.all()
  end
end
