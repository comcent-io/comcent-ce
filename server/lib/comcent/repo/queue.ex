defmodule Comcent.Repo.Queue do
  import Ecto.Query
  alias Comcent.Repo.Queue
  alias Comcent.Repo
  alias Comcent.Schemas.{Queue, Org, QueueMembership, OrgMember, User}

  def get_queue_by_name_and_subdomain(name, subdomain) do
    query =
      from(q in Queue,
        join: o in Org,
        on: q.org_id == o.id,
        where: q.name == ^name and o.subdomain == ^subdomain,
        select: %{
          id: q.id,
          name: q.name,
          org_id: q.org_id
        }
      )

    Repo.one(query)
  end

  def get_queue_id_by_extension_and_subdomain(extension, subdomain) do
    Repo.one(
      from(q in Queue,
        join: o in Org,
        on: q.org_id == o.id,
        where: o.subdomain == ^subdomain and q.extension == ^extension,
        select: q.id
      )
    )
  end

  def get_queue_by_id(id, subdomain) when not is_nil(id) and not is_nil(subdomain) do
    Repo.one(
      from(q in Queue,
        join: o in Org,
        on: q.org_id == o.id,
        where: o.subdomain == ^subdomain and q.id == ^id,
        select: q
      )
    )
  end

  def get_queue_with_members(id, subdomain) when not is_nil(id) and not is_nil(subdomain) do
    # First get the queue
    queue_query =
      from(q in Queue,
        join: o in Org,
        on: q.org_id == o.id,
        where: o.subdomain == ^subdomain and q.id == ^id,
        select: %{
          id: q.id,
          name: q.name,
          extension: q.extension,
          wrap_up_time: q.wrap_up_time,
          reject_delay_time: q.reject_delay_time,
          max_no_answers: q.max_no_answers,
          created_at: q.created_at,
          updated_at: q.updated_at,
          org_id: q.org_id
        }
      )

    case Repo.one(queue_query) do
      nil ->
        nil

      queue ->
        # Then get the queue memberships with user email
        members_query =
          from(qm in QueueMembership,
            join: om in OrgMember,
            on: om.user_id == qm.user_id and om.org_id == qm.org_id,
            join: u in User,
            on: u.id == om.user_id,
            where: qm.queue_id == ^id,
            select: %{
              id: qm.user_id,
              name: u.email,
              username: om.username
            }
          )

        members = Repo.all(members_query)

        %{
          queue: queue,
          subdomain: subdomain,
          queue_id: id,
          queue_members: members
        }
    end
  end

  def get_queues_by_org(subdomain) do
    Repo.all(
      from(q in Queue,
        join: o in Org,
        on: q.org_id == o.id,
        where: o.subdomain == ^subdomain,
        select: q
      )
    )
  end

  def update_queue(queue, params) do
    queue
    |> Queue.changeset(params)
    |> Repo.update()
  end

  def create_queue(params) do
    %Queue{}
    |> Queue.changeset(params)
    |> Repo.insert()
  end

  def delete_queue(queue) do
    Repo.delete(queue)
  end

  def get_available_agents(queue_id, subdomain) do
    query =
      from(m in OrgMember,
        join: qm in QueueMembership,
        on: qm.user_id == m.user_id and qm.org_id == m.org_id,
        join: o in Org,
        on: qm.org_id == o.id,
        where:
          o.subdomain == ^subdomain and qm.queue_id == ^queue_id and m.presence == "Available",
        select: %{
          user_id: m.user_id,
          username: m.username,
          presence: m.presence,
          org_id: o.id,
          subdomain: o.subdomain
        }
      )

    Repo.all(query)
  end

  def get_active_agents(queue_id, subdomain) do
    query =
      from(m in OrgMember,
        join: qm in QueueMembership,
        on: qm.user_id == m.user_id and qm.org_id == m.org_id,
        join: o in Org,
        on: qm.org_id == o.id,
        where:
          o.subdomain == ^subdomain and qm.queue_id == ^queue_id and m.presence != "Logged Out",
        select: %{
          user_id: m.user_id,
          username: m.username,
          presence: m.presence,
          org_id: o.id,
          subdomain: o.subdomain
        }
      )

    Repo.all(query)
  end

  def add_member_to_queue(%{org_id: org_id, user_id: user_id}, queue_id) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    %QueueMembership{}
    |> QueueMembership.changeset(%{
      queue_id: queue_id,
      org_id: org_id,
      user_id: user_id,
      created_at: now,
      updated_at: now
    })
    |> Repo.insert()
  end

  def remove_member_from_queue(queue_id, member_id, org_id) do
    query =
      from(qm in QueueMembership,
        where: qm.queue_id == ^queue_id and qm.org_id == ^org_id and qm.user_id == ^member_id
      )

    case Repo.delete_all(query) do
      {0, _} -> {:error, :member_not_found}
      {1, _} -> {:ok, :deleted}
      _ -> {:error, :unexpected_result}
    end
  end

  def get_total_agents_in_queue(queue_id, subdomain) do
    query =
      from(qm in QueueMembership,
        join: o in Org,
        on: qm.org_id == o.id,
        where: o.subdomain == ^subdomain and qm.queue_id == ^queue_id,
        select: count(qm.user_id)
      )

    Repo.one(query) || 0
  end
end
