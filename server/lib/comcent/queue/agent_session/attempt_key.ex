defmodule Comcent.Queue.AgentSession.AttemptKey do
  @moduledoc """
  Identifies one queue dial attempt to FreeSWITCH, for cleanup.

  Lives in its own module rather than in `Dialer` because both `Dialer` and
  `AgentSession` need it, and tests replace the whole `Dialer` module with a
  mock -- under which a call into it from `AgentSession`'s cleanup task
  crashed with `UndefinedFunctionError`.
  """

  @doc """
  The value of the `comcent_dialed_for_attempt` channel variable, which is what
  cleanup `hupall`s on.

  It must identify one attempt, not one call. A queued call is offered to
  agents one after another under the same call id, and a finished attempt
  reports to its owner BEFORE it cleans up -- so by the time its `hupall` ran,
  the scheduler had often already dialled the next agent. Keyed on the call id,
  that `hupall` killed the next agent's freshly ringing leg: the second agent
  saw a CANCEL a few hundred milliseconds after the INVITE, or `uuid_bridge`
  failed with "-ERR Invalid uuid" because the answered leg had just vanished.
  Whether it bit was pure timing, which is why it showed on a loaded CI runner
  and not on a fast laptop.

  The reservation id alone is not enough either: it is only unique within one
  BEAM node, and several nodes share a FreeSWITCH. The call id is a UUID, so the
  pair is globally unique.
  """
  def build(call_id, reservation_id), do: "#{call_id}_#{reservation_id}"
end
