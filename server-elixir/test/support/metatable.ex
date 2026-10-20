defmodule RadioAnalyzer.Metatable do
  @moduledoc false

  def station(overrides \\ %{}) do
    Map.merge(
      %{
        "stationuuid" => "station-1",
        "changeuuid" => "change-1",
        "name" => "Example FM",
        "url" => "http://example.com:8000/live",
        "url_resolved" => "http://example.com:8000/live",
        "lastcheckok" => true,
        "hls" => false,
        "clickcount" => 0
      },
      overrides
    )
  end

  def candidate(overrides \\ %{}) do
    Map.merge(
      %{
        stationuuid: "station-1",
        changeuuid: "change-1",
        stream_url: "http://example.com:8000/live",
        meta_state: "unknown",
        meta_source: nil,
        meta_checked_at: nil,
        meta_next_check_at: nil,
        fail_count: 0,
        idle_count: 0,
        last_title: nil,
        clickcount: 0,
        favorite: false
      },
      overrides
    )
  end

  def observation(overrides \\ %{}) do
    Map.merge(
      %{
        stationuuid: "station-1",
        observed_at: "2026-10-19T12:00:00.000000Z",
        raw_title: "Artist - Song",
        artist: "Artist",
        title: "Song",
        metadata: nil
      },
      overrides
    )
  end

  def now, do: ~U[2026-10-19 12:00:00.000000Z]

  def reset_db! do
    Enum.each(
      ["track_observations", "stations", "ingest_stats", "favorites"],
      &RadioAnalyzer.Repo.query!("DELETE FROM #{&1}")
    )
  end
end
