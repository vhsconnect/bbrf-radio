defmodule BBRF.Journal do
  @moduledoc """
  Puts the database file in the configured journal mode before the pool
  starts. The mode is stored in the file, and leaving the switch to the
  pool makes every connection try it at once: Exqlite sets the mode
  before the busy timeout, so a conversion (leaving WAL needs exclusive
  access) fails with "database is locked" on all but one connection.
  Done here once, with a timeout, the pool's own pragma finds the mode
  already set and does nothing.
  """

  alias Exqlite.Sqlite3

  @busy_timeout_ms 30_000

  @spec ensure!() :: :ok
  def ensure! do
    config = Application.get_env(:bbrf, BBRF.Repo, [])

    case {config[:database], config[:journal_mode]} do
      {path, mode} when is_binary(path) and path != ":memory:" and mode != nil ->
        set!(path, mode)

      _no_file_or_no_mode ->
        :ok
    end
  end

  defp set!(path, mode) do
    {:ok, conn} = Sqlite3.open(path)

    try do
      :ok = Sqlite3.set_busy_timeout(conn, @busy_timeout_ms)
      :ok = Sqlite3.execute(conn, "PRAGMA journal_mode=#{mode}")
    after
      Sqlite3.close(conn)
    end

    :ok
  end
end
