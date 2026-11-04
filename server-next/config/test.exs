import Config

config :bbrf, BBRF.Repo,
  database: ":memory:",
  pool_size: 1

config :bbrf, api: false, ingester: false

config :logger, level: :warning
