defmodule Comcent.Repo.User do
  import Ecto.Query
  alias Comcent.Repo
  alias Comcent.Schemas.User

  def find_user_and_org(email, subdomain) do
    User
    |> join(:inner, [u], om in assoc(u, :org_members))
    |> join(:inner, [u, om], o in assoc(om, :org))
    |> where([u, om, o], u.email == ^email and o.subdomain == ^subdomain)
    |> preload([u, om, o], org_members: {om, org: o})
    |> Repo.one()
  end
end
