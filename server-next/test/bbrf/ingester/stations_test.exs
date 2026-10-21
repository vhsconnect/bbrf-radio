defmodule BBRF.Ingester.StationsTest do
  use ExUnit.Case, async: false

  alias BBRF.{Metatable, Repo}
  alias BBRF.Ingester.Stations

  setup do
    Metatable.reset_db!()
    :ok
  end

  defp station_row(uuid) do
    %{rows: [row]} =
      Repo.query!(
        """
        SELECT meta_state, meta_fail_count, meta_next_check_at, synced_at
          FROM stations WHERE stationuuid = ?
        """,
        [uuid]
      )

    row
  end

  defp put_meta(uuid, state, due) do
    Repo.query!(
      """
      UPDATE stations SET meta_state = ?, meta_fail_count = 3, meta_next_check_at = ?
       WHERE stationuuid = ?
      """,
      [state, due, uuid]
    )
  end

  test "counts inserted, updated and unchanged stations, ignoring repeats" do
    Stations.upsert([
      Metatable.station(%{"stationuuid" => "a"}),
      Metatable.station(%{"stationuuid" => "b"})
    ])

    counts =
      Stations.upsert([
        Metatable.station(%{"stationuuid" => "a"}),
        Metatable.station(%{"stationuuid" => "b", "changeuuid" => "change-2"}),
        Metatable.station(%{"stationuuid" => "c"}),
        Metatable.station(%{"stationuuid" => "c"})
      ])

    assert counts == %{inserted: 1, updated: 1, unchanged: 1}
  end

  test "upserts more stations than fit in one statement" do
    stations = for n <- 1..1_000, do: Metatable.station(%{"stationuuid" => "s#{n}"})

    assert Stations.upsert(stations).inserted == 1_000
    assert %{rows: [[1_000]]} = Repo.query!("SELECT COUNT(*) FROM stations")
  end

  test "an edited dead station is reset and due now" do
    Stations.upsert([Metatable.station()])
    put_meta("station-1", "dead", "2026-11-01T00:00:00.000000Z")

    Stations.upsert([Metatable.station(%{"changeuuid" => "change-2"})])

    assert station_row("station-1") == ["unknown", 0, nil, nil]
  end

  test "an unchanged station keeps its state and schedule" do
    Stations.upsert([Metatable.station()])
    put_meta("station-1", "dead", "2026-11-01T00:00:00.000000Z")

    Stations.upsert([Metatable.station()])

    assert station_row("station-1") == ["dead", 3, "2026-11-01T00:00:00.000000Z", nil]
  end

  test "an edited ok station stays ok but is due now" do
    Stations.upsert([Metatable.station()])
    put_meta("station-1", "ok", "2026-11-01T00:00:00.000000Z")

    Stations.upsert([Metatable.station(%{"changeuuid" => "change-2"})])

    assert station_row("station-1") == ["ok", 0, nil, nil]
  end

  test "a removed station seen again comes back as unknown" do
    Stations.upsert([Metatable.station()])
    put_meta("station-1", "removed", "2026-11-01T00:00:00.000000Z")

    Stations.upsert([Metatable.station()])

    assert ["unknown", 3, nil, nil] = station_row("station-1")
  end

  test "synced_at is stamped by full syncs and kept by recent polls" do
    Stations.upsert([Metatable.station()], synced_at: "2026-10-19T00:00:00Z")
    Stations.upsert([Metatable.station()])

    assert [_state, _fails, _due, "2026-10-19T00:00:00Z"] = station_row("station-1")
  end
end
