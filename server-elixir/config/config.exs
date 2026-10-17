import Config

config :radio_analyzer, ecto_repos: [RadioAnalyzer.Repo]

config :logger, :console,
  format: "$time [$level] $message\n",
  level: :info

if config_env() == :test do
  import_config "test.exs"
end
