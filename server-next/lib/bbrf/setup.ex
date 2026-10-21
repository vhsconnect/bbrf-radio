defmodule BBRF.Setup do
  @moduledoc """
  One-time database setup at boot, started as a supervisor child before
  the schedulers so they always find a migrated, configured database:

  - apply pending migrations
  - import favorites from the bbrf-radio node server's storage.json when
    FAVORITES_IMPORT_FILE points at an existing file and the favorites table is empty
  - enable WAL (persistent in the database file, covers every future
    connection)
  - enable `auto_vacuum=INCREMENTAL` so the retention pruner can return
    freed pages to the OS via `PRAGMA incremental_vacuum`. SQLite only
    applies the pragma during a VACUUM, and the pragma + VACUUM must
    share a connection - hence `Repo.checkout/1`. The guard makes it a
    one-time cost: free on a fresh database, a single rewrite on an
    existing one.
  """

  use GenServer
  require Logger
  alias BBRF.Repo

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    configure()
    migrate()
    import_favorites()
    # nothing to supervise afterwards - child only exists for ordering
    :ignore
  end

  defp configure do
    Repo.query!("PRAGMA journal_mode=WAL")

    %{rows: [[auto_vacuum]]} = Repo.query!("PRAGMA auto_vacuum")

    unless auto_vacuum == 2 do
      # auto_vacuum only takes effect on an empty database or after a
      # VACUUM; fresh boots happen before any table exists, so the
      # pragma alone is enough and the exclusive VACUUM (which races
      # the pool's connection setup with a "database is locked") is
      # skipped. On an existing database the pragma + VACUUM must share
      # a connection - hence Repo.checkout/1.
      Repo.checkout(fn ->
        Repo.query!("PRAGMA auto_vacuum=INCREMENTAL")

        if tables_present?() do
          Repo.query!("VACUUM")
        end
      end)
    end
  end

  defp tables_present? do
    %{rows: [[count]]} = Repo.query!("SELECT COUNT(*) FROM sqlite_master")
    count > 0
  end

  defp migrate do
    Ecto.Migrator.run(Repo, :up, all: true)
  end

  defp import_favorites do
    path = System.get_env("FAVORITES_IMPORT_FILE")

    if path && File.regular?(path) && BBRF.Favorites.count() == 0 do
      count = BBRF.Favorites.import_json(path)
      Logger.info("favorites: imported #{count} from #{path}")
    end

    :ok
  end
end
