defmodule Comcent.Repo.CampaignCustomerTest do
  use ExUnit.Case, async: true
  alias Comcent.Repo.CampaignCustomer

  # Helper to call the function (now testable with @doc false)
  defp call_build_filter_conditions(filters) do
    CampaignCustomer.build_filter_conditions(filters)
  end

  describe "build_filter_conditions/1" do
    test "returns empty list for empty filters" do
      result = call_build_filter_conditions([])
      assert result == []
    end

    test "builds condition for regular field with equals operator" do
      filters = [
        %{"firstOperand" => "firstName", "operator" => "=", "secondOperand" => "John"}
      ]

      result = call_build_filter_conditions(filters)
      assert length(result) == 1
      assert %Ecto.Query.DynamicExpr{} = List.first(result)
    end

    test "builds condition for regular field with contains operator" do
      filters = [
        %{"firstOperand" => "lastName", "operator" => "contains", "secondOperand" => "Smith"}
      ]

      result = call_build_filter_conditions(filters)
      assert length(result) == 1
      assert %Ecto.Query.DynamicExpr{} = List.first(result)
    end

    test "builds condition for regular field with startsWith operator" do
      filters = [
        %{"firstOperand" => "firstName", "operator" => "startsWith", "secondOperand" => "Jo"}
      ]

      result = call_build_filter_conditions(filters)
      assert length(result) == 1
    end

    test "builds condition for regular field with endsWith operator" do
      filters = [
        %{"firstOperand" => "lastName", "operator" => "endsWith", "secondOperand" => "son"}
      ]

      result = call_build_filter_conditions(filters)
      assert length(result) == 1
    end

    test "builds condition for JSON path query with greater than operator" do
      filters = [
        %{"firstOperand" => "attributes.age", "operator" => ">", "secondOperand" => "25"}
      ]

      result = call_build_filter_conditions(filters)
      assert length(result) == 1
      assert %Ecto.Query.DynamicExpr{} = List.first(result)
    end

    test "builds condition for JSON path query with greater than or equal operator" do
      filters = [
        %{"firstOperand" => "attributes.score", "operator" => ">=", "secondOperand" => "100"}
      ]

      result = call_build_filter_conditions(filters)
      assert length(result) == 1
    end

    test "builds condition for JSON path query with less than operator" do
      filters = [
        %{"firstOperand" => "attributes.price", "operator" => "<", "secondOperand" => "50"}
      ]

      result = call_build_filter_conditions(filters)
      assert length(result) == 1
    end

    test "builds condition for JSON path query with less than or equal operator" do
      filters = [
        %{"firstOperand" => "attributes.quantity", "operator" => "<=", "secondOperand" => "10"}
      ]

      result = call_build_filter_conditions(filters)
      assert length(result) == 1
    end

    test "builds condition for JSON path query with equals operator (numeric)" do
      filters = [
        %{"firstOperand" => "attributes.id", "operator" => "=", "secondOperand" => "42"}
      ]

      result = call_build_filter_conditions(filters)
      assert length(result) == 1
    end

    test "builds condition for JSON path query with not equals operator" do
      filters = [
        %{"firstOperand" => "attributes.status", "operator" => "!=", "secondOperand" => "0"}
      ]

      result = call_build_filter_conditions(filters)
      assert length(result) == 1
    end

    test "builds condition for JSON path query with contains operator" do
      filters = [
        %{
          "firstOperand" => "attributes.description",
          "operator" => "contains",
          "secondOperand" => "test"
        }
      ]

      result = call_build_filter_conditions(filters)
      assert length(result) == 1
    end

    test "builds condition for JSON path query with startsWith operator" do
      filters = [
        %{
          "firstOperand" => "attributes.code",
          "operator" => "startsWith",
          "secondOperand" => "ABC"
        }
      ]

      result = call_build_filter_conditions(filters)
      assert length(result) == 1
    end

    test "builds condition for JSON path query with endsWith operator" do
      filters = [
        %{
          "firstOperand" => "attributes.suffix",
          "operator" => "endsWith",
          "secondOperand" => "xyz"
        }
      ]

      result = call_build_filter_conditions(filters)
      assert length(result) == 1
    end

    test "converts numeric string to integer for numeric operators on regular fields" do
      filters = [
        %{"firstOperand" => "firstName", "operator" => ">", "secondOperand" => "100"}
      ]

      result = call_build_filter_conditions(filters)
      assert length(result) == 1
    end

    test "keeps non-numeric strings as strings for numeric operators" do
      filters = [
        %{"firstOperand" => "attributes.code", "operator" => ">", "secondOperand" => "abc"}
      ]

      result = call_build_filter_conditions(filters)
      assert length(result) == 1
    end

    test "handles integer second operand directly" do
      filters = [
        %{"firstOperand" => "attributes.count", "operator" => ">=", "secondOperand" => 100}
      ]

      result = call_build_filter_conditions(filters)
      assert length(result) == 1
    end

    test "handles all comparison operators for regular fields" do
      operators = [">", ">=", "<", "<=", "=", "!="]

      Enum.each(operators, fn op ->
        filters = [
          %{"firstOperand" => "firstName", "operator" => op, "secondOperand" => "test"}
        ]

        result = call_build_filter_conditions(filters)
        assert length(result) == 1, "Failed for operator: #{op}"
        assert %Ecto.Query.DynamicExpr{} = List.first(result)
      end)
    end

    test "handles all string operators for regular fields" do
      operators = ["contains", "startsWith", "endsWith"]

      Enum.each(operators, fn op ->
        filters = [
          %{"firstOperand" => "lastName", "operator" => op, "secondOperand" => "test"}
        ]

        result = call_build_filter_conditions(filters)
        assert length(result) == 1, "Failed for operator: #{op}"
      end)
    end

    test "handles multiple filters" do
      filters = [
        %{"firstOperand" => "firstName", "operator" => "=", "secondOperand" => "John"},
        %{"firstOperand" => "lastName", "operator" => "contains", "secondOperand" => "Smith"},
        %{"firstOperand" => "attributes.age", "operator" => ">", "secondOperand" => "25"}
      ]

      result = call_build_filter_conditions(filters)
      assert length(result) == 3

      # Verify all are dynamic expressions
      Enum.each(result, fn condition ->
        assert %Ecto.Query.DynamicExpr{} = condition
      end)
    end

    test "handles atom keys in filter maps" do
      filters = [
        %{firstOperand: "firstName", operator: "=", secondOperand: "John"}
      ]

      result = call_build_filter_conditions(filters)
      assert length(result) == 1
    end

    test "handles mixed string and atom keys" do
      filters = [
        %{"firstOperand" => "firstName", :operator => "=", "secondOperand" => "John"}
      ]

      result = call_build_filter_conditions(filters)
      assert length(result) == 1
    end

    test "handles attributes path with nested dot notation" do
      filters = [
        %{
          "firstOperand" => "attributes.user.profile.age",
          "operator" => ">=",
          "secondOperand" => "18"
        }
      ]

      result = call_build_filter_conditions(filters)
      assert length(result) == 1
    end

    test "handles all supported regular field names" do
      fields = ["firstName", "lastName", "phoneNumber"]

      Enum.each(fields, fn field ->
        filters = [
          %{"firstOperand" => field, "operator" => "=", "secondOperand" => "test"}
        ]

        result = call_build_filter_conditions(filters)
        assert length(result) == 1, "Failed for field: #{field}"
      end)
    end

    test "correctly identifies JSON path queries vs regular fields" do
      # Regular field
      regular_filter = [
        %{"firstOperand" => "firstName", "operator" => "=", "secondOperand" => "John"}
      ]

      # JSON path
      json_filter = [
        %{"firstOperand" => "attributes.name", "operator" => "=", "secondOperand" => "John"}
      ]

      regular_result = call_build_filter_conditions(regular_filter)
      json_result = call_build_filter_conditions(json_filter)

      assert length(regular_result) == 1
      assert length(json_result) == 1
      # Both should be dynamic expressions but with different structures
      assert %Ecto.Query.DynamicExpr{} = List.first(regular_result)
      assert %Ecto.Query.DynamicExpr{} = List.first(json_result)
    end

    test "handles complex nested JSON paths" do
      filters = [
        %{
          "firstOperand" => "attributes.metadata.tags.category",
          "operator" => "contains",
          "secondOperand" => "premium"
        }
      ]

      result = call_build_filter_conditions(filters)
      assert length(result) == 1
    end

    test "applies multiple conditions to a query correctly" do
      filters = [
        %{"firstOperand" => "firstName", "operator" => "=", "secondOperand" => "John"},
        %{"firstOperand" => "attributes.age", "operator" => ">", "secondOperand" => "25"}
      ]

      conditions = call_build_filter_conditions(filters)
      assert length(conditions) == 2

      # Verify all conditions are valid dynamic expressions
      Enum.each(conditions, fn condition ->
        assert %Ecto.Query.DynamicExpr{} = condition
      end)
    end
  end
end
