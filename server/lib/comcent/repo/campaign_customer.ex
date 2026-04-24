defmodule Comcent.Repo.CampaignCustomer do
  import Ecto.Query

  alias Comcent.Repo
  alias Comcent.Repo.Campaign, as: CampaignRepo
  alias Comcent.Schemas.{Campaign, CampaignCustomer, CampaignGroup, Org}

  @doc """
  Fetch a single campaign customer by ID scoped to an org subdomain.
  Validates that the campaign customer belongs to a campaign in a campaign group
  that belongs to the organization identified by the subdomain.
  """
  def get_campaign_customer_by_id(campaign_customer_id, subdomain) do
    from(cc in CampaignCustomer,
      join: c in Campaign,
      on: cc.campaign_id == c.id,
      join: cg in CampaignGroup,
      on: c.campaign_group_id == cg.id,
      join: o in Org,
      on: cg.org_id == o.id,
      where: cc.id == ^campaign_customer_id and o.subdomain == ^subdomain
    )
    |> Repo.one()
  end

  @doc """
  Get a campaign customer to call for a given campaign, subdomain, and member ID.
  """
  def get_campaign_customer_to_call(campaign_id, subdomain, member_id) do
    now = DateTime.utc_now()

    # Update expired DISPLAYED_TO_AGENT records
    from(cc in CampaignCustomer,
      where:
        cc.campaign_id == ^campaign_id and
          cc.call_progress_status == "DISPLAYED_TO_AGENT" and
          not is_nil(cc.expiry_date) and
          cc.expiry_date <= ^now,
      update: [
        set: [
          call_progress_status: "NOT_SCHEDULED",
          expiry_date: nil,
          member_id: ""
        ]
      ]
    )
    |> Repo.update_all([])

    # Check for existing customer already displayed to agent
    existing_customer =
      from(cc in CampaignCustomer,
        where:
          cc.campaign_id == ^campaign_id and
            cc.call_progress_status == "DISPLAYED_TO_AGENT" and
            cc.member_id == ^member_id
      )
      |> Repo.one()

    if existing_customer do
      existing_customer
    else
      # Get campaign and filters
      campaign = CampaignRepo.get_campaign_by_id(campaign_id, subdomain)

      if is_nil(campaign) or is_nil(campaign.filters) do
        nil
      else
        filters = campaign.filters

        # Filter to only include first_name, last_name, phone_number, or attributes.* fields
        updated_filters =
          if is_list(filters) do
            Enum.filter(filters, fn filter ->
              first_operand =
                Map.get(filter, "first_operand") || Map.get(filter, :first_operand)

              first_operand in ["first_name", "last_name", "phone_number"] or
                (is_binary(first_operand) and String.starts_with?(first_operand, "attributes"))
            end)
          else
            []
          end

        # Build filter conditions
        filter_conditions = build_filter_conditions(updated_filters)

        # Find campaign customer to call
        base_query =
          from(cc in CampaignCustomer,
            where:
              cc.campaign_id == ^campaign_id and
                cc.disposition != "COMPLETED" and
                cc.call_progress_status not in ["CALL_IN_PROGESS", "COMPLETED"] and
                ((cc.disposition == "SCHEDULED" and not is_nil(cc.scheduled_date) and
                    cc.scheduled_date <= ^now) or
                   cc.call_progress_status != "DISPLAYED_TO_AGENT")
          )

        # Apply filter conditions
        query_with_filters =
          Enum.reduce(filter_conditions, base_query, fn condition, acc ->
            where(acc, ^condition)
          end)

        query_with_filters
        |> order_by([cc], asc: cc.created_at, asc: cc.id)
        |> limit(1)
        |> Repo.one()
      end
    end
  end

  @doc false
  def build_filter_conditions(filters) do
    operator_map = %{
      ">" => :gt,
      ">=" => :gte,
      "<" => :lt,
      "<=" => :lte,
      "=" => :equals,
      "!=" => :not,
      "contains" => :contains,
      "startsWith" => :starts_with,
      "endsWith" => :ends_with,
      "starts_with" => :starts_with,
      "ends_with" => :ends_with
    }

    json_operator_map = %{
      ">" => :gt,
      ">=" => :gte,
      "<" => :lt,
      "<=" => :lte,
      "=" => :equals,
      "!=" => :not,
      "contains" => :string_contains,
      "startsWith" => :string_starts_with,
      "endsWith" => :string_ends_with,
      "starts_with" => :string_starts_with,
      "ends_with" => :string_ends_with
    }

    numeric_operators = [">", ">=", "<", "<=", "=", "!="]

    Enum.map(filters, fn filter ->
      first_operand = get_filter_value(filter, "first_operand", :first_operand)
      operator = get_filter_value(filter, "operator", :operator)
      second_operand = get_filter_value(filter, "second_operand", :second_operand)

      first_operand_str =
        if is_binary(first_operand), do: first_operand, else: to_string(first_operand)

      operator_str = if is_binary(operator), do: operator, else: to_string(operator)

      if String.starts_with?(first_operand_str, "attributes") do
        # JSON path query
        json_path = String.replace(first_operand_str, ~r/^attributes\./, "")
        json_operator = Map.get(json_operator_map, operator_str)

        build_json_condition(
          json_path,
          json_operator,
          second_operand,
          operator_str in numeric_operators
        )
      else
        # Regular field query
        sql_operator = Map.get(operator_map, operator_str)

        second_operand_value =
          if operator_str in numeric_operators and is_binary(second_operand) do
            case Integer.parse(second_operand) do
              {int, _} -> int
              :error -> second_operand
            end
          else
            second_operand
          end

        build_field_condition(first_operand_str, sql_operator, second_operand_value)
      end
    end)
  end

  defp get_filter_value(filter, string_key, atom_key) do
    Map.get(filter, string_key) || Map.get(filter, atom_key)
  end

  defp build_json_condition(json_path, json_operator, second_operand, is_numeric) do
    second_operand_value =
      cond do
        is_numeric and is_binary(second_operand) ->
          case Integer.parse(second_operand) do
            {int, _} -> int
            :error -> second_operand
          end

        is_numeric and is_integer(second_operand) ->
          second_operand

        true ->
          second_operand
      end

    case json_operator do
      :gt ->
        dynamic(
          [cc],
          fragment("(?->>?)::numeric > ?", cc.attributes, ^json_path, ^second_operand_value)
        )

      :gte ->
        dynamic(
          [cc],
          fragment("(?->>?)::numeric >= ?", cc.attributes, ^json_path, ^second_operand_value)
        )

      :lt ->
        dynamic(
          [cc],
          fragment("(?->>?)::numeric < ?", cc.attributes, ^json_path, ^second_operand_value)
        )

      :lte ->
        dynamic(
          [cc],
          fragment("(?->>?)::numeric <= ?", cc.attributes, ^json_path, ^second_operand_value)
        )

      :equals ->
        if is_numeric do
          dynamic(
            [cc],
            fragment("(?->>?)::numeric = ?", cc.attributes, ^json_path, ^second_operand_value)
          )
        else
          dynamic([cc], fragment("?->>? = ?", cc.attributes, ^json_path, ^second_operand_value))
        end

      :not ->
        if is_numeric do
          dynamic(
            [cc],
            fragment("(?->>?)::numeric != ?", cc.attributes, ^json_path, ^second_operand_value)
          )
        else
          dynamic([cc], fragment("?->>? != ?", cc.attributes, ^json_path, ^second_operand_value))
        end

      :string_contains ->
        dynamic(
          [cc],
          fragment("?->>? ILIKE ?", cc.attributes, ^json_path, ^"%#{second_operand}%")
        )

      :string_starts_with ->
        dynamic([cc], fragment("?->>? ILIKE ?", cc.attributes, ^json_path, ^"#{second_operand}%"))

      :string_ends_with ->
        dynamic([cc], fragment("?->>? ILIKE ?", cc.attributes, ^json_path, ^"%#{second_operand}"))
    end
  end

  defp build_field_condition(field_name, operator, second_operand) do
    # Map field names to their atom equivalents
    field_atom =
      case field_name do
        "firstName" -> :first_name
        "first_name" -> :first_name
        "lastName" -> :last_name
        "last_name" -> :last_name
        "phoneNumber" -> :phone_number
        "phone_number" -> :phone_number
        atom when is_atom(atom) -> atom
        _ -> :first_name
      end

    case operator do
      :gt -> dynamic([cc], field(cc, ^field_atom) > ^second_operand)
      :gte -> dynamic([cc], field(cc, ^field_atom) >= ^second_operand)
      :lt -> dynamic([cc], field(cc, ^field_atom) < ^second_operand)
      :lte -> dynamic([cc], field(cc, ^field_atom) <= ^second_operand)
      :equals -> dynamic([cc], field(cc, ^field_atom) == ^second_operand)
      :not -> dynamic([cc], field(cc, ^field_atom) != ^second_operand)
      :contains -> dynamic([cc], ilike(field(cc, ^field_atom), ^"%#{second_operand}%"))
      :starts_with -> dynamic([cc], ilike(field(cc, ^field_atom), ^"#{second_operand}%"))
      :ends_with -> dynamic([cc], ilike(field(cc, ^field_atom), ^"%#{second_operand}"))
    end
  end
end
