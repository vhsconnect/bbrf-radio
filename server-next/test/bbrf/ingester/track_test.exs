defmodule BBRF.Ingester.TrackTest do
  use ExUnit.Case, async: true

  alias BBRF.Metatable
  alias BBRF.Ingester.Track

  describe "status_url/1" do
    test "builds scheme://host[:port]/status-json.xsl from a stream url" do
      assert Track.status_url("http://example.com:8000/mount.mp3") ==
               "http://example.com:8000/status-json.xsl"

      assert Track.status_url("https://radio.example.com/stream") ==
               "https://radio.example.com/status-json.xsl"

      assert Track.status_url("http://example.com") == "http://example.com/status-json.xsl"
    end

    test "nil for unparseable or scheme-less urls" do
      assert Track.status_url("not a url") == nil
      assert Track.status_url("example.com/stream") == nil
      assert Track.status_url("") == nil
      assert Track.status_url(nil) == nil
    end
  end

  describe "sources/1" do
    test "single source map becomes a one-element list" do
      assert Track.sources(%{"source" => %{"title" => "x"}}) == [%{"title" => "x"}]
    end

    test "array of mounts passes through" do
      mounts = [%{"listenurl" => "/a"}, %{"listenurl" => "/b"}]
      assert Track.sources(%{"source" => mounts}) == mounts
    end

    test "nil for missing icestats/source" do
      assert Track.sources(nil) == nil
      assert Track.sources(%{}) == nil
      assert Track.sources(%{"source" => "nonsense"}) == nil
    end
  end

  describe "match_source/2" do
    @sources [
      %{"listenurl" => "http://host:8000/a.mp3", "title" => "A"},
      %{"listenurl" => "http://host:8000/b.mp3", "title" => "B"}
    ]

    test "picks the mount matching the station's stream url path" do
      assert Track.match_source("http://other-host:9000/b.mp3", @sources)["title"] == "B"
    end

    test "nil when several mounts are served and none matches" do
      assert Track.match_source("http://other-host:9000/c.mp3", @sources) == nil
    end

    test "a single mount is taken whatever its listenurl" do
      assert Track.match_source("http://x/c.mp3", [%{"title" => "only"}])["title"] == "only"

      assert Track.match_source("http://x/c.mp3", [%{"listenurl" => "/a", "title" => "A"}])[
               "title"
             ] ==
               "A"
    end

    test "nil when there are no sources" do
      assert Track.match_source("http://x/y", nil) == nil
    end
  end

  describe "parse_title/1" do
    test "splits 'Artist - Title'" do
      assert Track.parse_title("Artist - Song") == %{artist: "Artist", title: "Song"}
    end

    test "splits on en and em dashes" do
      assert Track.parse_title("Artist – Song")[:artist] == "Artist"
      assert Track.parse_title("Artist — Song")[:artist] == "Artist"
    end

    test "whole string becomes the title when there is no dash" do
      assert Track.parse_title("Just A Title") == %{title: "Just A Title"}
    end

    test "nil stays nil-shaped" do
      assert Track.parse_title(nil) == %{}
    end
  end

  describe "classify/2" do
    test "a new title is a change carrying the observation" do
      observation = Metatable.observation()

      assert {:changed, "Artist - Song", ^observation} =
               Track.classify(
                 Metatable.candidate(%{last_title: "previous"}),
                 {:ok, observation}
               )
    end

    test "the same title is idle" do
      station = Metatable.candidate(%{meta_state: "ok", last_title: "Artist - Song"})
      assert Track.classify(station, {:ok, Metatable.observation()}) == :idle
    end

    test "a missing title keeps an ok station ok" do
      station = Metatable.candidate(%{meta_state: "ok", last_title: "Artist - Song"})
      assert Track.classify(station, {:ok, Metatable.observation(%{raw_title: nil})}) == :idle
    end

    test "a missing title on a station not yet ok is no metadata" do
      no_title = {:ok, Metatable.observation(%{raw_title: nil})}
      assert Track.classify(Metatable.candidate(), no_title) == :no_metadata
    end

    test "no mount, no status url and no status page are no metadata" do
      station = Metatable.candidate()
      assert Track.classify(station, :no_source) == :no_metadata
      assert Track.classify(station, :no_status_url) == :no_metadata
      assert Track.classify(station, :no_status_page) == :no_metadata
    end

    test "unreachable and errors are failures" do
      station = Metatable.candidate()
      assert Track.classify(station, {:unreachable, "HTTP 500"}) == :fail
      assert Track.classify(station, {:error, "timeout"}) == :fail
    end
  end

  describe "next_state/4" do
    test "a change makes the station ok, clears its counters and records the method" do
      station = Metatable.candidate(%{fail_count: 2, idle_count: 4})
      state = Track.next_state(station, {:changed, "t", %{}}, Metatable.now(), "icy")

      assert state == %{
               meta_state: "ok",
               meta_fail_count: 0,
               meta_idle_count: 0,
               meta_last_title: "t",
               meta_source: "icy",
               meta_checked_at: DateTime.to_iso8601(Metatable.now())
             }
    end

    test "an idle check counts up and keeps the known method" do
      station = Metatable.candidate(%{meta_state: "ok", meta_source: "icecast", idle_count: 2})

      assert %{meta_state: "ok", meta_idle_count: 3, meta_source: "icecast"} =
               Track.next_state(station, :idle, Metatable.now())
    end

    test "no metadata forgets the method and counts repeats" do
      station = Metatable.candidate(%{meta_source: "icy"})
      first = Track.next_state(station, :no_metadata, Metatable.now(), "icy")
      assert %{meta_state: "no-metadata", meta_idle_count: 1, meta_source: nil} = first

      again = Metatable.candidate(%{meta_state: "no-metadata", idle_count: 1})
      assert Track.next_state(again, :no_metadata, Metatable.now()).meta_idle_count == 2
    end

    test "the third failure in a row marks the station dead, keeping its method" do
      states =
        for fails <- 0..2 do
          Metatable.candidate(%{fail_count: fails, meta_source: "icy"})
          |> Track.next_state(:fail, Metatable.now())
        end

      assert Enum.map(states, & &1.meta_state) == ["unknown", "unknown", "dead"]
      assert Enum.map(states, & &1.meta_source) == ["icy", "icy", "icy"]
    end
  end
end
