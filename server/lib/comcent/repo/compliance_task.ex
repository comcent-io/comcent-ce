defmodule Comcent.Repo.ComplianceTask do
  import Ecto.Query
  alias Comcent.Repo
  alias Comcent.Schemas.ComplianceTask
  alias Comcent.Schemas.Org

  def change_compliance_task_status(compliance_task_id, subdomain, status) do
    query =
      from(ct in ComplianceTask,
        join: o in Org,
        on: ct.org_id == o.id,
        where: ct.id == ^compliance_task_id and o.subdomain == ^subdomain,
        select: ct
      )

    case Repo.one(query) do
      nil ->
        {:error, :not_found}

      task ->
        task
        |> Ecto.Changeset.change(%{status: status})
        |> Repo.update()
    end
  end

  def change_compliance_task_status_and_file_name(
        compliance_task_id,
        subdomain,
        status,
        file_name
      ) do
    query =
      from(ct in ComplianceTask,
        join: o in Org,
        on: ct.org_id == o.id,
        where: ct.id == ^compliance_task_id and o.subdomain == ^subdomain,
        select: ct
      )

    case Repo.one(query) do
      nil ->
        {:error, :not_found}

      task ->
        task
        |> Ecto.Changeset.change(%{
          status: status,
          data: Map.put(task.data || %{}, "file_name", file_name)
        })
        |> Repo.update()
    end
  end
end
