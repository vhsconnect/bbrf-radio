import Config

# The database sits in the working directory unless BBRF_DB says
# otherwise (the container points it at a volume).
if config_env() != :test do
  config :logger, level: String.to_existing_atom(System.get_env("LOG_LEVEL", "info"))

  db_path = System.get_env("BBRF_DB", "data/bbrf.sqlite")

  journal_mode =
    case System.get_env("JOURNAL_MODE", "delete") do
      "delete" -> :delete
      "wal" -> :wal
      other -> raise ArgumentError, "JOURNAL_MODE must be delete or wal, got #{inspect(other)}"
    end

  role =
    case System.get_env("BBRF_ROLE", "all") do
      "hub" -> :hub
      "ingest" -> :ingest
      "all" -> :all
      other -> raise ArgumentError, "BBRF_ROLE must be hub, ingest or all, got #{inspect(other)}"
    end

  config :bbrf, role: role

  File.mkdir_p(Path.dirname(Path.expand(db_path)))

  config :bbrf, BBRF.Repo,
    database: db_path,
    pool_size: String.to_integer(System.get_env("DB_POOL_SIZE", "5")),
    # busy_timeout gives colliding transactions room to wait for the file lock
    journal_mode: journal_mode,
    synchronous: :normal,
    busy_timeout: 5_000,
    # page cache per connection, in KiB when negative. ecto_sqlite3 defaults
    # to 64 MB, and every pooled connection that scans the stations table
    # fills its own copy of pages the OS already caches for the file
    cache_size: -String.to_integer(System.get_env("DB_CACHE_KB", "8000"))
end
