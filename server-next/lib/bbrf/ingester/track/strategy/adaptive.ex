defmodule BBRF.Ingester.Track.Strategy.Adaptive do
  @moduledoc """
  `adaptive`: every station has its own due time (`meta_next_check_at`,
  NULL meaning now), and each check moves it according to what it found:

      title changed           -> back in 3 min
      same title, or none     -> backs off 5 -> 10 -> 20 min
      no metadata, failure    -> `BBRF.Ingester.Track.Backoff`

  The ok intervals are doubled for stations that are neither a favorite
  nor popular, and stations read over ICY are checked at most every
  `icy_interval_minutes` unless they are a favorite, since every ICY
  check streams audio.

  A wave takes the due stations with a known method first, ok ones
  leading, then at most `discovery_per_wave` due stations whose method is
  not known yet, never-checked first. Discovery can cost a status page
  and an ICY read per station, so a backlog of it (a fresh catalogue, a
  migration) is worked through at that pace rather than at full
  concurrency.

  Options, each falling back to its env var:

    * `:discovery_per_wave` - DISCOVERY_PER_WAVE (500)
    * `:icy_interval_minutes` - ICY_INTERVAL_MINUTES (60)
    * `:popular_clickcount` - POPULAR_CLICKCOUNT (20), clicks from which a station is popular
  """

  @behaviour BBRF.Ingester.Track.Strategy

  import Ecto.Query
  alias BBRF.Env
  alias BBRF.Ingester.Track.{Backoff, Strategy}

  @changed_minutes 3
  @idle_minutes [5, 10, 20]
  @long_tail_factor 2

  @impl true
  def init(opts) do
    %{
      discovery_per_wave: option(opts, :discovery_per_wave, "DISCOVERY_PER_WAVE", 500),
      icy_interval_minutes: option(opts, :icy_interval_minutes, "ICY_INTERVAL_MINUTES", 60),
      popular_clickcount: option(opts, :popular_clickcount, "POPULAR_CLICKCOUNT", 20)
    }
  end

  defp option(opts, key, env, default),
    do: Keyword.get_lazy(opts, key, fn -> Env.int(env, default) end)

  @impl true
  def describe(config) do
    "adaptive (#{config.discovery_per_wave} discovery per wave, ICY at most every " <>
      "#{config.icy_interval_minutes} min, popular from #{config.popular_clickcount} clicks)"
  end

  @impl true
  def select(now, limit, config) do
    now = DateTime.to_iso8601(now)

    known =
      due(now)
      |> where([s], not is_nil(s.meta_source))
      |> order_by([s],
        desc: fragment("? = 'ok'", s.meta_state),
        asc: s.meta_next_check_at,
        asc: s.stationuuid
      )
      |> limit(^limit)
      |> Strategy.load()

    discovery =
      case min(config.discovery_per_wave, limit - length(known)) do
        n when n > 0 ->
          due(now)
          |> where([s], is_nil(s.meta_source))
          |> order_by([s], asc: s.meta_next_check_at, asc: s.stationuuid)
          |> limit(^n)
          |> Strategy.load()

        _none ->
          []
      end

    known ++ discovery
  end

  defp due(now), do: Backoff.due(Strategy.candidates(), now)

  @impl true
  def next_check_at(station, outcome, state, now, config) do
    Backoff.next_check_at(outcome, state, now) ||
      DateTime.add(now, ok_minutes(station, outcome, state, config) * 60, :second)
  end

  defp ok_minutes(station, {:changed, _title, _observation}, state, config),
    do: scaled(station, state, @changed_minutes, config)

  defp ok_minutes(station, :idle, state, config),
    do: scaled(station, state, step(@idle_minutes, state.meta_idle_count), config)

  defp scaled(station, state, minutes, config) do
    priority? = station.favorite or station.clickcount >= config.popular_clickcount
    minutes = if priority?, do: minutes, else: minutes * @long_tail_factor

    if state.meta_source == "icy" and not station.favorite,
      do: max(minutes, config.icy_interval_minutes),
      else: minutes
  end

  # nth step of a back-off ladder, staying on the last step
  defp step(ladder, n), do: Enum.at(ladder, min(n, length(ladder)) - 1)
end
