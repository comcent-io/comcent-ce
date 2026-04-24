import Config

# config/runtime.exs is executed for all environments, including
# during releases. It is executed after compilation and before the
# system starts, so it is typically used to load production configuration
# and secrets from environment variables or elsewhere. Do not define
# any compile-time configuration in here, as it won't be applied.
# The block below contains prod specific runtime configuration.

# Sentry Configuration
if sentry_dsn = System.get_env("SERVER_SENTRY_DSN") do
  config :sentry,
    dsn: sentry_dsn
end

# Deepgram API configuration
deepgram_api_key =
  System.get_env("DEEPGRAM_API_KEY") ||
    raise """
    environment variable DEEPGRAM_API_KEY is missing.
    You can get one from https://console.deepgram.com/
    """

config :comcent, :deepgram, api_key: deepgram_api_key

# AWS Configuration
aws_access_key_id =
  System.get_env("AWS_ACCESS_KEY_ID", "")

aws_secret_access_key =
  System.get_env("AWS_SECRET_ACCESS_KEY", "")

aws_region = System.get_env("BUCKET_REGION", "us-east-1")
s3_endpoint_url = System.get_env("S3_ENDPOINT_URL")

s3_config =
  case s3_endpoint_url do
    nil ->
      []

    "" ->
      []

    url ->
      uri = URI.parse(url)

      [
        scheme: "#{uri.scheme}://",
        host: uri.host,
        port: uri.port
      ]
  end

config :ex_aws,
  debug_requests: true,
  json_codec: Jason,
  access_key_id: aws_access_key_id,
  secret_access_key: aws_secret_access_key,
  region: aws_region,
  service: :s3,
  http_client: ExAws.Request.Hackney

config :ex_aws, :s3, s3_config

# Storage bucket configuration
storage_bucket_name =
  System.get_env("STORAGE_BUCKET_NAME") ||
    raise """
    environment variable STORAGE_BUCKET_NAME is missing.
    """

config :comcent, :storage, bucket_name: storage_bucket_name

# OpenAI API configuration
openai_api_key =
  System.get_env("OPENAI_API_KEY") ||
    raise """
    environment variable OPENAI_API_KEY is missing.
    You can get one from https://platform.openai.com/account/api-keys
    """

config :comcent, :openai, api_key: openai_api_key

# ## Using releases
#
# If you use `mix release`, you need to explicitly enable the server
# by passing the PHX_SERVER=true when you start it:
#
#     PHX_SERVER=true bin/comcent start
#
# Alternatively, you can use `mix phx.gen.release` to generate a `bin/server`
# script that automatically sets the env var above.
if System.get_env("PHX_SERVER") do
  config :comcent, ComcentWeb.Endpoint, server: true
end

if config_env() == :prod do
  database_url =
    System.get_env("DATABASE_URL") ||
      raise """
      environment variable DATABASE_URL is missing.
      For example: ecto://USER:PASS@HOST/DATABASE
      """

  maybe_ipv6 = if System.get_env("ECTO_IPV6") in ~w(true 1), do: [:inet6], else: []

  config :comcent, Comcent.Repo,
    # ssl: true,
    url: database_url,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10"),
    socket_options: maybe_ipv6,
    ssl: System.get_env("POSTGRES_SSL_ENABLED", "true") |> String.downcase() == "true",
    ssl_opts: [
      verify: :verify_none
    ],
    types: Comcent.PostgrexTypes

  # The secret key base is used to sign/encrypt cookies and other secrets.
  # A default value is used in config/dev.exs and config/test.exs but you
  # want to use a different value for prod and you most likely don't want
  # to check this value into version control, so we use an environment
  # variable instead.
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  host = System.get_env("PHX_HOST") || "example.com"
  port = String.to_integer(System.get_env("PORT") || "4000")

  config :comcent, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  config :comcent, ComcentWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [
      # Enable IPv6 and bind on all interfaces.
      # Set it to  {0, 0, 0, 0, 0, 0, 0, 1} for local network only access.
      # See the documentation on https://hexdocs.pm/bandit/Bandit.html#t:options/0
      # for details about using IPv6 vs IPv4 and loopback vs public addresses.
      ip: {0, 0, 0, 0, 0, 0, 0, 0},
      port: port
    ],
    secret_key_base: secret_key_base

  # ## SSL Support
  #
  # To get SSL working, you will need to add the `https` key
  # to your endpoint configuration:
  #
  #     config :comcent, ComcentWeb.Endpoint,
  #       https: [
  #         ...,
  #         port: 443,
  #         cipher_suite: :strong,
  #         keyfile: System.get_env("SOME_APP_SSL_KEY_PATH"),
  #         certfile: System.get_env("SOME_APP_SSL_CERT_PATH")
  #       ]
  #
  # The `cipher_suite` is set to `:strong` to support only the
  # latest and more secure SSL ciphers. This means old browsers
  # and clients may not be supported. You can set it to
  # `:compatible` for wider support.
  #
  # `:keyfile` and `:certfile` expect an absolute path to the key
  # and cert in disk or a relative path inside priv, for example
  # "priv/ssl/server.key". For all supported SSL configuration
  # options, see https://hexdocs.pm/plug/Plug.SSL.html#configure/1
  #
  # We also recommend setting `force_ssl` in your config/prod.exs,
  # ensuring no data is ever sent via http, always redirecting to https:
  #
  #     config :comcent, ComcentWeb.Endpoint,
  #       force_ssl: [hsts: true]
  #
  # Check `Plug.SSL` for all available options in `force_ssl`.

  # LibCluster Configuration
  cluster_strategy = System.get_env("CLUSTER_STRATEGY", "gossip")

  libcluster_config =
    case cluster_strategy do
      "kubernetes" ->
        [
          k8s: [
            strategy: Cluster.Strategy.Kubernetes,
            config: [
              kubernetes_selector: System.get_env("K8S_SELECTOR", "app=comcent"),
              kubernetes_node_basename: System.get_env("K8S_NODE_BASENAME", "comcent")
            ]
          ]
        ]

      "gossip" ->
        [
          gossip: [
            strategy: Cluster.Strategy.Gossip
          ]
        ]

      other ->
        IO.puts("Warning: Unknown cluster strategy: #{other}, defaulting to gossip")

        [
          gossip: [
            strategy: Cluster.Strategy.Gossip
          ]
        ]
    end

  config :libcluster, topologies: libcluster_config
end

redis_url = System.get_env("REDIS_URL")

if redis_url do
  config :comcent, :redis, Redix.URI.to_start_options(redis_url)
else
  IO.puts("No Redis URL found")
end

# Kamailio RPC Configuration
kamailio_ip =
  System.get_env("KAMAILIO_IP") ||
    raise """
    environment variable KAMAILIO_IP is missing.
    For example: 192.168.1.100
    """

rpc_api_token =
  System.get_env("RPC_API_TOKEN") ||
    raise """
    environment variable RPC_API_TOKEN is missing.
    """

config :comcent, :kamailio,
  ip: kamailio_ip,
  rpc_api_token: rpc_api_token

# RabbitMQ Configuration
rabbitmq_url =
  System.get_env("RABBITMQ_URL") ||
    raise """
    environment variable RABBITMQ_URL is missing.
    For example: amqp://user:pass@localhost:5672
    """

config :comcent, :rabbitmq, url: rabbitmq_url

# Authentication Configuration
password_enabled =
  System.get_env("AUTH_PASSWORD_ENABLED", "true")
  |> String.downcase()
  |> then(&(&1 in ["true", "1", "yes"]))

oidc_providers =
  System.get_env("AUTH_OIDC_PROVIDERS_JSON", "{}")
  |> Jason.decode!()

config :comcent, :auth,
  password_enabled: password_enabled,
  oidc_providers: oidc_providers

# Email Configuration
smtp_url =
  System.get_env("SMTP_URL") ||
    raise """
    environment variable SMTP_URL is missing.
    For example: smtp://username:password@mail.example.com:587
    """

smtp_uri = URI.parse(smtp_url)

unless smtp_uri.scheme in ["smtp", "smtps"] and smtp_uri.host do
  raise """
  environment variable SMTP_URL is invalid.
  Expected format: smtp://username:password@mail.example.com:587
  """
end

smtp_username =
  if smtp_uri.userinfo,
    do: URI.decode_www_form(smtp_uri.userinfo |> String.split(":") |> hd()),
    else: ""

smtp_password =
  case smtp_uri.userinfo do
    nil ->
      ""

    userinfo ->
      case String.split(userinfo, ":", parts: 2) do
        [_username, password] -> URI.decode_www_form(password)
        [_username] -> ""
      end
  end

smtp_port =
  cond do
    is_integer(smtp_uri.port) ->
      smtp_uri.port

    smtp_uri.scheme == "smtps" ->
      465

    true ->
      587
  end

config :comcent, Comcent.Mailer,
  adapter: Swoosh.Adapters.SMTP,
  relay: smtp_uri.host,
  port: smtp_port,
  username: smtp_username,
  password: smtp_password,
  ssl: smtp_uri.scheme == "smtps",
  tls: if(smtp_uri.scheme == "smtps", do: :never, else: :if_available),
  auth: :if_available,
  retries: 2,
  no_mx_lookups: false

config :swoosh, :api_client, false

# Email Configuration
source_email =
  System.get_env("SOURCE_EMAIL") ||
    raise """
    environment variable SOURCE_EMAIL is missing.
    """

config :comcent, Comcent.Mailer, source_email: source_email

# Public Root URL Configuration
public_root_url =
  System.get_env("PUBLIC_ROOT_URL") ||
    raise """
    environment variable PUBLIC_ROOT_URL is missing.
    """

config :comcent, :public_root_url, public_root_url

# SIP Domain Configuration
# Used for SIP address formatting, domain detection in call routing,
# and Registry keys. Self-hosters set this to their own domain; defaults
# kept unset so missing config fails loudly at boot rather than silently
# using a wrong domain.
sip_domain =
  System.get_env("SIP_DOMAIN") ||
    raise """
    environment variable SIP_DOMAIN is missing.
    Example: SIP_DOMAIN=sip.example.com
    """

config :comcent, :sip_domain, sip_domain

# App Base URL — used by email templates for clickable links back to the web app.
# Fallback derives from PUBLIC_APP_BASE_URL (which is shared with the Svelte
# frontend); either one works.
app_base_url =
  System.get_env("APP_BASE_URL") ||
    System.get_env("PUBLIC_APP_BASE_URL") ||
    "https://app.example.com"

config :comcent, :app_base_url, app_base_url
