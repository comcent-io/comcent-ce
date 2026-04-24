defmodule ComcentWeb.AdminMemberController do
  use ComcentWeb, :controller
  require Logger

  import Ecto.Query
  alias Ecto.Multi
  alias Comcent.Emails
  alias Comcent.Repo
  alias Comcent.Schemas.{OrgInvite, User}
  alias Comcent.Schemas.OrgMember, as: OrgMemberSchema

  @invite_resend_cooldown_seconds 60
  @invite_resend_limit_per_day 3
  @invite_resend_window_seconds 24 * 60 * 60

  def list_members(conn, params) do
    subdomain = conn.assigns[:subdomain]
    Logger.info("Listing members for org #{subdomain}")

    current_page = String.to_integer(params["page"] || "1")
    items_per_page = parse_items_per_page(params["items_per_page"])

    members = get_paginated_members(subdomain, items_per_page, current_page)
    member_count = get_member_count(subdomain)
    org_settings = Comcent.Repo.Org.get_org_settings(subdomain)

    allow_member_invite =
      if org_settings do
        member_count < (org_settings.max_members || 100)
      else
        false
      end

    formatted_members =
      Enum.map(members, fn member ->
        %{
          user_id: member.user_id,
          org_id: member.org_id,
          role: member.role,
          username: member.username,
          sip_password: member.sip_password,
          extension_number: member.extension_number,
          presence: member.presence,
          user: %{
            id: member.user.id,
            name: member.user.name,
            email: member.user.email
          },
          number:
            if member.number do
              %{id: member.number.id, number: member.number.number}
            else
              nil
            end
        }
      end)

    pending_invites = get_pending_invites(subdomain)

    json(conn, %{
      members: formatted_members,
      pending_invites: pending_invites,
      member_count: member_count,
      pending_invite_count: length(pending_invites),
      total_pages: ceil_div(member_count, items_per_page),
      current_page: current_page,
      items_per_page: items_per_page,
      allow_member_invite: allow_member_invite
    })
  end

  def get_member(conn, %{"member_id" => member_id}) do
    subdomain = conn.assigns[:subdomain]
    Logger.info("Getting member #{member_id} for org #{subdomain}")

    case find_member_with_id(member_id, subdomain) do
      nil ->
        conn |> put_status(:not_found) |> json(%{error: "Member not found"})

      member ->
        json(conn, %{
          user_id: member.user_id,
          org_id: member.org_id,
          role: member.role,
          username: member.username,
          sip_password: member.sip_password,
          extension_number: member.extension_number,
          user: %{
            id: member.user.id,
            name: member.user.name,
            email: member.user.email
          },
          number:
            if member.number do
              %{id: member.number.id, number: member.number.number}
            else
              nil
            end
        })
    end
  end

  def update_role(conn, %{"member_id" => member_id} = params) do
    subdomain = conn.assigns[:subdomain]
    Logger.info("Updating role for member #{member_id} in org #{subdomain}")

    role = params["role"]

    if role not in ["ADMIN", "MEMBER"] do
      conn |> put_status(:bad_request) |> json(%{error: "Invalid role"})
    else
      case find_org_id(subdomain) do
        nil ->
          conn |> put_status(:not_found) |> json(%{error: "Organization not found"})

        org_id ->
          query =
            from(om in OrgMemberSchema,
              where: om.user_id == ^member_id and om.org_id == ^org_id,
              update: [set: [role: ^String.to_existing_atom(role)]]
            )

          case Repo.update_all(query, []) do
            {0, _} ->
              conn |> put_status(:not_found) |> json(%{error: "Member not found"})

            {_, _} ->
              Logger.info("Role updated for member #{member_id} in org #{subdomain}")
              conn |> put_status(:ok) |> json(%{message: "Role updated successfully"})
          end
      end
    end
  end

  def regenerate_password(conn, %{"member_id" => member_id}) do
    subdomain = conn.assigns[:subdomain]
    Logger.info("Regenerating password for member #{member_id} in org #{subdomain}")

    case find_org_id(subdomain) do
      nil ->
        conn |> put_status(:not_found) |> json(%{error: "Organization not found"})

      org_id ->
        new_password = :crypto.strong_rand_bytes(16) |> Base.url_encode64(padding: false)

        query =
          from(om in OrgMemberSchema,
            where: om.user_id == ^member_id and om.org_id == ^org_id,
            update: [set: [sip_password: ^new_password]]
          )

        case Repo.update_all(query, []) do
          {0, _} ->
            conn |> put_status(:not_found) |> json(%{error: "Member not found"})

          {_, _} ->
            Logger.info("Password regenerated for member #{member_id} in org #{subdomain}")
            conn |> put_status(:ok) |> json(%{message: "Password regenerated successfully"})
        end
    end
  end

  def invite_member(conn, params) do
    subdomain = conn.assigns[:subdomain]
    Logger.info("Inviting member to org #{subdomain}")

    email = params["email"]
    role = params["role"]

    with {:ok, email} <- validate_email(email),
         {:ok, role} <- validate_role(role),
         :not_member <- if(is_already_member?(email, subdomain), do: :member, else: :not_member),
         :not_invited <-
           if(is_already_invited?(email, subdomain), do: :invited, else: :not_invited) do
      case Comcent.Repo.Org.get_org_by_subdomain(subdomain) do
        nil ->
          conn |> put_status(:not_found) |> json(%{error: "Organization not found"})

        org ->
          attrs = %{
            "email" => email,
            "role" => role,
            "status" => "PENDING",
            "org_id" => org.id,
            "invite_email_sent_at" => DateTime.utc_now(),
            "invite_resend_count" => 0
          }

          new_invite = %OrgInvite{id: Ecto.UUID.generate()}

          case create_and_email_invite(new_invite, attrs, org.name) do
            {:ok, _invite} ->
              Logger.info("Member invited successfully to org #{subdomain}")
              conn |> put_status(:ok) |> json(%{success: true})

            {:error, changeset} ->
              Logger.error("Failed to invite member: #{inspect(changeset.errors)}")

              conn
              |> put_status(:bad_request)
              |> json(%{error: format_errors(changeset)})

            {:error, :deliver_invite_email, reason, _changes_so_far} ->
              Logger.error("Failed to send invite email: #{inspect(reason)}")

              conn
              |> put_status(:bad_gateway)
              |> json(%{error: "Unable to send invitation email. Please try again."})
          end
      end
    else
      {:error, msg} ->
        conn |> put_status(:bad_request) |> json(%{error: msg})

      :member ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "User is already a member of this organization"})

      :invited ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "User is already invited to this organization"})
    end
  end

  def resend_invite(conn, %{"invite_id" => invite_id}) do
    subdomain = conn.assigns[:subdomain]
    now = DateTime.utc_now()

    case find_pending_invite(invite_id, subdomain) do
      nil ->
        conn |> put_status(:not_found) |> json(%{error: "Invite not found"})

      invite ->
        case resend_org_invite(invite, now) do
          {:ok, payload} ->
            json(conn, payload)

          {:error, :cooldown_active, retry_after_seconds} ->
            conn
            |> put_status(:too_many_requests)
            |> json(%{
              error:
                "Please wait #{retry_after_seconds} seconds before resending this invitation."
            })

          {:error, :daily_limit_reached} ->
            conn
            |> put_status(:too_many_requests)
            |> json(%{error: "This invitation can only be resent 3 times in 24 hours."})

          {:error, _reason} ->
            conn
            |> put_status(:bad_gateway)
            |> json(%{error: "Unable to resend invitation email. Please try again."})
        end
    end
  end

  defp validate_email(nil), do: {:error, "Email is required"}

  defp validate_email(email) do
    if String.match?(email, ~r/^[^\s@]+@[^\s@]+\.[^\s@]+$/) do
      {:ok, email}
    else
      {:error, "Invalid email address"}
    end
  end

  defp validate_role(nil), do: {:error, "Role is required"}
  defp validate_role(role) when role in ["MEMBER", "ADMIN"], do: {:ok, role}
  defp validate_role(_), do: {:error, "Invalid role"}

  defp is_already_member?(email, subdomain) do
    query =
      from(om in OrgMemberSchema,
        join: o in Comcent.Schemas.Org,
        on: om.org_id == o.id,
        join: u in User,
        on: om.user_id == u.id,
        where: o.subdomain == ^subdomain and u.email == ^email
      )

    Repo.exists?(query)
  end

  defp is_already_invited?(email, subdomain) do
    query =
      from(i in OrgInvite,
        join: o in Comcent.Schemas.Org,
        on: i.org_id == o.id,
        where: o.subdomain == ^subdomain and i.email == ^email and i.status == "PENDING"
      )

    Repo.exists?(query)
  end

  defp get_pending_invites(subdomain) do
    from(i in OrgInvite,
      join: o in Comcent.Schemas.Org,
      on: i.org_id == o.id,
      where: o.subdomain == ^subdomain and i.status == "PENDING",
      order_by: [desc: i.created_at],
      select: %{
        id: i.id,
        email: i.email,
        role: i.role,
        status: i.status,
        created_at: i.created_at,
        invite_email_sent_at: i.invite_email_sent_at,
        invite_resend_count: i.invite_resend_count
      }
    )
    |> Repo.all()
  end

  defp create_and_email_invite(new_invite, attrs, org_name) do
    invite_changeset = Comcent.Schemas.OrgInvite.changeset(new_invite, attrs)

    Multi.new()
    |> Multi.insert(:invite, invite_changeset)
    |> Multi.run(:deliver_invite_email, fn _repo, %{invite: invite} ->
      Emails.send_org_invite_email(invite, org_name)
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{invite: invite}} -> {:ok, invite}
      {:error, :invite, changeset, _changes_so_far} -> {:error, changeset}
      {:error, step, reason, changes_so_far} -> {:error, step, reason, changes_so_far}
    end
  end

  defp resend_org_invite(invite, now) do
    Repo.transaction(fn ->
      invite = Repo.get!(OrgInvite, invite.id) |> Repo.preload(:org)

      with :ok <- ensure_invite_resend_cooldown_elapsed(invite, now),
           :ok <- ensure_invite_daily_limit_not_reached(invite, now) do
        updated_invite =
          invite
          |> OrgInvite.changeset(invite_resend_tracking_attrs(invite, now))
          |> Repo.update!()

        case Emails.send_org_invite_email(updated_invite, updated_invite.org.name) do
          {:ok, _} -> %{success: true}
          {:error, reason} -> Repo.rollback(reason)
        end
      else
        {:error, reason, value} -> Repo.rollback({reason, value})
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
    |> case do
      {:ok, payload} ->
        {:ok, payload}

      {:error, {:cooldown_active, retry_after_seconds}} ->
        {:error, :cooldown_active, retry_after_seconds}

      {:error, :daily_limit_reached} ->
        {:error, :daily_limit_reached}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp ensure_invite_resend_cooldown_elapsed(%OrgInvite{invite_email_sent_at: nil}, _now), do: :ok

  defp ensure_invite_resend_cooldown_elapsed(%OrgInvite{invite_email_sent_at: sent_at}, now) do
    elapsed_seconds = DateTime.diff(now, sent_at, :second)

    if elapsed_seconds >= @invite_resend_cooldown_seconds do
      :ok
    else
      {:error, :cooldown_active, @invite_resend_cooldown_seconds - elapsed_seconds}
    end
  end

  defp ensure_invite_daily_limit_not_reached(invite, now) do
    window_started_at = invite.invite_resend_window_started_at

    cond do
      is_nil(window_started_at) ->
        :ok

      DateTime.diff(now, window_started_at, :second) >= @invite_resend_window_seconds ->
        :ok

      (invite.invite_resend_count || 0) >= @invite_resend_limit_per_day ->
        {:error, :daily_limit_reached}

      true ->
        :ok
    end
  end

  defp invite_resend_tracking_attrs(invite, now) do
    window_started_at = invite.invite_resend_window_started_at

    cond do
      is_nil(window_started_at) or
          DateTime.diff(now, window_started_at, :second) >= @invite_resend_window_seconds ->
        %{
          invite_email_sent_at: now,
          invite_resend_count: 1,
          invite_resend_window_started_at: now
        }

      true ->
        %{
          invite_email_sent_at: now,
          invite_resend_count: (invite.invite_resend_count || 0) + 1,
          invite_resend_window_started_at: window_started_at
        }
    end
  end

  defp find_pending_invite(invite_id, subdomain) do
    from(i in OrgInvite,
      join: o in Comcent.Schemas.Org,
      on: i.org_id == o.id,
      where: i.id == ^invite_id and o.subdomain == ^subdomain and i.status == "PENDING",
      preload: [org: o]
    )
    |> Repo.one()
  end

  defp find_member_with_id(user_id, subdomain) do
    query =
      from(om in OrgMemberSchema,
        join: o in Comcent.Schemas.Org,
        on: om.org_id == o.id,
        join: u in User,
        on: om.user_id == u.id,
        where: o.subdomain == ^subdomain and u.id == ^user_id,
        preload: [:user, :number]
      )

    Repo.one(query)
  end

  defp find_org_id(subdomain) do
    case Comcent.Repo.Org.get_org_by_subdomain(subdomain) do
      nil -> nil
      org -> org.id
    end
  end

  defp get_paginated_members(subdomain, items_per_page, current_page) do
    query =
      from(om in OrgMemberSchema,
        join: o in Comcent.Schemas.Org,
        on: om.org_id == o.id,
        join: u in User,
        on: om.user_id == u.id,
        where: o.subdomain == ^subdomain,
        order_by: [asc: u.email],
        limit: ^items_per_page,
        offset: ^((current_page - 1) * items_per_page),
        preload: [:user, :number]
      )

    Repo.all(query)
  end

  defp get_member_count(subdomain) do
    query =
      from(om in OrgMemberSchema,
        join: o in Comcent.Schemas.Org,
        on: om.org_id == o.id,
        where: o.subdomain == ^subdomain
      )

    Repo.aggregate(query, :count)
  end

  defp parse_items_per_page(value) do
    allowed = [5, 10, 20, 50]
    parsed = String.to_integer(value || "10")
    if parsed in allowed, do: parsed, else: 10
  rescue
    _ -> 10
  end

  defp ceil_div(a, b) when is_integer(a) and is_integer(b) do
    div(a + b - 1, b)
  end

  defp format_errors(changeset) do
    Enum.map(changeset.errors, fn {field, {message, _}} -> "#{field}: #{message}" end)
    |> Enum.join(", ")
  end
end
