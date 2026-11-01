defmodule BBRF.SyncTest do
  use ExUnit.Case, async: false

  @moduletag :capture_log

  alias BBRF.{History, Metatable, Repo, Sync, TrackObservation}
  alias BBRF.Ingester.Stations
  alias BBRF.Sync.Receiver

  setup do
    ingest = start_repo!(:ingest)
    hub = start_repo!(:hub)
    start_supervised!({Receiver, repo: hub, ingest_node: node()})
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
      Enum.each(~w(RETENTION_DAYS SYNC_HUB_NODE), &System.delete_env/1)
    end)

    %{ingest: ingest, hub: hub}
  end

  defp start_repo!(id) do
    repo = start_supervised!({Repo, name: nil, database: ":memory:", pool_size: 1}, id: id)
    # the boot already loaded the migration modules
    Code.put_compiler_option(:ignore_module_conflict, true)
    Ecto.Migrator.run(Repo, :up, all: true, dynamic_repo: repo, log: false)
    Code.put_compiler_option(:ignore_module_conflict, false)
    repo
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

  test "copies the stations and the track history into the hub", ctx do
    assert Sync.sync(node()) == {:ok, %{stations: 2, artists: 0, observations: 2}}

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

    assert Sync.sync(node()) == {:ok, %{stations: 2, artists: 0, observations: 1}}
    assert tracks(ctx.hub) == tracks(ctx.ingest)

    assert ctx.hub |> tracks() |> Enum.map(& &1["station"]["name"]) |> Enum.uniq() |> Enum.sort() ==
             ["Another FM", "Renamed FM"]
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
    start_supervised!({Receiver, repo: ctx.hub, ingest_node: :impostor@elsewhere})

    assert Sync.sync(node()) == {:error, :not_allowed}
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
