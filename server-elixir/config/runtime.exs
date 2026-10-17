import Config

# The database sits in the working directory unless RADIO_ANALYZER_DB says
# otherwise (the container points it at a volume).
if config_env() != :test do
  db_path = System.get_env("RADIO_ANALYZER_DB", "data/radio-analyzer-elixir.db")

  File.mkdir_p(Path.dirname(Path.expand(db_path)))

  config :radio_analyzer, RadioAnalyzer.Repo,
    database: db_path,
    pool_size: String.to_integer(System.get_env("DB_POOL_SIZE", "5")),
    # WAL lets the scheduler jobs read/write concurrently instead of
    # whole-file locking (same pragmas the clojure original sets at boot);
    # busy_timeout gives colliding write transactions room to wait
    journal_mode: :wal,
    synchronous: :normal,
    busy_timeout: 5_000
end
