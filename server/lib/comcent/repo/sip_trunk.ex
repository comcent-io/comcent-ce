defmodule Comcent.Repo.SipTrunk do
  import Ecto.Query

  alias Comcent.Repo
  alias Comcent.Schemas.{SipTrunk, Org, Number}

  def get_all_by_org(subdomain) do
    from(st in SipTrunk,
      join: o in Org,
      on: st.org_id == o.id,
      where: o.subdomain == ^subdomain,
      select: st
    )
    |> Repo.all()
  end

  def get_by_id(id, subdomain) do
    from(st in SipTrunk,
      join: o in Org,
      on: st.org_id == o.id,
      where: st.id == ^id and o.subdomain == ^subdomain
    )
    |> Repo.one()
  end

  def get_numbers_for_trunk(id) do
    from(n in Number,
      where: n.sip_trunk_id == ^id,
      select: n
    )
    |> Repo.all()
  end
end
