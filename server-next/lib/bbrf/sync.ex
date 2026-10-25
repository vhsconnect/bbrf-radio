defmodule BBRF.Sync do
  @moduledoc """
  Copies the ingest node's stations and track history into the hub's
  database over Erlang distribution. Both databases have the same
  schema; the hub keeps its own window of history (its RETENTION_DAYS)
  and prunes it like the ingester does.

  The ingest node pushes and the hub's `BBRF.Sync.Receiver` only
  answers. A sync, on the ingest node:

    1. connects to SYNC_HUB_NODE
    2. says hello with its schema version (the newest migration). The
       hub refuses unless it is at the same one; otherwise it replies
       with its highest observation id and the oldest observation time
       its retention keeps
    3. upserts every station
    4. sends the observations newer than both, by id
    5. disconnects

  Rows go in batches, one call each, so the hub sets the pace and writes
  in short transactions. A sync that breaks off resumes from the hub's
  highest id the next time. The last successful one is recorded in
  ingest_stats under `sync`; the next is due SYNC_INTERVAL_HOURS
  (default 24) after it, checked every 10 minutes so a failed one is
  retried soon.

  The nodes run TLS distribution, set up by `scripts/launch.fish`, which
  leaves the shared cookie in BBRF_COOKIE_FILE for `use_cookie/0`.
  """

  require Logger
  alias BBRF.{Env, IngestStat, Repo}
  alias BBRF.Ingester.{Scheduler, Track}
  alias BBRF.Sync.Receiver

  @endpoint "sync"
  @call_timeout 60_000
  # SQLite binds at most 32766 parameters per statement
  @max_params 32_000

  @spec hub_node() :: node() | nil
  def hub_node, do: node_env("SYNC_HUB_NODE")

  @spec ingest_node() :: node() | nil
  def ingest_node, do: node_env("SYNC_INGEST_NODE")

  def interval_hours, do: Env.int("SYNC_INTERVAL_HOURS", 24)

  @doc "The sync processes `role` runs: the receiver and retention on a hub, the push when due on an ingest node with a hub configured."
  def children(:hub), do: [Receiver, BBRF.Ingester.prune_child()]

  def children(:ingest) do
    if hub_node() do
      [
        {Scheduler,
         name: BBRF.Sync.Scheduler,
         label: "sync",
         interval_ms: 600_000,
         job: {__MODULE__, :sync_if_due, []}}
      ]
    else
      []
    end
  end

  def children(:all), do: []

  def describe(:hub),
    do:
      "sync: receiving from #{ingest_node() || "nobody (SYNC_INGEST_NODE unset)"}, keeping #{Track.retention_days()} days"

  def describe(:ingest) do
    case hub_node() do
      nil -> "sync off (SYNC_HUB_NODE unset)"
      hub -> "sync: pushing to #{hub} every #{interval_hours()}h"
    end
  end

  def describe(:all), do: "sync off (one database)"

  @doc "Switch to the cookie in BBRF_COOKIE_FILE, when set, before any node connects."
  @spec use_cookie() :: :ok
  def use_cookie do
    case System.get_env("BBRF_COOKIE_FILE") do
      nil -> :ok
      path -> path |> File.read!() |> String.trim() |> String.to_atom() |> Node.set_cookie()
    end

    :ok
  end

  @spec sync_if_due() :: {:ok, map()} | {:error, term()} | :not_due
  def sync_if_due do
    if due?(), do: sync(hub_node()), else: :not_due
  end

  defp due? do
    cutoff =
      DateTime.utc_now() |> DateTime.add(-interval_hours(), :hour) |> DateTime.to_iso8601()

    %{rows: rows} =
      Repo.query!(
        "SELECT 1 FROM ingest_stats WHERE endpoint = ? AND error IS NULL AND polled_at > ? LIMIT 1",
        [@endpoint, cutoff]
      )

    rows == []
  end

  @doc "Push to the receiver on `hub` now, and record the outcome."
  @spec sync(node()) :: {:ok, map()} | {:error, term()}
  def sync(hub) do
    started = System.monotonic_time(:millisecond)

    result =
      with :ok <- connect(hub),
           {:ok, %{cursor: cursor, since: since}} <- call(hub, {:hello, schema_version()}),
           {:ok, stations} <- push_table(hub, "stations", 0),
           {:ok, observations} <- push_table(hub, "track_observations", first_id(cursor, since)) do
        {:ok, %{stations: stations, observations: observations}}
      end

    disconnect(hub)
    record(result, System.monotonic_time(:millisecond) - started)
    result
  end

  @doc "The newest migration this database has run."
  @spec schema_version() :: integer() | nil
  def schema_version do
    %{rows: [[version]]} = Repo.query!("SELECT MAX(version) FROM schema_migrations")
    version
  end

  @doc "`table`'s columns, in the order the database stores them."
  @spec columns(String.t()) :: [String.t()]
  def columns(table) do
    %{rows: rows} = Repo.query!("SELECT name FROM pragma_table_info(?) ORDER BY cid", [table])
    List.flatten(rows)
  end

  defp node_env(name) do
    case Env.str(name, "") do
      "" -> nil
      value -> String.to_atom(value)
    end
  end

  defp connect(hub) when hub == node(), do: :ok

  defp connect(hub) do
    case Node.connect(hub) do
      true -> :ok
      false -> {:error, {:unreachable, hub}}
      :ignored -> {:error, :not_distributed}
    end
  end

  defp disconnect(hub) when hub == node(), do: :ok
  defp disconnect(hub), do: Node.disconnect(hub)

  defp call(hub, message) do
    GenServer.call({Receiver, hub}, message, @call_timeout)
  catch
    :exit, reason -> {:error, {:exit, reason}}
  end

  # the hub's highest id, moved up to the oldest observation its
  # retention keeps so a fresh hub is not sent the whole history
  defp first_id(cursor, nil), do: cursor

  defp first_id(cursor, since) do
    %{rows: [[first]]} =
      Repo.query!("SELECT MIN(id) FROM track_observations WHERE observed_at >= ?", [since])

    if first, do: max(cursor, first - 1), else: cursor
  end

  # rows after `after_rowid` in rowid order (an observation's rowid is its
  # id), a batch per call, each read its own short statement
  defp push_table(hub, table, after_rowid) do
    columns = columns(table)

    select =
      "SELECT rowid, #{Enum.map_join(columns, ", ", &~s("#{&1}"))} FROM #{table} WHERE rowid > ? ORDER BY rowid LIMIT ?"

    push_batches(hub, table, columns, select, div(@max_params, length(columns)), after_rowid, 0)
  end

  defp push_batches(hub, table, columns, select, limit, after_rowid, sent) do
    case Repo.query!(select, [after_rowid, limit]).rows do
      [] ->
        {:ok, sent}

      rows ->
        [last_rowid | _] = List.last(rows)

        case call(hub, {:rows, table, columns, Enum.map(rows, &tl/1)}) do
          :ok -> push_batches(hub, table, columns, select, limit, last_rowid, sent + length(rows))
          error -> error
        end
    end
  end

  defp record(result, duration_ms) do
    stats =
      case result do
        {:ok, sent} ->
          %{row_count: sent.observations, updated: sent.stations, error: nil}

        error ->
          %{row_count: 0, updated: 0, error: inspect(error)}
      end

    IngestStat.record(
      @endpoint,
      Map.merge(stats, %{inserted: stats.row_count, unchanged: 0, duration_ms: duration_ms})
    )
  end
end
