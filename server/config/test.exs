import Config

# Test defaults for env-driven config — runtime.exs is also loaded in test
# mode but needs these to be set either via env vars or (preferred for CI)
# via this file so tests don't depend on the developer's .env.
config :comcent, :sip_domain, System.get_env("SIP_DOMAIN", "example.com")
config :comcent, :app_base_url, System.get_env("APP_BASE_URL", "https://app.example.com")

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :comcent, Comcent.Repo,
  username: System.get_env("POSTGRES_USER", "postgres"),
  password: System.get_env("POSTGRES_PASSWORD", "password"),
  hostname: System.get_env("POSTGRES_HOST", "localhost"),
  port: String.to_integer(System.get_env("POSTGRES_PORT", "5432")),
  database: System.get_env("POSTGRES_DB", "comcent_test#{System.get_env("MIX_TEST_PARTITION")}"),
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2,
  types: Comcent.PostgrexTypes

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :comcent, ComcentWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "S/iZNY3dJ3bl7QwCltQDASpiQ8EoKMX6ii81PxcmE4fkQTKrXlW5yajZGl+umv06",
  server: false

# In test we don't send emails
config :comcent, Comcent.Mailer, adapter: Swoosh.Adapters.Test

# Disable swoosh api client as it is only required for production adapters
config :swoosh, :api_client, false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Configure libcluster for test environment
config :libcluster,
  topologies: [
    test: [
      strategy: Cluster.Strategy.Gossip
    ]
  ]

# Configure the scheduler for test environment
config :comcent, Comcent.Schedular, jobs: []
