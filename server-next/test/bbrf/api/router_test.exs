defmodule BBRF.API.RouterTest do
  use ExUnit.Case, async: false
  import Plug.Test
  import Plug.Conn

  alias BBRF.{Favorites, Metatable, Repo, TrackObservation}
  alias BBRF.API.Router
  alias BBRF.Ingester.Stations

  @station %{
    "stationuuid" => "abc-123",
    "url" => "http://example.com/stream",
    "name" => "Example FM",
    "countrycode" => "SE",
    "bitrate" => 128
  }

  setup do
    Repo.query!("DELETE FROM favorites")

    dir = Path.join(System.tmp_dir!(), "bbrf-static-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    File.write!(Path.join(dir, "index.html"), "<html>bbrf</html>")
    File.write!(Path.join(dir, "secret.txt"), "nope")
    System.put_env("STATIC_DIR", dir)

    on_exit(fn ->
      System.delete_env("STATIC_DIR")
      File.rm_rf!(dir)
    end)

    :ok
  end

  defp call(method, path, body \\ "") do
    Router.call(conn(method, path, body), Router.init([]))
  end

  defp json(conn), do: Jason.decode!(conn.resp_body)

  test "GET /fader reports the default fader value" do
    conn = call(:get, "/fader")

    assert conn.status == 200
    assert json(conn) == %{"value" => 25}
  end

  test "GET / serves index.html from STATIC_DIR" do
    conn = call(:get, "/")

    assert conn.status == 200
    assert conn.resp_body == "<html>bbrf</html>"
    assert get_resp_header(conn, "content-type") == ["text/html; charset=utf-8"]
  end

  test "GET serves only the allowlisted bundle files" do
    assert call(:get, "/secret.txt").status == 404
  end

  test "unknown paths are 404" do
    assert call(:get, "/nowhere").status == 404
  end

  test "favorites are added, listed in order, and removed" do
    assert json(call(:get, "/favorites")) == []

    added = call(:post, "/write/addStation/abc-123", Jason.encode!(@station))
    assert json(added) == [@station]

    call(
      :post,
      "/write/addStation/def-456",
      Jason.encode!(%{@station | "stationuuid" => "def-456"})
    )

    assert [%{"stationuuid" => "abc-123"}, %{"stationuuid" => "def-456"}] =
             json(call(:get, "/favorites"))

    assert [%{"stationuuid" => "def-456"}] = json(call(:post, "/write/removeStation/abc-123"))
  end

  test "adding a favorite twice keeps a single row in its original place" do
    call(:post, "/write/addStation/abc-123", Jason.encode!(@station))
    call(:post, "/write/addStation/abc-123", Jason.encode!(@station))

    assert json(call(:get, "/favorites")) == [@station]
  end

  test "GET /bytrack/:query finds the stations that played a matching track" do
    Metatable.reset_db!()

    Stations.upsert([
      Metatable.station(),
      Metatable.station(%{"stationuuid" => "station-2", "name" => "Other FM"})
    ])

    Repo.insert_all(TrackObservation, [
      Metatable.observation(%{
        raw_title: "AC/DC - Thunderstruck",
        artist: "AC/DC",
        title: "Thunderstruck"
      }),
      Metatable.observation(%{
        stationuuid: "station-2",
        observed_at: "2026-10-19T12:05:00.000000Z",
        raw_title: "AC/DC - Thunderstruck",
        artist: "AC/DC",
        title: "Thunderstruck"
      })
    ])

    assert [
             %{"stationuuid" => "station-2"},
             %{"stationuuid" => "station-1", "name" => "Example FM"}
           ] =
             json(call(:get, "/bytrack/AC%2FDC"))

    System.put_env("ITEMS_PER_PAGE", "1")
    on_exit(fn -> System.delete_env("ITEMS_PER_PAGE") end)

    assert [%{"stationuuid" => "station-1"}] = json(call(:get, "/bytrack/thunder?offset=1"))
    assert json(call(:get, "/bytrack/thunder?offset=2")) == []
  end

  test "import_json copies favorites from a node storage.json and skips duplicates" do
    path = Path.join(System.tmp_dir!(), "storage-#{System.unique_integer([:positive])}.json")
    File.write!(path, Jason.encode!(%{"apiVersion" => 1, "favorites" => [@station]}))
    on_exit(fn -> File.rm(path) end)

    Favorites.add(@station)
    assert Favorites.import_json(path) == 1
    assert json(call(:get, "/favorites")) == [@station]
  end
end
