defmodule Comcent.CallFixtures do
  @moduledoc """
  Live calls for the Live Calls dashboard tests.

  Each helper drives the FreeSWITCH event the event router would, through a
  real `Comcent.CallSession`, and returns once the call process has handled
  it, rather than writing to the registry behind the session's back.
  """

  alias Comcent.CallSession
  alias Comcent.CallSession.Registry

  def subdomain, do: "acme-#{unique()}"

  @doc """
  Puts one call up for `subdomain` and returns its call story id.
  """
  def start_call(subdomain) do
    call_story_id = "call-#{unique()}"
    CallSession.start_and_dispatch(call_story_id, channel_create(call_story_id, subdomain))
    _ = :sys.get_state(Registry.whereis(call_story_id))
    call_story_id
  end

  @doc """
  Adds another leg to a call that is already up and returns its channel id.
  """
  def add_leg(call_story_id, subdomain) do
    channel = Ecto.UUID.generate()

    dispatch(call_story_id, %{
      channel_create(call_story_id, subdomain)
      | "Unique-ID" => channel
    })

    channel
  end

  @doc """
  Answers a leg of the call (the first one by default), which puts the call on
  the Live Calls dashboard.
  """
  def answer(call_story_id, subdomain, channel \\ nil) do
    dispatch(call_story_id, %{
      "Event-Name" => "CHANNEL_ANSWER",
      "Event-Date-Timestamp" => Integer.to_string(System.system_time(:microsecond)),
      "Unique-ID" => channel || call_story_id,
      "Channel-Call-UUID" => call_story_id,
      "Call-Direction" => "inbound",
      "Channel-Name" => "sofia/internal/1001@#{subdomain}",
      "Caller-Caller-ID-Number" => "1001",
      "Caller-Destination-Number" => "+13478266412",
      "variable_comcent_subdomain" => subdomain
    })
  end

  @doc """
  Hangs up an answered leg, which broadcasts `call_ended`.
  """
  def hang_up(call_story_id, subdomain, channel) do
    dispatch(call_story_id, %{
      "Event-Name" => "CHANNEL_DESTROY",
      "Event-Date-Timestamp" => Integer.to_string(System.system_time(:microsecond)),
      "Unique-ID" => channel,
      "Channel-Call-UUID" => call_story_id,
      "Call-Direction" => "inbound",
      "variable_comcent_subdomain" => subdomain
    })
  end

  def stop_call(call_story_id) do
    case Registry.whereis(call_story_id) do
      nil ->
        :ok

      pid ->
        ref = Process.monitor(pid)
        Horde.DynamicSupervisor.terminate_child(Comcent.DynamicSupervisor, pid)

        receive do
          {:DOWN, ^ref, :process, ^pid, _reason} -> :ok
        after
          1_000 -> :ok
        end
    end
  end

  # Returns once the call process has handled the event.
  defp dispatch(call_story_id, body) do
    CallSession.dispatch(call_story_id, body)
    _ = :sys.get_state(Registry.whereis(call_story_id))
    :ok
  end

  defp channel_create(call_story_id, subdomain) do
    %{
      "Event-Name" => "CHANNEL_CREATE",
      "Event-UUID" => Ecto.UUID.generate(),
      "Event-Date-Timestamp" => Integer.to_string(System.system_time(:microsecond)),
      "Unique-ID" => call_story_id,
      "Channel-Call-UUID" => call_story_id,
      "Call-Direction" => "inbound",
      "Caller-Context" => "default",
      "Channel-Name" => "sofia/internal/1001@#{subdomain}",
      "Caller-Destination-Number" => "+13478266412"
    }
  end

  defp unique, do: System.unique_integer([:positive])
end
