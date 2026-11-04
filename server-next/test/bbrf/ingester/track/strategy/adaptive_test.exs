defmodule BBRF.Ingester.Track.Strategy.AdaptiveTest do
  use ExUnit.Case, async: false

  alias BBRF.{Metatable, Repo}
  alias BBRF.Ingester.{Stations, Track}
  alias BBRF.Ingester.Track.Strategy.Adaptive

  @config Adaptive.init(discovery_per_wave: 500, icy_interval_minutes: 60, popular_clickcount: 20)

  setup do
    Metatable.reset_db!()
    :ok
  end

  defp uuids(wave), do: Enum.map(wave, & &1.stationuuid)

  defp set_due(uuid, due) do
    Repo.query!("UPDATE stations SET meta_next_check_at = ? WHERE stationuuid = ?", [due, uuid])
  end

  defp popular(overrides \\ %{}),
    do: Metatable.candidate(Map.merge(%{clickcount: 100}, overrides))

  defp due_in_minutes(station, outcome, method \\ nil) do
    state = Track.next_state(station, outcome, Metatable.now(), method)
    next = Adaptive.next_check_at(station, outcome, state, Metatable.now(), @config)
    DateTime.diff(next, Metatable.now(), :minute)
  end

  describe "select/3" do
    test "takes due ok stations, then discovery: never-checked, then most overdue" do
      Stations.upsert([
        Metatable.station(%{"stationuuid" => "later"}),
        Metatable.station(%{"stationuuid" => "overdue"}),
        Metatable.station(%{"stationuuid" => "new"}),
        Metatable.station(%{"stationuuid" => "not-due"}),
        Metatable.station(%{"stationuuid" => "ok"}),
        Metatable.station(%{"stationuuid" => "ok-not-due"})
      ])

      set_due("later", "2026-10-19T11:59:00.000000Z")
      set_due("overdue", "2026-10-19T11:00:00.000000Z")
      set_due("not-due", "2026-10-19T12:30:00.000000Z")
      set_due("ok", "2026-10-19T11:59:30.000000Z")
      set_due("ok-not-due", "2026-10-19T12:01:00.000000Z")

      Repo.query!(
        "UPDATE stations SET meta_state = 'ok', meta_source = 'icecast' WHERE stationuuid LIKE 'ok%'"
      )

      assert uuids(Adaptive.select(Metatable.now(), 10, @config)) ==
               ["ok", "new", "overdue", "later"]

      assert uuids(Adaptive.select(Metatable.now(), 2, @config)) == ["ok", "new"]
    end

    test "caps discovery but not stations with a known method" do
      Stations.upsert(for n <- 1..5, do: Metatable.station(%{"stationuuid" => "s#{n}"}))

      Repo.query!(
        "UPDATE stations SET meta_source = 'icy' WHERE stationuuid IN ('s1', 's2', 's3')"
      )

      one_discovery = %{@config | discovery_per_wave: 1}

      assert uuids(Adaptive.select(Metatable.now(), 10, one_discovery)) ==
               ["s1", "s2", "s3", "s4"]

      assert uuids(Adaptive.select(Metatable.now(), 2, @config)) == ["s1", "s2"]
    end

    test "skips removed, broken and hls stations" do
      Stations.upsert([
        Metatable.station(%{"stationuuid" => "removed"}),
        Metatable.station(%{"stationuuid" => "broken", "lastcheckok" => false}),
        Metatable.station(%{"stationuuid" => "hls", "hls" => true}),
        Metatable.station(%{"stationuuid" => "fine"})
      ])

      Repo.query!("UPDATE stations SET meta_state = 'removed' WHERE stationuuid = 'removed'")

      assert uuids(Adaptive.select(Metatable.now(), 10, @config)) == ["fine"]
    end

    test "loads clickcounts" do
      Stations.upsert([
        Metatable.station(%{"stationuuid" => "quiet"}),
        Metatable.station(%{"stationuuid" => "popular", "clickcount" => 500})
      ])

      assert Adaptive.select(Metatable.now(), 10, @config)
             |> Map.new(&{&1.stationuuid, &1.clickcount}) ==
               %{"quiet" => 0, "popular" => 500}
    end
  end

  describe "next_check_at/5" do
    test "a change is checked again in 3 minutes" do
      assert due_in_minutes(popular(), {:changed, "t", %{}}) == 3
    end

    test "idle checks back off 5, 10, then stay at 20 minutes" do
      minutes =
        for idle <- 0..3 do
          due_in_minutes(popular(%{meta_state: "ok", idle_count: idle}), :idle)
        end

      assert minutes == [5, 10, 20, 20]
    end

    test "stations that are not popular refresh at half the rate" do
      long_tail = Metatable.candidate(%{clickcount: 3})

      assert due_in_minutes(long_tail, {:changed, "t", %{}}) == 6
      assert due_in_minutes(long_tail, :idle) == 10
    end

    test "failures and no metadata follow the shared back-off" do
      assert due_in_minutes(Metatable.candidate(%{fail_count: 1}), :fail) == 30
      assert due_in_minutes(Metatable.candidate(), :no_metadata) == 7 * 24 * 60
    end

    test "ICY stations are checked at most every icy_interval_minutes" do
      assert due_in_minutes(popular(), {:changed, "t", %{}}, "icy") == 60
      assert due_in_minutes(popular(%{meta_state: "ok", meta_source: "icy"}), :idle) == 60
    end
  end
end
