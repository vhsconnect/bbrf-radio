import Config

config :radio_analyzer, RadioAnalyzer.Repo,
  database: ":memory:",
  pool_size: 1

config :radio_analyzer, web: false

config :logger, level: :warning
