defmodule BBRF.MusicBrainzTest do
  use ExUnit.Case, async: false

  import Plug.Conn
  alias BBRF.MusicBrainz

  setup do
    plug = fn conn, _opts ->
      conn = fetch_query_params(conn)

      case conn.request_path do
        "/ws/2/artist/missing" ->
          send_resp(conn, 404, "")

        path ->
          conn
          |> put_resp_content_type("application/json")
          |> send_resp(
            200,
            Jason.encode!(%{
              path: path,
              query: conn.query_string,
              params: conn.query_params,
              user_agent: get_req_header(conn, "user-agent"),
              at: System.monotonic_time(:millisecond)
            })
          )
      end
    end

    server = start_supervised!({Bandit, plug: plug, ip: :loopback, port: 0, startup_log: false})
    {:ok, {_ip, port}} = ThousandIsland.listener_info(server)

    System.put_env("MUSICBRAINZ_BASE_URL", "http://127.0.0.1:#{port}/ws/2")
    System.put_env("MUSICBRAINZ_INTERVAL_MS", "0")

    on_exit(fn ->
      System.delete_env("MUSICBRAINZ_BASE_URL")
      System.delete_env("MUSICBRAINZ_INTERVAL_MS")
    end)
  end

  test "looks up an entity by mbid with its includes, as json, with the user agent" do
    response = MusicBrainz.lookup(:release_group, "rg-1", inc: ~w(artists tags))

    assert response["path"] == "/ws/2/release-group/rg-1"
    assert response["query"] =~ "inc=artists+tags"
    assert response["params"]["fmt"] == "json"
    assert response["user_agent"] == [MusicBrainz.user_agent()]
  end

  test "a lookup of an unknown mbid is nil" do
    assert MusicBrainz.lookup(:artist, "missing") == nil
  end

  test "browses by a linked entity, joining release types" do
    response = MusicBrainz.browse(:release_group, :artist, "a-1", type: ~w(album ep), limit: 100)

    assert response["path"] == "/ws/2/release-group"

    assert %{"artist" => "a-1", "type" => "album|ep", "limit" => "100"} =
             response["params"]
  end

  test "browses releases by track artist and by release group" do
    assert %{"track_artist" => "a-1"} =
             MusicBrainz.browse(:release, :track_artist, "a-1")["params"]

    assert %{"release-group" => "rg-1"} =
             MusicBrainz.browse(:release, :release_group, "rg-1")["params"]
  end

  test "refuses a browse MusicBrainz does not offer" do
    assert_raise ArgumentError, fn -> MusicBrainz.browse(:artist, :label, "l-1") end
  end

  test "searches with a phrase escaped from untrusted text" do
    query = "artist:" <> MusicBrainz.phrase(~S(The "Best" \ Band))
    response = MusicBrainz.search(:artist, query, limit: 5)

    assert response["path"] == "/ws/2/artist"
    assert response["params"]["query"] == ~S(artist:"The \"Best\" \\ Band")
  end

  test "looks up a url entity by its resource" do
    response = MusicBrainz.url("https://example.com/band")

    assert response["path"] == "/ws/2/url"
    assert response["params"]["resource"] == "https://example.com/band"
  end

  test "concurrent requests are spaced one interval apart" do
    System.put_env("MUSICBRAINZ_INTERVAL_MS", "100")

    [first, second, third] =
      1..3
      |> Enum.map(fn _ -> Task.async(fn -> MusicBrainz.genres()["at"] end) end)
      |> Task.await_many()
      |> Enum.sort()

    assert second - first >= 90
    assert third - second >= 90
  end
end
