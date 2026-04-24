import Config

# Configures Swoosh API client support used by runtime mailer adapters.

# Configures Swoosh API Client
config :swoosh, :api_client, Swoosh.ApiClient.Hackney

# Configure logger for production with JSON formatting
config :logger, :default_handler,
  level: :info,
  formatter: {
    LoggerJSON.Formatters.Basic,
    metadata: [
      :request_id,
      :application,
      :module,
      :function,
      :mfa,
      :line,
      :pid,
      :crash_reason,
      :trace_id,
      :span_id
    ]
  },
  compile_time_purge_matching: [
    [level_lower_than: :info]
  ]

# Runtime production configuration, including reading
# of environment variables, is done on config/runtime.exs.

# Configure the scheduler for production
config :comcent, Comcent.Schedular,
  jobs: [
    check_wallet_balance: [
      schedule: "0 9 * * *",
      task: {Comcent.EmailHandler, :check_and_send_alerts, []},
      run_strategy: Quantum.RunStrategy.Local
    ],
    monthly_billing: [
      # Run at midnight on the first day of each month
      schedule: "0 0 1 * *",
      task: {Comcent.MonthlyBilling, :process_monthly_billing, []},
      run_strategy: Quantum.RunStrategy.Local
    ],
    daily_summary: [
      # Run every minute to check for organizations that need daily summaries
      schedule: "* * * * *",
      task: {Comcent.DailySummary, :generate_daily_summaries, []},
      run_strategy: Quantum.RunStrategy.Local
    ],
    hourly_job: [
      # Run every hour at minute 0
      schedule: "0 * * * *",
      task: {Comcent, :hourly_task, []},
      run_strategy: Quantum.RunStrategy.Local
    ]
  ]
