defmodule RadioAnalyzer.Application do
  @moduledoc """
  Long-running radio analysis collector. Three loops, each an OTP
  scheduler GenServer (the replacement for chime):

  - ingest (every POLL_MINUTES, default 10): poll the radio-browser
    'recently added/changed' and 'recently clicked' endpoints and upsert
    stations into SQLite.
  - track waves (every TRACK_CYCLE_MINUTES, default 5): poll the icecast
    status page of every station in the working set with bounded
    concurrency and one shared wave deadline - see the README section
    'Track polling: waves'.
  - retention (every PRUNE_HOURS, default 24): delete track observations
    older than RETENTION_DAYS (default 365) and return the space to the OS.

  The HTTP server (`RadioAnalyzer.Web.Router`) serves the bbrf frontend
  bundle and its JSON API from the same node, so the API reads the data
  the collectors write.
  """

  use Application
  require Logger
  alias RadioAnalyzer.{Env, Report, Scheduler, Setup, Track}
  alias RadioAnalyzer.Web.Router

  # BBRF_INGESTION=0 runs only the api: no station poll, track waves or prune
  defp ingest_children(poll_minutes, track_cycle_minutes, prune_hours) do
    if Env.flag("BBRF_INGESTION", true) do
      [
        {Scheduler,
         name: RadioAnalyzer.Scheduler.Ingest,
         label: "ingest",
         interval_ms: poll_minutes * 60_000,
         job: {RadioAnalyzer.Ingest, :poll_recent, []}},
        {Scheduler,
         name: RadioAnalyzer.Scheduler.Track,
         label: "wave",
         interval_ms: track_cycle_minutes * 60_000,
         job: {Track, :poll_wave, []}},
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
    poll_minutes = Env.int("POLL_MINUTES", 10)
    track_cycle_minutes = Env.int("TRACK_CYCLE_MINUTES", 5)
    prune_hours = Env.int("PRUNE_HOURS", 24)

    children =
      [
        RadioAnalyzer.Repo,
        # pragmas + migrations before any job starts ticking
        Setup,
        # one process per station fetch during a wave
        {Task.Supervisor, name: RadioAnalyzer.WaveSup},
        Report
      ] ++ ingest_children(poll_minutes, track_cycle_minutes, prune_hours) ++ web_children()

    Logger.info("""
    radio-analyzer started
      #{if Env.flag("BBRF_INGESTION", true) do
      """
        - ingest every #{poll_minutes} min
        - track waves every #{track_cycle_minutes} min (deadline #{Track.wave_deadline_seconds()}s, max #{Track.wave_max_stations()} stations, concurrency #{Track.wave_concurrency()})
        - prune every #{prune_hours}h (retention #{Track.retention_days()} days)
      """
    else
      "  - ingest, track waves and prune off (BBRF_INGESTION=0)"
    end}
      - report every #{Env.int("REPORT_SECONDS", 10)} s
      - db: #{Keyword.get(Application.get_env(:radio_analyzer, RadioAnalyzer.Repo, []), :database)}
    """)

    Supervisor.start_link(children, strategy: :one_for_one, name: RadioAnalyzer.Supervisor)
  end
end
