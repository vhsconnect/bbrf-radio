defmodule BBRF.Sync.Receiver do
  @moduledoc """
  The hub's end of `BBRF.Sync`, registered under its module name so the
  ingest node can call it as `{BBRF.Sync.Receiver, hub_node}`.

  It answers only processes on SYNC_INGEST_NODE (nobody when unset),
  only when both databases are at the same migration, and only writes
  `stations` and the artist catalogue (upserted) and `track_observations`
  (rows it already has are left alone) with exactly the columns its own
  tables have.

  Options: `:ingest_node` overrides SYNC_INGEST_NODE, and `:repo` makes
  it write to a dynamic repo (the tests run both ends on one node).
  """

  use GenServer
  require Logger
  alias BBRF.{Repo, Sync}
  alias BBRF.Ingester.Track

  # the key each upserted table is matched on
  @keys %{
    "stations" => ~w(stationuuid),
    "artists" => ~w(mbid),
    "artist_tags" => ~w(artist_mbid tag),
    "artist_aliases" => ~w(artist_mbid alias),
    "artist_links" => ~w(artist_mbid url),
    "artist_credits" => ~w(id),
    "artist_credit_artists" => ~w(artist_credit_id position)
  }

  @tables ["track_observations" | Map.keys(@keys)]

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(opts) do
    if repo = opts[:repo], do: Repo.put_dynamic_repo(repo)
    {:ok, %{ingest_node: Keyword.get_lazy(opts, :ingest_node, &Sync.ingest_node/0)}}
  end

  @impl true
  def handle_call(message, {caller, _tag}, %{ingest_node: allowed} = state)
      when node(caller) != allowed do
    Logger.warning("sync: refused #{elem_name(message)} from #{node(caller)}")
    {:reply, {:error, :not_allowed}, state}
  end

  def handle_call({:hello, version}, {caller, _tag}, state) do
    case Sync.schema_version() do
      ^version ->
        Logger.info("sync: started by #{node(caller)}")
        {:reply, {:ok, %{cursor: cursor(), since: since()}}, state}

      ours ->
        Logger.warning(
          "sync: refused, the hub is at migration #{ours} and the ingest node at #{version}"
        )

        {:reply, {:error, {:schema_mismatch, ours, version}}, state}
    end
  end

  def handle_call({:rows, table, columns, rows}, _from, state)
      when table in @tables do
    if columns == Sync.columns(table) do
      insert(table, columns, rows)
      {:reply, :ok, state}
    else
      {:reply, {:error, {:columns_mismatch, table}}, state}
    end
  end

  def handle_call(message, _from, state) do
    {:reply, {:error, {:unknown_message, elem_name(message)}}, state}
  end

  defp cursor do
    %{rows: [[id]]} = Repo.query!("SELECT COALESCE(MAX(id), 0) FROM track_observations")
    id
  end

  defp since do
    if Track.retention_days() > 0 do
      DateTime.utc_now() |> DateTime.add(-Track.retention_days(), :day) |> DateTime.to_iso8601()
    end
  end

  defp insert(_table, _columns, []), do: :ok

  defp insert(table, columns, rows) do
    row = "(" <> Enum.map_join(columns, ", ", fn _ -> "?" end) <> ")"

    Repo.query!(
      """
      INSERT INTO #{table} (#{Enum.map_join(columns, ", ", &~s("#{&1}"))})
      VALUES #{Enum.map_join(rows, ", ", fn _ -> row end)}
      #{on_conflict(table, columns)}
      """,
      List.flatten(rows)
    )
  end

  defp on_conflict("track_observations", _columns), do: "ON CONFLICT (id) DO NOTHING"

  defp on_conflict(table, columns) do
    keys = @keys[table]

    "ON CONFLICT (#{Enum.map_join(keys, ", ", &~s("#{&1}"))}) DO UPDATE SET " <>
      Enum.map_join(columns -- keys, ", ", &~s("#{&1}" = excluded."#{&1}"))
  end

  defp elem_name(message) when is_tuple(message), do: inspect(elem(message, 0))
  defp elem_name(message), do: inspect(message)
end
