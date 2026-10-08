defmodule Comcent.Schemas.ConstraintNamesTest do
  @moduledoc """
  A `unique_constraint` or `foreign_key_constraint` only turns a database
  error into a changeset error when its name matches the real constraint.
  Ecto guesses `<table>_<column>_index`, but most of ours came from the
  initial schema as `<table>_<column>_key`, so a guessed name let a duplicate
  raise and the request answer 500 (COM-133).
  """

  use Comcent.DataCase, async: true

  alias Comcent.Schemas.{Number, Org, OrgMember, Queue, SipTrunk, User}

  defp schema_modules do
    {:ok, modules} = :application.get_key(:comcent, :modules)

    Enum.filter(modules, fn module ->
      Code.ensure_loaded?(module) and
        String.starts_with?(inspect(module), "Comcent.Schemas.") and
        function_exported?(module, :__schema__, 1) and
        function_exported?(module, :changeset, 2)
    end)
  end

  defp database_constraint_names do
    %{rows: rows} =
      Repo.query!("""
      SELECT conname FROM pg_constraint
      UNION
      SELECT indexname FROM pg_indexes WHERE schemaname = 'public'
      """)

    MapSet.new(rows, fn [name] -> name end)
  end

  test "every constraint a schema changeset names exists in the database" do
    existing = database_constraint_names()

    missing =
      for module <- schema_modules(),
          %{constraint: name, type: type} <- module.changeset(struct(module), %{}).constraints,
          not MapSet.member?(existing, name) do
        {module, type, name}
      end

    assert missing == []
  end

  defp insert_org! do
    Repo.insert!(%Org{
      id: Ecto.UUID.generate(),
      name: "Riverbend Dental",
      subdomain: "riverbend#{System.unique_integer([:positive])}",
      use_custom_domain: false,
      assign_ext_automatically: false
    })
  end

  defp insert_user! do
    Repo.insert!(%User{
      id: Ecto.UUID.generate(),
      name: "Mira Holt",
      email: "mira.#{System.unique_integer([:positive])}@example.com"
    })
  end

  defp insert_sip_trunk!(org) do
    Repo.insert!(%SipTrunk{
      id: Ecto.UUID.generate(),
      name: "Main trunk",
      outbound_contact: "sip.example.com",
      inbound_ips: [],
      org_id: org.id
    })
  end

  test "a number that is already added is an error on :number, not a raise" do
    org = insert_org!()
    trunk = insert_sip_trunk!(org)

    attrs = %{
      "name" => "Front desk",
      "number" => "+15550100123",
      "inbound_flow_graph" => %{"nodes" => %{}, "start" => nil},
      "org_id" => org.id,
      "sip_trunk_id" => trunk.id
    }

    assert {:ok, _} =
             %Number{id: Ecto.UUID.generate()} |> Number.changeset(attrs) |> Repo.insert()

    assert {:error, changeset} =
             %Number{id: Ecto.UUID.generate()} |> Number.changeset(attrs) |> Repo.insert()

    assert {"is already added", _} = changeset.errors[:number]
  end

  test "an email that is already registered is an error on :email, not a raise" do
    user = insert_user!()

    assert {:error, changeset} =
             %User{id: Ecto.UUID.generate()}
             |> User.changeset(%{name: "Someone Else", email: user.email})
             |> Repo.insert()

    assert {"is already registered", _} = changeset.errors[:email]
  end

  test "a username taken in the org is an error on :username, not a raise" do
    org = insert_org!()

    attrs = fn user ->
      %{
        user_id: user.id,
        org_id: org.id,
        role: :MEMBER,
        username: "frontdesk",
        sip_password: "secret"
      }
    end

    assert {:ok, _} = %OrgMember{} |> OrgMember.changeset(attrs.(insert_user!())) |> Repo.insert()

    assert {:error, changeset} =
             %OrgMember{} |> OrgMember.changeset(attrs.(insert_user!())) |> Repo.insert()

    assert {"is already taken in this organization", _} = changeset.errors[:username]
  end

  test "joining an org twice is an error on :user_id, not a raise" do
    org = insert_org!()
    user = insert_user!()

    attrs = fn username ->
      %{
        user_id: user.id,
        org_id: org.id,
        role: :MEMBER,
        username: username,
        sip_password: "secret"
      }
    end

    assert {:ok, _} = %OrgMember{} |> OrgMember.changeset(attrs.("mira")) |> Repo.insert()

    assert {:error, changeset} =
             %OrgMember{} |> OrgMember.changeset(attrs.("mira2")) |> Repo.insert()

    assert {"is already a member of this organization", _} = changeset.errors[:user_id]
  end

  test "a queue name taken in the org is an error on :name, not a raise" do
    org = insert_org!()
    attrs = fn -> %{"id" => Ecto.UUID.generate(), "name" => "support", "org_id" => org.id} end

    assert {:ok, _} = %Queue{} |> Queue.changeset(attrs.()) |> Repo.insert()
    assert {:error, changeset} = %Queue{} |> Queue.changeset(attrs.()) |> Repo.insert()
    assert {"is already taken", _} = changeset.errors[:name]
  end
end
