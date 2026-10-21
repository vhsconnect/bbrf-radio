defmodule BBRF.Ingester.RecentPolls do
  @moduledoc """
  Polls the 'recent' radio-browser endpoints, each on its own schedule,
  and upserts what they return:

    * `poll_changes/0` (`stations/lastchange`) is the incremental feed
      between full catalogue syncs (`BBRF.Ingester.Catalogue`): stations
      added or edited upstream show up here first
    * `poll_clicks/0` (`stations/lastclick`) only refreshes check and click
      data for the stations people listen to; once the catalogue is
      complete it brings in no new stations, so it runs far less often
  """

  alias BBRF.{Env, IngestStat, RadioBrowser}
  alias BBRF.Ingester.Stations
  require Logger

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
      counts = Stations.upsert(stations)

      stats = %{
        row_count: length(stations),
        inserted: counts.inserted,
        updated: counts.updated,
        unchanged: counts.unchanged,
        duration_ms: System.monotonic_time(:millisecond) - start,
        error: nil
      }

      IngestStat.record(endpoint, stats)
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

        IngestStat.record(endpoint, stats)
        stats
    end
  end
end
