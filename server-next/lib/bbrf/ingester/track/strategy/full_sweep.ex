defmodule BBRF.Ingester.Track.Strategy.FullSweep do
  @moduledoc """
  `full-sweep`: rotates through the catalogue, least recently checked
  first (never-checked at the front), so every station that reads fine
  is visited once per cycle. What a read finds does not change when the
  station comes round again.

  Stations whose last check failed or found no metadata leave the
  rotation and follow `BBRF.Ingester.Track.Backoff`, the same retry
  schedule `adaptive` uses: each wave adds up to `retries_per_wave` of
  them whose due time has come, most overdue first. A station that reads
  fine on a retry rejoins the rotation.

  The pace is set as how long one cycle should take: each wave takes
  `rotation size * wave interval / cycle_minutes` stations, capped by the
  wave limit. When waves cannot keep up the cycle takes longer, and the
  rotation stays fair either way.

  Options, each falling back to its env var:

    * `:cycle_minutes` - SWEEP_CYCLE_MINUTES (60)
    * `:retries_per_wave` - SWEEP_RETRIES_PER_WAVE (500)
    * `:wave_minutes` - TRACK_CYCLE_MINUTES (1), the time between waves
  """

  @behaviour BBRF.Ingester.Track.Strategy

  import Ecto.Query
  alias BBRF.Env
  alias BBRF.Ingester.Track.{Backoff, Strategy}

  @impl true
  def init(opts) do
    %{
      cycle_minutes: option(opts, :cycle_minutes, "SWEEP_CYCLE_MINUTES", 60),
      retries_per_wave: option(opts, :retries_per_wave, "SWEEP_RETRIES_PER_WAVE", 500),
      wave_minutes: option(opts, :wave_minutes, "TRACK_CYCLE_MINUTES", 1)
    }
  end

  defp option(opts, key, env, default),
    do: Keyword.get_lazy(opts, key, fn -> Env.int(env, default) end)

  @impl true
  def describe(config) do
    "full-sweep (catalogue every #{config.cycle_minutes} min, " <>
      "#{config.retries_per_wave} back-off retries per wave)"
  end

  @impl true
  def select(now, limit, config) do
    rotation = Backoff.not_backing_off(Strategy.candidates())
    per_wave = ceil(Strategy.count(rotation) * config.wave_minutes / config.cycle_minutes)

    swept =
      rotation
      |> order_by([s], asc: s.meta_checked_at, asc: s.stationuuid)
      |> limit(^min(limit, per_wave))
      |> Strategy.load()

    retries =
      case min(config.retries_per_wave, limit - length(swept)) do
        n when n > 0 ->
          Strategy.candidates()
          |> Backoff.backing_off()
          |> Backoff.due(DateTime.to_iso8601(now))
          |> order_by([s], asc: s.meta_next_check_at, asc: s.stationuuid)
          |> limit(^n)
          |> Strategy.load()

        _none ->
          []
      end

    swept ++ retries
  end

  @impl true
  def next_check_at(_station, outcome, state, now, _config),
    do: Backoff.next_check_at(outcome, state, now)
end
