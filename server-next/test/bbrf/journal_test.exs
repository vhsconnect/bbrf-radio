defmodule BBRF.JournalTest do
  use ExUnit.Case, async: false

  alias BBRF.Journal
  alias Exqlite.Sqlite3

  @repo_config Application.compile_env(:bbrf, BBRF.Repo)

  setup do
    path =
      Path.join(System.tmp_dir!(), "bbrf-journal-#{System.unique_integer([:positive])}.sqlite")

    on_exit(fn -> Enum.each([path, path <> "-wal", path <> "-shm"], &File.rm/1) end)

    put_repo_config(database: path, journal_mode: :delete)
    on_exit(fn -> Application.put_env(:bbrf, BBRF.Repo, @repo_config) end)

    {:ok, path: path}
  end

  test "converts a WAL database to the configured mode", %{path: path} do
    set_mode(path, "wal")
    assert mode(path) == "wal"

    assert :ok = Journal.ensure!()

    assert mode(path) == "delete"
  end

  test "converts a database to WAL when configured", %{path: path} do
    put_repo_config(database: path, journal_mode: :wal)

    assert :ok = Journal.ensure!()

    assert mode(path) == "wal"
  end

  test "leaves an in-memory database alone" do
    put_repo_config(database: ":memory:", journal_mode: :delete)

    assert :ok = Journal.ensure!()
  end

  defp put_repo_config(overrides),
    do: Application.put_env(:bbrf, BBRF.Repo, Keyword.merge(@repo_config, overrides))

  defp set_mode(path, mode), do: query(path, "PRAGMA journal_mode=#{mode}")
  defp mode(path), do: path |> query("PRAGMA journal_mode") |> hd() |> hd()

  defp query(path, sql) do
    {:ok, conn} = Sqlite3.open(path)
    {:ok, statement} = Sqlite3.prepare(conn, sql)
    {:ok, rows} = Sqlite3.fetch_all(conn, statement)
    :ok = Sqlite3.release(conn, statement)
    Sqlite3.close(conn)
    rows
  end
end
