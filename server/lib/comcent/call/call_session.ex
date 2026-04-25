defmodule Comcent.CallSession do
  @moduledoc """
  Per-call GenServer. One of these lives cluster-wide for every `call_story_id`
  seen by the system (registered via `Comcent.CallSession.Registry`).

  This process is the single source of truth for a call: all FreeSWITCH events
  related to this call arrive here via `GenServer.cast` and are handled in
  FIFO order, so span start/end, hangup-party detection, recording bookkeeping
  and final persistence are deterministic without Redis repair logic.

  State fields
  ------------
    * `:call_story_id`        — unique id for this call (aka comcent_context_id)
    * `:subdomain`            — learned from events as they arrive
    * `:caller` / `:callee` / `:direction` / `:outbound_caller_id` /
      `:hangup_party` / `:start_at` — populated from the inbound root
      CHANNEL_CREATE
    * `:open_spans`           — `%{{type, channel_id} => span}` for in-flight
      spans
    * `:completed_spans`      — finalized spans, in arrival order
    * `:completed_events`     — finalized point-in-time story events
    * `:channel_count`        — live channels tracked for this story
    * `:record_count`         — recording uploads we're waiting on
    * `:recording_uploads`    — `%{file_name => upload_meta}` arrived before
      RECORD_STOP (merged at span finalize)
    * `:story_initialized?`   — true after the inbound root CHANNEL_CREATE
    * `:persisted?`           — true after Repo insert
    * `:seen_event_uuids`     — MapSet of already-handled `Event-UUID`s (dedup
      for redelivery)
    * `:seen_order`           — FIFO queue of event UUIDs to bound the MapSet
    * `:idle_timer_ref`       — timer to terminate idle processes
  """

  use GenServer, restart: :transient
  require Logger

  alias Comcent.Call.{LiveCalls, Persistence}
  alias Comcent.CallSession.Registry
  alias Comcent.Queue.AgentSession
  alias Comcent.Repo.OrgMember
  alias Comcent.Schemas.VoiceBot
  alias Comcent.Repo

  @idle_timeout :timer.minutes(30)
  @shutdown_grace :timer.seconds(5)
  @max_seen_events 2_000

  @type span_type ::
          :HOLD | :ON_CALL | :DIAL_WAIT | :RINGING | :QUEUED | :RECORDING

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  def start_link(call_story_id) when is_binary(call_story_id) do
    GenServer.start_link(__MODULE__, call_story_id, name: Registry.via(call_story_id))
  end

  def child_spec(call_story_id) do
    %{
      id: {__MODULE__, call_story_id},
      start: {__MODULE__, :start_link, [call_story_id]},
      restart: :transient,
      type: :worker
    }
  end

  @doc """
  Route an event to an already-running call process. If no process exists,
  the event is dropped (typical for non-root legs / late events).
  """
  def dispatch(call_story_id, body) when is_binary(call_story_id) do
    case Registry.whereis(call_story_id) do
      nil ->
        Logger.info("No call process for #{call_story_id}; dropping #{body["Event-Name"]}")

        :ok

      pid ->
        GenServer.cast(pid, {:event, body})
    end
  end

  @doc """
  Start the call process (if needed) and route the event to it. Use only for
  events that legitimately begin a call story (the inbound root
  CHANNEL_CREATE, and outbound legs that carry an explicit comcent context).
  """
  def start_and_dispatch(call_story_id, body) when is_binary(call_story_id) do
    {:ok, _} = Registry.start_call(call_story_id)
    GenServer.cast(Registry.via(call_story_id), {:event, body})
  end

  @doc """
  Used by `QueueManager.Worker` to append a span (typically `QUEUED`) or a
  call-story record to the per-call process.
  """
  def append_story_span(call_story_id, %{type: _type} = span) do
    {:ok, _} = Registry.start_call(call_story_id)
    GenServer.cast(Registry.via(call_story_id), {:append_span, span})
  end

  def append_story_record(call_story_id, %{caller: _} = record) do
    {:ok, _} = Registry.start_call(call_story_id)
    GenServer.cast(Registry.via(call_story_id), {:append_story_record, record})
  end

  def append_story_event(call_story_id, %{type: _type, occurred_at: _occurred_at} = event) do
    {:ok, _} = Registry.start_call(call_story_id)
    GenServer.cast(Registry.via(call_story_id), {:append_event, event})
  end

  # ---------------------------------------------------------------------------
  # GenServer callbacks
  # ---------------------------------------------------------------------------

  @impl true
  def init(call_story_id) do
    Process.flag(:trap_exit, true)

    state = %{
      call_story_id: call_story_id,
      subdomain: nil,
      caller: nil,
      callee: nil,
      direction: nil,
      outbound_caller_id: nil,
      hangup_party: nil,
      start_at: nil,
      open_spans: %{},
      completed_spans: [],
      completed_events: [],
      channel_count: 0,
      record_count: 0,
      recording_uploads: %{},
      story_initialized?: false,
      persisted?: false,
      seen_event_uuids: MapSet.new(),
      seen_order: :queue.new(),
      idle_timer_ref: nil
    }

    {:ok, arm_idle_timer(state)}
  end

  @impl true
  def handle_cast({:event, body}, state) do
    state = arm_idle_timer(state)

    case dedup(state, body) do
      {:seen, state} ->
        {:noreply, state}

      {:fresh, state} ->
        state
        |> handle_event(body)
        |> maybe_finalize()
    end
  end

  def handle_cast({:append_span, span}, state) do
    state = arm_idle_timer(state)

    state = %{state | completed_spans: state.completed_spans ++ [span]}
    {:noreply, state}
  end

  def handle_cast({:append_event, event}, state) do
    state = arm_idle_timer(state)
    state = %{state | completed_events: state.completed_events ++ [event]}
    {:noreply, state}
  end

  def handle_cast({:append_story_record, record}, state) do
    state = arm_idle_timer(state)

    state =
      state
      |> Map.merge(Map.take(record, [:caller, :callee, :direction, :start_at]))
      |> Map.put(:story_initialized?, true)

    {:noreply, state}
  end

  @impl true
  def handle_info(:idle_timeout, state) do
    Logger.warning("Call #{state.call_story_id} idle-timed out; terminating without persistence")

    {:stop, :normal, state}
  end

  def handle_info(:shutdown, state) do
    {:stop, :normal, state}
  end

  def handle_info({:EXIT, _pid, _reason}, state) do
    {:noreply, state}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  # ---------------------------------------------------------------------------
  # Event handling
  # ---------------------------------------------------------------------------

  defp handle_event(state, %{"Event-Name" => "CHANNEL_CREATE"} = body) do
    handle_channel_create(state, body)
  end

  defp handle_event(state, %{"Event-Name" => "CHANNEL_ANSWER"} = body) do
    handle_channel_answer(state, body)
  end

  defp handle_event(state, %{"Event-Name" => "CHANNEL_DESTROY"} = body) do
    handle_channel_destroy(state, body)
  end

  defp handle_event(state, %{"Event-Name" => "CHANNEL_HOLD"} = body) do
    start_span(state, "HOLD", body)
  end

  defp handle_event(state, %{"Event-Name" => "CHANNEL_UNHOLD"} = body) do
    close_span(state, "HOLD", channel_id(body), body, %{})
  end

  defp handle_event(state, %{"Event-Name" => "RECORD_START"} = body) do
    handle_record_start(state, body)
  end

  defp handle_event(state, %{"Event-Name" => "RECORD_STOP"} = body) do
    handle_record_stop(state, body)
  end

  defp handle_event(
         state,
         %{"Event-Name" => "CUSTOM", "Event-Subclass" => "comcent::s3UploadCompleted"} = body
       ) do
    handle_upload_completed(state, body)
  end

  defp handle_event(state, body) do
    Logger.info(
      "Call #{state.call_story_id} ignoring unhandled event #{inspect(body["Event-Name"])}"
    )

    state
  end

  # ---------------------------------------------------------------------------
  # CHANNEL_CREATE
  # ---------------------------------------------------------------------------

  defp handle_channel_create(state, body) do
    direction_from_ctx =
      if body["Caller-Context"] == "default", do: "outbound", else: "inbound"

    state = learn_subdomain(state, body)

    state =
      if inbound_root?(body) do
        start_at = date_from_unix(body["Event-Date-Timestamp"])

        Logger.info("Call Story Started #{state.call_story_id}")

        %{
          state
          | caller: user_from_body(body),
            callee: get_callee_from_body(body),
            direction: direction_from_ctx,
            start_at: start_at,
            story_initialized?: true
        }
      else
        maybe_learn_outbound_caller_id(state, body, direction_from_ctx)
      end

    channel_id = channel_id(body)

    span_type =
      case body["Call-Direction"] do
        "inbound" -> "DIAL_WAIT"
        _ -> "RINGING"
      end

    span = %{
      type: span_type,
      call_story_id: state.call_story_id,
      channel_id: channel_id,
      start_at: date_from_unix(body["Event-Date-Timestamp"]),
      current_party: user_from_body(body)
    }

    state =
      state
      |> put_open_span(span_type, channel_id, span)
      |> Map.update!(:channel_count, &(&1 + 1))

    _ = channel_id
    state
  end

  defp inbound_root?(body) do
    body["Unique-ID"] == body["Channel-Call-UUID"] &&
      body["Call-Direction"] == "inbound"
  end

  defp maybe_learn_outbound_caller_id(state, body, "outbound") do
    if is_nil(state.outbound_caller_id) and
         body["Unique-ID"] != body["Channel-Call-UUID"] and
         body["Call-Direction"] == "outbound" do
      %{state | outbound_caller_id: body["Caller-Caller-ID-Number"]}
    else
      state
    end
  end

  defp maybe_learn_outbound_caller_id(state, _body, _dir), do: state

  # ---------------------------------------------------------------------------
  # CHANNEL_ANSWER
  # ---------------------------------------------------------------------------

  defp handle_channel_answer(state, body) do
    state = learn_subdomain(state, body)
    channel = channel_id(body)

    ringing_type =
      case body["Call-Direction"] do
        "inbound" -> "DIAL_WAIT"
        "outbound" -> "RINGING"
        _ -> nil
      end

    state =
      if ringing_type do
        close_span(state, ringing_type, channel, body, %{})
      else
        state
      end

    current_party = user_from_body(body)

    on_call_span = %{
      type: "ON_CALL",
      call_story_id: state.call_story_id,
      channel_id: channel,
      start_at: date_from_unix(body["Event-Date-Timestamp"]),
      current_party: current_party
    }

    state = put_open_span(state, "ON_CALL", channel, on_call_span)

    broadcast_call_started(state, body, current_party)
    maybe_mark_member_on_call(current_party)

    state
  end

  defp broadcast_call_started(state, body, current_party) do
    display =
      case Repo.get(VoiceBot, current_party) do
        nil -> current_party
        bot -> "#{bot.name} (Voice Bot)"
      end

    LiveCalls.broadcast(body["variable_comcent_subdomain"], "call_started", %{
      call_story_id: state.call_story_id,
      start_at: date_from_unix(body["Event-Date-Timestamp"]),
      current_party: display,
      caller: body["Caller-Caller-ID-Number"],
      callee: body["Caller-Destination-Number"],
      direction: body["Call-Direction"]
    })
  end

  defp maybe_mark_member_on_call(current_party) do
    case parse_party_user_id(current_party) do
      {:ok, {subdomain, user_id}} ->
        case AgentSession.queue_member_answered(subdomain, user_id) do
          {:error, :not_found} ->
            Logger.warning(
              "Unable to mark member #{user_id} as On Call for subdomain #{subdomain}: user not found"
            )

          _ ->
            :ok
        end

      :error ->
        :ok
    end
  end

  # ---------------------------------------------------------------------------
  # CHANNEL_DESTROY
  # ---------------------------------------------------------------------------

  defp handle_channel_destroy(state, body) do
    state = learn_subdomain(state, body)
    channel = channel_id(body)

    ringing_type =
      case body["Call-Direction"] do
        "inbound" -> "DIAL_WAIT"
        _ -> "RINGING"
      end

    ringing_span = Map.get(state.open_spans, {ringing_type, channel})
    on_call_span = Map.get(state.open_spans, {"ON_CALL", channel})

    state =
      cond do
        ringing_span != nil ->
          handle_destroy_during_ringing(state, body, ringing_span, ringing_type, channel)

        on_call_span != nil ->
          handle_destroy_during_oncall(state, body, on_call_span, channel)

        true ->
          Logger.info(
            "CHANNEL_DESTROY for #{channel} had no open ringing/on_call span in call #{state.call_story_id}"
          )

          state
      end

    # Queue notification for customer hangup is now fired from
    # EventRouter directly (side-channel, off the RabbitMQ consumer
    # thread) so the scheduler learns immediately without waiting for
    # CallSession's mailbox to drain. Nothing to do here.
    state
  end

  defp handle_destroy_during_ringing(state, body, span, ringing_type, channel) do
    span =
      span
      |> Map.put(:end_at, date_from_unix(body["Event-Date-Timestamp"]))
      |> Map.put(:metadata, %{
        answer_state: body["Answer-State"],
        hangup_cause: body["Hangup-Cause"]
      })

    state =
      if body["Answer-State"] == "hangup" &&
           ((body["Call-Direction"] == "inbound" &&
               body["Hangup-Cause"] == "ORIGINATOR_CANCEL") or
              (body["Call-Direction"] == "outbound" &&
                 body["Hangup-Cause"] == "NO_USER_RESPONSE")) do
        %{state | hangup_party: span.current_party}
      else
        state
      end

    state =
      state
      |> close_open_span(ringing_type, channel, span)
      |> Map.update!(:channel_count, &max(&1 - 1, 0))

    if body["variable_comcent_dialed_by"] == "queue_member_dialer" do
      reschedule_presence_after_reject(body, span.current_party)
    end

    state
  end

  defp handle_destroy_during_oncall(state, body, span, channel) do
    span = Map.put(span, :end_at, date_from_unix(body["Event-Date-Timestamp"]))

    state =
      if body["variable_sip_hangup_disposition"] == "recv_bye" do
        %{state | hangup_party: span.current_party}
      else
        state
      end

    state =
      state
      |> close_open_span("ON_CALL", channel, span)
      |> Map.update!(:channel_count, &max(&1 - 1, 0))

    LiveCalls.broadcast(body["variable_comcent_subdomain"], "call_ended", %{
      call_story_id: state.call_story_id
    })

    reschedule_presence_after_oncall(body, span.current_party)
    state
  end

  defp reschedule_presence_after_reject(body, current_party) do
    case parse_party_user_id(current_party) do
      {:ok, {subdomain, user_id}} ->
        with queue_id when is_binary(queue_id) <- body["variable_comcent_dialed_by_queue_id"] do
          AgentSession.queue_member_rejected(subdomain, user_id, queue_id)
        else
          _ -> :ok
        end

      :error ->
        :ok
    end
  end

  defp reschedule_presence_after_oncall(body, current_party) do
    case parse_party_user_id(current_party) do
      {:ok, {subdomain, user_id}} ->
        if body["variable_comcent_dialed_by"] == "queue_member_dialer" do
          queue_id = body["variable_comcent_dialed_by_queue_id"]
          AgentSession.queue_member_call_ended(subdomain, user_id, queue_id)
        else
          OrgMember.revert_member_presence_from_on_call(subdomain, user_id)
        end

      :error ->
        :ok
    end
  end

  defp parse_party_user_id(current_party) do
    with {:ok, {subdomain, user}} <- parse_comcent_party(current_party),
         decoded_user <- URI.decode(user),
         user_id when is_binary(user_id) <-
           OrgMember.get_user_id_by_username_and_subdomain(decoded_user, subdomain) do
      {:ok, {subdomain, user_id}}
    else
      _ -> :error
    end
  end

  # Fire call_hung_up exactly when the customer (inbound-root) channel
  # destroys. The queue_id is looked up from the live QueuedCall process
  # (which owns that fact) rather than from a channel variable — earlier
  # attempts to latch variable_comcent_waiting_queue_id off the event
  # stream proved fragile (the dialplan's `export` action runs after
  # CHANNEL_CREATE, and the variable didn't reliably survive to later
  # events on the customer leg). If QueuedCall has already exited — i.e.
  # the call was answered and stopped — we have nothing to do.

  # ---------------------------------------------------------------------------
  # RECORD_START / RECORD_STOP / upload completed
  # ---------------------------------------------------------------------------

  defp handle_record_start(state, body) do
    state = learn_subdomain(state, body)
    channel = channel_id(body)
    metadata = recording_meta(body)
    key = "RECORDING_#{metadata.direction}"

    span = %{
      type: "RECORDING",
      call_story_id: state.call_story_id,
      channel_id: channel,
      start_at: date_from_unix(body["Event-Date-Timestamp"]),
      current_party: user_from_body(body),
      metadata: metadata
    }

    state
    |> put_open_span(key, channel, span)
    |> Map.update!(:record_count, &(&1 + 1))
  end

  defp handle_record_stop(state, body) do
    state = learn_subdomain(state, body)
    channel = channel_id(body)
    metadata = recording_meta(body)
    key = "RECORDING_#{metadata.direction}"

    case Map.get(state.open_spans, {key, channel}) do
      nil ->
        Logger.info(
          "RECORD_STOP without open recording span for channel #{channel} in call #{state.call_story_id}"
        )

        state

      span ->
        upload_meta = Map.get(state.recording_uploads, metadata.file_name, %{})
        merged_metadata = Map.merge(metadata, upload_meta)

        span =
          span
          |> Map.put(:end_at, date_from_unix(body["Event-Date-Timestamp"]))
          |> Map.put(:metadata, merged_metadata)

        state
        |> close_open_span(key, channel, span)
    end
  end

  defp handle_upload_completed(state, body) do
    channel = body["Channel-Id"]
    metadata = recording_meta(body)
    upload_meta = %{sha512: body["SHA-512"], fileSize: body["File-Size"]}

    Logger.info(
      "Recording upload completed for channel #{channel} in call #{state.call_story_id} dir #{metadata.direction}"
    )

    state = learn_subdomain(state, body)

    completed_spans =
      Enum.map(state.completed_spans, fn span ->
        if recording_span_matches?(span, metadata) do
          Map.put(
            span,
            :metadata,
            Map.merge(Map.get(span, :metadata, %{}) || %{}, upload_meta)
          )
        else
          span
        end
      end)

    %{
      state
      | completed_spans: completed_spans,
        recording_uploads: Map.put(state.recording_uploads, metadata.file_name, upload_meta),
        record_count: max(state.record_count - 1, 0)
    }
  end

  # ---------------------------------------------------------------------------
  # Span helpers
  # ---------------------------------------------------------------------------

  defp put_open_span(state, type, channel, span) do
    %{state | open_spans: Map.put(state.open_spans, {type, channel}, span)}
  end

  defp close_open_span(state, type, channel, span) do
    %{
      state
      | open_spans: Map.delete(state.open_spans, {type, channel}),
        completed_spans: state.completed_spans ++ [span]
    }
  end

  defp start_span(state, type, body) do
    channel = channel_id(body)

    span = %{
      type: type,
      call_story_id: state.call_story_id,
      channel_id: channel,
      start_at: date_from_unix(body["Event-Date-Timestamp"]),
      current_party: user_from_body(body)
    }

    put_open_span(state, type, channel, span)
  end

  defp close_span(state, type, channel, body, extra_metadata) do
    case Map.get(state.open_spans, {type, channel}) do
      nil ->
        state

      span ->
        span =
          span
          |> Map.put(:end_at, date_from_unix(body["Event-Date-Timestamp"]))
          |> merge_metadata(extra_metadata)

        close_open_span(state, type, channel, span)
    end
  end

  defp merge_metadata(span, metadata) when map_size(metadata) == 0, do: span

  defp merge_metadata(span, metadata) do
    Map.put(span, :metadata, Map.merge(Map.get(span, :metadata, %{}) || %{}, metadata))
  end

  defp recording_span_matches?(%{type: "RECORDING"} = span, recording_metadata) do
    metadata = Map.get(span, :metadata, %{}) || %{}

    metadata_value(metadata, "file_name", :file_name) == recording_metadata.file_name and
      metadata_value(metadata, "direction", :direction) == recording_metadata.direction
  end

  defp recording_span_matches?(_, _), do: false

  defp metadata_value(metadata, string_key, atom_key) do
    Map.get(metadata, string_key) || Map.get(metadata, atom_key)
  end

  # ---------------------------------------------------------------------------
  # Persistence + termination
  # ---------------------------------------------------------------------------

  defp maybe_finalize(state) do
    cond do
      state.channel_count > 0 or state.record_count > 0 ->
        {:noreply, state}

      state.persisted? ->
        {:noreply, state}

      true ->
        state = persist(state)
        Process.send_after(self(), :shutdown, @shutdown_grace)
        {:noreply, state}
    end
  end

  defp persist(%{story_initialized?: false} = state) do
    Logger.info("Call #{state.call_story_id} ending with no story record; not persisting")
    %{state | persisted?: true}
  end

  defp persist(state) do
    story_record = %{
      id: state.call_story_id,
      caller: state.caller,
      callee: state.callee,
      direction: state.direction,
      outbound_caller_id: state.outbound_caller_id,
      hangup_party: state.hangup_party,
      start_at: state.start_at
    }

    case Persistence.save(story_record, state.completed_spans, state.completed_events) do
      {:ok, _} ->
        trigger_new_call_story(state)
        %{state | persisted?: true}

      {:error, _} ->
        state
    end
  end

  defp trigger_new_call_story(state) do
    subdomain = state.subdomain || subdomain_from_state(state)

    if subdomain do
      Task.Supervisor.start_child(
        Comcent.TaskSupervisor,
        Comcent.NewCallStoryProcessor,
        :new_call_story_processor,
        [
          %{
            type: "NEW_CALL_STORY",
            data: %{subdomain: subdomain, call_story_id: state.call_story_id}
          }
        ]
      )
    end
  end

  defp subdomain_from_state(state) do
    Persistence.get_subdomain_from_story(%{
      caller: state.caller,
      callee: state.callee
    })
  end

  # ---------------------------------------------------------------------------
  # Dedup, idle timer, misc helpers
  # ---------------------------------------------------------------------------

  defp dedup(state, body) do
    uuid = body["Event-UUID"]

    cond do
      is_nil(uuid) ->
        {:fresh, state}

      MapSet.member?(state.seen_event_uuids, uuid) ->
        {:seen, state}

      true ->
        {set, queue} = track_seen(state.seen_event_uuids, state.seen_order, uuid)
        {:fresh, %{state | seen_event_uuids: set, seen_order: queue}}
    end
  end

  defp track_seen(set, queue, uuid) do
    set = MapSet.put(set, uuid)
    queue = :queue.in(uuid, queue)

    if MapSet.size(set) > @max_seen_events do
      {{:value, old}, queue} = :queue.out(queue)
      {MapSet.delete(set, old), queue}
    else
      {set, queue}
    end
  end

  defp arm_idle_timer(%{idle_timer_ref: ref} = state) do
    if ref, do: Process.cancel_timer(ref)
    %{state | idle_timer_ref: Process.send_after(self(), :idle_timeout, @idle_timeout)}
  end

  defp learn_subdomain(state, body) do
    case state.subdomain do
      nil ->
        case body["variable_comcent_subdomain"] do
          s when is_binary(s) and s != "" -> %{state | subdomain: s}
          _ -> state
        end

      _ ->
        state
    end
  end

  defp channel_id(body), do: body["Unique-ID"]

  defp user_from_body(body) do
    channel_name = body["Channel-Name"]

    cond do
      is_nil(channel_name) ->
        nil

      true ->
        parts = String.split(channel_name, "/")
        user = Enum.at(parts, 2) || ""

        user =
          if String.ends_with?(user, "invalid") do
            body["Channel-Presence-ID"] || user
          else
            user
          end

        sip_user_root_domain = Application.fetch_env!(:comcent, :sip_user_root_domain)

        cond do
          is_nil(user) ->
            nil

          String.ends_with?(user, sip_user_root_domain) ->
            user

          true ->
            [first | _] = String.split(user, "@")
            String.replace(first, "%2B", "+")
        end
    end
  end

  defp get_callee_from_body(body) do
    callee = body["Caller-Destination-Number"]

    with {:ok, phone_number} <- ExPhoneNumber.parse(callee, nil),
         true <- ExPhoneNumber.is_valid_number?(phone_number) do
      ExPhoneNumber.format(phone_number, :e164)
    else
      _ ->
        sip_address = body["variable_sip_req_uri"] || ""
        sip_user_root_domain = Application.fetch_env!(:comcent, :sip_user_root_domain)

        cond do
          String.ends_with?(sip_address, sip_user_root_domain) ->
            sip_address

          true ->
            Logger.info("Attention needed. Unusual callee #{inspect(callee)}")

            case String.split(sip_address, "@") do
              [head | _] -> head
              _ -> callee
            end
        end
    end
  end

  defp recording_meta(body) do
    file_path = body["Record-File-Path"] || ""
    parts = String.split(file_path, "/")
    file_name = List.last(parts) || ""
    direction = if String.contains?(file_name, "in"), do: "in", else: "both"
    %{file_name: file_name, direction: direction}
  end

  defp parse_comcent_party(nil), do: :error

  defp parse_comcent_party(party) when is_binary(party) do
    sip_user_root_domain = Application.fetch_env!(:comcent, :sip_user_root_domain)

    if String.contains?(party, sip_user_root_domain) do
      [user, domain] = String.split(party, "@")

      case String.split(domain, ".") do
        [subdomain | _] -> {:ok, {subdomain, user}}
        _ -> :error
      end
    else
      :error
    end
  end

  defp parse_comcent_party(_), do: :error

  def date_from_unix(nil), do: nil

  def date_from_unix(unix_timestamp) when is_binary(unix_timestamp) do
    date_from_unix(String.to_integer(unix_timestamp))
  end

  def date_from_unix(unix_timestamp) when is_integer(unix_timestamp) do
    case DateTime.from_unix(div(unix_timestamp, 1_000_000)) do
      {:ok, date} ->
        date

      err ->
        Logger.error("Error converting unix timestamp #{unix_timestamp}: #{inspect(err)}")
        nil
    end
  end
end
