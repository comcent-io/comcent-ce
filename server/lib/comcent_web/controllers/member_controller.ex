defmodule ComcentWeb.MemberController do
  use ComcentWeb, :controller
  import Ecto.Query
  alias Comcent.Repo
  alias Comcent.Repo.Org, as: OrgRepo
  alias Comcent.Repo.Number, as: NumberRepo
  alias Comcent.Repo.OrgMember, as: OrgMemberRepo
  alias Comcent.Schemas.{Org, OrgMember, User, Number, MemberApiKey}
  require Logger

  def update_presence(conn, %{"subdomain" => subdomain} = params) do
    current_user = conn.assigns[:current_user]
    email = current_user.email
    member = OrgMemberRepo.is_user_with_email_an_org_member(email, subdomain)
    %{"presence" => presence} = params

    if presence not in ["Logged Out", "Available", "On Break"] do
      Logger.error("Wrong presence value #{presence}")

      conn
      |> put_resp_header("Access-Control-Allow-Origin", "*")
      |> put_resp_header("Access-Control-Allow-Methods", "GET, OPTIONS")
      |> put_resp_header("Access-Control-Allow-Headers", "Content-Type, Authorization")
      |> put_status(400)
      |> json(%{error: "Wrong presence value #{presence}"})
      |> halt()
    else
      OrgMemberRepo.update_member_presence(subdomain, member.user_id, presence)

      Logger.info("Updated presence for member #{member.user_id} to #{presence}")

      conn
      |> put_resp_header("Access-Control-Allow-Origin", "*")
      |> put_resp_header("Access-Control-Allow-Methods", "GET, OPTIONS")
      |> put_resp_header("Access-Control-Allow-Headers", "Content-Type, Authorization")
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
    |> put_resp_header("Access-Control-Allow-Origin", "*")
    |> put_resp_header("Access-Control-Allow-Methods", "GET, OPTIONS")
    |> put_resp_header("Access-Control-Allow-Headers", "Content-Type, Authorization")
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
      |> put_widget_cors_headers()
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
      |> put_resp_header("Access-Control-Allow-Origin", "*")
      |> put_resp_header("Access-Control-Allow-Methods", "GET, OPTIONS")
      |> put_resp_header("Access-Control-Allow-Headers", "Content-Type, Authorization")
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

  def search_members(conn, %{"subdomain" => subdomain} = params) do
    search = String.trim(params["search"] || "")
    conn = put_widget_cors_headers(conn)

    if search == "" do
      json(conn, %{members: []})
    else
      json(conn, %{members: search_members_for_subdomain(subdomain, search)})
    end
  end

  def update_default_number(conn, %{"subdomain" => subdomain, "number" => number}) do
    current_user = conn.assigns[:current_user]
    conn = put_widget_cors_headers(conn)

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

  def get_widget_init_config(conn, %{"subdomain" => subdomain} = _params) do
    current_user = conn.assigns[:current_user]
    conn = put_widget_cors_headers(conn)

    member_profile =
      from(om in OrgMember,
        join: o in Org,
        on: om.org_id == o.id,
        join: u in User,
        on: om.user_id == u.id,
        where: o.subdomain == ^subdomain and u.email == ^current_user.email,
        select: %{
          name: u.name,
          username: om.username,
          sip_password: om.sip_password
        }
      )
      |> Repo.one()

    if member_profile do
      outbound_numbers =
        NumberRepo.get_numbers_by_org(subdomain)
        |> Enum.map(fn number ->
          %{
            id: number.id,
            name: number.name,
            number: number.number,
            sip_trunk: %{
              id: number.sip_trunk.id,
              name: number.sip_trunk.name
            }
          }
        end)

      sip_domain = Application.fetch_env!(:comcent, :sip_domain)

      json(conn, %{
        name: member_profile.name,
        username: member_profile.username,
        subdomain: subdomain,
        sip_password: member_profile.sip_password,
        serverDomain: "ws.#{subdomain}.#{sip_domain}",
        outboundNumbers: outbound_numbers
      })
    else
      conn |> put_status(:unauthorized) |> json(%{error: "Invalid email."})
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

    api_keys =
      if member_profile do
        from(mak in MemberApiKey,
          where: mak.org_id == ^member_profile.org_id and mak.user_id == ^member_profile.user.id,
          order_by: [asc: mak.name],
          select: %{
            api_key: mak.api_key,
            name: mak.name,
            created_at: mak.created_at,
            updated_at: mak.updated_at
          }
        )
        |> Repo.all()
      else
        []
      end

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
      memberProfile: Map.put(member_profile || %{}, :api_keys, api_keys),
      organizations: organizations,
      orgSettings: OrgRepo.get_org_settings(subdomain),
      numbers: numbers
    })
  end

  def create_api_key(conn, %{"subdomain" => subdomain, "name" => name}) do
    current_user = conn.assigns[:current_user]

    cond do
      String.trim(name) == "" or String.length(String.trim(name)) < 3 ->
        conn
        |> put_status(:bad_request)
        |> json(%{errorMessage: "Name must be at least 3 characters"})

      true ->
        case get_member_identity(current_user.email, subdomain) do
          nil ->
            conn |> put_status(:not_found) |> json(%{error: "Org member not found"})

          %{org_id: org_id, user_id: user_id} ->
            now = DateTime.utc_now() |> DateTime.truncate(:second)

            attrs = %{
              api_key: :crypto.strong_rand_bytes(32) |> Base.encode16(case: :lower),
              name: String.trim(name),
              org_id: org_id,
              user_id: user_id,
              created_at: now,
              updated_at: now
            }

            case Repo.insert(MemberApiKey.changeset(%MemberApiKey{}, attrs)) do
              {:ok, api_key} ->
                conn |> put_status(:ok) |> json(%{api_key: api_key.api_key, name: api_key.name})

              {:error, changeset} ->
                conn
                |> put_status(:bad_request)
                |> json(%{error: inspect(changeset.errors)})
            end
        end
    end
  end

  def delete_api_key(conn, %{"subdomain" => subdomain, "api_key" => api_key}) do
    current_user = conn.assigns[:current_user]

    case get_member_identity(current_user.email, subdomain) do
      nil ->
        conn |> put_status(:not_found) |> json(%{error: "Org member not found"})

      %{org_id: org_id, user_id: user_id} ->
        {deleted_count, _} =
          from(mak in MemberApiKey,
            where: mak.org_id == ^org_id and mak.user_id == ^user_id and mak.api_key == ^api_key
          )
          |> Repo.delete_all()

        if deleted_count > 0 do
          json(conn, %{success: true})
        else
          conn |> put_status(:not_found) |> json(%{error: "API key not found"})
        end
    end
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

  def options_widget(conn, _params) do
    conn
    |> put_widget_cors_headers()
    |> send_resp(204, "")
  end

  defp put_widget_cors_headers(conn) do
    conn
    |> put_resp_header("access-control-allow-origin", "*")
    |> put_resp_header("access-control-allow-methods", "GET, POST, OPTIONS")
    |> put_resp_header("access-control-allow-headers", "Content-Type, Authorization")
  end
end
