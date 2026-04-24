defmodule Comcent.Repo.VoiceBot do
  import Ecto.Query
  alias Comcent.Repo
  alias Comcent.Schemas.{VoiceBot, Org}

  def get_voicebots_by_org(subdomain) do
    from(v in VoiceBot,
      join: o in Org,
      on: v.org_id == o.id,
      where: o.subdomain == ^subdomain,
      select: v
    )
    |> Repo.all()
  end

  def get_by_id(id, subdomain) do
    from(v in VoiceBot,
      join: o in Org,
      on: v.org_id == o.id,
      where: v.id == ^id and o.subdomain == ^subdomain
    )
    |> Repo.one()
  end
end
