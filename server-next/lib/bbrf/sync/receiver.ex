defmodule BBRF.Sync.Receiver do
  @moduledoc """
  The hub's end of `BBRF.Sync`, registered under its module name so the
  ingest node can call it as `{BBRF.Sync.Receiver, hub_node}`.

  It answers only processes on the SYNC_INGEST_NODE nodes (nobody when unset),
  only when both databases are at the same migration, and only writes
  `stations`, the artist catalogue and `station_metrics` (upserted) and
  `track_observations` with exactly the columns its own tables have. It
  deletes the station metrics it holds from runs the ingest node has no
  rows from any more.

  Every ingest node numbers its observations on its own, so the hub gives
  each one a new id and keeps where it came from: `origin` (the node's row
  in `sync_origins`) and `origin_id` (its id there). An observation it
  already has from that node is left alone, and each node resumes from the
  highest `origin_id` the hub has from it.

  A station any ingest node sent as 'removed' in the last
  REMOVED_TTL_DAYS (30) stays removed whatever the others send:
  each node only learns of a removal at its own catalogue sync, and the
  nodes resend their removed stations every time. Once no node has sent
  it as removed for that long, the station takes the state sent.

  Options: `:ingest_nodes` overrides SYNC_INGEST_NODE, `:repo` makes it
  write to a dynamic repo, and `:caller_node` counts every caller as that
  node (the tests run every end on one node).
  """

  use GenServer
  require Logger
  alias BBRF.{Env, Repo, Sync}
  alias BBRF.Ingester.Track

  # the key each upserted table is matched on
  @keys %{
    "stations" => ~w(stationuuid),
    "artists" => ~w(mbid),
    "artist_tags" => ~w(artist_mbid tag),
    "artist_aliases" => ~w(artist_mbid alias),
    "artist_links" => ~w(artist_mbid url),
    "artist_credits" => ~w(id),
    "artist_credit_artists" => ~w(artist_credit_id position),
    "station_metrics" => ~w(stationuuid metric)
  }

  @tables ["track_observations" | Map.keys(@keys)]

  def removed_ttl_days, do: Env.int("REMOVED_TTL_DAYS", 30)

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(opts) do
    if repo = opts[:repo], do: Repo.put_dynamic_repo(repo)

    {:ok,
     %{
       ingest_nodes: Keyword.get_lazy(opts, :ingest_nodes, &Sync.ingest_nodes/0),
       caller_node: opts[:caller_node]
     }}
  end

  @impl true
  def handle_call(message, {pid, _tag}, state) do
    caller = state.caller_node || node(pid)

    if caller in state.ingest_nodes do
      answer(message, caller, state)
    else
      Logger.warning("sync: refused #{elem_name(message)} from #{caller}")
      {:reply, {:error, :not_allowed}, state}
    end
  end

  defp answer({:hello, version}, caller, state) do
    case Sync.schema_version() do
      ^version ->
        Logger.info("sync: started by #{caller}")
        {:reply, {:ok, %{cursor: cursor(origin!(caller)), since: since()}}, state}

      ours ->
        Logger.warning(
          "sync: refused, the hub is at migration #{ours} and the ingest node at #{version}"
        )

        {:reply, {:error, {:schema_mismatch, ours, version}}, state}
    end
  end

  defp answer({:rows, table, columns, rows}, caller, state)
       when table in @tables do
    if columns == Sync.columns(table) do
      {columns, rows} = prepare(table, columns, rows, caller)
      insert(table, columns, rows)
      {:reply, :ok, state}
    else
      {:reply, {:error, {:columns_mismatch, table}}, state}
    end
  end

  defp answer({:metric_runs, runs}, _caller, state) when is_list(runs) do
    drop_stale_metrics(runs)
    {:reply, :ok, state}
  end

  defp answer(message, _caller, state) do
    {:reply, {:error, {:unknown_message, elem_name(message)}}, state}
  end

  defp origin!(node) do
    name = Atom.to_string(node)

    Repo.query!("INSERT INTO sync_origins (node) VALUES (?) ON CONFLICT (node) DO NOTHING", [name])

    %{rows: [[id]]} = Repo.query!("SELECT id FROM sync_origins WHERE node = ?", [name])
    id
  end

  defp cursor(origin) do
    %{rows: [[id]]} =
      Repo.query!(
        "SELECT COALESCE(MAX(origin_id), 0) FROM track_observations WHERE origin = ?",
        [origin]
      )

    id
  end

  defp since do
    if Track.retention_days() > 0 do
      DateTime.utc_now() |> DateTime.add(-Track.retention_days(), :day) |> DateTime.to_iso8601()
    end
  end

  defp drop_stale_metrics(runs) do
    stale =
      Enum.map_join(runs, " AND ", fn _run -> "NOT (metric = ? AND computed_at = ?)" end)

    Repo.query!(
      "DELETE FROM station_metrics" <> if(runs == [], do: "", else: " WHERE " <> stale),
      Enum.flat_map(runs, &Tuple.to_list/1)
    )
  end

  defp prepare("track_observations", columns, rows, caller) do
    origin = origin!(caller)
    [id_at, origin_at, origin_id_at] = Enum.map(~w(id origin origin_id), &column_at(columns, &1))

    rows =
      Enum.map(rows, fn row ->
        row
        |> List.replace_at(origin_at, origin)
        |> List.replace_at(origin_id_at, Enum.at(row, id_at))
        |> List.delete_at(id_at)
      end)

    {List.delete_at(columns, id_at), rows}
  end

  defp prepare("stations", columns, rows, _caller) do
    [state_at, seen_at] = Enum.map(~w(meta_state removed_seen_at), &column_at(columns, &1))
    now = DateTime.to_iso8601(DateTime.utc_now())

    rows =
      Enum.map(rows, fn row ->
        List.replace_at(row, seen_at, if(Enum.at(row, state_at) == "removed", do: now))
      end)

    {columns, rows}
  end

  defp prepare(_table, columns, rows, _caller), do: {columns, rows}

  defp column_at(columns, column), do: Enum.find_index(columns, &(&1 == column))

  defp insert(_table, _columns, []), do: :ok

  defp insert(table, columns, rows) do
    row = "(" <> Enum.map_join(columns, ", ", fn _ -> "?" end) <> ")"
    {on_conflict, params} = on_conflict(table, columns)

    Repo.query!(
      """
      INSERT INTO #{table} (#{Enum.map_join(columns, ", ", &~s("#{&1}"))})
      VALUES #{Enum.map_join(rows, ", ", fn _ -> row end)}
      #{on_conflict}
      """,
      List.flatten(rows) ++ params
    )
  end

  defp on_conflict("track_observations", _columns),
    do: {"ON CONFLICT (origin, origin_id) WHERE origin IS NOT NULL DO NOTHING", []}

  defp on_conflict("stations", columns) do
    cutoff =
      DateTime.utc_now() |> DateTime.add(-removed_ttl_days(), :day) |> DateTime.to_iso8601()

    {upsert("stations", columns -- ~w(meta_state removed_seen_at)) <>
       """
       , meta_state = CASE
           WHEN excluded.meta_state = 'removed' OR stations.removed_seen_at > ? THEN 'removed'
           ELSE excluded.meta_state END,
         removed_seen_at = COALESCE(excluded.removed_seen_at, stations.removed_seen_at)
       """, [cutoff]}
  end

  defp on_conflict(table, columns), do: {upsert(table, columns), []}

  defp upsert(table, columns) do
    keys = @keys[table]

    "ON CONFLICT (#{Enum.map_join(keys, ", ", &~s("#{&1}"))}) DO UPDATE SET " <>
      Enum.map_join(columns -- keys, ", ", &~s("#{&1}" = excluded."#{&1}"))
  end

  defp elem_name(message) when is_tuple(message), do: inspect(elem(message, 0))
  defp elem_name(message), do: inspect(message)
end
