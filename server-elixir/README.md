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
- `FAVORITES_IMPORT_FILE` optional path to a node server `storage.json`; imported only while the favorites table is empty
- `FADER_VALUE` (25), `ITEMS_PER_PAGE` (5000)
- collector settings: `POLL_MINUTES`, `TRACK_CYCLE_MINUTES`, `PRUNE_HOURS`, `WAVE_CONCURRENCY`, and the rest in `lib/radio_analyzer/`

## Docker

From the bbrf-radio repo root (the image builds the frontend from `src/`):

    docker compose up -d bbrf-elixir    # http://localhost:4882

## Layout

- `lib/radio_analyzer/web/router.ex` HTTP: static bundle and JSON API (same paths as the node server)
- `lib/radio_analyzer/favorites.ex` favorites in SQLite
- `lib/radio_analyzer/application.ex` supervision tree
- `lib/radio_analyzer/*.ex` collectors (ingest, track waves, prune, report)
- `priv/repo/migrations/` schema, applied at boot
