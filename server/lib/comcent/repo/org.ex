defmodule Comcent.Repo.Org do
  import Ecto.Query
  import Ecto.Query
  alias Comcent.Repo
  alias Comcent.Schemas.{Org, OrgAuditLog}
  alias Comcent.Money
  require Logger

  def get_org_by_subdomain(subdomain) do
    Repo.one(from(o in Org, where: o.subdomain == ^subdomain, select: o))
  end

  def get_org_settings(subdomain) do
    Repo.one(
      from(o in Org,
        where: o.subdomain == ^subdomain,
        select: %{
          id: o.id,
          name: o.name,
          subdomain: o.subdomain,
          enable_transcription: o.enable_transcription,
          enable_sentiment_analysis: o.enable_sentiment_analysis,
          enable_call_recording: o.enable_call_recording,
          enable_summary: o.enable_summary,
          max_members: o.max_members,
          alert_threshold_balance: o.alert_threshold_balance,
          is_active: o.is_active,
          wallet_balance: o.wallet_balance
        }
      )
    )
  end

  def charge_org_wallet_by_org_id(org_id, price, type, call_story_id, quantity, cost) do
    price = Money.convert_dollars_to_wallet_balance(price)
    cost = Money.convert_dollars_to_wallet_balance(cost)
    audit_log_type = if is_binary(type), do: String.to_existing_atom(type), else: type

    try do
      Repo.transaction(fn ->
        # Update wallet balance
        from(o in Org,
          where: o.id == ^org_id,
          update: [set: [wallet_balance: o.wallet_balance - ^price]]
        )
        |> Repo.update_all([])

        # Create audit log
        %OrgAuditLog{
          id: Ecto.UUID.generate(),
          org_id: org_id,
          type: audit_log_type,
          quantity: quantity * 1.0,
          call_story_id: call_story_id,
          price: price,
          cost: cost
        }
        |> Repo.insert!()
      end)

      :ok
    rescue
      error ->
        Logger.error("Failed to charge org wallet: #{inspect(error)}")
        :error
    end
  end

  @doc """
  Gets all organizations that have daily summary enabled and have valid time/timezone settings.
  """
  def get_orgs_with_daily_summary_enabled do
    Repo.all(
      from(o in Org,
        where: o.enable_daily_summary == true,
        where: not is_nil(o.daily_summary_time),
        where: not is_nil(o.daily_summary_time_zone),
        where: o.daily_summary_time != "",
        select: %{
          id: o.id,
          subdomain: o.subdomain,
          daily_summary_time: o.daily_summary_time,
          daily_summary_time_zone: o.daily_summary_time_zone
        }
      )
    )
  end
end
