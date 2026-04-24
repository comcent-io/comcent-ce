defmodule Comcent.Repo.Campaign do
  import Ecto.Query

  alias Comcent.Repo
  alias Comcent.Schemas.{Campaign, CampaignGroup, Org}

  @doc """
  Fetch a single campaign by ID scoped to an org subdomain.
  Preloads campaign_script, campaign_customers, and number to mirror the Prisma include.
  """
  def get_campaign_by_id(campaign_id, subdomain) do
    from(c in Campaign,
      join: cg in CampaignGroup,
      on: c.campaign_group_id == cg.id,
      join: o in Org,
      on: cg.org_id == o.id,
      where: c.id == ^campaign_id and o.subdomain == ^subdomain
    )
    |> preload([:campaign_script, :campaign_customers, :number])
    |> Repo.one()
  end

  @doc """
  List all campaigns for a campaign group scoped to an org subdomain.
  Preloads campaign_customers to mirror the Prisma include.
  """
  def get_all_campaigns(subdomain, campaign_group_id) do
    from(c in Campaign,
      join: cg in CampaignGroup,
      on: c.campaign_group_id == cg.id,
      join: o in Org,
      on: cg.org_id == o.id,
      where: cg.id == ^campaign_group_id and o.subdomain == ^subdomain
    )
    |> preload(:campaign_customers)
    |> Repo.all()
  end
end
