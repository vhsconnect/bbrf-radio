# CLI

Commands run by hand against a node's database, next to the running server.

## Station metrics

Scores every station played in the last `METRICS_WINDOW_DAYS` on each metric and stores the scores in `station_metrics`. Metrics are not computed on a schedule: run them on the ingest node (or the `all` node). The next sync copies them to the hub.

    make metrics                                                     # on the host
    docker compose exec bbrf bin/bbrf eval "BBRF.Metrics.CLI.main()" # in the container

The ingester can keep running. The CLI reads a chunk of stations at a time and writes it in one statement, so the ingester's writes get in between.

| | `make metrics` | `docker compose exec` |
|---|---|---|
| Code | the checkout | the image |
| Settings | `.env`, read on each run | `.env`, as of the container's last start |
| Database | `$(STATE_DIR)/db.sqlite`, or `DB=` | `/data/db.sqlite`, the same file mounted |

With the ingester in Docker and the CLI on the host, keep the checkout on the same commit as the image. The CLI refuses a database that is missing a migration from its code, and never migrates itself.

### Settings

| Variable | Default | |
|---|---|---|
| `METRICS_WINDOW_DAYS` | 60 | days of plays, counted back from now |
| `METRICS_MIN_PLAYS` | 50 | plays a station needs in the window to be scored |
| `INTERNATIONAL_MIN_COVERAGE` | 50 | % of plays with an artist country the international metric needs |

### Output

    metrics: computing international, balance, no_ss_ads over the last 60 days in /var/lib/bbrf/db.sqlite
    metrics: international 25%
    ...
    metrics: international done, 25159 of 34870 stations scored in 74.1s
    ...
    metrics: finished in 214.3s

A failed metric prints `metrics: <name> failed: <reason>` to stderr and keeps its rows from the previous run; the others still run. The exit code is 1 when a metric failed or the database is missing migrations, 0 otherwise. Each metric's outcome is also recorded in `ingest_stats` under `metric:<name>`.

## Favorites export

Prints the favorites to stdout as JSON, in the shape `GET /favorites` returns: an array of `{stationuuid, url, name, countrycode, bitrate}` in the order they were added.

    make favorites-export > favorites.json                                 # on the host
    docker compose exec bbrf bin/bbrf eval "BBRF.Favorites.CLI.main()" > favorites.json # in the container

`make favorites-export` reads `$(STATE_DIR)/db.sqlite`, or `DB=`. Compile output and nix warnings go to stderr, so stdout holds only the JSON.

The output is not what `FAVORITES_IMPORT_FILE` reads: that is the node server's `storage.json`, an object with the array under `"favorites"`.
