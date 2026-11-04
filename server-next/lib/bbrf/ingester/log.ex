defmodule BBRF.Ingester.Log do
  @moduledoc """
  The ingester's log, built from telemetry events. The code that does
  the work only emits events; this module decides what reaches the log.

      [:bbrf, :scheduler, :job, :start | :stop | :exception]
          a scheduler tick; stop/exception carry the job's duration
      [:bbrf, :ingest, :stat]
          a finished sync, poll, wave or prune, with its ingest_stats row
      [:bbrf, :track, :check]
          one station checked in a wave: outcome, method, title or reason
      [:bbrf, :track, :wave]
          a finished wave: how many were checked and why the failures failed

  Handlers run in the emitting process, so every line carries the `job`
  and `run` Logger metadata the scheduler set for that tick. Per-station
  lines are `:debug`; run the node with `LOG_LEVEL=debug` to see them.
  """

  require Logger

  @handler_id "bbrf-ingester-log"
  @failure_reasons_shown 5

  @events [
    [:bbrf, :scheduler, :job, :start],
    [:bbrf, :scheduler, :job, :stop],
    [:bbrf, :scheduler, :job, :exception],
    [:bbrf, :ingest, :stat],
    [:bbrf, :track, :check],
    [:bbrf, :track, :wave]
  ]

  def attach do
    :telemetry.detach(@handler_id)
    :telemetry.attach_many(@handler_id, @events, &__MODULE__.handle_event/4, nil)
  end

  def run_id, do: Base.encode16(:crypto.strong_rand_bytes(3), case: :lower)

  def handle_event([:bbrf, :scheduler, :job, :start], _measurements, _meta, _config) do
    Logger.debug("tick")
  end

  def handle_event([:bbrf, :scheduler, :job, :stop], %{duration: duration}, _meta, _config) do
    Logger.debug("tick done in #{ms(duration)}ms")
  end

  def handle_event([:bbrf, :scheduler, :job, :exception], _measurements, meta, _config) do
    Logger.error("job crashed:\n" <> Exception.format(meta.kind, meta.reason, meta.stacktrace))
  end

  def handle_event([:bbrf, :ingest, :stat], _measurements, %{endpoint: endpoint, stats: stats}, _) do
    Logger.log(
      stat_level(endpoint, stats),
      "#{endpoint} rows=#{stats.row_count} inserted=#{stats.inserted} " <>
        "updated=#{stats.updated} unchanged=#{stats.unchanged} #{stats.duration_ms}ms" <>
        if(stats.error, do: " #{stats.error}", else: "")
    )
  end

  def handle_event([:bbrf, :track, :check], _measurements, meta, _config) do
    Logger.debug(fn ->
      detail = meta.title || meta.reason || "-"
      "#{meta.station.stationuuid} #{meta.outcome} via #{meta.method || "-"} #{detail}"
    end)
  end

  def handle_event([:bbrf, :track, :wave], %{checked: checked, cut: cut}, meta, _config) do
    Logger.info(
      "wave #{meta.strategy}: checked=#{checked} cut=#{cut}" <>
        failures_suffix(meta.failures)
    )
  end

  # a wave's error column holds its outcome counters, not an error
  defp stat_level("track-wave", _stats), do: :info
  defp stat_level(_endpoint, %{error: nil}), do: :info
  defp stat_level(_endpoint, _stats), do: :warning

  defp failures_suffix(failures) when failures == %{}, do: ""

  defp failures_suffix(failures) do
    shown =
      failures
      |> Enum.sort_by(fn {_reason, n} -> -n end)
      |> Enum.take(@failure_reasons_shown)
      |> Enum.map_join(", ", fn {reason, n} -> "#{reason} x#{n}" end)

    " failures: " <> shown
  end

  defp ms(native), do: System.convert_time_unit(native, :native, :millisecond)
end
