defmodule Comcent.Repo.Number do
  import Ecto.Query
  alias Comcent.Repo
  alias Comcent.Schemas.{Number, Org, Campaign}

  def get_numbers_by_org(subdomain) do
    Repo.all(
      from(n in Number,
        join: o in Org,
        on: n.org_id == o.id,
        where: o.subdomain == ^subdomain,
        preload: [:sip_trunk],
        select: n
      )
    )
  end

  def get_numbers_paginated(subdomain, page, items_per_page) do
    offset = (page - 1) * items_per_page

    numbers =
      from(n in Number,
        join: o in Org,
        on: n.org_id == o.id,
        where: o.subdomain == ^subdomain,
        preload: [:sip_trunk],
        order_by: [asc: n.name],
        limit: ^items_per_page,
        offset: ^offset,
        select: n
      )
      |> Repo.all()

    total_count =
      from(n in Number,
        join: o in Org,
        on: n.org_id == o.id,
        where: o.subdomain == ^subdomain,
        select: count(n.id)
      )
      |> Repo.one()

    %{numbers: numbers, total_count: total_count}
  end

  def clear_default_for_org(subdomain) do
    from(n in Number,
      join: o in Org,
      on: n.org_id == o.id,
      where: o.subdomain == ^subdomain
    )
    |> Repo.update_all(set: [is_default_outbound_number: false])
  end

  def get_by_id(id, subdomain) do
    from(n in Number,
      join: o in Org,
      on: n.org_id == o.id,
      where: n.id == ^id and o.subdomain == ^subdomain
    )
    |> Repo.one()
  end

  def get_by_number(number_value) do
    Repo.one(from(n in Number, where: n.number == ^number_value))
  end

  def get_campaigns_for_number(id) do
    from(c in Campaign, where: c.number_id == ^id, select: c)
    |> Repo.all()
  end
end
