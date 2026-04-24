defmodule Comcent.VoiceBot do
  @moduledoc """
  The VoiceBot context.

  This module handles operations related to voice bots, including
  retrieving voice bot configurations and processing voice bot actions.
  """

  import Ecto.Query
  alias Comcent.Repo

  @doc """
  Gets a voice bot by ID.

  ## Examples

      iex> get_voice_bot("123")
      %{id: "123", name: "Customer Service Bot", ...}

      iex> get_voice_bot("456")
      nil

  """
  def get_voice_bot(id) when is_binary(id) do
    # Query for the voice bot
    query =
      from(vb in Comcent.Schemas.VoiceBot,
        where: vb.id == ^id,
        left_join: o in Comcent.Schemas.Org,
        on: vb.org_id == o.id,
        select: %{
          id: vb.id,
          name: vb.name,
          instructions: vb.instructions,
          not_to_do_instructions: vb.not_to_do_instructions,
          greeting_instructions: vb.greeting_instructions,
          mcp_servers: vb.mcp_servers,
          is_hangup: vb.is_hangup,
          is_enqueue: vb.is_enqueue,
          queues: vb.queues,
          pipeline: vb.pipeline,
          org_id: vb.org_id,
          org: %{
            id: o.id,
            subdomain: o.subdomain
          }
        }
      )

    Repo.one(query)
  end
end
