# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :comcent,
  ecto_repos: [Comcent.Repo],
  generators: [timestamp_type: :utc_datetime]

# Configure Elixir to use tzdata for time zone data
config :elixir, :time_zone_database, Tzdata.TimeZoneDatabase

# Configure ExAws
config :ex_aws,
  debug_requests: true,
  json_codec: Jason

# Configures the endpoint
config :comcent, ComcentWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [json: ComcentWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Comcent.PubSub,
  live_view: [signing_salt: "OHF5I7ll"]

# Configures the mailer
#
# By default it uses the "Local" adapter which stores the emails
# locally. You can see the emails in your browser, at "/dev/mailbox".
#
# For production it's recommended to configure a different adapter
# at the `config/runtime.exs`.
config :comcent, Comcent.Mailer, adapter: Swoosh.Adapters.Local

# Configures Elixir's Logger
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

config :tailwind, :version, "4.0.9"

config :esbuild, :version, "0.25.0"

# Sentry Configuration
config :sentry,
  environment_name: config_env(),
  enable_source_code_context: true,
  root_source_code_paths: [File.cwd!()]

# Add Sentry as a Logger handler
config :logger,
  backends: [:console]

config :logger, :sentry, capture_log_messages: true

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
