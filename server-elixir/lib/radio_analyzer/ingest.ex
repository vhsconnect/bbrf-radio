defmodule RadioAnalyzer.Ingest do
  @moduledoc """
  Polls the 'recent' radio-browser endpoints and upserts stations into
  SQLite, recording per-poll stats. The upsert mirrors the clojure
  original: `last_changed_at` only moves when the station's `changeuuid`
  actually changed since the last time we stored it.
  """

  alias RadioAnalyzer.{Env, IngestStat, RadioBrowser, Repo}
  require Logger

  # the endpoints we poll for 'recent' stations
  @recent_endpoints ["stations/lastchange", "stations/lastclick"]

  @station_columns [
    "changeuuid",
    "stationuuid",
    "serveruuid",
    "name",
    "url",
    "url_resolved",
    "homepage",
    "favicon",
    "tags",
    "country",
    "countrycode",
    "iso_3166_2",
    "state",
    "language",
    "languagecodes",
    "votes",
    "lastchangetime",
    "lastchangetime_iso8601",
    "codec",
    "bitrate",
    "hls",
    "lastcheckok",
    "lastchecktime",
    "lastchecktime_iso8601",
    "lastcheckoktime",
    "lastcheckoktime_iso8601",
    "lastlocalchecktime",
    "lastlocalchecktime_iso8601",
    "clicktimestamp",
    "clicktimestamp_iso8601",
    "clickcount",
    "clicktrend",
    "ssl_error",
    "geo_lat",
    "geo_long",
    "geo_distance",
    "has_extended_info"
  ]

  @placeholders Enum.map_join(0..(length(@station_columns) + 1), ", ", fn _ -> "?" end)

  @conflict_set Enum.map_join(
                  List.delete(@station_columns, "stationuuid"),
                  ", ",
                  &"#{&1} = excluded.#{&1}"
                )

  @upsert_sql """
  INSERT INTO stations (#{Enum.join(@station_columns, ", ")}, first_seen_at, last_changed_at)
  VALUES (#{@placeholders})
  ON CONFLICT(stationuuid) DO UPDATE SET
    #{@conflict_set},
    last_changed_at = CASE
      WHEN stations.changeuuid IS NOT excluded.changeuuid THEN excluded.last_changed_at
      ELSE stations.last_changed_at END
  """

  def poll_limit, do: Env.int("POLL_LIMIT", 1000)

  @doc "Poll both 'recent' endpoints. Returns %{endpoint => stats}; never throws."
  def poll_recent do
    Map.new(@recent_endpoints, fn endpoint -> {endpoint, poll_endpoint(endpoint)} end)
  end

  @doc """
  Poll one recent endpoint, upsert the returned stations and record
  ingest stats. Returns the stats map; never throws.
  """
  def poll_endpoint(endpoint) do
    start = System.monotonic_time(:millisecond)

    try do
      stations = RadioBrowser.api_get(endpoint, limit: poll_limit())
      counts = upsert_stations(stations)

      stats = %{
        row_count: length(stations),
        inserted: counts.inserted,
        updated: counts.updated,
        unchanged: counts.unchanged,
        duration_ms: System.monotonic_time(:millisecond) - start,
        error: nil
      }

      record_stats(endpoint, stats)
      stats
    rescue
      exception ->
        Logger.error(
          "ingest poll failed for #{endpoint}:\n" <>
            Exception.format(:error, exception, __STACKTRACE__)
        )

        stats = %{
          row_count: 0,
          inserted: 0,
          updated: 0,
          unchanged: 0,
          duration_ms: System.monotonic_time(:millisecond) - start,
          error: Exception.message(exception)
        }

        record_stats(endpoint, stats)
        stats
    end
  end

  @doc """
  Upsert a batch of station maps (string-keyed, as decoded from the API).
  Returns `%{inserted: n, updated: n, unchanged: n}` - 'updated' means
  the station's changeuuid changed since we last saw it, 'unchanged'
  means we stored it before with the same changeuuid.
  """
  def upsert_stations(stations) do
    now = now_iso()
    existing = existing_changeuuids(Enum.map(stations, & &1["stationuuid"]))

    counts =
      Enum.frequencies_by(stations, fn station ->
        prev = Map.get(existing, station["stationuuid"])

        cond do
          is_nil(prev) -> :inserted
          prev != station["changeuuid"] -> :updated
          true -> :unchanged
        end
      end)

    {:ok, _} =
      Repo.transaction(fn ->
        Enum.each(stations, fn station ->
          params =
            Enum.map(@station_columns, &bind(station[&1])) ++ [now, now]

          Repo.query!(@upsert_sql, params)
        end)
      end)

    %{
      inserted: Map.get(counts, :inserted, 0),
      updated: Map.get(counts, :updated, 0),
      unchanged: Map.get(counts, :unchanged, 0)
    }
  end

  @doc "Insert one bookkeeping row for a poll (also used by the wave/prune jobs)."
  def record_stats(endpoint, stats) do
    Repo.insert_all(IngestStat, [
      %{
        endpoint: endpoint,
        polled_at: now_iso(),
        row_count: stats.row_count,
        inserted: stats.inserted,
        updated: stats.updated,
        unchanged: stats.unchanged,
        duration_ms: stats.duration_ms,
        error: stats.error
      }
    ])
  end

  # stationuuid -> changeuuid for all stations already in the table,
  # in chunks of 500 to stay under the host parameter limit
  defp existing_changeuuids(uuids) do
    uuids
    |> Enum.reject(&is_nil/1)
    |> Enum.chunk_every(500)
    |> Enum.flat_map(fn chunk ->
      placeholders = Enum.map_join(chunk, ", ", fn _ -> "?" end)

      {:ok, %{rows: rows}} =
        Repo.query(
          "SELECT stationuuid, changeuuid FROM stations WHERE stationuuid IN (#{placeholders})",
          chunk
        )

      # sql rows are lists - Map.new needs {key, value} tuples
      Enum.map(rows, fn [stationuuid, changeuuid] -> {stationuuid, changeuuid} end)
    end)
    |> Map.new()
  end

  # normalize a JSON-decoded value for sqlite (true/false -> 1/0)
  defp bind(true), do: 1
  defp bind(false), do: 0
  defp bind(value), do: value

  defp now_iso, do: DateTime.to_iso8601(DateTime.utc_now())
end
