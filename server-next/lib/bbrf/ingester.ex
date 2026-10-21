defmodule BBRF.Ingester do
  @moduledoc """
  The collecting component: loops that keep the station catalogue and
  the tracks the stations play up to date in SQLite, each an OTP
  `BBRF.Ingester.Scheduler`:

    * catalogue (checked hourly): page through the full radio-browser
      station list when the last sync is older than FULL_SYNC_HOURS
      (default 168), see `BBRF.Ingester.Catalogue`
    * changes (every CHANGES_POLL_MINUTES, default 10) and clicks (every
      CLICKS_POLL_MINUTES, default 360): poll the radio-browser 'recently
      changed' and 'recently clicked' endpoints, see `BBRF.Ingester.RecentPolls`
    * track waves (every TRACK_CYCLE_MINUTES, default 1): check the
      stations the TRACK_STRATEGY selects, see `BBRF.Ingester.Track` and
      `BBRF.Ingester.Track.Strategy`
    * retention (every PRUNE_HOURS, default 24): delete track observations
      older than RETENTION_DAYS (default 365) and return the space to the OS

  `BBRF.Ingester.Report` logs what they did every REPORT_SECONDS.
  """

  alias BBRF.Env
  alias BBRF.Ingester.{Catalogue, RecentPolls, Report, Scheduler, Track}
  alias BBRF.Ingester.Track.Strategy

  def prune_hours, do: Env.int("PRUNE_HOURS", 24)

  def children(strategy) do
    [
      # one process per station fetch during a wave
      {Task.Supervisor, name: BBRF.Ingester.WaveSup},
      Report,
      {Scheduler,
       name: BBRF.Ingester.Scheduler.Catalogue,
       label: "catalogue",
       interval_ms: 3_600_000,
       job: {Catalogue, :sync_if_due, []}},
      {Scheduler,
       name: BBRF.Ingester.Scheduler.Changes,
       label: "changes",
       interval_ms: RecentPolls.changes_interval_minutes() * 60_000,
       job: {RecentPolls, :poll_changes, []}},
      {Scheduler,
       name: BBRF.Ingester.Scheduler.Clicks,
       label: "clicks",
       interval_ms: RecentPolls.clicks_interval_minutes() * 60_000,
       job: {RecentPolls, :poll_clicks, []}},
      {Scheduler,
       name: BBRF.Ingester.Scheduler.Track,
       label: "wave",
       interval_ms: Track.wave_interval_minutes() * 60_000,
       job: {Track, :poll_wave, [strategy]}},
      {Scheduler,
       name: BBRF.Ingester.Scheduler.Prune,
       label: "prune",
       interval_ms: prune_hours() * 3_600_000,
       job: {Track, :prune_observations, []}}
    ]
  end

  def describe(strategy) do
    """
    ingester
        - catalogue sync every #{Catalogue.interval_hours()}h
        - changes poll every #{RecentPolls.changes_interval_minutes()} min, clicks poll every #{RecentPolls.clicks_interval_minutes()} min
        - track waves every #{Track.wave_interval_minutes()} min using #{Strategy.describe(strategy)}
          (deadline #{Track.wave_deadline_seconds()}s, max #{Track.wave_max_stations()} stations, concurrency #{Track.wave_concurrency()})
        - prune every #{prune_hours()}h (retention #{Track.retention_days()} days)
        - report every #{Env.int("REPORT_SECONDS", 10)} s\
    """
  end
end
