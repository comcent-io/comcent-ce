defmodule Comcent.Queue.AgentSession.Dialer do
  @moduledoc """
  One-shot FreeSWITCH dialer for a single queue attempt.

  Lifecycle (one process per attempt):
    1. Open an ESL connection.
    2. Issue synchronous `api originate {originate_timeout=N}<dial> &park()`.
       `api` runs on this connection's own FS thread and parallelizes
       across connections (verified empirically); unlike `bgapi`, it is not
       bottlenecked by FS's shared background thread pool, which saturates
       under 30-concurrent-originate stress and caused BG_JOB dispatch to
       lag >10 s behind our attempt timer.
    3. On `+OK <uuid>`, issue synchronous `api uuid_bridge` to the customer
       leg.
    4. Report `{:dialer_answered, reservation_id, member_uuid}` or
       `{:dialer_failed, reservation_id, reason}` to the owning AgentSession.
    5. Exit.

  On `{:cancel, reason}` the dialer issues
  `hupall NORMAL_CLEARING comcent_dialed_for_call_id <call_id>` to kill any
  member legs still alive (forked branches, parked channel, etc.), then exits
  without reporting further outcomes.

  Design notes
    * The owner is monitored, not linked. If the owner dies, the `{:DOWN, ...}`
      it sees wins; this process exits on the `:cancel` it expects.
    * `originate_timeout` is set a little below the owner's attempt timer so
      FreeSWITCH gives up first; the AgentSession timer is the backstop.
    * No bare `receive`. All messages go through GenServer callbacks.
    * No channel-id tracking is done here; cleanup is a single `hupall` on the
      attempt-scoped channel variable.
  """

  use GenServer, restart: :temporary
  require Logger

  alias Comcent.DialUtils

  @type attempt :: %{
          owner: pid(),
          reservation_id: String.t(),
          member_username: String.t(),
          subdomain: String.t(),
          call_id: String.t(),
          customer_uuid: String.t(),
          freeswitch_ip: String.t(),
          from_user: String.t(),
          from_name: String.t(),
          to_user: String.t(),
          to_name: String.t(),
          comcent_context_id: String.t(),
          queue_id: String.t(),
          originate_timeout_ms: pos_integer()
        }

  @esl_password "ClueCon"

  # Public API -----------------------------------------------------------------

  def start_link(%{owner: owner} = attempt) when is_pid(owner) do
    GenServer.start_link(__MODULE__, attempt, [])
  end

  @doc "Cancel the attempt. The dialer hangs up any member legs and exits."
  def cancel(pid, reason) when is_pid(pid) do
    send(pid, {:cancel, reason})
    :ok
  end

  # GenServer callbacks --------------------------------------------------------

  @impl true
  def init(attempt) do
    # Don't link to the owner — the owner monitors us. That way an owner crash
    # doesn't take us down mid-hangup, and a dialer crash is a plain :DOWN.
    Process.flag(:trap_exit, true)
    {:ok, %{attempt: attempt, conn: nil}, {:continue, :connect}}
  end

  @impl true
  def handle_continue(:connect, %{attempt: attempt} = state) do
    case SwitchX.Connection.Inbound.start_link(host: attempt.freeswitch_ip, port: 8021) do
      {:ok, conn} ->
        # Synchronous `api originate` runs on this connection's own FS thread
        # and parallelizes cleanly across connections (verified empirically:
        # 5 concurrent `api msleep 3000` finished in ~3 s total, not 15 s).
        # This sidesteps the `bgapi` thread-pool saturation we hit under
        # 30-concurrent-originate stress, where FS's BG_JOB dispatch lagged
        # by 10+ seconds and outlasted our attempt timer.
        with {:ok, "Accepted"} <- SwitchX.auth(conn, @esl_password) do
          case SwitchX.api(conn, originate_cmd(attempt)) do
            {:ok, %SwitchX.Event{body: "+OK " <> rest}} ->
              uuid = String.trim(rest)

              Logger.info(
                "Dialer originate answered call=#{attempt.call_id} member=#{attempt.member_username} uuid=#{uuid}"
              )

              bridge(%{state | conn: conn}, uuid)

            {:ok, %SwitchX.Event{body: "-ERR " <> reason}} ->
              Logger.info(
                "Dialer originate rejected call=#{attempt.call_id} member=#{attempt.member_username} reason=#{String.trim(reason)}"
              )

              fail(%{state | conn: conn}, {:originate_rejected, String.trim(reason)})

            other ->
              Logger.warning(
                "Dialer originate unexpected reply call=#{attempt.call_id} member=#{attempt.member_username} reply=#{inspect(other)}"
              )

              fail(%{state | conn: conn}, {:originate_unexpected, other})
          end
        else
          error ->
            Logger.warning(
              "Dialer auth failed call=#{attempt.call_id} member=#{attempt.member_username}: #{inspect(error)}"
            )

            fail(state, {:auth_failed, error})
        end

      {:error, reason} ->
        fail(state, {:esl_connect_failed, reason})
    end
  end

  @impl true
  def handle_info({:switchx_event, _}, state), do: {:noreply, state}

  def handle_info({:cancel, reason}, state) do
    Logger.info(
      "Dialer cancel for call #{state.attempt.call_id} (#{state.attempt.member_username}): #{inspect(reason)}"
    )

    hupall(state)
    close(state.conn)
    {:stop, :normal, %{state | conn: nil}}
  end

  def handle_info({:EXIT, pid, reason}, %{conn: conn} = state) when pid == conn do
    fail(state, {:esl_connection_exit, reason})
  end

  def handle_info(_msg, state), do: {:noreply, state}

  @impl true
  def terminate(_reason, %{conn: conn}) when is_pid(conn) do
    close(conn)
    :ok
  end

  def terminate(_reason, _state), do: :ok

  # Internals ------------------------------------------------------------------

  defp bridge(%{attempt: attempt, conn: conn} = state, member_uuid) do
    cmd = "uuid_bridge #{member_uuid} #{attempt.customer_uuid}"

    case SwitchX.api(conn, cmd) do
      {:ok, %SwitchX.Event{body: "+OK" <> _}} ->
        send(attempt.owner, {:dialer_answered, attempt.reservation_id, member_uuid})
        close(conn)
        {:stop, :normal, %{state | conn: nil}}

      other ->
        Logger.info(
          "Dialer bridge failed for call #{attempt.call_id} (#{attempt.member_username}): #{inspect(other)}"
        )

        _ = SwitchX.api(conn, "uuid_kill #{member_uuid}")
        fail(state, {:bridge_failed, other})
    end
  end

  defp fail(%{attempt: attempt} = state, reason) do
    send(attempt.owner, {:dialer_failed, attempt.reservation_id, reason})
    hupall(state)
    close(state.conn)
    {:stop, :normal, %{state | conn: nil}}
  end

  defp hupall(%{conn: nil}), do: :ok

  defp hupall(%{attempt: attempt, conn: conn}) do
    _ =
      SwitchX.api(
        conn,
        "hupall NORMAL_CLEARING comcent_dialed_for_call_id #{attempt.call_id}"
      )

    :ok
  end

  defp close(nil), do: :ok

  defp close(conn) do
    _ = SwitchX.close(conn)
    :ok
  end

  defp originate_cmd(attempt) do
    storage_bucket = System.get_env("STORAGE_BUCKET_NAME") || ""

    channel_vars = [
      "comcent_context_id=#{attempt.comcent_context_id}",
      "comcent_subdomain=#{attempt.subdomain}",
      "comcent_recording_bucket_name=#{storage_bucket}",
      "comcent_dialed_by=queue_member_dialer",
      "comcent_dialed_by_queue_id=#{attempt.queue_id}",
      "comcent_dialed_for_call_id=#{attempt.call_id}",
      "effective_caller_id_number=#{attempt.from_user}",
      "effective_caller_id_name=#{attempt.from_name}",
      "sip_h_X-Inbound-Info=:#{attempt.to_user}:#{attempt.to_name}",
      "origination_caller_id_number=#{attempt.from_user}",
      "origination_caller_id_name=#{attempt.from_name}"
    ]

    dial_string =
      DialUtils.create_dial_string_for_user(
        attempt.member_username,
        attempt.subdomain,
        channel_vars
      )

    originate_timeout_s = max(div(attempt.originate_timeout_ms, 1000), 1)
    "originate {originate_timeout=#{originate_timeout_s}}#{dial_string} &park()"
  end
end
