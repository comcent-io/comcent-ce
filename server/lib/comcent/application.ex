defmodule Comcent.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application
  require Logger

  @impl true
  def start(_type, _args) do
    # Attach Sentry logger handler for capturing logged errors
    :logger.add_handler(:sentry_handler, Sentry.LoggerHandler, %{
      config: %{metadata: [:file, :line]}
    })

    children = [
      ComcentWeb.Telemetry,
      Comcent.Repo,
      {DNSCluster, query: Application.get_env(:comcent, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Comcent.PubSub},
      # Start the Finch HTTP client for sending emails
      {Finch, name: Comcent.Finch},
      # Start Redis client
      Comcent.RedisClient,
      # Start to serve requests, typically the last entry
      ComcentWeb.Endpoint,
      {Task.Supervisor, name: Comcent.TaskSupervisor},
      # Start libcluster for node discovery
      {Cluster.Supervisor,
       [Application.get_env(:libcluster, :topologies), [name: Comcent.ClusterSupervisor]]},
      {Horde.Registry, [name: Comcent.Registry, keys: :unique, members: :auto]},
      {Horde.DynamicSupervisor,
       [name: Comcent.DynamicSupervisor, strategy: :one_for_one, members: :auto]},
      {Horde.DynamicSupervisor,
       [name: Comcent.QueueDynamicSupervisor, strategy: :one_for_one, members: :auto]},
      Comcent.RedisListener
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Comcent.Supervisor]
    {:ok, sup} = Supervisor.start_link(children, opts)

    # After the supervisor has started, start queue manager processes
    Task.start(fn ->
      # Give the database connection time to fully establish
      Process.sleep(3000)
      Comcent.CountryStateSeeder.seed_if_needed()
    end)

    Task.start(fn ->
      # Give the database connection time to fully establish
      Process.sleep(3000)
      Comcent.Queue.AgentSession.start_all_active_sessions()
    end)

    Task.start(fn ->
      # Give the database connection time to fully establish
      Process.sleep(3000)
      Comcent.QueueManager.start_queue_manager()
    end)

    Task.start(fn ->
      # Give the database connection time to fully establish
      Process.sleep(3000)
      Logger.info("Starting Quantum scheduler")

      Horde.DynamicSupervisor.start_child(
        Comcent.DynamicSupervisor,
        Comcent.Schedular
      )
    end)

    Task.start(fn ->
      # Wait for Horde to settle before trying to register the cluster-wide
      # singleton RabbitMQ consumer — start_link returns :ignore on any node
      # where it's already running.
      Process.sleep(3000)

      Horde.DynamicSupervisor.start_child(
        Comcent.DynamicSupervisor,
        Comcent.RabbitMQ
      )
    end)

    Logger.info("The node is #{Node.self()}")

    {:ok, sup}
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    ComcentWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
