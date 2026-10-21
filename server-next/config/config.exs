import Config

config :bbrf, ecto_repos: [BBRF.Repo]

config :logger, :console,
  format: "$time [$level] $message\n",
  level: :info

if config_env() == :test do
  import_config "test.exs"
end
