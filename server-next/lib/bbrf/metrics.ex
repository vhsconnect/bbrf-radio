defmodule BBRF.Metrics do
  @moduledoc """
  Scores stations on what they played over the last METRICS_WINDOW_DAYS
  (default 60) and stores the scores in `station_metrics`, a row per
  station and metric (`all/0`). Run by hand with `BBRF.Metrics.CLI` on
  the node that ingests; `BBRF.Sync` copies the rows to the hub.

  A run goes through the stations played in the window in chunks: each
  metric reads a chunk in one query and writes it in one statement, so
  the ingester's writes get in between, whatever the journal mode. Every
  row a run writes carries the run's start as `computed_at`. Once a
  metric has gone through every chunk, its rows from earlier runs
  (stations it no longer scores) are deleted, and after the run the rows
  of metrics no longer listed. Each metric records its outcome in
  ingest_stats under `metric:<name>`, which emits `[:bbrf, :ingest, :stat]`,
  and emits `[:bbrf, :metrics, :chunk]` (`done` and `total` chunks,
  `metric` name) after each chunk.
  """

  require Logger
  alias BBRF.{Env, History, IngestStat, Repo}
  alias BBRF.Ingester.Stations
  alias BBRF.Metrics.{Balance, International, NoSsAds}

  @chunk 500

  def window_days, do: Env.int("METRICS_WINDOW_DAYS", 60)

  @doc "The fewest plays in the window a station needs to be scored."
  def min_plays, do: Env.int("METRICS_MIN_PLAYS", 50)

  def all, do: [International, Balance, NoSsAds]

  def names, do: Enum.map(all(), & &1.name())

  @doc """
  Compute `metrics` once at `now`. A metric that raises is recorded and
  skipped and keeps its previous rows. Returns `[{name, :ok | {:error, message}}]`.
  """
  def run(metrics \\ all(), now \\ DateTime.utc_now()) do
    computed_at = DateTime.to_iso8601(now)
    since = now |> DateTime.add(-window_days(), :day) |> DateTime.to_iso8601()
    stations = stations(since)

    results = Enum.map(metrics, &{&1.name(), run_metric(&1, stations, since, computed_at)})
    drop_unlisted(Enum.map(metrics, & &1.name()))
    results
  end

  @doc """
  `stations` (radio-browser station maps) each with a `"metrics"` map of
  its stored rows by metric name, as `%{"value" => value, "sample" => sample}`.
  A station without rows gets an empty map.
  """
  def enrich([]), do: []

  def enrich(stations) when is_list(stations) do
    by_station = for_stations(Enum.map(stations, & &1["stationuuid"]))

    Enum.map(stations, fn station ->
      Map.put(station, "metrics", Map.get(by_station, station["stationuuid"], %{}))
    end)
  end

  @doc """
  Catalogue stations matching `filter` (`BBRF.History.station_condition/1`),
  highest `metric` value first, enriched like `enrich/1`. Stations without
  a value come last; ties go by name. Stations the catalogue sync marked
  removed are left out.
  """
  @spec ranked({atom(), String.t()}, String.t(), pos_integer(), non_neg_integer()) :: [map()]
  def ranked(filter, metric, limit, offset) do
    {condition, params} = History.station_condition(filter)

    %{rows: rows} =
      Repo.query!(
        """
        SELECT #{Enum.map_join(Stations.api_columns(), ", ", &"s.#{&1}")}
          FROM stations s
          LEFT JOIN station_metrics m ON m.stationuuid = s.stationuuid AND m.metric = ?
         WHERE s.meta_state != 'removed' AND #{condition}
         ORDER BY m.value IS NULL, m.value DESC, s.name COLLATE NOCASE, s.stationuuid
         LIMIT ? OFFSET ?
        """,
        [metric | params] ++ [limit, offset]
      )

    rows
    |> Enum.map(&Stations.to_api/1)
    |> enrich()
  end

  defp for_stations(stationuuids) do
    %{rows: rows} =
      Repo.query!(
        """
        SELECT stationuuid, metric, value, sample
          FROM station_metrics
         WHERE stationuuid IN (SELECT value FROM json_each(?))
        """,
        [Jason.encode!(stationuuids)]
      )

    rows
    |> Enum.group_by(&hd/1, fn [_stationuuid, metric, value, sample] ->
      {metric, %{"value" => value, "sample" => sample}}
    end)
    |> Map.new(fn {stationuuid, metrics} -> {stationuuid, Map.new(metrics)} end)
  end

  @doc "SQL placeholders for an `IN` list of `values`."
  def placeholders(values), do: Enum.map_join(values, ", ", fn _ -> "?" end)

  defp stations(since) do
    %{rows: rows} =
      Repo.query!(
        "SELECT DISTINCT stationuuid FROM track_observations WHERE observed_at >= ? ORDER BY stationuuid",
        [since]
      )

    List.flatten(rows)
  end

  defp run_metric(metric, stations, since, computed_at) do
    start = System.monotonic_time(:millisecond)
    chunks = Enum.chunk_every(stations, @chunk)
    total = length(chunks)

    try do
      written =
        chunks
        |> Enum.with_index(1)
        |> Enum.reduce(0, fn {chunk, done}, written ->
          written = written + write(metric.name(), metric.compute(chunk, since), computed_at)

          :telemetry.execute(
            [:bbrf, :metrics, :chunk],
            %{done: done, total: total},
            %{metric: metric.name()}
          )

          written
        end)

      Repo.query!(
        "DELETE FROM station_metrics WHERE metric = ? AND computed_at < ?",
        [metric.name(), computed_at]
      )

      record(metric, length(stations), written, nil, start)
      :ok
    rescue
      exception ->
        Logger.error(
          "metric #{metric.name()} failed:\n" <>
            Exception.format(:error, exception, __STACKTRACE__)
        )

        record(metric, length(stations), 0, Exception.message(exception), start)
        {:error, Exception.message(exception)}
    end
  end

  defp write(_name, [], _computed_at), do: 0

  defp write(name, rows, computed_at) do
    entries =
      Enum.map(rows, fn {stationuuid, value, sample} ->
        %{
          stationuuid: stationuuid,
          metric: name,
          value: value,
          sample: sample,
          computed_at: computed_at
        }
      end)

    {written, _} =
      Repo.insert_all("station_metrics", entries,
        on_conflict: {:replace, [:value, :sample, :computed_at]},
        conflict_target: [:stationuuid, :metric]
      )

    written
  end

  defp drop_unlisted(names) do
    Repo.query!("DELETE FROM station_metrics WHERE metric NOT IN (#{placeholders(names)})", names)
  end

  defp record(metric, stations, written, error, start) do
    IngestStat.record("metric:#{metric.name()}", %{
      row_count: stations,
      inserted: written,
      updated: 0,
      unchanged: 0,
      duration_ms: System.monotonic_time(:millisecond) - start,
      error: error
    })
  end
end
