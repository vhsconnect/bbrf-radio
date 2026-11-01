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
    * artists (every ARTIST_RESOLVE_MINUTES, default 10): resolve the
      most played artist credits to MusicBrainz artists, see
      `BBRF.Ingester.Artists`
    * retention (every PRUNE_HOURS, default 24): delete track observations
      older than RETENTION_DAYS (default 365) and return the space to the OS

  Their I/O runs in the lanes of `BBRF.Ingester.WorkQueue`, which hands
  its WORK_SLOTS out by lane priority (`lanes/0`).

  `BBRF.Ingester.Report` logs what they did every REPORT_SECONDS.
  """

  alias BBRF.Env
  alias BBRF.Ingester.{Artists, Catalogue, RecentPolls, Report, Scheduler, Track, WorkQueue}
  alias BBRF.Ingester.Track.Strategy

  def prune_hours, do: Env.int("PRUNE_HOURS", 24)

  @doc "The work queue lanes, highest priority first."
  def lanes do
    [
      wave: [],
      # MusicBrainz serves one request per second per IP
      musicbrainz: [max_concurrency: 1, interval_ms: BBRF.MusicBrainz.interval_ms()]
    ]
  end

  def children(strategy) do
    [
      {WorkQueue, lanes: lanes()},
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
       name: BBRF.Ingester.Scheduler.Artists,
       label: "artists",
       interval_ms: Artists.interval_minutes() * 60_000,
       job: {Artists, :resolve_due, []}},
      prune_child()
    ]
  end

  @doc "The retention loop; a hub runs it too, to keep its own window of history."
  def prune_child do
    {Scheduler,
     name: BBRF.Ingester.Scheduler.Prune,
     label: "prune",
     interval_ms: prune_hours() * 3_600_000,
     job: {Track, :prune_observations, []}}
  end

  def describe(strategy) do
    """
    ingester
        - catalogue sync every #{Catalogue.interval_hours()}h
        - changes poll every #{RecentPolls.changes_interval_minutes()} min, clicks poll every #{RecentPolls.clicks_interval_minutes()} min
        - track waves every #{Track.wave_interval_minutes()} min using #{Strategy.describe(strategy)}
          (deadline #{Track.wave_deadline_seconds()}s, max #{Track.wave_max_stations()} stations)
        - artist resolve every #{Artists.interval_minutes()} min, up to #{Artists.batch_size()} credits
        - work queue: #{WorkQueue.slots()} slots, lanes #{lanes() |> Keyword.keys() |> Enum.join(" > ")}
        - prune every #{prune_hours()}h (retention #{Track.retention_days()} days)
        - report every #{Env.int("REPORT_SECONDS", 10)} s\
    """
  end
end
