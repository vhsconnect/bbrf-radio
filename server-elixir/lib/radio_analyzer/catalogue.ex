defmodule RadioAnalyzer.Catalogue do
  @moduledoc """
  Full copy of the radio-browser station list. The 'recent' polls in
  `RadioAnalyzer.Ingest` only see stations someone clicked or edited
  lately; this pages through `/json/stations` so the long tail gets
  catalogued too. It runs when the last successful sync is older than
  FULL_SYNC_HOURS (default 168), so restarts do not re-download it.

  Pages are ordered by change time, so stations added or edited during
  the sync land on the last page, and consecutive pages overlap so a
  deletion upstream cannot shift a station past a page boundary.
  Stations a completed sync did not see are marked 'removed' rather
  than deleted, so their track observations keep their station; any
  later sync or poll that sees them again brings them back.
  """

  alias RadioAnalyzer.{Env, Ingest, RadioBrowser, Repo}
  require Logger

  @endpoint "stations-full"
  @page_size 10_000
  @overlap 200
  @page_timeout_ms 60_000

  # a sync seeing fewer than this share of the stations we hold is
  # treated as a broken response, not as mass removal upstream
  @min_seen_ratio 0.5

  def interval_hours, do: Env.int("FULL_SYNC_HOURS", 168)

  def sync_if_due(opts \\ []) do
    if due?(), do: full_sync(opts), else: :not_due
  end

  def due? do
    cutoff =
      DateTime.utc_now() |> DateTime.add(-interval_hours(), :hour) |> DateTime.to_iso8601()

    %{rows: rows} =
      Repo.query!(
        "SELECT 1 FROM ingest_stats WHERE endpoint = ? AND error IS NULL AND polled_at > ? LIMIT 1",
        [@endpoint, cutoff]
      )

    rows == []
  end

  @doc """
  Page through every station, upsert each page, then mark the stations
  the sync missed as 'removed'. Records stats under 'stations-full';
  never throws.

  Options (for tests): `:fetch_page` (`fn offset, limit -> stations end`),
  `:page_size`, `:overlap`.
  """
  def full_sync(opts \\ []) do
    fetch_page = Keyword.get(opts, :fetch_page, &fetch_page/2)
    page_size = Keyword.get(opts, :page_size, @page_size)
    overlap = Keyword.get(opts, :overlap, @overlap)
    start = System.monotonic_time(:millisecond)
    started_at = DateTime.to_iso8601(DateTime.utc_now())

    try do
      {seen, counts} = sync_pages(fetch_page, page_size, overlap, started_at)
      held = active_count()

      if held > 0 and seen < held * @min_seen_ratio do
        raise "sync saw #{seen} stations but #{held} are held, not marking any removed"
      end

      removed = mark_removed(started_at)

      stats =
        Map.merge(counts, %{
          row_count: seen,
          duration_ms: System.monotonic_time(:millisecond) - start,
          error: nil
        })

      Ingest.record_stats(@endpoint, stats)
      Map.put(stats, :removed, removed)
    rescue
      exception ->
        Logger.error(
          "catalogue sync failed:\n" <> Exception.format(:error, exception, __STACKTRACE__)
        )

        stats = %{
          row_count: 0,
          inserted: 0,
          updated: 0,
          unchanged: 0,
          duration_ms: System.monotonic_time(:millisecond) - start,
          error: Exception.message(exception)
        }

        Ingest.record_stats(@endpoint, stats)
        stats
    end
  end

  defp fetch_page(offset, limit) do
    RadioBrowser.api_get(
      "stations",
      [order: "changetimestamp", offset: offset, limit: limit],
      receive_timeout: @page_timeout_ms
    )
  end

  defp sync_pages(fetch_page, page_size, overlap, started_at) do
    empty = %{inserted: 0, updated: 0, unchanged: 0}

    {uuids, counts} =
      Stream.iterate(0, &(&1 + page_size - overlap))
      |> Enum.reduce_while({[], empty}, fn offset, {uuids, counts} ->
        page = fetch_page.(offset, page_size)
        page_counts = Ingest.upsert_stations(page, synced_at: started_at)
        uuids = Enum.map(page, & &1["stationuuid"]) ++ uuids
        counts = Map.merge(counts, page_counts, fn _key, a, b -> a + b end)

        if length(page) < page_size,
          do: {:halt, {uuids, counts}},
          else: {:cont, {uuids, counts}}
      end)

    uuids = Enum.reject(uuids, &is_nil/1)
    unique = length(Enum.uniq(uuids))

    # the overlap re-upserts stations the previous page stored, which
    # count as 'unchanged' a second time
    {unique, %{counts | unchanged: max(counts.unchanged - (length(uuids) - unique), 0)}}
  end

  defp active_count do
    %{rows: [[n]]} = Repo.query!("SELECT COUNT(*) FROM stations WHERE meta_state != 'removed'")
    n
  end

  # stations first stored after the sync started came from the recent
  # polls and are kept even if the pages missed them
  defp mark_removed(started_at) do
    %{num_rows: removed} =
      Repo.query!(
        """
        UPDATE stations SET meta_state = 'removed'
         WHERE meta_state != 'removed'
           AND (synced_at IS NULL OR synced_at < ?)
           AND first_seen_at < ?
        """,
        [started_at, started_at]
      )

    removed
  end
end
