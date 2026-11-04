defmodule BBRF.Metatable do
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
        clickcount: 0
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

  @doc "A MusicBrainz recording search response with one recording per credit, as `[{score, [{credited_as, mbid, join_phrase}]}]`."
  def mb_recordings(recordings) do
    %{
      "recordings" =>
        Enum.map(recordings, fn {score, credit} ->
          %{
            "id" => "recording-1",
            "score" => score,
            "title" => "Halo",
            "artist-credit" =>
              Enum.map(credit, fn {name, mbid, join_phrase} ->
                %{
                  "name" => name,
                  "joinphrase" => join_phrase,
                  "artist" => %{"id" => mbid, "name" => name}
                }
              end)
          }
        end)
    }
  end

  def mb_artist(overrides \\ %{}) do
    Map.merge(
      %{
        "id" => "mbid-beyonce",
        "name" => "Beyoncé",
        "sort-name" => "Beyoncé",
        "type" => "Person",
        "gender" => "Female",
        "country" => "US",
        "area" => %{"name" => "United States"},
        "begin-area" => %{"name" => "Houston"},
        "end-area" => nil,
        "life-span" => %{"begin" => "1981-09-04", "end" => nil, "ended" => false},
        "disambiguation" => "",
        "aliases" => [
          %{"name" => "Beyonce", "locale" => nil, "primary" => nil},
          %{"name" => "Beyonce", "locale" => "en", "primary" => true},
          %{"name" => "ビヨンセ", "locale" => "ja", "primary" => true}
        ],
        "tags" => [%{"name" => "pop", "count" => 7}, %{"name" => "american", "count" => 2}],
        "genres" => [%{"name" => "pop", "count" => 7}],
        "relations" => [
          %{
            "type" => "official homepage",
            "target-type" => "url",
            "url" => %{"resource" => "https://www.beyonce.com/"}
          },
          %{"type" => "member of band", "target-type" => "artist", "artist" => %{"id" => "x"}}
        ]
      },
      overrides
    )
  end

  def now, do: ~U[2026-10-19 12:00:00.000000Z]

  def reset_db! do
    Enum.each(
      ~w(track_observations stations ingest_stats favorites artist_credit_artists artist_credits
         artist_tags artist_aliases artist_links artists),
      &BBRF.Repo.query!("DELETE FROM #{&1}")
    )
  end
end
