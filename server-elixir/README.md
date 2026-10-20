# bbrf-radio Elixir server

One Elixir node that serves the bbrf frontend bundle and its JSON API, and runs the
collectors that record stations and the tracks they play into SQLite. It replaces
the node server in `../server/` once the frontend is switched over; until then both
run side by side.

## Running

    nix shell nixpkgs#beam.packages.erlang_28.elixir nixpkgs#beam.packages.erlang_28.erlang
    mix deps.get
    mix test
    mix run --no-halt

Environment:

- `PORT` (4881) HTTP port
- `STATIC_DIR` (`static`) directory holding `index.html`, `index.js`, `styles.css`, `favicon-16x16.png`
- `RADIO_ANALYZER_DB` (`data/radio-analyzer-elixir.db`) SQLite file
- `DB_POOL_SIZE` (5) SQLite connections; `DB_CACHE_KB` (8000) page cache per connection, kept small since the OS already caches the file
- `FAVORITES_IMPORT_FILE` optional path to a node server `storage.json`; imported only while the favorites table is empty
- `FADER_VALUE` (25), `ITEMS_PER_PAGE` (5000)
- `BBRF_INGESTION` (1) `1` runs the collectors (catalogue sync, recent polls, track waves, pruning), `0` runs only the api. Any other value stops the boot
- `RADIO_BROWSER_BASE_URL` pins a radio-browser server; unset, a mirror is picked from `all.api.radio-browser.info`
- `FULL_SYNC_HOURS` (168) age of the last full catalogue sync before the next one runs
- `CHANGES_POLL_MINUTES` (10) how often `stations/lastchange` is polled for added and edited stations
- `CLICKS_POLL_MINUTES` (360) how often `stations/lastclick` is polled to refresh click and check data
- `TRACK_CYCLE_MINUTES` (1), `WAVE_DEADLINE_SECONDS` (60), `WAVE_CONCURRENCY` (56), `WAVE_MAX_STATIONS` (10000) track waves
- `TRACK_STRATEGY` (`full-sweep`) how waves cycle through the stations, `adaptive` or `full-sweep` (below). Any other value stops the boot
- `adaptive` options: `DISCOVERY_PER_WAVE` (500) stations without a known method probed per wave, which bounds the cpu a backlog of them costs; `ICY_INTERVAL_MINUTES` (60) shortest interval between checks of a station read over ICY, favorites excepted; `POPULAR_CLICKCOUNT` (20) stations below it that are not favorites refresh at half the rate
- `full-sweep` options: `SWEEP_CYCLE_MINUTES` (60) how long one pass over the rotation should take; `SWEEP_RETRIES_PER_WAVE` (500) back-off retries per wave
- other collector settings: `POLL_LIMIT`, `PRUNE_HOURS`, `RETENTION_DAYS`, `REPORT_SECONDS`

## Collectors

- **catalogue** pages through every radio-browser station when the last full sync is older than `FULL_SYNC_HOURS`; stations it no longer sees become `removed`
- **changes** polls `stations/lastchange` between full syncs, which is where added and edited stations show up; an edited station is reset and checked again right away
- **clicks** polls `stations/lastclick`, which only refreshes click and check data once the catalogue is complete, so it runs every few hours
- **track waves** read the now-playing title of the stations the strategy picks: the icecast `status-json.xsl` first, then the stream's in-band ICY metadata when that has no title. ICY reads one metadata interval of audio (typically 16 KB) per check
- **prune** deletes observations older than `RETENTION_DAYS`

### Track strategies

A strategy (`lib/radio_analyzer/track/strategy.ex`) decides which stations go into each wave and when a checked station is due again; fetching, classifying and storing results are shared. `TRACK_STRATEGY` picks one:

Whatever the strategy, a station whose last check failed or found no metadata backs off (`lib/radio_analyzer/track/backoff.ex`): failures retry after 15 min, doubling up to 30 days (`dead` after 3 in a row), no metadata after 7 days, then every 30.

- **`adaptive`**: every station has its own due time, moved by what each check finds: a new track in 3 min, the same track backs off to 20 min. Long-tail stations refresh at half the rate and ICY stations at most every `ICY_INTERVAL_MINUTES`, favorites excepted. Stations with a known method go first (ok ones leading), then up to `DISCOVERY_PER_WAVE` stations still being classified, never-checked first
- **`full-sweep`** (default): rotates through the stations that read fine, least recently checked first. Each wave takes rotation size / `SWEEP_CYCLE_MINUTES` stations, so each is visited once per cycle whatever it plays, plus up to `SWEEP_RETRIES_PER_WAVE` back-off retries that are due. At 60 min the ICY traffic is about the same as adaptive's

Switching strategies keeps every station's state and back-off. `full-sweep` does not move the due times of stations that read fine, so after a stretch of it `adaptive` finds those overdue and catches up over the following waves
`make status` (from the repo root) prints where they stand, read-only from the database: catalogue size, first-pass progress, when stations are due next, wave pace and the backlog still due, and each collector's last run. `make status-watch` refreshes it every 10 seconds; `DB=path` points it at another database, such as the docker one.

## Docker

From the bbrf-radio repo root (the image builds the frontend from `src/`):

    docker compose up -d bbrf-elixir    # http://localhost:4882

## Layout

- `lib/radio_analyzer/web/router.ex` HTTP: static bundle and JSON API (same paths as the node server)
- `lib/radio_analyzer/favorites.ex` favorites in SQLite
- `lib/radio_analyzer/application.ex` supervision tree
- `lib/radio_analyzer/*.ex` collectors (ingest, track waves, prune, report)
- `priv/repo/migrations/` schema, applied at boot
