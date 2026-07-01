defmodule Comcent.InstanceSetup do
  @moduledoc """
  First-run instance bootstrap. On a fresh CE install, the operator needs a
  way to claim the instance as super-admin without exposing open signup to
  the public internet. This module generates a one-time setup token on first
  boot, prints it to the server logs, and lets the operator consume it by
  POSTing to `/api/v2/auth/claim-setup`. Once claimed, the install is locked
  to invite-only (with an optional domain allowlist) — see
  `Comcent.Auth.ProviderConfig.allowed_signup_domains/0`.
  """

  require Logger
  import Ecto.Query

  alias Comcent.Auth.Password
  alias Comcent.Repo
  alias Comcent.Schemas.{InstanceSetup, Org, OrgMember, User}
  alias Ecto.Multi

  @singleton_id 1
  @trial_max_members 10

  @doc """
  Returns true when no super-admin exists yet — i.e. the instance still
  needs to be claimed.
  """
  def bootstrap_mode? do
    not Repo.exists?(from(u in User, where: u.is_super_admin == true))
  end

  @doc """
  Called from `Comcent.Application.start/2` after the Repo is up. If the
  instance still needs a super-admin, ensure a setup-token row exists and
  print the claim banner to the logs.
  """
  def ensure_token! do
    if bootstrap_mode?() do
      row = ensure_row!()
      log_banner(row.token)
    else
      :ok
    end
  end

  @doc """
  Atomically claim the instance. Creates the super-admin user, the org, and
  the OrgMember ADMIN row, then marks the token consumed.
  """
  def claim(name, email, password, %{
        org_name: org_name,
        subdomain: subdomain,
        sip_username: sip_username,
        token: token
      }) do
    with :ok <- validate_inputs(name, email, password, org_name, subdomain, sip_username, token),
         {:ok, %{user: user}} <- run_claim_transaction(name, email, password, org_name, subdomain, sip_username, token) do
      {:ok, user}
    else
      {:error, _step, %Ecto.Changeset{} = changeset, _changes} ->
        {:error, format_changeset_error(changeset)}

      {:error, reason} when is_atom(reason) or is_binary(reason) ->
        {:error, reason}
    end
  end

  @doc """
  Regenerate the token. When `force?` is true, also clears `consumed_at`
  and `consumed_by_user_id`. Used by `mix comcent.reset_setup_token`.
  """
  def regenerate_token!(force? \\ false) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    new_token = generate_token()

    row = ensure_row!()

    cond do
      not is_nil(row.consumed_at) and not force? ->
        {:error, :already_consumed}

      true ->
        attrs = %{
          token: new_token,
          generated_at: now,
          consumed_at: if(force?, do: nil, else: row.consumed_at),
          consumed_by_user_id: if(force?, do: nil, else: row.consumed_by_user_id)
        }

        row
        |> InstanceSetup.changeset(attrs)
        |> Repo.update!()

        {:ok, new_token}
    end
  end

  # ---------------------------------------------------------------------------

  defp ensure_row! do
    case Repo.get(InstanceSetup, @singleton_id) do
      nil ->
        %InstanceSetup{}
        |> InstanceSetup.changeset(%{
          id: @singleton_id,
          token: generate_token(),
          generated_at: DateTime.utc_now() |> DateTime.truncate(:second)
        })
        |> Repo.insert!()

      %InstanceSetup{token: nil} = row ->
        row
        |> InstanceSetup.changeset(%{
          token: generate_token(),
          generated_at: DateTime.utc_now() |> DateTime.truncate(:second)
        })
        |> Repo.update!()

      row ->
        row
    end
  end

  defp generate_token do
    :crypto.strong_rand_bytes(24) |> Base.url_encode64(padding: false)
  end

  defp log_banner(token) do
    public_url = Application.get_env(:comcent, :public_root_url, "<your public URL>")

    Logger.info("""

    ╔══════════════════════════════════════════════════════════════════════╗
    ║  COMCENT FIRST-RUN SETUP                                             ║
    ║                                                                      ║
    ║  This instance has no super-admin yet. Claim it by visiting:         ║
    ║    #{String.pad_trailing(public_url <> "/setup", 66)}║
    ║                                                                      ║
    ║  Setup token (one-time use — do NOT share):                          ║
    ║    #{String.pad_trailing(token, 66)}║
    ║                                                                      ║
    ║  This banner will reappear on every restart until claimed. Lost the  ║
    ║  token? Run:  mix comcent.reset_setup_token  (or --force after       ║
    ║  consumption).                                                       ║
    ╚══════════════════════════════════════════════════════════════════════╝
    """)
  end

  defp validate_inputs(name, email, password, org_name, subdomain, sip_username, token) do
    cond do
      blank?(name) -> {:error, "Name is required"}
      blank?(email) -> {:error, "Email is required"}
      blank?(password) or String.length(password) < 8 ->
        {:error, "Password must be at least 8 characters"}
      blank?(org_name) -> {:error, "Organization name is required"}
      blank?(subdomain) -> {:error, "Subdomain is required"}
      blank?(sip_username) -> {:error, "SIP username is required"}
      blank?(token) -> {:error, "Setup token is required"}
      true -> :ok
    end
  end

  defp run_claim_transaction(name, email, password, org_name, subdomain, sip_username, token) do
    user_id = Ecto.UUID.generate()
    org_id = Ecto.UUID.generate()
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    normalized_email = email |> String.trim() |> String.downcase()

    Multi.new()
    |> Multi.run(:setup_row, fn repo, _ ->
      case repo.get(InstanceSetup, @singleton_id) do
        nil -> {:error, "Setup token is not configured. Restart the server."}
        %InstanceSetup{consumed_at: %DateTime{}} -> {:error, "This instance has already been claimed."}
        %InstanceSetup{token: stored} = row when stored == token -> {:ok, row}
        _ -> {:error, "Invalid setup token."}
      end
    end)
    |> Multi.run(:no_super_admin, fn repo, _ ->
      if repo.exists?(from(u in User, where: u.is_super_admin == true)) do
        {:error, "This instance has already been claimed."}
      else
        {:ok, :ok}
      end
    end)
    |> Multi.run(:email_unique, fn repo, _ ->
      if repo.exists?(from(u in User, where: u.email == ^normalized_email)) do
        {:error, "Email already exists"}
      else
        {:ok, :ok}
      end
    end)
    |> Multi.insert(:user,
      User.changeset(%User{id: user_id}, %{
        name: String.trim(name),
        email: normalized_email,
        password_hash: Password.hash(password),
        is_email_verified: true,
        is_super_admin: true
      })
    )
    |> Multi.insert(:org,
      Org.changeset(%Org{id: org_id}, %{
        name: String.trim(org_name),
        subdomain: String.trim(subdomain),
        use_custom_domain: false,
        assign_ext_automatically: false,
        max_members: @trial_max_members
      })
    )
    |> Multi.insert(:member,
      OrgMember.changeset(%OrgMember{}, %{
        user_id: user_id,
        org_id: org_id,
        role: "ADMIN",
        username: String.trim(sip_username),
        sip_password: :crypto.strong_rand_bytes(16) |> Base.url_encode64(padding: false)
      })
    )
    |> Multi.update(:consume_token, fn %{setup_row: row, user: user} ->
      InstanceSetup.changeset(row, %{
        consumed_at: now,
        consumed_by_user_id: user.id
      })
    end)
    |> Repo.transaction()
  end

  defp blank?(nil), do: true
  defp blank?(value) when is_binary(value), do: String.trim(value) == ""
  defp blank?(_), do: true

  defp format_changeset_error(changeset) do
    case changeset.errors do
      [{field, {message, _opts}} | _rest] -> "#{field} #{message}"
      _ -> "Setup failed"
    end
  end
end
