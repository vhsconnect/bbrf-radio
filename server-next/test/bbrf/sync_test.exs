defmodule BBRF.SyncTest do
  use ExUnit.Case, async: false

  @moduletag :capture_log

  alias BBRF.{History, Metatable, Repo, Sync, TrackObservation}
  alias BBRF.Ingester.Stations
  alias BBRF.Sync.Receiver

  setup do
    ingest = start_repo!(:ingest)
    hub = start_repo!(:hub)
    start_supervised!({Receiver, repo: hub, ingest_nodes: [node()]})
    Repo.put_dynamic_repo(ingest)

    on(ingest, fn ->
      Stations.upsert([
        Metatable.station(%{"stationuuid" => "station-1", "name" => "Example FM"}),
        Metatable.station(%{"stationuuid" => "station-2", "name" => "Another FM"})
      ])

      Repo.insert_all(TrackObservation, [
        Metatable.observation(%{stationuuid: "station-1", artist: "Beyoncé", title: "Halo"}),
        Metatable.observation(%{stationuuid: "station-2", artist: "Halo Effect", title: "Shine"})
      ])
    end)

    on_exit(fn ->
      Enum.each(~w(RETENTION_DAYS SYNC_HUB_NODE SYNC_INGEST_NODE BBRF_ROLE), &System.delete_env/1)
    end)

    %{ingest: ingest, hub: hub}
  end

  defp start_repo!(id, migrate_opts \\ [all: true]) do
    repo = start_supervised!({Repo, name: nil, database: ":memory:", pool_size: 1}, id: id)
    migrate!(repo, migrate_opts)
    repo
  end

  defp migrate!(repo, opts \\ [all: true]) do
    # the boot already loaded the migration modules
    Code.put_compiler_option(:ignore_module_conflict, true)
    Ecto.Migrator.run(Repo, :up, opts ++ [dynamic_repo: repo, log: false])
    Code.put_compiler_option(:ignore_module_conflict, false)
  end

  defp on(repo, fun) do
    previous = Repo.put_dynamic_repo(repo)

    try do
      fun.()
    after
      Repo.put_dynamic_repo(previous)
    end
  end

  defp tracks(repo), do: on(repo, fn -> History.tracks([], "played", "desc", 50, 0) end)

  defp second_ingest!(hub, observations) do
    second = start_repo!(:second)
    on(second, fn -> Repo.insert_all(TrackObservation, observations) end)

    stop_supervised!(Receiver)

    start_supervised!(
      {Receiver, repo: hub, ingest_nodes: [:second@ingest], caller_node: :second@ingest}
    )

    second
  end

  defp titles(repo) do
    repo |> tracks() |> Enum.map(& &1["title"]) |> Enum.sort()
  end

  test "copies the stations and the track history into the hub", ctx do
    assert Sync.sync(node()) == {:ok, %{stations: 2, artists: 0, metrics: 0, observations: 2}}

    assert tracks(ctx.hub) == tracks(ctx.ingest)
    assert ctx.hub |> on(fn -> History.search("halo", 50, 0) end) |> length() == 2
  end

  test "a second sync sends the new observations and updates the stations", ctx do
    {:ok, _} = Sync.sync(node())

    on(ctx.ingest, fn ->
      Stations.upsert([
        Metatable.station(%{"stationuuid" => "station-1", "name" => "Renamed FM"})
      ])

      Repo.insert_all(TrackObservation, [Metatable.observation(%{title: "Encore"})])
    end)

    assert Sync.sync(node()) == {:ok, %{stations: 2, artists: 0, metrics: 0, observations: 1}}
    assert tracks(ctx.hub) == tracks(ctx.ingest)

    assert ctx.hub |> tracks() |> Enum.map(& &1["station"]["name"]) |> Enum.uniq() |> Enum.sort() ==
             ["Another FM", "Renamed FM"]
  end

  test "keeps the observations of two ingest nodes that number them alike", ctx do
    {:ok, _} = Sync.sync(node())

    second =
      second_ingest!(ctx.hub, [
        Metatable.observation(%{title: "Elsewhere"}),
        Metatable.observation(%{title: "Elsewhere too"})
      ])

    assert {:ok, %{observations: 2}} = on(second, fn -> Sync.sync(node()) end)
    assert titles(ctx.hub) == ["Elsewhere", "Elsewhere too", "Halo", "Shine"]

    on(second, fn ->
      Repo.insert_all(TrackObservation, [Metatable.observation(%{title: "New"})])
    end)

    assert {:ok, %{observations: 1}} = on(second, fn -> Sync.sync(node()) end)
  end

  test "a hub upgraded with its history keeps it as the ingest node's", ctx do
    hub = start_repo!(:legacy_hub, to: 20_261_110_120_011)

    on(hub, fn ->
      Repo.insert_all(TrackObservation, [
        Metatable.observation(%{title: "Halo"}),
        Metatable.observation(%{title: "Shine"})
      ])
    end)

    System.put_env("BBRF_ROLE", "hub")
    System.put_env("SYNC_INGEST_NODE", to_string(node()))
    migrate!(hub)

    stop_supervised!(Receiver)
    start_supervised!({Receiver, repo: hub, ingest_nodes: [node()]})

    assert {:ok, %{observations: 0}} = Sync.sync(node())
    assert titles(hub) == titles(ctx.ingest)
  end

  defp station_state(repo, stationuuid) do
    %{rows: [[state]]} =
      on(repo, fn ->
        Repo.query!("SELECT meta_state FROM stations WHERE stationuuid = ?", [stationuuid])
      end)

    state
  end

  defp ingest_state(ctx, state) do
    on(ctx.ingest, fn ->
      Repo.query!("UPDATE stations SET meta_state = ? WHERE stationuuid = 'station-1'", [state])
    end)
  end

  test "keeps a station removed while an ingest node sent it as removed lately", ctx do
    ingest_state(ctx, "removed")
    {:ok, _} = Sync.sync(node())

    ingest_state(ctx, "ok")
    {:ok, _} = Sync.sync(node())

    assert station_state(ctx.hub, "station-1") == "removed"
  end

  test "takes the state sent once no ingest node sent the station as removed for REMOVED_TTL_DAYS",
       ctx do
    ingest_state(ctx, "removed")
    {:ok, _} = Sync.sync(node())

    on(ctx.hub, fn ->
      Repo.query!("UPDATE stations SET removed_seen_at = '2026-01-01T00:00:00Z'")
    end)

    ingest_state(ctx, "ok")
    {:ok, _} = Sync.sync(node())

    assert station_state(ctx.hub, "station-1") == "ok"
  end

  test "a removal resent by an ingest node keeps the station removed", ctx do
    ingest_state(ctx, "removed")
    {:ok, _} = Sync.sync(node())

    on(ctx.hub, fn ->
      Repo.query!("UPDATE stations SET removed_seen_at = '2026-01-01T00:00:00Z'")
    end)

    {:ok, _} = Sync.sync(node())
    ingest_state(ctx, "ok")
    {:ok, _} = Sync.sync(node())

    assert station_state(ctx.hub, "station-1") == "removed"
  end

  test "copies the artist catalogue and updates it on the next sync", ctx do
    artist = fn name ->
      on(ctx.ingest, fn ->
        Repo.query!(
          "INSERT INTO artists (mbid, name, fetched_at) VALUES ('mbid-1', ?, '2026-10-29') " <>
            "ON CONFLICT (mbid) DO UPDATE SET name = excluded.name",
          [name]
        )
      end)
    end

    artist.("Beyonce")

    on(ctx.ingest, fn ->
      Repo.query!(
        "INSERT INTO artist_credits (id, name, status, attempts, checked_at) VALUES (1, 'Beyoncé', 'resolved', 1, '2026-10-29')"
      )

      Repo.query!(
        "INSERT INTO artist_credit_artists (artist_credit_id, position, artist_mbid) VALUES (1, 0, 'mbid-1')"
      )
    end)

    assert {:ok, %{artists: 3}} = Sync.sync(node())

    artist.("Beyoncé")
    assert {:ok, %{artists: 3}} = Sync.sync(node())

    assert %{rows: [["Beyoncé", 0]]} =
             on(ctx.hub, fn ->
               Repo.query!(
                 "SELECT a.name, ca.position FROM artist_credit_artists ca JOIN artists a ON a.mbid = ca.artist_mbid"
               )
             end)
  end

  test "copies the station metrics and drops the hub's rows from other runs", ctx do
    metric = fn stationuuid, computed_at ->
      on(ctx.ingest, fn ->
        Repo.query!(
          "INSERT INTO station_metrics (stationuuid, metric, value, sample, computed_at) VALUES (?, 'balance', 0.5, 60, ?)",
          [stationuuid, computed_at]
        )
      end)
    end

    hub_metrics = fn ->
      on(ctx.hub, fn ->
        Repo.query!(
          "SELECT stationuuid, metric, computed_at FROM station_metrics ORDER BY stationuuid"
        ).rows
      end)
    end

    metric.("station-1", "run-1")
    metric.("station-2", "run-1")
    assert {:ok, %{metrics: 2}} = Sync.sync(node())

    on(ctx.ingest, fn -> Repo.query!("DELETE FROM station_metrics") end)
    metric.("station-1", "run-2")
    assert {:ok, %{metrics: 1}} = Sync.sync(node())

    assert hub_metrics.() == [["station-1", "balance", "run-2"]]
  end

  test "keeps the hub's rows from every run the ingest node still has", ctx do
    on(ctx.ingest, fn ->
      Repo.query!(
        "INSERT INTO station_metrics (stationuuid, metric, value, sample, computed_at) VALUES ('station-1', 'balance', 0.5, 60, 'run-1'), ('station-2', 'balance', 0.5, 60, 'run-2')"
      )
    end)

    {:ok, _} = Sync.sync(node())

    assert %{rows: [[2]]} =
             on(ctx.hub, fn -> Repo.query!("SELECT COUNT(*) FROM station_metrics") end)
  end

  test "leaves out observations older than the hub keeps", ctx do
    System.put_env("RETENTION_DAYS", "1")

    on(ctx.ingest, fn ->
      Repo.insert_all(TrackObservation, [
        Metatable.observation(%{
          title: "Today",
          observed_at: DateTime.to_iso8601(DateTime.utc_now())
        })
      ])
    end)

    assert {:ok, %{observations: 1}} = Sync.sync(node())
    assert ctx.hub |> tracks() |> Enum.map(& &1["title"]) == ["Today"]
  end

  test "refuses a hub at another migration", ctx do
    on(ctx.hub, fn ->
      Repo.query!(
        "INSERT INTO schema_migrations (version, inserted_at) VALUES (99990101000000, '2026-10-25')"
      )
    end)

    assert {:error, {:schema_mismatch, 99_990_101_000_000, _ingest}} = Sync.sync(node())
    assert tracks(ctx.hub) == []
  end

  test "refuses callers from other nodes", ctx do
    stop_supervised!(Receiver)
    start_supervised!({Receiver, repo: ctx.hub, ingest_nodes: [:impostor@elsewhere]})

    assert Sync.sync(node()) == {:error, :not_allowed}
  end

  test "accepts any of the ingest nodes it is given", ctx do
    stop_supervised!(Receiver)
    start_supervised!({Receiver, repo: ctx.hub, ingest_nodes: [:other@elsewhere, node()]})

    assert {:ok, _} = Sync.sync(node())
  end

  test "reads several ingest nodes from SYNC_INGEST_NODE" do
    System.put_env("SYNC_INGEST_NODE", "bbrf_ingest@10.0.0.1, bbrf_ingest@10.0.0.2")

    assert Sync.ingest_nodes() == [:"bbrf_ingest@10.0.0.1", :"bbrf_ingest@10.0.0.2"]
  end

  test "refuses rows for other tables or with other columns" do
    assert GenServer.call(Receiver, {:rows, "stations", ["stationuuid"], [["x"]]}) ==
             {:error, {:columns_mismatch, "stations"}}

    assert {:error, {:unknown_message, _}} =
             GenServer.call(Receiver, {:rows, "favorites", ["id"], [[1]]})
  end

  test "an unreachable hub is recorded as a failed sync" do
    assert {:error, _reason} = Sync.sync(:hub@nowhere)

    assert %{rows: [[error]]} =
             Repo.query!("SELECT error FROM ingest_stats WHERE endpoint = 'sync'")

    assert error =~ "hub@nowhere" or error =~ "not_distributed"
  end

  test "sync_if_due waits for the interval after a successful sync" do
    System.put_env("SYNC_HUB_NODE", to_string(node()))

    assert {:ok, _} = Sync.sync_if_due()
    assert Sync.sync_if_due() == :not_due
  end
end
