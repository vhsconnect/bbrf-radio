defmodule BBRF.HistoryTest do
  use ExUnit.Case, async: false

  alias BBRF.{History, Metatable, Repo, TrackObservation}
  alias BBRF.Ingester.Stations

  setup do
    Metatable.reset_db!()

    Stations.upsert([
      Metatable.station(%{"stationuuid" => "station-1", "name" => "Example FM"}),
      Metatable.station(%{"stationuuid" => "station-2", "name" => "Other FM"})
    ])

    Repo.insert_all(TrackObservation, [
      Metatable.observation(%{
        stationuuid: "station-1",
        observed_at: "2026-10-19T12:00:00.000000Z",
        raw_title: "Beyoncé - Halo",
        artist: "Beyoncé",
        title: "Halo"
      }),
      Metatable.observation(%{
        stationuuid: "station-2",
        observed_at: "2026-10-19T12:05:00.000000Z",
        raw_title: "Halo Effect - Shine",
        artist: "Halo Effect",
        title: "Shine"
      }),
      Metatable.observation(%{
        stationuuid: "station-1",
        observed_at: "2026-10-19T12:10:00.000000Z",
        raw_title: "Beyoncé - Love On Top",
        artist: "Beyoncé",
        title: "Love On Top"
      }),
      Metatable.observation(%{
        stationuuid: "station-gone",
        observed_at: "2026-10-19T12:15:00.000000Z",
        raw_title: "Halo - Nowhere",
        artist: "Halo",
        title: "Nowhere"
      })
    ])

    :ok
  end

  defp uuids(stations), do: Enum.map(stations, & &1["stationuuid"])

  describe "search/3" do
    test "returns each matching station once, most recent match first" do
      assert uuids(History.search("halo", 50, 0)) == ["station-2", "station-1"]
      assert uuids(History.search("beyonce", 50, 0)) == ["station-1"]
    end

    test "ignores case and diacritics and treats words as prefixes" do
      assert uuids(History.search("BEYON", 50, 0)) == ["station-1"]
      assert uuids(History.search("halo shi", 50, 0)) == ["station-2"]
    end

    test "requires every word to match" do
      assert History.search("shine love", 50, 0) == []
    end

    test "pages with limit and offset" do
      assert uuids(History.search("halo", 1, 1)) == ["station-1"]
    end

    test "returns stations in the radio-browser shape" do
      assert [station] = History.search("love", 50, 0)

      assert station |> Map.keys() |> Enum.sort() == Enum.sort(Stations.api_columns())
      assert %{"name" => "Example FM", "has_extended_info" => false} = station
    end

    test "skips stations missing from the catalogue" do
      assert History.search("nowhere", 50, 0) == []
    end

    test "query syntax is treated as plain words" do
      assert History.search(~s["halo* OR NEAR(), :title], 50, 0) == []
      assert History.search("  -- ", 50, 0) == []
    end

    test "follows deletes made by the retention pruner" do
      Repo.query!("DELETE FROM track_observations WHERE title = 'Halo'")

      assert uuids(History.search("halo", 50, 0)) == ["station-2"]
    end
  end
end
