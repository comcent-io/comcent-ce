defmodule Comcent.RabbitMQ do
  @moduledoc """
  Cluster-wide singleton RabbitMQ consumer for FreeSWITCH events.

  Only one process runs in the cluster at any time (via `Horde.Registry`).
  Deliveries are decoded and dispatched to a per-call `GenServer` through
  `Comcent.Call.EventRouter`, which owns event ordering and lifecycle. Acks
  always happen after routing — the call process is the idempotency boundary,
  and redelivered events are deduped on `Event-UUID` there.
  """

  require Logger
  use GenServer
  use AMQP

  alias Comcent.Call.EventRouter

  @tap_exchange "TAP.Events"
  @tap_queue "tap_events_queue"

  @doc """
  Via-tuple for the cluster-wide singleton consumer.
  """
  def via, do: {:via, Horde.Registry, {Comcent.Registry, :rabbitmq_consumer}}

  def start_link(_opts) do
    case GenServer.start_link(__MODULE__, %{}, name: via()) do
      {:ok, pid} ->
        Logger.info("RabbitMQ singleton consumer started on #{inspect(Node.self())}")
        {:ok, pid}

      {:error, {:already_started, _pid}} ->
        Logger.info("RabbitMQ singleton consumer already running on another node")
        :ignore
    end
  end

  def child_spec(_opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [[]]},
      restart: :transient,
      type: :worker
    }
  end

  @impl true
  def init(state) do
    {:ok, state, {:continue, :connect_to_rabbitmq}}
  end

  @impl true
  def handle_continue(:connect_to_rabbitmq, state) do
    Process.sleep(3000)
    rabbitmq_config = Application.get_env(:comcent, :rabbitmq)
    rabbitmq_url = rabbitmq_config[:url]
    consumer_opts = [ignore_consumer_down: [:normal, :shutdown]]

    with {:ok, conn} <- Connection.open(rabbitmq_url),
         {:ok, chan} <- Channel.open(conn, {AMQP.DirectConsumer, {self(), consumer_opts}}) do
      setup_consumer_queue(chan)

      {:noreply, state |> Map.put(:conn, conn) |> Map.put(:channel, chan)}
    else
      {:error, reason} ->
        Logger.error("Failed to connect to RabbitMQ: #{inspect(reason)}")
        {:stop, reason, state}
    end
  end

  @impl true
  def handle_info({:basic_consume_ok, %{consumer_tag: _}}, state), do: {:noreply, state}

  @impl true
  def handle_info({:basic_cancel, %{consumer_tag: _}}, state), do: {:stop, :normal, state}

  @impl true
  def handle_info({:basic_cancel_ok, %{consumer_tag: _}}, state), do: {:noreply, state}

  @impl true
  def handle_info(
        {:basic_deliver, payload, %{delivery_tag: tag, redelivered: redelivered}},
        %{channel: channel} = state
      ) do
    try do
      EventRouter.handle_payload(payload)
      :ok = Basic.ack(channel, tag)
    rescue
      error ->
        stacktrace =
          case Process.info(self(), :current_stacktrace) do
            {_, trace} when is_list(trace) -> trace
            _ -> []
          end

        sample =
          if is_binary(payload), do: String.slice(payload, 0, 500), else: inspect(payload)

        Logger.error("""
        Error routing RabbitMQ message: #{inspect(error)}
        Payload sample: #{sample}
        Stacktrace:
        #{Exception.format_stacktrace(stacktrace)}
        """)

        :ok = Basic.reject(channel, tag, requeue: not redelivered)
    end

    {:noreply, state}
  end

  defp setup_consumer_queue(chan) do
    :ok = Exchange.declare(chan, @tap_exchange, :topic, durable: true)
    {:ok, _} = Queue.declare(chan, @tap_queue, durable: true)
    :ok = Queue.bind(chan, @tap_queue, @tap_exchange, routing_key: "#")
    :ok = Basic.qos(chan, prefetch_count: 10)
    {:ok, _tag} = Basic.consume(chan, @tap_queue)
  end
end
