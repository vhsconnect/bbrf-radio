defmodule RadioAnalyzer.Application do
  @moduledoc """
  Long-running radio analysis collector. Five loops, each an OTP
  scheduler GenServer (the replacement for chime):

  - catalogue (checked hourly): page through the full radio-browser
    station list when the last sync is older than FULL_SYNC_HOURS
    (default 168), see `RadioAnalyzer.Catalogue`.
  - changes (every CHANGES_POLL_MINUTES, default 10) and clicks (every
    CLICKS_POLL_MINUTES, default 360): poll the radio-browser 'recently
    changed' and 'recently clicked' endpoints, see `RadioAnalyzer.Ingest`.
  - track waves (every TRACK_CYCLE_MINUTES, default 1): check the
    stations the TRACK_STRATEGY selects, see `RadioAnalyzer.Track` and
    `RadioAnalyzer.Track.Strategy`.
  - retention (every PRUNE_HOURS, default 24): delete track observations
    older than RETENTION_DAYS (default 365) and return the space to the OS.

  The HTTP server (`RadioAnalyzer.Web.Router`) serves the bbrf frontend
  bundle and its JSON API from the same node, so the API reads the data
  the collectors write.
  """

  use Application
  require Logger
  alias RadioAnalyzer.{Catalogue, Env, Ingest, Report, Scheduler, Setup, Track}
  alias RadioAnalyzer.Track.Strategy
  alias RadioAnalyzer.Web.Router

  # BBRF_INGESTION=0 runs only the api: no catalogue sync, station poll, track waves or prune
  defp collectors? do
    Application.get_env(:radio_analyzer, :collectors, true) and Env.flag("BBRF_INGESTION", true)
  end

  defp collector_children(strategy, prune_hours) do
    if collectors?() do
      [
        {Scheduler,
         name: RadioAnalyzer.Scheduler.Catalogue,
         label: "catalogue",
         interval_ms: 3_600_000,
         job: {Catalogue, :sync_if_due, []}},
        {Scheduler,
         name: RadioAnalyzer.Scheduler.Changes,
         label: "changes",
         interval_ms: Ingest.changes_interval_minutes() * 60_000,
         job: {Ingest, :poll_changes, []}},
        {Scheduler,
         name: RadioAnalyzer.Scheduler.Clicks,
         label: "clicks",
         interval_ms: Ingest.clicks_interval_minutes() * 60_000,
         job: {Ingest, :poll_clicks, []}},
        {Scheduler,
         name: RadioAnalyzer.Scheduler.Track,
         label: "wave",
         interval_ms: Track.wave_interval_minutes() * 60_000,
         job: {Track, :poll_wave, [strategy]}},
        {Scheduler,
         name: RadioAnalyzer.Scheduler.Prune,
         label: "prune",
         interval_ms: prune_hours * 3_600_000,
         job: {Track, :prune_observations, []}}
      ]
    else
      []
    end
  end

  defp web_children do
    if Application.get_env(:radio_analyzer, :web, true) do
      [{Bandit, plug: Router, scheme: :http, ip: {0, 0, 0, 0}, port: Env.int("PORT", 4881)}]
    else
      []
    end
  end

  @impl true
  def start(_type, _args) do
    prune_hours = Env.int("PRUNE_HOURS", 24)
    strategy = if collectors?(), do: Strategy.from_env()

    children =
      [
        RadioAnalyzer.Repo,
        # pragmas + migrations before any job starts ticking
        Setup,
        # one process per station fetch during a wave
        {Task.Supervisor, name: RadioAnalyzer.WaveSup},
        Report
      ] ++ collector_children(strategy, prune_hours) ++ web_children()

    Logger.info("""
    radio-analyzer started
      #{if collectors?() do
      """
        - catalogue sync every #{Catalogue.interval_hours()}h
        - changes poll every #{Ingest.changes_interval_minutes()} min, clicks poll every #{Ingest.clicks_interval_minutes()} min
        - track waves every #{Track.wave_interval_minutes()} min using #{Strategy.describe(strategy)}
          (deadline #{Track.wave_deadline_seconds()}s, max #{Track.wave_max_stations()} stations, concurrency #{Track.wave_concurrency()})
        - prune every #{prune_hours}h (retention #{Track.retention_days()} days)
      """
    else
      "  - catalogue sync, ingest, track waves and prune off"
    end}
      - report every #{Env.int("REPORT_SECONDS", 10)} s
      - db: #{Keyword.get(Application.get_env(:radio_analyzer, RadioAnalyzer.Repo, []), :database)}
    """)

    Supervisor.start_link(children, strategy: :one_for_one, name: RadioAnalyzer.Supervisor)
  end
end
