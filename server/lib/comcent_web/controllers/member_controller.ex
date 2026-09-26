defmodule ComcentWeb.MemberController do
  use ComcentWeb, :controller
  import Ecto.Query
  alias Comcent.Repo
  alias Comcent.Repo.Org, as: OrgRepo
  alias Comcent.Repo.Number, as: NumberRepo
  alias Comcent.Repo.OrgMember, as: OrgMemberRepo
  alias Comcent.Schemas.{Org, OrgMember, User, Number}
  require Logger

  def update_presence(conn, %{"subdomain" => subdomain} = params) do
    current_user = conn.assigns[:current_user]
    email = current_user.email
    member = OrgMemberRepo.is_user_with_email_an_org_member(email, subdomain)
    %{"presence" => presence} = params

    if presence not in ["Logged Out", "Available", "On Break"] do
      Logger.error("Wrong presence value #{presence}")

      conn
      |> put_status(400)
      |> json(%{error: "Wrong presence value #{presence}"})
      |> halt()
    else
      OrgMemberRepo.update_member_presence(subdomain, member.user_id, presence)

      Logger.info("Updated presence for member #{member.user_id} to #{presence}")

      conn
      |> json(%{
        id: member.user.id,
        name: member.user.name,
        email: member.user.email,
        presence: presence
      })
    end
  end

  def get_presence(conn, %{"subdomain" => subdomain} = _params) do
    current_user = conn.assigns[:current_user]
    email = current_user.email
    member = OrgMemberRepo.is_user_with_email_an_org_member(email, subdomain)

    conn
    |> json(%{
      id: member.user.id,
      name: member.user.name,
      email: member.user.email,
      presence: member.presence
    })
  end

  def get_aggregate_presence(conn, %{"subdomain" => subdomain} = _params) do
    statuses = ["Available", "On Call", "On Break", "Logged Out"]
    # Get all members for the subdomain and group by presence
    presence_counts = OrgMemberRepo.get_presence_counts(subdomain)

    # Format the response to match the TypeScript structure
    status =
      Enum.map(statuses, fn presence ->
        count = Map.get(presence_counts, presence, 0)
        %{name: presence, value: count}
      end)

    json(conn, %{status: status})
  end

  def get_all_members(conn, %{"subdomain" => subdomain} = params) do
    search = String.trim(params["search"] || "")

    if search != "" do
      conn
      |> json(%{members: search_members_for_subdomain(subdomain, search)})
    else
      formatted_members =
        from(om in OrgMember,
          join: o in Org,
          on: om.org_id == o.id,
          join: u in User,
          on: om.user_id == u.id,
          left_join: ps in "presence_spans",
          on:
            field(ps, :org_id) == om.org_id and
              field(ps, :user_id) == om.user_id and
              is_nil(field(ps, :end_at)),
          where: o.subdomain == ^subdomain,
          order_by: [asc: u.email],
          select: %{
            id: om.user_id,
            username: om.username,
            extension_number: om.extension_number,
            presence: om.presence,
            presence_start_at: field(ps, :start_at),
            user: %{
              id: u.id,
              name: u.name,
              email: u.email,
              picture: u.picture
            }
          }
        )
        |> Repo.all()
        |> Enum.map(fn member ->
          presence_span =
            case member.presence_start_at do
              nil -> []
              start_at -> [%{start_at: start_at}]
            end

          member
          |> Map.delete(:presence_start_at)
          |> Map.put(:presence_span, presence_span)
        end)

      conn
      |> json(%{members: formatted_members})
    end
  end

  def get_access(conn, %{"subdomain" => subdomain} = _params) do
    current_user = conn.assigns[:current_user]

    access =
      from(om in OrgMember,
        join: o in Org,
        on: om.org_id == o.id,
        join: u in User,
        on: om.user_id == u.id,
        where: o.subdomain == ^subdomain and u.email == ^current_user.email,
        select: %{
          org_id: om.org_id,
          role: om.role,
          username: om.username,
          extension_number: om.extension_number
        }
      )
      |> Repo.one()

    if access do
      json(conn, %{access: access})
    else
      conn |> put_status(:not_found) |> json(%{error: "Org member not found"})
    end
  end

  def update_default_number(conn, %{"subdomain" => subdomain, "number" => number}) do
    current_user = conn.assigns[:current_user]

    case get_member_identity(current_user.email, subdomain) do
      nil ->
        conn |> put_status(:not_found) |> json(%{error: "Org member not found"})

      %{org_id: org_id, user_id: user_id} ->
        number_id =
          case String.trim(number || "") do
            "" ->
              nil

            number_value ->
              from(n in Number,
                join: o in Org,
                on: n.org_id == o.id,
                where: o.subdomain == ^subdomain and n.number == ^number_value,
                select: n.id
              )
              |> Repo.one()
          end

        cond do
          number_id == nil and String.trim(number || "") != "" ->
            conn
            |> put_status(:not_found)
            |> json(%{error: "number #{number} not found"})

          true ->
            from(om in OrgMember,
              where: om.org_id == ^org_id and om.user_id == ^user_id
            )
            |> Repo.update_all(set: [number_id: number_id])

            json(conn, %{status: "success"})
        end
    end
  end

  defp search_members_for_subdomain(subdomain, search) do
    from(om in OrgMember,
      join: o in Org,
      on: om.org_id == o.id,
      join: u in User,
      on: om.user_id == u.id,
      where:
        o.subdomain == ^subdomain and
          (ilike(om.username, ^"%#{search}%") or ilike(u.name, ^"%#{search}%")),
      order_by: [asc: u.name],
      limit: 5,
      select: %{
        id: u.id,
        name: u.name,
        username: om.username,
        presence: om.presence
      }
    )
    |> Repo.all()
  end

  def get_app_context(conn, %{"subdomain" => subdomain} = _params) do
    current_user = conn.assigns[:current_user]

    member_profile =
      from(om in OrgMember,
        join: o in Org,
        on: om.org_id == o.id,
        join: u in User,
        on: om.user_id == u.id,
        left_join: n in Number,
        on: om.number_id == n.id,
        where: o.subdomain == ^subdomain and u.email == ^current_user.email,
        select: %{
          user: %{
            id: u.id,
            name: u.name,
            email: u.email
          },
          number: %{
            id: n.id,
            number: n.number
          },
          org_id: om.org_id,
          role: om.role,
          username: om.username,
          sip_password: om.sip_password,
          extension_number: om.extension_number
        }
      )
      |> Repo.one()

    organizations =
      from(u in User,
        join: om in OrgMember,
        on: om.user_id == u.id,
        join: o in Org,
        on: om.org_id == o.id,
        where: u.email == ^current_user.email,
        order_by: [asc: o.name],
        select: %{
          id: o.id,
          name: o.name,
          subdomain: o.subdomain
        }
      )
      |> Repo.all()

    numbers =
      NumberRepo.get_numbers_by_org(subdomain)
      |> Enum.map(fn number ->
        %{
          id: number.id,
          name: number.name,
          number: number.number,
          sip_trunk_id: number.sip_trunk_id,
          is_default_outbound_number: number.is_default_outbound_number
        }
      end)

    json(conn, %{
      memberProfile: member_profile || %{},
      organizations: organizations,
      orgSettings: OrgRepo.get_org_settings(subdomain),
      numbers: numbers
    })
  end

  defp get_member_identity(email, subdomain) do
    from(om in OrgMember,
      join: o in Org,
      on: om.org_id == o.id,
      join: u in User,
      on: om.user_id == u.id,
      where: o.subdomain == ^subdomain and u.email == ^email,
      select: %{org_id: om.org_id, user_id: om.user_id}
    )
    |> Repo.one()
  end
end
