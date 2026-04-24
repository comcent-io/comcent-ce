defmodule Comcent.Emails do
  require Logger

  alias Comcent.Mailer
  alias Comcent.Schemas.{OrgInvite, User}

  def send_verification_email(%User{} = user, token) do
    verification_url = verification_url(token)

    html = """
    <html lang="en">
    <head><title>Verify your email</title></head>
    <body>
      <h3>Hello #{user.name},</h3>
      <p>Please verify your email address to finish creating your Comcent account.</p>
      <p><a href="#{verification_url}">Verify email address</a></p>
      <p>If you did not create this account, you can ignore this email.</p>
    </body>
    </html>
    """

    text = """
    Hello #{user.name},

    Please verify your email address to finish creating your Comcent account.

    Verify email address: #{verification_url}

    If you did not create this account, you can ignore this email.
    """

    deliver_email(user.email, "Verify your Comcent email", html, text)
  end

  def send_org_invite_email(%OrgInvite{} = invite, org_name) do
    invitation_url = invitation_url(invite.id)

    html = """
    <html lang="en">
    <head><title>You've been invited to Comcent</title></head>
    <body>
      <h3>Hello,</h3>
      <p>You have been invited to join #{org_name} on Comcent as a #{invite.role}.</p>
      <p><a href="#{invitation_url}">Review invitation</a></p>
      <p>Sign in or create your account with #{invite.email} to accept the invitation.</p>
    </body>
    </html>
    """

    text = """
    Hello,

    You have been invited to join #{org_name} on Comcent as a #{invite.role}.

    Review invitation: #{invitation_url}

    Sign in or create your account with #{invite.email} to accept the invitation.
    """

    deliver_email(invite.email, "Invitation to join #{org_name} on Comcent", html, text)
  end

  def deliver_email(to, subject, html, text) do
    source_email = Application.fetch_env!(:comcent, Comcent.Mailer)[:source_email]

    email =
      Swoosh.Email.new()
      |> Swoosh.Email.to(to)
      |> Swoosh.Email.from(normalize_from(source_email))
      |> Swoosh.Email.subject(subject)
      |> Swoosh.Email.html_body(html)
      |> Swoosh.Email.text_body(text)

    case Mailer.deliver(email) do
      {:ok, result} ->
        {:ok, result}

      {:error, reason} ->
        Logger.error("Failed to send email to #{to}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp verification_url(token) do
    public_root_url = Application.fetch_env!(:comcent, :public_root_url)
    "#{normalize_public_root_url(public_root_url)}/auth/verify-email/#{token}"
  end

  defp invitation_url(invitation_id) do
    public_root_url = Application.fetch_env!(:comcent, :public_root_url)
    "#{normalize_public_root_url(public_root_url)}/invitation/#{invitation_id}"
  end

  defp normalize_from({name, email}), do: {name, email}

  defp normalize_from(email) when is_binary(email) do
    case Regex.run(~r/^\s*(.*?)\s*<([^>]+)>\s*$/, email) do
      [_, name, address] ->
        {String.trim(name), String.trim(address)}

      _ ->
        String.trim(email)
    end
  end

  defp normalize_public_root_url(url) do
    if String.starts_with?(url, "http://") or String.starts_with?(url, "https://") do
      String.trim_trailing(url, "/")
    else
      "https://#{String.trim_trailing(url, "/")}"
    end
  end
end
