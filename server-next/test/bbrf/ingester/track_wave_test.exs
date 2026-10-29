defmodule BBRF.Ingester.TrackWaveTest do
  use ExUnit.Case, async: false

  alias BBRF.{Metatable, Repo}
  alias BBRF.Ingester.{Stations, Track, WorkQueue}
  alias BBRF.Ingester.Track.Strategy

  @adaptive Strategy.new("adaptive",
              discovery_per_wave: 500,
              icy_interval_minutes: 60,
              popular_clickcount: 20
            )

  setup do
    Metatable.reset_db!()
    :ok
  end

  defp wave(strategy \\ @adaptive), do: Strategy.select(strategy, Metatable.now(), 10)

  defp station_row(uuid) do
    %{rows: [row]} =
      Repo.query!(
        """
        SELECT meta_state, meta_fail_count, meta_last_title, meta_next_check_at
          FROM stations WHERE stationuuid = ?
        """,
        [uuid]
      )

    row
  end

  test "persist_wave stores changed titles and schedules every station" do
    Stations.upsert([
      Metatable.station(%{"stationuuid" => "playing"}),
      Metatable.station(%{"stationuuid" => "down"})
    ])

    [down, playing] = wave()

    counts =
      Track.persist_wave(
        [
          {playing, {"icecast", {:ok, Metatable.observation(%{stationuuid: "playing"})}}},
          {down, {"icecast", {:error, "timeout"}}}
        ],
        Metatable.now(),
        @adaptive
      )

    assert counts == %{changed: 1, fail: 1, icy: 0}

    assert %{rows: [["playing", "Artist - Song"]]} =
             Repo.query!("SELECT stationuuid, raw_title FROM track_observations")

    assert station_row("playing") == ["ok", 0, "Artist - Song", "2026-10-19T12:06:00.000000Z"]
    assert station_row("down") == ["unknown", 1, nil, "2026-10-19T12:15:00.000000Z"]
  end

  test "persist_wave emits one check event per station" do
    Stations.upsert([
      Metatable.station(%{"stationuuid" => "playing"}),
      Metatable.station(%{"stationuuid" => "down"})
    ])

    test_pid = self()

    :telemetry.attach(
      "check-test",
      [:bbrf, :track, :check],
      fn _event, _measurements, meta, _config -> send(test_pid, {:check, meta}) end,
      nil
    )

    on_exit(fn -> :telemetry.detach("check-test") end)

    [down, playing] = wave()

    Track.persist_wave(
      [
        {playing, {"icecast", {:ok, Metatable.observation(%{stationuuid: "playing"})}}},
        {down, {"icecast", {:error, "timeout"}}}
      ],
      Metatable.now(),
      @adaptive
    )

    assert_received {:check,
                     %{
                       station: %{stationuuid: "playing"},
                       outcome: :changed,
                       method: "icecast",
                       title: "Artist - Song",
                       reason: nil
                     }}

    assert_received {:check,
                     %{
                       station: %{stationuuid: "down"},
                       outcome: :fail,
                       title: nil,
                       reason: "timeout"
                     }}
  end

  test "persist_wave leaves stations edited during the wave due" do
    Stations.upsert([Metatable.station()])
    [station] = wave()

    Stations.upsert([Metatable.station(%{"changeuuid" => "change-2"})])
    Track.persist_wave([{station, {nil, {:error, "timeout"}}}], Metatable.now(), @adaptive)

    assert station_row("station-1") == ["unknown", 0, nil, nil]
  end

  test "persist_wave records which method produced the title" do
    Stations.upsert([Metatable.station()])
    [station] = wave()

    counts =
      Track.persist_wave(
        [{station, {"icy", {:ok, Metatable.observation()}}}],
        Metatable.now(),
        @adaptive
      )

    assert counts.icy == 1

    assert %{rows: [["icy", "2026-10-19T13:00:00.000000Z"]]} =
             Repo.query!("SELECT meta_source, meta_next_check_at FROM stations")
  end

  test "persist_wave keeps the due time when the strategy does not set one" do
    Stations.upsert([Metatable.station()])
    Repo.query!("UPDATE stations SET meta_next_check_at = '2026-11-01T00:00:00.000000Z'")
    sweep = Strategy.new("full-sweep", cycle_minutes: 1, retries_per_wave: 500, wave_minutes: 1)
    [station] = wave(sweep)

    Track.persist_wave(
      [{station, {"icecast", {:ok, Metatable.observation()}}}],
      Metatable.now(),
      sweep
    )

    assert station_row("station-1") == ["ok", 0, "Artist - Song", "2026-11-01T00:00:00.000000Z"]
  end

  test "poll_wave fetches the selected stations through the work queue" do
    start_supervised!({WorkQueue, lanes: [wave: []]})

    status_page = fn conn, _opts ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(
        200,
        Jason.encode!(%{icestats: %{source: %{title: "Artist - Song"}}})
      )
    end

    server =
      start_supervised!({Bandit, plug: status_page, ip: :loopback, port: 0, startup_log: false})

    {:ok, {_ip, port}} = ThousandIsland.listener_info(server)
    url = "http://127.0.0.1:#{port}/live"

    Stations.upsert([
      Metatable.station(%{"stationuuid" => "playing", "url" => url, "url_resolved" => url})
    ])

    assert %{row_count: 1, inserted: 1} = Track.poll_wave(@adaptive)

    assert %{rows: [["playing", "Artist - Song"]]} =
             Repo.query!("SELECT stationuuid, raw_title FROM track_observations")
  end
end
