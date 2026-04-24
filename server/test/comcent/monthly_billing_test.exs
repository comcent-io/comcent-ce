defmodule Comcent.MonthlyBillingTest do
  use Comcent.DataCase
  import Mock

  alias Comcent.MonthlyBilling

  describe "process_monthly_billing/0" do
    test "completes successfully with no organizations" do
      # Mock the get_all_organizations function to return an empty list
      with_mock(Comcent.MonthlyBilling, [:passthrough], get_all_organizations: fn -> [] end) do
        assert :ok = MonthlyBilling.process_monthly_billing()
      end
    end

    test "processes each organization individually" do
      # Mock the organizations and the process_organization function
      test_orgs = [
        %{id: "1", subdomain: "org1", storageUsed: 1024, maxMonthlyStorageUsed: 512},
        %{id: "2", subdomain: "org2", storageUsed: 2048, maxMonthlyStorageUsed: 1024}
      ]

      # Create a counter to track calls
      process_org_calls = :ets.new(:process_org_calls, [:set, :public])
      :ets.insert(process_org_calls, {:count, 0})
      :ets.insert(process_org_calls, {:orgs, []})

      with_mock(Comcent.MonthlyBilling, [:passthrough],
        get_all_organizations: fn -> test_orgs end,
        process_organization: fn org ->
          # Track that this was called with this org
          count = :ets.lookup_element(process_org_calls, :count, 2)
          orgs = :ets.lookup_element(process_org_calls, :orgs, 2)
          :ets.insert(process_org_calls, {:count, count + 1})
          :ets.insert(process_org_calls, {:orgs, [org | orgs]})
          :ok
        end
      ) do
        assert :ok = MonthlyBilling.process_monthly_billing()

        # Verify each organization was processed
        processed_count = :ets.lookup_element(process_org_calls, :count, 2)
        processed_orgs = :ets.lookup_element(process_org_calls, :orgs, 2)

        assert processed_count == 2
        assert length(processed_orgs) == 2

        # Verify each org was processed
        Enum.each(test_orgs, fn test_org ->
          assert Enum.any?(processed_orgs, fn processed_org ->
                   processed_org.id == test_org.id &&
                     processed_org.subdomain == test_org.subdomain
                 end)
        end)
      end

      :ets.delete(process_org_calls)
    end
  end

  describe "process_organization/1" do
    test "calls update_wallet_balance and update_storage_used_per_month in a transaction" do
      org =
        Repo.insert!(%Comcent.Schemas.Org{
          id: "1",
          name: "Org 1",
          subdomain: "org1",
          use_custom_domain: false,
          assign_ext_automatically: false,
          is_active: true,
          enable_transcription: true,
          enable_sentiment_analysis: true,
          enable_summary: true,
          enable_labels: true,
          enable_call_recording: true,
          enable_daily_summary: true,
          wallet_balance: 1_000,
          storage_used: 1024,
          max_monthly_storage_used: 512
        })

      with_mock(Comcent.Repo, [:passthrough],
        transaction: fn fun ->
          Process.put(:in_transaction, true)
          result = fun.()
          Process.put(:in_transaction, false)
          result
        end
      ) do
        assert :ok = MonthlyBilling.process_organization(org)

        updated_org = Repo.get!(Comcent.Schemas.Org, org.id)

        assert updated_org.max_monthly_storage_used == org.storage_used
        assert updated_org.wallet_balance < org.wallet_balance
        assert Process.get(:in_transaction) == false
      end
    end
  end
end
