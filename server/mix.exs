defmodule Comcent.MixProject do
  use Mix.Project

  def project do
    [
      app: :comcent,
      version: "0.1.0",
      elixir: "~> 1.14",
      elixirc_paths: elixirc_paths(Mix.env()),
      elixirc_options: [warnings_as_errors: false],
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps()
    ]
  end

  # Configuration for the OTP application.
  #
  # Type `mix help compile.app` for more information.
  def application do
    [
      mod: {Comcent.Application, []},
      extra_applications: [:logger, :runtime_tools]
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Specifies your project dependencies.
  #
  # Type `mix help deps` for examples and options.
  defp deps do
    [
      {:phoenix, "~> 1.7.20"},
      {:phoenix_ecto, "~> 4.5"},
      {:ecto_sql, "~> 3.10"},
      {:postgrex, ">= 0.0.0"},
      {:phoenix_live_dashboard, "~> 0.8.3"},
      {:swoosh, "~> 1.18"},
      {:gen_smtp, "~> 1.3.0"},
      {:finch, "~> 0.19"},
      {:telemetry_metrics, "~> 1.0"},
      {:telemetry_poller, "~> 1.0"},
      {:gettext, "~> 0.26"},
      {:jason, "~> 1.2"},
      {:dns_cluster, "~> 0.1.1"},
      {:bandit, "~> 1.5"},
      {:ex_phone_number, "~> 0.4.8"},
      {:ex_aws, "~> 2.4"},
      {:ex_aws_s3, "~> 2.4"},
      {:hackney, "~> 1.23"},
      {:tzdata, "~> 1.1"},
      {:redix, "~> 1.1"},
      {:horde, "~> 0.8.5"},
      {:libcluster, "~> 3.3"},
      {:switchx, "~> 1.0.1"},
      {:joken, "~> 2.5"},
      {:httpoison, "~> 2.0"},
      {:jose, "~> 1.11"},
      {:quantum, "~> 3.5.3"},
      {:envy, "~> 1.1.1"},
      {:logger_json, "~> 7.0.1"},
      {:mock, "~> 0.3.0", only: [:test]},
      {:amqp, "~> 4.0"},
      {:recase, "~> 0.8.1"},
      {:text_chunker, "~> 0.4.0"},
      {:pgvector, "~> 0.3.0"},
      {:sweet_xml, "~> 0.7"},
      {:tailwind, "~> 0.3.1"},
      {:esbuild, "~> 0.8"},
      {:sentry, "~> 10.0"},
      {:bcrypt_elixir, "~> 3.2"}
    ]
  end

  # Aliases are shortcuts or tasks specific to the current project.
  # For example, to install project dependencies and perform other setup tasks, run:
  #
  #     $ mix setup
  #
  # See the documentation for `Mix` for more info on aliases.
  defp aliases do
    [
      setup: ["deps.get", "ecto.setup"],
      "ecto.setup": ["ecto.create", "ecto.migrate", "run priv/repo/seeds.exs"],
      "ecto.reset": ["ecto.drop", "ecto.setup"],
      test: ["ecto.create --quiet", "ecto.migrate --quiet", "test"],
      "assets.build": ["tailwind default --minify", "esbuild default --minify"],
      "assets.watch": ["tailwind default --watch", "esbuild default --watch"]
    ]
  end
end
