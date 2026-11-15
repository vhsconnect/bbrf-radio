defmodule BBRF.Ingester.NetworkLogTest do
  use ExUnit.Case, async: true

  alias BBRF.Metatable
  alias BBRF.Ingester.NetworkLog

  test "a title read shows the country, the bar, the method, the time and the title" do
    station = Metatable.candidate(%{name: "KCRW", countrycode: "US"})
    result = {:ok, Metatable.observation(%{raw_title: "Artist - Song"})}

    assert NetworkLog.line(station, "icecast", result, 400) ==
             "KCRW                     US [##                            ] icecast success        0.4 seconds | Artist - Song"
  end

  test "a failure shows its reason and a timeout fills the bar" do
    station = Metatable.candidate(%{name: "Dead Air", countrycode: nil})

    assert NetworkLog.line(station, nil, {:error, "timeout"}, 6_000) ==
             "Dead Air                 -- [##############################] -       fail           6.0 seconds | timeout"
  end

  test "the bar stops at the per-check cap" do
    line = NetworkLog.line(Metatable.candidate(), "icy", :no_source, 9_000)

    assert line =~ "[" <> String.duplicate("#", 30) <> "] icy     no-source"
  end

  test "a station without a name is shown by its uuid, a long name is cut" do
    unnamed = Metatable.candidate(%{name: " "})
    long_name = Metatable.candidate(%{name: String.duplicate("x", 40)})

    assert NetworkLog.line(unnamed, "icy", :no_source, 0) =~ ~r/^station-1 +US \[ {30}\]/
    assert NetworkLog.line(long_name, "icy", :no_source, 0) =~ ~r/^x{24} US \[/
  end

  test "a lowercase country code is shown uppercased, a malformed one as unknown" do
    assert NetworkLog.line(Metatable.candidate(%{countrycode: "se"}), "icy", :no_source, 0) =~
             " SE ["

    assert NetworkLog.line(Metatable.candidate(%{countrycode: ""}), "icy", :no_source, 0) =~
             " -- ["
  end

  test "a MusicBrainz search shows the entity, the time, the wait for its slot and the query" do
    params = [fmt: "json", query: ~s{recording:"Halo" AND artist:(beyonce)}, limit: 10]

    assert NetworkLog.request_line("recording", params, {:ok, 200}, 400, 1_100) ==
             ~s{musicbrainz recording       [##                            ] search  success        0.4 seconds, waited 1.1 | recording:"Halo" AND artist:(beyonce)}
  end

  test "a MusicBrainz lookup shows the mbid, a browse what it browses by" do
    lookup = [fmt: "json", inc: "aliases tags"]
    browse = [{:fmt, "json"}, {"artist", "a-1"}, {:limit, 100}]

    assert NetworkLog.request_line("artist/mbid-1", lookup, {:ok, 404}, 0, 0) =~
             ~r/^musicbrainz artist +\[ {30}\] lookup  not-found .* \| mbid-1$/

    assert NetworkLog.request_line("release-group", browse, {:ok, 200}, 0, 0) =~
             ~r/ browse  success .* \| artist=a-1 limit=100$/
  end

  test "a busy MusicBrainz shows as busy, a failed request its reason" do
    assert NetworkLog.request_line("artist/mbid-1", [], {:ok, 503}, 0, 0) =~ " lookup  busy "

    assert NetworkLog.request_line("artist/mbid-1", [], {:error, "timeout"}, 0, 0) =~
             ~r/ fail .* \| timeout$/
  end

  test "a resolved credit shows its attempt and the artists MusicBrainz credits" do
    credit = %{name: "Kygo & Avicii", title: "Forever Yours", attempts: 1}

    artists = [
      %{artist_mbid: "mbid-kygo", credited_as: "Kygo", join_phrase: " & "},
      %{artist_mbid: "mbid-avicii", credited_as: "Avicii", join_phrase: ""}
    ]

    assert NetworkLog.credit_line(credit, {:resolved, artists, []}, 2_900) ==
             "artist credit               [###############               ] try 2   resolved       2.9 seconds | Kygo & Avicii - Forever Yours => Kygo & Avicii"
  end

  test "an unresolved, failed or timed out credit shows what it was played with" do
    credit = %{name: "gummihuset.se", title: "Reklam", attempts: 0}

    assert NetworkLog.credit_line(credit, :unresolved, 0) =~
             ~r/ try 1   unresolved .* \| gummihuset.se - Reklam$/

    assert NetworkLog.credit_line(credit, :failed, 0) =~ " try 1   fail "

    assert NetworkLog.credit_line(credit, :timeout, 120_000) =~
             "[" <> String.duplicate("#", 30) <> "] try 1   timeout"
  end
end
