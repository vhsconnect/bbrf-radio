defmodule RadioAnalyzer.Track.Strategy.FullSweepTest do
  use ExUnit.Case, async: false

  alias RadioAnalyzer.{Ingest, Metatable, Repo, Track}
  alias RadioAnalyzer.Track.Strategy.FullSweep

  @config FullSweep.init(cycle_minutes: 1, retries_per_wave: 500, wave_minutes: 1)

  setup do
    Metatable.reset_db!()
    :ok
  end

  defp uuids(wave), do: Enum.map(wave, & &1.stationuuid)

  defp checked(uuid, at) do
    Repo.query!("UPDATE stations SET meta_checked_at = ? WHERE stationuuid = ?", [at, uuid])
  end

  defp backing_off(uuid, state, fails, due) do
    Repo.query!(
      """
      UPDATE stations
         SET meta_state = ?, meta_fail_count = ?, meta_next_check_at = ?,
             meta_checked_at = '2026-10-19T00:00:00.000000Z'
       WHERE stationuuid = ?
      """,
      [state, fails, due, uuid]
    )
  end

  test "rotates through the stations that read fine, least recently checked first" do
    Ingest.upsert_stations(
      for uuid <- ~w(fresh new old), do: Metatable.station(%{"stationuuid" => uuid})
    )

    checked("fresh", "2026-10-19T11:59:00.000000Z")
    checked("old", "2026-10-19T08:00:00.000000Z")

    assert uuids(FullSweep.select(Metatable.now(), 10, @config)) == ["new", "old", "fresh"]
  end

  test "retries failing and no-metadata stations only when their back-off is due" do
    Ingest.upsert_stations(
      for uuid <- ~w(dead-due dead-later empty-due empty-later fine) do
        Metatable.station(%{"stationuuid" => uuid})
      end
    )

    backing_off("dead-due", "dead", 3, "2026-10-19T11:00:00.000000Z")
    backing_off("dead-later", "dead", 3, "2026-10-20T00:00:00.000000Z")
    backing_off("empty-due", "no-metadata", 0, "2026-10-19T11:30:00.000000Z")
    backing_off("empty-later", "no-metadata", 0, "2026-10-26T00:00:00.000000Z")

    assert uuids(FullSweep.select(Metatable.now(), 10, @config)) ==
             ["fine", "dead-due", "empty-due"]

    one_retry = %{@config | retries_per_wave: 1}
    assert uuids(FullSweep.select(Metatable.now(), 10, one_retry)) == ["fine", "dead-due"]
  end

  test "sizes each wave so the rotation is covered once per cycle" do
    Ingest.upsert_stations(for n <- 1..10, do: Metatable.station(%{"stationuuid" => "s#{n}"}))
    backing_off("s10", "dead", 3, "2026-11-01T00:00:00.000000Z")

    five_minute_cycle = %{@config | cycle_minutes: 5}
    two_minute_waves = %{five_minute_cycle | wave_minutes: 2}

    assert length(FullSweep.select(Metatable.now(), 100, five_minute_cycle)) == 2
    assert length(FullSweep.select(Metatable.now(), 100, two_minute_waves)) == 4
    assert length(FullSweep.select(Metatable.now(), 3, @config)) == 3
  end

  test "schedules back-off after a failure, leaves due times alone after a read" do
    station = Metatable.candidate()
    failed = Track.next_state(station, :fail, Metatable.now())
    read = Track.next_state(station, {:changed, "t", %{}}, Metatable.now())

    assert FullSweep.next_check_at(station, :fail, failed, Metatable.now(), @config) ==
             DateTime.add(Metatable.now(), 15 * 60, :second)

    assert FullSweep.next_check_at(station, {:changed, "t", %{}}, read, Metatable.now(), @config) ==
             nil
  end
end
