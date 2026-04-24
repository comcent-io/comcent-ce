defmodule ComcentWeb.UserController do
  use ComcentWeb, :controller
  import Ecto.Query

  alias Comcent.Repo
  alias Ecto.Multi
  alias Comcent.Schemas.{Country, Org, OrgBillingAddress, OrgInvite, OrgMember, State, User}

  @username_regex ~r/^[a-zA-Z][a-zA-Z0-9._+]*$/
  @trial_max_members 10

  def get_session(conn, _params) do
    current_user = conn.assigns[:current_user]

    json(conn, %{
      user: %{
        id: current_user.id,
        email: current_user.email,
        name: current_user.name,
        picture: current_user.picture,
        has_agreed_to_tos: current_user.has_agreed_to_tos
      }
    })
  end

  def generate_user_token(conn, %{"subdomain" => subdomain} = params) do
    conn = put_public_api_cors_headers(conn)
    email = String.trim(params["email"] || "")

    if email == "" do
      conn |> put_status(:bad_request) |> json(%{error: "Email missing."})
    else
      case Comcent.Repo.OrgMember.get_member_by_email_and_subdomain(email, subdomain) do
        nil ->
          conn |> put_status(:unauthorized) |> json(%{error: "Invalid email."})

        member ->
          sip_domain = Application.fetch_env!(:comcent, :sip_domain)

          claims = %{
            "sub" => member.user.id,
            "name" => member.user.name,
            "email" => member.user.email,
            "picture" => member.user.picture,
            "sipAddress" => "#{member.username}@#{subdomain}.#{sip_domain}",
            "sipUsername" => member.username,
            "subdomain" => subdomain
          }

          token = sign_widget_token(claims)
          json(conn, %{token: token})
      end
    end
  end

  def get_orgs(conn, _params) do
    current_user = conn.assigns[:current_user]

    orgs =
      from(o in Org,
        join: om in OrgMember,
        on: om.org_id == o.id,
        where: om.user_id == ^current_user.id,
        order_by: [asc: o.name],
        select: %{
          id: o.id,
          name: o.name,
          subdomain: o.subdomain
        }
      )
      |> Repo.all()

    invites =
      from(i in OrgInvite,
        join: o in Org,
        on: i.org_id == o.id,
        where: i.email == ^current_user.email and i.status == "PENDING",
        order_by: [asc: o.name],
        select: %{
          id: i.id,
          email: i.email,
          org: %{
            id: o.id,
            name: o.name,
            subdomain: o.subdomain
          }
        }
      )
      |> Repo.all()

    json(conn, %{orgs: orgs, invites: invites})
  end

  def get_org_creation_context(conn, _params) do
    countries =
      Country
      |> order_by([c], asc: c.name)
      |> preload(states: ^from(s in State, order_by: [asc: s.name]))
      |> Repo.all()

    formatted_countries =
      Enum.map(countries, fn country ->
        %{
          code: country.code,
          name: country.name,
          states:
            Enum.map(country.states, fn state ->
              %{
                name: state.name,
                code: state.country_code
              }
            end)
        }
      end)

    country_states_map =
      Map.new(formatted_countries, fn country ->
        {country.code, country.states}
      end)

    json(conn, %{countries: formatted_countries, country_states_map: country_states_map})
  end

  def create_org(conn, params) do
    current_user = conn.assigns[:current_user]

    with :ok <- validate_create_org_params(params),
         {:ok, org} <- insert_org(current_user, params) do
      json(conn, %{success: true, org: %{id: org.id, subdomain: org.subdomain}})
    else
      {:error, message} ->
        conn |> put_status(:bad_request) |> json(%{error: message})
    end
  end

  def get_invitation(conn, %{"id" => id}) do
    current_user = conn.assigns[:current_user]

    case find_invitation(id, current_user.email) do
      nil ->
        conn |> put_status(:not_found) |> json(%{error: "Invalid invitation."})

      invitation ->
        suggested_username =
          current_user.email
          |> suggested_username()
          |> maybe_clear_taken_username(invitation.org.id)

        json(conn, %{
          invitation: %{
            id: invitation.id,
            email: invitation.email,
            role: invitation.role,
            org: %{
              id: invitation.org.id,
              name: invitation.org.name
            }
          },
          suggested_username: suggested_username
        })
    end
  end

  def accept_invitation(conn, %{"id" => id, "username" => username}) do
    current_user = conn.assigns[:current_user]
    trimmed_username = String.trim(username || "")

    with :ok <- validate_username(trimmed_username),
         invitation when not is_nil(invitation) <- find_invitation(id, current_user.email),
         false <- username_taken?(invitation.org.id, trimmed_username),
         {:ok, _result} <-
           accept_invitation_transaction(invitation, current_user, trimmed_username) do
      json(conn, %{success: true})
    else
      nil ->
        conn |> put_status(:bad_request) |> json(%{error: "Invalid invitation."})

      true ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "Username #{trimmed_username} already taken for this org"})

      {:error, message} ->
        conn |> put_status(:bad_request) |> json(%{error: message})

      {:error, _step, changeset, _changes_so_far} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: format_changeset_error(changeset)})
    end
  end

  def accept_terms(conn, _params) do
    current_user = conn.assigns[:current_user]
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    from(u in User, where: u.id == ^current_user.id)
    |> Repo.update_all(set: [has_agreed_to_tos: true, agreed_to_tos_at: now])

    json(conn, %{success: true})
  end

  def options_public_api(conn, _params) do
    conn
    |> put_public_api_cors_headers()
    |> send_resp(204, "")
  end

  defp validate_create_org_params(params) do
    required_fields = [
      {"name", 3},
      {"subdomain", 3},
      {"sip_username", 3},
      {"country", 2},
      {"state", 2},
      {"city", 2},
      {"zip", 2},
      {"user_name", 2}
    ]

    case Enum.find(required_fields, fn {field, min_length} ->
           value = params[field] |> to_string() |> String.trim()
           String.length(value) < min_length
         end) do
      {field, _} ->
        {:error, "#{field} is invalid"}

      nil ->
        validate_username(String.trim(params["sip_username"] || ""))
    end
  end

  defp validate_username(username) do
    cond do
      String.length(username) < 3 or String.length(username) > 20 ->
        {:error, "Username must be 3 or more characters"}

      not String.match?(username, @username_regex) ->
        {:error, "Username is Invalid"}

      true ->
        :ok
    end
  end

  defp insert_org(current_user, params) do
    org_id = Ecto.UUID.generate()
    billing_address_id = Ecto.UUID.generate()

    org_attrs = %{
      "name" => String.trim(params["name"] || ""),
      "subdomain" => String.trim(params["subdomain"] || ""),
      "use_custom_domain" => params["use_custom_domain"] || false,
      "custom_domain" => blank_to_nil(params["custom_domain"]),
      "assign_ext_automatically" => params["assign_ext_automatically"] || false,
      "auto_ext_start" => blank_to_nil(params["auto_ext_start"]),
      "auto_ext_end" => blank_to_nil(params["auto_ext_end"]),
      "max_members" => @trial_max_members
    }

    member_attrs = %{
      "user_id" => current_user.id,
      "org_id" => org_id,
      "role" => "ADMIN",
      "username" => String.trim(params["sip_username"] || ""),
      "sip_password" => random_password(),
      "extension_number" => blank_to_nil(params["user_ext"])
    }

    billing_address_attrs = %{
      "org_id" => org_id,
      "username" => String.trim(params["user_name"] || ""),
      "line_1" => String.trim(params["name"] || ""),
      "city" => String.trim(params["city"] || ""),
      "state" => String.trim(params["state"] || ""),
      "country" => String.trim(params["country"] || ""),
      "postal_code" => String.trim(params["zip"] || "")
    }

    Multi.new()
    |> Multi.insert(:org, Org.changeset(%Org{id: org_id}, org_attrs))
    |> Multi.insert(:member, OrgMember.changeset(%OrgMember{}, member_attrs))
    |> Multi.insert(
      :billing_address,
      OrgBillingAddress.changeset(
        %OrgBillingAddress{id: billing_address_id},
        billing_address_attrs
      )
    )
    |> Repo.transaction()
    |> case do
      {:ok, %{org: org}} ->
        {:ok, org}

      {:error, _step, changeset, _changes_so_far} ->
        {:error, format_changeset_error(changeset)}
    end
  end

  defp put_public_api_cors_headers(conn) do
    conn
    |> put_resp_header("access-control-allow-origin", "*")
    |> put_resp_header("access-control-allow-methods", "GET, OPTIONS")
    |> put_resp_header("access-control-allow-headers", "Content-Type, Authorization, X-API-KEY")
  end

  defp find_invitation(id, email) do
    from(i in OrgInvite,
      join: o in Org,
      on: i.org_id == o.id,
      where: i.id == ^id and i.email == ^email and i.status == "PENDING",
      select: %{
        id: i.id,
        email: i.email,
        role: i.role,
        org: %{
          id: o.id,
          name: o.name
        }
      }
    )
    |> Repo.one()
  end

  defp sign_widget_token(claims) do
    signing_key = System.get_env("SIGNING_KEY")
    jwk = JOSE.JWK.from_oct(signing_key)

    {_, token} =
      jwk
      |> JOSE.JWT.sign(
        %{"alg" => "HS256"},
        Map.put(claims, "exp", System.os_time(:second) + 86_400)
      )
      |> JOSE.JWS.compact()

    token
  end

  defp suggested_username(email) do
    email
    |> String.split("@")
    |> List.first()
    |> Kernel.||("")
  end

  defp maybe_clear_taken_username(username, org_id) do
    if username == "" or username_taken?(org_id, username) do
      ""
    else
      username
    end
  end

  defp username_taken?(org_id, username) do
    from(om in OrgMember,
      where: om.org_id == ^org_id and om.username == ^username,
      select: om.user_id
    )
    |> Repo.exists?()
  end

  defp accept_invitation_transaction(invitation, current_user, username) do
    member_attrs = %{
      "user_id" => current_user.id,
      "org_id" => invitation.org.id,
      "role" => invitation.role,
      "username" => username,
      "sip_password" => random_password()
    }

    Multi.new()
    |> Multi.insert(:member, OrgMember.changeset(%OrgMember{}, member_attrs))
    |> Multi.update_all(
      :invite,
      from(i in OrgInvite, where: i.id == ^invitation.id),
      set: [status: "ACCEPTED"]
    )
    |> Repo.transaction()
  end

  defp random_password do
    :crypto.strong_rand_bytes(16) |> Base.url_encode64(padding: false)
  end

  defp blank_to_nil(nil), do: nil

  defp blank_to_nil(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp blank_to_nil(value), do: value

  defp format_changeset_error(changeset) do
    case changeset.errors do
      [{field, {message, _opts}} | _rest] ->
        "#{field} #{message}"

      _ ->
        "Request failed"
    end
  end
end
