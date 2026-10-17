defmodule RadioAnalyzer.TrackTest do
  use ExUnit.Case, async: true

  alias RadioAnalyzer.Track

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

    test "falls back to the first source when nothing matches" do
      assert Track.match_source("http://other-host:9000/c.mp3", @sources)["title"] == "A"
    end

    test "falls back when listenurl is missing" do
      assert Track.match_source("http://x/c.mp3", [%{"title" => "only"}])["title"] == "only"
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
    @obs %{
      stationuuid: "uuid",
      observed_at: "now",
      raw_title: "Artist - Song",
      artist: "Artist",
      title: "Song",
      metadata: nil
    }

    test "ok + changed title produces an observation" do
      assert {:ok, "Artist - Song", observation} = Track.classify("previous", {:ok, @obs})
      assert observation == @obs
    end

    test "ok + unchanged title only updates the station" do
      assert {:ok, "Artist - Song", nil} = Track.classify("Artist - Song", {:ok, @obs})
    end

    test "ok without a title never produces track data" do
      assert :no_metadata = Track.classify(nil, {:ok, %{@obs | raw_title: nil}})
    end

    test "no mount info / no status url demote to no-metadata" do
      assert :no_metadata = Track.classify(nil, :no_source)
      assert :no_metadata = Track.classify(nil, :no_status_url)
    end

    test "unreachable and error count as failures" do
      assert :fail = Track.classify(nil, {:unreachable, "HTTP 404"})
      assert :fail = Track.classify(nil, {:error, "econnrefused"})
    end
  end

  describe "Env" do
    test "int falls back to the default for missing or garbage values" do
      assert RadioAnalyzer.Env.int("DEFINITELY_NOT_SET_#{:erlang.unique_integer()}", 7) == 7
    end
  end
end
