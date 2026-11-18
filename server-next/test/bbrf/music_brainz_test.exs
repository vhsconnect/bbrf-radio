defmodule BBRF.MusicBrainzTest do
  use ExUnit.Case, async: false

  import Plug.Conn
  alias BBRF.MusicBrainz

  # index 1: 503s still to answer on /artist/busy; index 2: requests it got
  setup do
    busy = :counters.new(2, [])
    test_pid = self()

    plug = fn conn, _opts ->
      conn = fetch_query_params(conn)

      case conn.request_path do
        "/ws/2/artist/missing" ->
          send_resp(conn, 404, "")

        "/ws/2/artist/busy" ->
          :counters.add(busy, 2, 1)
          send(test_pid, {:busy_at, System.monotonic_time(:millisecond)})

          if :counters.get(busy, 1) > 0 do
            :counters.sub(busy, 1, 1)
            send_resp(conn, 503, "")
          else
            conn |> put_resp_content_type("application/json") |> send_resp(200, ~s({"id":"busy"}))
          end

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

    {:ok, busy: busy}
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

  test "retries a busy answer and returns what follows", %{busy: busy} do
    :counters.put(busy, 1, 3)

    assert MusicBrainz.lookup(:artist, "busy") == %{"id" => "busy"}
    assert :counters.get(busy, 2) == 4
  end

  test "raises once MusicBrainz stays busy past the retries", %{busy: busy} do
    :counters.put(busy, 1, 10)

    assert_raise RuntimeError, ~r/HTTP 503/, fn -> MusicBrainz.lookup(:artist, "busy") end
    assert :counters.get(busy, 2) == 4
  end

  test "waits two intervals before retrying a busy answer", %{busy: busy} do
    System.put_env("MUSICBRAINZ_INTERVAL_MS", "50")
    :counters.put(busy, 1, 1)

    MusicBrainz.lookup(:artist, "busy")

    assert_received {:busy_at, first}
    assert_received {:busy_at, retry}
    assert retry - first >= 90
  end

  test "a busy answer holds back the next caller too", %{busy: busy} do
    System.put_env("MUSICBRAINZ_INTERVAL_MS", "50")
    :counters.put(busy, 1, 4)

    assert_raise RuntimeError, fn -> MusicBrainz.lookup(:artist, "busy") end
    assert_received {:busy_at, _first}
    assert_received {:busy_at, _second}
    assert_received {:busy_at, _third}
    assert_received {:busy_at, last_busy}

    assert MusicBrainz.genres()["at"] - last_busy >= 390
  end

  test "concurrent requests are spaced one interval apart" do
    MusicBrainz.genres()
    System.put_env("MUSICBRAINZ_INTERVAL_MS", "100")

    [first, second, third] =
      1..3
      |> Enum.map(fn _ -> Task.async(fn -> MusicBrainz.genres()["at"] end) end)
      |> Task.await_many()
      |> Enum.sort()

    assert second - first >= 90
    assert third - second >= 90
  end

  test "reports every request, a retried one each time, with its wait for a slot", %{busy: busy} do
    test_pid = self()
    handler = "musicbrainz-test-#{inspect(test_pid)}"

    :telemetry.attach(
      handler,
      [:bbrf, :musicbrainz, :request],
      fn _event, measurements, meta, pid ->
        if self() == pid, do: send(pid, {:request, meta.path, meta.result, measurements})
      end,
      test_pid
    )

    on_exit(fn -> :telemetry.detach(handler) end)
    :counters.put(busy, 1, 1)

    MusicBrainz.lookup(:artist, "busy")

    assert_received {:request, "artist/busy", {:ok, 503}, _measurements}
    assert_received {:request, "artist/busy", {:ok, 200}, %{duration: duration, wait: wait}}
    assert duration > 0 and wait >= 0
  end
end
