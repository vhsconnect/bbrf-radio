defmodule BBRF.Ingester.Stations do
  @moduledoc """
  Writes radio-browser station structs into the `stations` table, for
  the catalogue sync and the recent polls. `last_changed_at` only moves
  when the station's `changeuuid` actually changed since the last time
  we stored it.
  """

  alias BBRF.Repo

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

  @doc "The radio-browser station fields, as stored in the stations table."
  def api_columns, do: @station_columns

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

  @doc """
  Upsert a batch of station maps (string-keyed, as decoded from the API).
  Returns `%{inserted: n, updated: n, unchanged: n}` - 'updated' means
  the station's changeuuid changed since we last saw it, 'unchanged'
  means we stored it before with the same changeuuid.

  `synced_at:` stamps the rows as seen by the full sync that started then.
  """
  def upsert(stations, opts \\ []) do
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
