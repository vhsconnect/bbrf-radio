import Config

config :bbrf, ecto_repos: [BBRF.Repo]

config :logger, :console,
  format: "$time [$level] $metadata$message\n",
  metadata: [:job, :run],
  level: :info

if config_env() == :test do
  import_config "test.exs"
end
