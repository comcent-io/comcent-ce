defmodule Comcent.EmailHandler do
  require Logger
  import Ecto.Query
  alias Comcent.Emails
  alias Comcent.Repo
  alias Comcent.Schemas.{Org, OrgMember, User}

  @doc """
  Check for organizations with wallet balances below their alert threshold
  and send email notifications to admin users.
  Sends alerts at most 3 times at 9am after threshold breach, resets if balance recovers.
  """
  def check_and_send_alerts do
    Logger.info("Running wallet balance check")

    # Get organizations with active subscriptions and wallet balances below threshold
    orgs_query =
      from(o in Org,
        where: o.wallet_balance < o.alert_threshold_balance and o.alert_threshold_balance > 0,
        select: %{
          id: o.id,
          name: o.name,
          alert_threshold_balance: o.alert_threshold_balance,
          low_balance_alert_triggered_at: o.low_balance_alert_triggered_at,
          low_balance_alert_count: o.low_balance_alert_count
        }
      )

    orgs = Repo.all(orgs_query)

    for org <- orgs do
      # Check if we should send an alert
      should_send_alert = should_send_alert?(org)

      if should_send_alert do
        Logger.info("Sending emails to admins of Org: #{org.name}")

        # Get admin users for the organization
        admins_query =
          from(m in OrgMember,
            join: u in User,
            on: u.id == m.user_id,
            where: m.org_id == ^org.id,
            where: m.role == :ADMIN,
            select: %{username: m.username, email: u.email}
          )

        admins = Repo.all(admins_query)

        for admin <- admins do
          send_email(
            org.name,
            admin.email,
            admin.username,
            org.alert_threshold_balance,
            "Low wallet balance"
          )
        end

        # Update alert tracking
        update_alert_tracking(org)
      else
        Logger.info(
          "Skipping alert for Org: #{org.name} - alert count limit reached or not triggered yet"
        )
      end
    end

    # Reset alert tracking for orgs that have recovered
    reset_recovered_orgs()

    :ok
  end

  defp should_send_alert?(org) do
    is_nil(org.low_balance_alert_triggered_at) or org.low_balance_alert_count < 3
  end

  defp update_alert_tracking(org) do
    now = DateTime.utc_now()

    update_query =
      from(o in Org,
        where: o.id == ^org.id,
        update: [
          set: [low_balance_alert_triggered_at: ^now],
          inc: [low_balance_alert_count: 1]
        ]
      )

    case Repo.update_all(update_query, []) do
      {1, _} ->
        Logger.info(
          "Updated alert tracking for Org: #{org.name}, count: #{org.low_balance_alert_count}"
        )

      {0, _} ->
        Logger.warning("Failed to update alert tracking for Org: #{org.name}")

      _ ->
        Logger.error("Unexpected result updating alert tracking for Org: #{org.name}")
    end
  end

  defp reset_recovered_orgs do
    # Find orgs that have recovered (balance above threshold) and reset their alert tracking
    reset_query =
      from(o in Org,
        where:
          o.wallet_balance >= o.alert_threshold_balance and
            (not is_nil(o.low_balance_alert_triggered_at) or o.low_balance_alert_count > 0),
        update: [
          set: [
            low_balance_alert_triggered_at: nil,
            low_balance_alert_count: 0
          ]
        ]
      )

    case Repo.update_all(reset_query, []) do
      {count, _} when count > 0 ->
        Logger.info("Reset alert tracking for #{count} recovered organizations")

      {0, _} ->
        Logger.info("No organizations needed alert tracking reset")

      _ ->
        Logger.error("Unexpected result resetting alert tracking")
    end
  end

  defp send_email(org_name, user_email, user_name, alert_threshold_balance, subject) do
    Logger.info("Sending email to #{user_email} of org: #{org_name} with subject #{subject}")

    {html, text} =
      low_balance_alert_mail_template(
        org_name,
        user_name,
        alert_threshold_balance
      )

    case Emails.deliver_email(user_email, subject, html, text) do
      {:ok, _} ->
        Logger.info("Email sent successfully to #{user_email}")
        :ok

      {:error, reason} ->
        Logger.error("Failed to send email to #{user_email}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp low_balance_alert_mail_template(org_name, user_name, alert_threshold_balance) do
    threshold_in_dollars =
      Comcent.Money.convert_wallet_balance_to_dollars(alert_threshold_balance)

    app_base_url = Application.fetch_env!(:comcent, :app_base_url)

    html = """
    <html lang="en">
    <head><title>Low wallet balance alert</title></head>
    <body>
      <h3>Hello #{user_name},</h3>
      <p>Your organization <b>#{org_name}</b>'s wallet balance is below USD #{threshold_in_dollars}.</p>
      <p><a href="#{app_base_url}" data-click-track="off">Click here to top up your wallet</a></p>
      <p>Thanks</p>
    </body>
    </html>
    """

    text = """
    Hello #{user_name},

    Your wallet balance is below #{alert_threshold_balance}$.

    Click here to top up your wallet: #{app_base_url}

    Thanks
    """

    {html, text}
  end
end
