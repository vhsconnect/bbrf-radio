defmodule RadioAnalyzer.Ingest do
  @moduledoc """
  Polls the 'recent' radio-browser endpoints and upserts stations into
  SQLite, recording per-poll stats. Each endpoint runs on its own
  schedule:

    * `poll_changes/0` (`stations/lastchange`) is the incremental feed
      between full catalogue syncs (`RadioAnalyzer.Catalogue`): stations
      added or edited upstream show up here first
    * `poll_clicks/0` (`stations/lastclick`) only refreshes check and click
      data for the stations people listen to; once the catalogue is
      complete it brings in no new stations, so it runs far less often

  The upsert mirrors the clojure original: `last_changed_at` only moves
  when the station's `changeuuid` actually changed since the last time
  we stored it.
  """

  alias RadioAnalyzer.{Env, IngestStat, RadioBrowser, Repo}
  require Logger

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

  @insert_columns @station_columns ++ ["first_seen_at", "last_changed_at", "synced_at"]

  @row_placeholders "(" <> Enum.map_join(@insert_columns, ", ", fn _ -> "?" end) <> ")"

  @conflict_set Enum.map_join(
                  List.delete(@station_columns, "stationuuid"),
                  ", ",
                  &"#{&1} = excluded.#{&1}"
                )

  # SET expressions read the pre-update row, so every CASE compares the
  # stored changeuuid with the incoming one. An edited station (new
  # changeuuid) gets its failure history cleared and is due right away,
  # since its stream url may have changed; a station a full sync had
  # marked 'removed' comes back as 'unknown'.
  @upsert_conflict """
  ON CONFLICT(stationuuid) DO UPDATE SET
    #{@conflict_set},
    last_changed_at = CASE
      WHEN stations.changeuuid IS NOT excluded.changeuuid THEN excluded.last_changed_at
      ELSE stations.last_changed_at END,
    synced_at = COALESCE(excluded.synced_at, stations.synced_at),
    meta_state = CASE
      WHEN stations.meta_state = 'removed' THEN 'unknown'
      WHEN stations.changeuuid IS NOT excluded.changeuuid
           AND stations.meta_state IN ('dead', 'no-metadata') THEN 'unknown'
      ELSE stations.meta_state END,
    meta_fail_count = CASE
      WHEN stations.changeuuid IS NOT excluded.changeuuid THEN 0
      ELSE stations.meta_fail_count END,
    meta_idle_count = CASE
      WHEN stations.changeuuid IS NOT excluded.changeuuid THEN 0
      ELSE stations.meta_idle_count END,
    meta_next_check_at = CASE
      WHEN stations.meta_state = 'removed'
           OR stations.changeuuid IS NOT excluded.changeuuid THEN NULL
      ELSE stations.meta_next_check_at END
  """

  # rows per INSERT; 400 * 39 columns stays under sqlite's 32766 host parameters
  @upsert_chunk 400

  def poll_limit, do: Env.int("POLL_LIMIT", 1000)

  def changes_interval_minutes, do: Env.int("CHANGES_POLL_MINUTES", 10)
  def clicks_interval_minutes, do: Env.int("CLICKS_POLL_MINUTES", 360)

  @doc "Poll the stations added or edited lately. Returns the stats; never throws."
  def poll_changes, do: poll_endpoint("stations/lastchange")

  @doc "Poll the stations clicked lately. Returns the stats; never throws."
  def poll_clicks, do: poll_endpoint("stations/lastclick")

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

  `synced_at:` stamps the rows as seen by the full sync that started then.
  """
  def upsert_stations(stations, opts \\ []) do
    now = now_iso()
    synced_at = Keyword.get(opts, :synced_at)

    stations =
      stations
      |> Enum.reject(&is_nil(&1["stationuuid"]))
      |> Enum.uniq_by(& &1["stationuuid"])

    existing = existing_changeuuids(Enum.map(stations, & &1["stationuuid"]))

    counts =
      Enum.frequencies_by(stations, fn station ->
        prev = Map.get(existing, station["stationuuid"])

        cond do
          not Map.has_key?(existing, station["stationuuid"]) -> :inserted
          prev != station["changeuuid"] -> :updated
          true -> :unchanged
        end
      end)

    {:ok, _} =
      Repo.transaction(fn ->
        stations
        |> Enum.chunk_every(@upsert_chunk)
        |> Enum.each(fn chunk ->
          params =
            Enum.flat_map(chunk, fn station ->
              Enum.map(@station_columns, &bind(station[&1])) ++ [now, now, synced_at]
            end)

          Repo.query!(upsert_sql(length(chunk)), params)
        end)
      end)

    %{
      inserted: Map.get(counts, :inserted, 0),
      updated: Map.get(counts, :updated, 0),
      unchanged: Map.get(counts, :unchanged, 0)
    }
  end

  defp upsert_sql(rows) do
    """
    INSERT INTO stations (#{Enum.join(@insert_columns, ", ")})
    VALUES #{Enum.map_join(1..rows, ", ", fn _ -> @row_placeholders end)}
    #{@upsert_conflict}
    """
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
