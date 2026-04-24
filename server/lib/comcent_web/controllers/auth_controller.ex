defmodule ComcentWeb.AuthController do
  use ComcentWeb, :controller
  import Ecto.Query

  alias Comcent.Auth
  alias Comcent.Auth.Oidc
  alias Comcent.Auth.Password
  alias Comcent.Auth.ProviderConfig
  alias Comcent.Emails
  alias Comcent.Repo
  alias Comcent.Schemas.{User, UserIdentity}

  @verification_resend_cooldown_seconds 60
  @verification_resend_limit_per_day 3
  @verification_resend_window_seconds 24 * 60 * 60

  def config(conn, _params) do
    json(conn, %{
      password_enabled: ProviderConfig.password_enabled?(),
      oauth_providers: ProviderConfig.public_provider_configs()
    })
  end

  def register(conn, params) do
    if ProviderConfig.password_enabled?() do
      with :ok <- validate_registration(params),
           {:ok, _user} <- create_password_user(params) do
        json(conn, %{message: "Check your email to verify your account before signing in."})
      else
        {:error, message} ->
          conn |> put_status(:bad_request) |> json(%{error: message})
      end
    else
      conn |> put_status(:not_found) |> json(%{error: "Password authentication is disabled"})
    end
  end

  def login(conn, %{"email" => email, "password" => password}) do
    trimmed_email = normalize_email(email)

    case Repo.get_by(User, email: trimmed_email) do
      %User{} = user ->
        if Password.verify(password, user.password_hash) do
          if user.is_email_verified do
            token = Auth.sign_session_token(user, "password")
            json(conn, %{token: token, user: session_user(user, "password")})
          else
            conn
            |> put_status(:forbidden)
            |> json(%{
              error: "Email is not verified. Please check your inbox for the verification link."
            })
          end
        else
          conn |> put_status(:unauthorized) |> json(%{error: "Invalid email or password"})
        end

      _ ->
        conn |> put_status(:unauthorized) |> json(%{error: "Invalid email or password"})
    end
  end

  def login(conn, _params) do
    conn |> put_status(:bad_request) |> json(%{error: "Email and password are required"})
  end

  def oauth_start(conn, %{"provider" => provider, "redirect_uri" => redirect_uri}) do
    case Oidc.build_authorize_url(provider, redirect_uri) do
      {:ok, auth_url} ->
        json(conn, %{auth_url: auth_url})

      {:error, :provider_not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "OAuth provider not found"})

      {:error, reason} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "Unable to start OAuth login: #{inspect(reason)}"})
    end
  end

  def oauth_callback(
        conn,
        %{
          "provider" => provider,
          "code" => code,
          "state" => state,
          "redirect_uri" => redirect_uri
        }
      ) do
    with {:ok, oauth_user} <- Oidc.exchange_code_for_user(provider, code, state, redirect_uri),
         {:ok, user} <- find_or_create_oauth_user(oauth_user) do
      token = Auth.sign_session_token(user, provider)
      json(conn, %{token: token, user: session_user(user, provider)})
    else
      {:error, :provider_not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "OAuth provider not found"})

      {:error, reason} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "OAuth login failed: #{inspect(reason)}"})
    end
  end

  def oauth_callback(conn, _params) do
    conn |> put_status(:bad_request) |> json(%{error: "Missing OAuth callback parameters"})
  end

  def verify_email(conn, %{"token" => token}) do
    with {:ok, claims} <- Auth.verify_any_token(token),
         :ok <- validate_email_verification_claims(claims),
         {:ok, user} <- mark_user_email_verified(claims) do
      session_token = Auth.sign_session_token(user, "password")
      json(conn, %{token: session_token, user: session_user(user, "password")})
    else
      {:error, :token_expired} ->
        conn |> put_status(:bad_request) |> json(%{error: "Verification link has expired."})

      {:error, :invalid_token} ->
        conn |> put_status(:bad_request) |> json(%{error: "Verification link is invalid."})

      {:error, :user_not_found} ->
        conn |> put_status(:bad_request) |> json(%{error: "Verification link is invalid."})

      {:error, message} when is_binary(message) ->
        conn |> put_status(:bad_request) |> json(%{error: message})

      _ ->
        conn |> put_status(:bad_request) |> json(%{error: "Verification link is invalid."})
    end
  end

  def verify_email(conn, _params) do
    conn |> put_status(:bad_request) |> json(%{error: "Verification token is required"})
  end

  def resend_verification(conn, %{"email" => email}) do
    if ProviderConfig.password_enabled?() do
      normalized_email = normalize_email(email)

      response =
        case Repo.get_by(User, email: normalized_email) do
          %User{} = user when not user.is_email_verified and is_binary(user.password_hash) ->
            resend_verification_email(user)

          _ ->
            {:ok, generic_resend_response()}
        end

      case response do
        {:ok, payload} ->
          json(conn, payload)

        {:error, :cooldown_active, retry_after_seconds} ->
          conn
          |> put_status(:too_many_requests)
          |> json(%{
            error:
              "Please wait #{retry_after_seconds} seconds before requesting another verification email.",
            retry_after_seconds: retry_after_seconds
          })

        {:error, :daily_limit_reached} ->
          conn
          |> put_status(:too_many_requests)
          |> json(%{
            error:
              "You can request up to #{@verification_resend_limit_per_day} verification emails per day."
          })

        {:error, _reason} ->
          conn
          |> put_status(:bad_request)
          |> json(%{error: "Unable to send verification email. Please try again."})
      end
    else
      conn |> put_status(:not_found) |> json(%{error: "Password authentication is disabled"})
    end
  end

  def resend_verification(conn, _params) do
    conn |> put_status(:bad_request) |> json(%{error: "Email is required"})
  end

  defp validate_registration(params) do
    email = normalize_email(params["email"])
    password = String.trim(params["password"] || "")
    name = String.trim(params["name"] || "")

    cond do
      name == "" -> {:error, "Name is required"}
      email == "" -> {:error, "Email is required"}
      password == "" -> {:error, "Password is required"}
      String.length(password) < 8 -> {:error, "Password must be at least 8 characters"}
      Repo.exists?(from(u in User, where: u.email == ^email)) -> {:error, "Email already exists"}
      true -> :ok
    end
  end

  defp create_password_user(params) do
    Repo.transaction(fn ->
      user =
        %User{id: Ecto.UUID.generate()}
        |> User.changeset(%{
          email: normalize_email(params["email"]),
          name: String.trim(params["name"] || ""),
          password_hash: Password.hash(params["password"]),
          is_email_verified: false,
          verification_email_sent_at: DateTime.utc_now(),
          verification_resend_count: 0
        })
        |> Repo.insert!()

      case send_verification_email(user) do
        :ok -> user
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
    |> case do
      {:ok, user} -> {:ok, user}
      {:error, _reason} -> {:error, "Unable to send verification email. Please try again."}
    end
  end

  defp send_verification_email(user) do
    user
    |> Auth.sign_email_verification_token()
    |> then(&Emails.send_verification_email(user, &1))
    |> case do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp resend_verification_email(user) do
    now = DateTime.utc_now()

    Repo.transaction(fn ->
      user = Repo.get!(User, user.id)

      with :ok <- ensure_resend_cooldown_elapsed(user, now),
           :ok <- ensure_daily_resend_limit_not_reached(user, now) do
        updated_user =
          user
          |> User.changeset(resend_tracking_attrs(user, now))
          |> Repo.update!()

        case send_verification_email(updated_user) do
          :ok -> generic_resend_response()
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

  defp ensure_resend_cooldown_elapsed(%User{verification_email_sent_at: nil}, _now), do: :ok

  defp ensure_resend_cooldown_elapsed(%User{verification_email_sent_at: sent_at}, now) do
    elapsed_seconds = DateTime.diff(now, sent_at, :second)

    if elapsed_seconds >= @verification_resend_cooldown_seconds do
      :ok
    else
      {:error, :cooldown_active, @verification_resend_cooldown_seconds - elapsed_seconds}
    end
  end

  defp ensure_daily_resend_limit_not_reached(user, now) do
    window_started_at = user.verification_resend_window_started_at

    cond do
      is_nil(window_started_at) ->
        :ok

      DateTime.diff(now, window_started_at, :second) >= @verification_resend_window_seconds ->
        :ok

      (user.verification_resend_count || 0) >= @verification_resend_limit_per_day ->
        {:error, :daily_limit_reached}

      true ->
        :ok
    end
  end

  defp resend_tracking_attrs(user, now) do
    window_started_at = user.verification_resend_window_started_at

    cond do
      is_nil(window_started_at) or
          DateTime.diff(now, window_started_at, :second) >= @verification_resend_window_seconds ->
        %{
          verification_email_sent_at: now,
          verification_resend_count: 1,
          verification_resend_window_started_at: now
        }

      true ->
        %{
          verification_email_sent_at: now,
          verification_resend_count: (user.verification_resend_count || 0) + 1,
          verification_resend_window_started_at: window_started_at
        }
    end
  end

  defp generic_resend_response do
    %{
      message: "If an account exists for that email, a verification email has been sent.",
      retry_after_seconds: @verification_resend_cooldown_seconds
    }
  end

  defp validate_email_verification_claims(%{"token_type" => "email_verification"}), do: :ok
  defp validate_email_verification_claims(_claims), do: {:error, :invalid_token}

  defp mark_user_email_verified(%{"sub" => user_id, "email" => email}) do
    normalized_email = normalize_email(email)

    case Repo.get(User, user_id) do
      %User{} = user ->
        if normalize_email(user.email) != normalized_email do
          {:error, :invalid_token}
        else
          user
          |> User.changeset(%{
            is_email_verified: true,
            verification_email_sent_at: nil,
            verification_resend_count: 0,
            verification_resend_window_started_at: nil
          })
          |> Repo.update()
        end

      nil ->
        {:error, :user_not_found}
    end
  end

  defp mark_user_email_verified(_claims), do: {:error, :invalid_token}

  defp find_or_create_oauth_user(oauth_user) do
    if normalize_email(oauth_user.email) == "" do
      {:error, :missing_email}
    else
      Repo.transaction(fn ->
        case Repo.get_by(UserIdentity,
               provider: oauth_user.provider,
               provider_user_id: oauth_user.provider_user_id
             )
             |> maybe_preload_user() do
          %UserIdentity{user: %User{} = user} = identity ->
            updated_user = update_user_from_oauth(user, oauth_user)
            update_identity(identity, oauth_user)
            updated_user

          nil ->
            user =
              Repo.get_by(User, email: normalize_email(oauth_user.email))
              |> case do
                nil -> insert_oauth_user(oauth_user)
                %User{} = existing_user -> update_user_from_oauth(existing_user, oauth_user)
              end

            insert_identity(user, oauth_user)
            user
        end
      end)
      |> case do
        {:ok, user} -> {:ok, user}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  defp maybe_preload_user(nil), do: nil
  defp maybe_preload_user(identity), do: Repo.preload(identity, :user)

  defp insert_oauth_user(oauth_user) do
    %User{id: Ecto.UUID.generate()}
    |> User.changeset(%{
      email: normalize_email(oauth_user.email),
      name: oauth_user.name,
      picture: oauth_user.picture,
      is_email_verified: oauth_user.email_verified
    })
    |> Repo.insert!()
  end

  defp update_user_from_oauth(user, oauth_user) do
    user
    |> User.changeset(%{
      name: oauth_user.name || user.name,
      picture: oauth_user.picture || user.picture,
      is_email_verified: oauth_user.email_verified || user.is_email_verified
    })
    |> Repo.update!()
  end

  defp insert_identity(user, oauth_user) do
    %UserIdentity{id: Ecto.UUID.generate()}
    |> UserIdentity.changeset(%{
      user_id: user.id,
      provider: oauth_user.provider,
      provider_user_id: oauth_user.provider_user_id,
      email: normalize_email(oauth_user.email),
      name: oauth_user.name,
      picture: oauth_user.picture
    })
    |> Repo.insert!()
  end

  defp update_identity(identity, oauth_user) do
    identity
    |> UserIdentity.changeset(%{
      email: normalize_email(oauth_user.email),
      name: oauth_user.name,
      picture: oauth_user.picture
    })
    |> Repo.update!()
  end

  defp session_user(user, auth_provider) do
    %{
      id: user.id,
      email: user.email,
      name: user.name,
      picture: user.picture,
      auth_provider: auth_provider
    }
  end

  defp normalize_email(email) when is_binary(email) do
    email |> String.trim() |> String.downcase()
  end

  defp normalize_email(_email), do: ""
end
