defmodule Comcent.Repo.CampaignGroup do
  import Ecto.Query

  alias Comcent.Repo
  alias Comcent.Schemas.{CampaignGroup, Org}

  @doc """
  Fetch a single campaign group by ID scoped to an org subdomain.
  Preloads the group's campaigns to mirror the Prisma include.
  """
  def get_campaign_group_by_id(campaign_group_id, subdomain) do
    from(cg in CampaignGroup,
      join: o in Org,
      on: cg.org_id == o.id,
      where: cg.id == ^campaign_group_id and o.subdomain == ^subdomain
    )
    |> preload(:campaigns)
    |> Repo.one()
  end

  @doc """
  List all campaign groups for an org by subdomain.
  """
  def get_all_campaign_groups(subdomain) do
    from(cg in CampaignGroup,
      join: o in Org,
      on: cg.org_id == o.id,
      where: o.subdomain == ^subdomain
    )
    |> Repo.all()
  end
end
