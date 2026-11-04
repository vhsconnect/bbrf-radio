defmodule BBRF.HistoryTest do
  use ExUnit.Case, async: false

  alias BBRF.{History, Metatable, Repo, TrackObservation}
  alias BBRF.Ingester.Stations

  setup do
    Metatable.reset_db!()

    Stations.upsert([
      Metatable.station(%{
        "stationuuid" => "station-1",
        "name" => "Example FM",
        "countrycode" => "SE",
        "tags" => "pop, r&b,Soul"
      }),
      Metatable.station(%{
        "stationuuid" => "station-2",
        "name" => "Another FM",
        "countrycode" => "DE",
        "tags" => "metal,pop rock"
      })
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

  describe "tracks/5" do
    defp titles(tracks), do: Enum.map(tracks, & &1["title"])

    defp sorted(sort, dir), do: titles(History.tracks([], sort, dir, 50, 0))

    defp filtered(filters), do: titles(History.tracks(filters, "played", "desc", 50, 0))

    test "sorts by when the track was played" do
      assert sorted("played", "desc") == ["Love On Top", "Shine", "Halo"]
      assert sorted("played", "asc") == ["Halo", "Shine", "Love On Top"]
    end

    test "sorts by country, most recent first within a country" do
      assert sorted("country", "asc") == ["Shine", "Love On Top", "Halo"]
      assert sorted("country", "desc") == ["Love On Top", "Halo", "Shine"]
    end

    test "sorts by station name, most recent first within a station" do
      assert sorted("station", "asc") == ["Shine", "Love On Top", "Halo"]
      assert sorted("station", "desc") == ["Love On Top", "Halo", "Shine"]
    end

    test "filters by countrycode ignoring case" do
      assert filtered(countrycode: "se") == ["Love On Top", "Halo"]
    end

    test "sorts and filters stations with lowercase or empty countrycodes" do
      Stations.upsert([
        Metatable.station(%{"stationuuid" => "station-3", "countrycode" => "fr"}),
        Metatable.station(%{"stationuuid" => "station-4", "countrycode" => ""})
      ])

      Repo.insert_all(TrackObservation, [
        Metatable.observation(%{stationuuid: "station-3", title: "Bonjour"}),
        Metatable.observation(%{stationuuid: "station-4", title: "Silence"})
      ])

      assert sorted("country", "asc") == ["Shine", "Bonjour", "Love On Top", "Halo", "Silence"]
      assert sorted("country", "desc") == ["Love On Top", "Halo", "Bonjour", "Shine", "Silence"]
      assert filtered(countrycode: "FR") == ["Bonjour"]
    end

    test "filters by whole tags ignoring case" do
      assert filtered(tag: "SOUL") == ["Love On Top", "Halo"]
      assert filtered(tag: "r&b") == ["Love On Top", "Halo"]
      assert filtered(tag: "pop rock") == ["Shine"]
      assert filtered(tag: "rock") == []
    end

    test "filters by part of the station name ignoring case" do
      assert filtered(station: "EXAMPLE") == ["Love On Top", "Halo"]
      assert filtered(station: " another ") == ["Shine"]
      assert filtered(station: "fm") == ["Love On Top", "Shine", "Halo"]
      assert filtered(station: "%") == []
    end

    test "filters by artist and title like search/3" do
      assert filtered(q: "beyon") == ["Love On Top", "Halo"]
      assert filtered(q: "halo shi") == ["Shine"]
      assert filtered(q: "  -- ") == []
    end

    test "combines filters and ignores empty ones" do
      assert filtered(countrycode: "DE", tag: "soul") == []

      assert filtered(countrycode: "", tag: nil, station: "", q: nil) == [
               "Love On Top",
               "Shine",
               "Halo"
             ]
    end

    test "pages with limit and offset" do
      assert titles(History.tracks([], "played", "desc", 1, 1)) == ["Shine"]
    end

    test "joins the station that played the track" do
      assert [track | _] = History.tracks([], "played", "desc", 50, 0)

      assert %{
               "id" => _,
               "observed_at" => "2026-10-19T12:10:00.000000Z",
               "raw_title" => "Beyoncé - Love On Top",
               "artist" => "Beyoncé",
               "station" => %{
                 "stationuuid" => "station-1",
                 "name" => "Example FM",
                 "countrycode" => "SE",
                 "tags" => "pop, r&b,Soul"
               }
             } = track
    end
  end
end
