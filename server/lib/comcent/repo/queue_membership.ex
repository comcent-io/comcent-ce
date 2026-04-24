defmodule Comcent.Repo.QueueMembership do
  alias Comcent.Schemas.QueueMembership
  alias Comcent.Repo
  import Ecto.Query

  @doc """
  Deletes all queue memberships for a given queue ID.
  """
  def delete_queue_memberships(queue_id) do
    QueueMembership
    |> where([qm], qm.queue_id == ^queue_id)
    |> Repo.delete_all()
  end
end
