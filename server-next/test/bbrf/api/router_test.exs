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

  defp call_get(path), do: json(call(:get, path))

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

    Repo.query!(
      "INSERT INTO station_metrics (stationuuid, metric, value, sample, computed_at) VALUES ('station-1', 'balance', 0.5, 60, 'run-1')"
    )

    assert [
             %{"stationuuid" => "station-2", "metrics" => %{}},
             %{
               "stationuuid" => "station-1",
               "name" => "Example FM",
               "metrics" => %{"balance" => %{"value" => 0.5, "sample" => 60}}
             }
           ] =
             json(call(:get, "/bytrack/AC%2FDC"))

    System.put_env("ITEMS_PER_PAGE", "1")
    on_exit(fn -> System.delete_env("ITEMS_PER_PAGE") end)

    assert [%{"stationuuid" => "station-1"}] = json(call(:get, "/bytrack/thunder?offset=1"))
    assert json(call(:get, "/bytrack/thunder?offset=2")) == []
  end

  test "GET /metrics lists the metric names a /by* route sorts on" do
    assert call_get("/metrics") == BBRF.Metrics.names()
  end

  test "GET /by* with ?sort ranks the catalogue by a metric, unscored stations last" do
    Metatable.reset_db!()

    Stations.upsert([
      Metatable.station(%{"name" => "Low FM", "tags" => "jazz,soul"}),
      Metatable.station(%{"stationuuid" => "station-2", "name" => "High FM", "tags" => "jazz"}),
      Metatable.station(%{
        "stationuuid" => "station-3",
        "name" => "Unscored FM",
        "tags" => "jazz"
      }),
      Metatable.station(%{"stationuuid" => "station-4", "name" => "Rock FM", "tags" => "rock"}),
      Metatable.station(%{"stationuuid" => "station-5", "name" => "Gone FM", "tags" => "jazz"})
    ])

    Repo.query!("UPDATE stations SET meta_state = 'removed' WHERE stationuuid = 'station-5'")

    Repo.query!("""
    INSERT INTO station_metrics (stationuuid, metric, value, sample, computed_at)
    VALUES ('station-1', 'balance', 0.2, 60, 'run-1'),
           ('station-2', 'balance', 0.9, 60, 'run-1'),
           ('station-4', 'balance', 1.0, 60, 'run-1'),
           ('station-5', 'balance', 1.0, 60, 'run-1')
    """)

    names = fn path -> path |> call_get() |> Enum.map(& &1["name"]) end

    assert names.("/bytag/jazz?sort=balance") == ["High FM", "Low FM", "Unscored FM"]
    assert names.("/byname/fm?sort=balance") == ["Rock FM", "High FM", "Low FM", "Unscored FM"]

    assert [%{"metrics" => %{"balance" => %{"value" => 0.9}}, "has_extended_info" => false} | _] =
             call_get("/bytag/jazz?sort=balance")

    System.put_env("ITEMS_PER_PAGE", "2")
    on_exit(fn -> System.delete_env("ITEMS_PER_PAGE") end)

    assert names.("/bytag/jazz?sort=balance&offset=1") == ["Unscored FM"]

    assert call(:get, "/bytag/jazz?sort=loudness").status == 400
  end

  test "GET /by* with ?sort=hi_qlty or lo_qlty ranks the catalogue by quality, unknown last" do
    Metatable.reset_db!()

    Stations.upsert([
      Metatable.station(%{"name" => "Mid FM", "codec" => "MP3", "bitrate" => 128}),
      Metatable.station(%{
        "stationuuid" => "station-2",
        "name" => "Hi FM",
        "codec" => "MP3",
        "bitrate" => 320
      }),
      Metatable.station(%{
        "stationuuid" => "station-3",
        "name" => "Unknown FM",
        "codec" => "MP3",
        "bitrate" => 0
      }),
      Metatable.station(%{
        "stationuuid" => "station-4",
        "name" => "Lo FM",
        "codec" => "MP3",
        "bitrate" => 32
      })
    ])

    names = fn path -> path |> call_get() |> Enum.map(& &1["name"]) end

    assert names.("/byname/fm?sort=hi_qlty") == ["Hi FM", "Mid FM", "Lo FM", "Unknown FM"]
    assert names.("/byname/fm?sort=lo_qlty") == ["Lo FM", "Mid FM", "Hi FM", "Unknown FM"]

    assert [%{"metrics" => %{"lo_qlty" => %{"value" => 32.0, "sample" => 32}}} | _] =
             call_get("/byname/fm?sort=lo_qlty")
  end

  test "GET /by* with ?sort=hi_clicks or lo_clicks ranks the catalogue by clicks, none last" do
    Metatable.reset_db!()

    Stations.upsert([
      Metatable.station(%{"name" => "Mid FM", "clickcount" => 40}),
      Metatable.station(%{"stationuuid" => "station-2", "name" => "Hi FM", "clickcount" => 900}),
      Metatable.station(%{"stationuuid" => "station-3", "name" => "Idle FM", "clickcount" => 0}),
      Metatable.station(%{"stationuuid" => "station-4", "name" => "Lo FM", "clickcount" => 2})
    ])

    names = fn path -> path |> call_get() |> Enum.map(& &1["name"]) end

    assert names.("/byname/fm?sort=hi_clicks") == ["Hi FM", "Mid FM", "Lo FM", "Idle FM"]
    assert names.("/byname/fm?sort=lo_clicks") == ["Lo FM", "Mid FM", "Hi FM", "Idle FM"]

    assert [%{"metrics" => %{"lo_clicks" => %{"value" => 2, "sample" => 2}}} | _] =
             call_get("/byname/fm?sort=lo_clicks")
  end

  test "GET /bytrack/:query with ?sort ranks the stations that played a match" do
    Metatable.reset_db!()

    Stations.upsert([
      Metatable.station(),
      Metatable.station(%{"stationuuid" => "station-2", "name" => "Other FM"}),
      Metatable.station(%{"stationuuid" => "station-3", "name" => "Silent FM"})
    ])

    Repo.insert_all(TrackObservation, [
      Metatable.observation(%{title: "Thunderstruck"}),
      Metatable.observation(%{stationuuid: "station-2", title: "Thunderstruck"})
    ])

    Repo.query!("""
    INSERT INTO station_metrics (stationuuid, metric, value, sample, computed_at)
    VALUES ('station-2', 'balance', 0.9, 60, 'run-1'),
           ('station-3', 'balance', 1.0, 60, 'run-1')
    """)

    assert ["station-2", "station-1"] =
             "/bytrack/thunder?sort=balance" |> call_get() |> Enum.map(& &1["stationuuid"])
  end

  test "GET /tracks filters, sorts and pages plays joined with their station" do
    Metatable.reset_db!()

    Stations.upsert([
      Metatable.station(%{"countrycode" => "SE", "tags" => "jazz"}),
      Metatable.station(%{
        "stationuuid" => "station-2",
        "name" => "Another FM",
        "countrycode" => "DE"
      })
    ])

    Repo.insert_all(TrackObservation, [
      Metatable.observation(%{title: "First"}),
      Metatable.observation(%{
        stationuuid: "station-2",
        observed_at: "2026-10-19T12:05:00.000000Z",
        title: "Second"
      })
    ])

    titles = fn path -> path |> call_get() |> Enum.map(& &1["title"]) end

    assert titles.("/tracks") == ["Second", "First"]
    assert titles.("/tracks?dir=asc") == ["First", "Second"]
    assert titles.("/tracks?sort=country&dir=asc") == ["Second", "First"]
    assert titles.("/tracks?sort=country&dir=desc") == ["First", "Second"]
    assert titles.("/tracks?countrycode=SE") == ["First"]
    assert titles.("/tracks?tag=jazz&countrycode=se") == ["First"]
    assert titles.("/tracks?station=another") == ["Second"]
    assert titles.("/tracks?q=second") == ["Second"]

    assert [%{"station" => %{"name" => "Another FM"}} | _] = call_get("/tracks")

    assert call(:get, "/tracks?sort=random").status == 400
    assert call(:get, "/tracks?dir=sideways").status == 400

    System.put_env("TRACKS_PER_PAGE", "1")
    on_exit(fn -> System.delete_env("TRACKS_PER_PAGE") end)

    assert titles.("/tracks") == ["Second"]
    assert titles.("/tracks?offset=1") == ["First"]
  end

  test "import_json copies favorites from a node storage.json and skips duplicates" do
    path = Path.join(System.tmp_dir!(), "storage-#{System.unique_integer([:positive])}.json")
    File.write!(path, Jason.encode!(%{"apiVersion" => 1, "favorites" => [@station]}))
    on_exit(fn -> File.rm(path) end)

    Favorites.add(@station)
    assert Favorites.import_json(path) == 1
    assert json(call(:get, "/favorites")) == [@station]
  end

  test "GET /nowplaying/:uuid is 204 for a station we do not know" do
    conn = call(:get, "/nowplaying/missing")

    assert conn.status == 204
    assert conn.resp_body == ""
  end
end
