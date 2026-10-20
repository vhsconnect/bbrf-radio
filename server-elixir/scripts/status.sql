-- Where the collectors stand, read straight from the database. Read-only,
-- safe while the server runs: `make status`, or `make status-watch`.
.headers on
.mode box

CREATE TEMP VIEW scannable AS
SELECT *
  FROM stations
 WHERE meta_state != 'removed'
   AND lastcheckok = 1
   AND hls = 0
   AND COALESCE(NULLIF(url_resolved, ''), url) IS NOT NULL;

.print
.print 'Catalogue'
SELECT (SELECT COUNT(*) FROM stations) AS stored,
       (SELECT COUNT(*) FROM stations WHERE meta_state = 'removed') AS removed,
       (SELECT COUNT(*) FROM stations WHERE meta_state != 'removed' AND lastcheckok IS NOT 1) AS broken_upstream,
       (SELECT COUNT(*) FROM stations WHERE meta_state != 'removed' AND hls = 1) AS hls,
       (SELECT COUNT(*) FROM scannable) AS scannable,
       (SELECT MAX(polled_at) FROM ingest_stats WHERE endpoint = 'stations-full' AND error IS NULL) AS last_full_sync;

.print
.print 'First pass over scannable stations'
SELECT SUM(meta_checked_at IS NOT NULL) AS scanned,
       SUM(meta_checked_at IS NULL) AS never_scanned,
       printf('%5.1f%%', 100.0 * SUM(meta_checked_at IS NOT NULL) / COUNT(*)) AS done,
       printf('[%.*c%.*c]',
              CAST(40 * SUM(meta_checked_at IS NOT NULL) / COUNT(*) AS INTEGER), '#',
              40 - CAST(40 * SUM(meta_checked_at IS NOT NULL) / COUNT(*) AS INTEGER), '.') AS progress
  FROM scannable;

.print
.print 'Scannable stations by state'
SELECT meta_state AS state,
       COUNT(*) AS stations,
       printf('%5.1f%%', 100.0 * COUNT(*) / (SELECT COUNT(*) FROM scannable)) AS share,
       SUM(meta_fail_count > 0) AS failing
  FROM scannable
 GROUP BY meta_state
 ORDER BY stations DESC;

.print
.print 'Where titles come from (ok stations)'
SELECT COALESCE(meta_source, '?') AS method,
       COUNT(*) AS stations,
       printf('%5.1f%%', 100.0 * COUNT(*) / (SELECT COUNT(*) FROM scannable WHERE meta_state = 'ok')) AS share
  FROM scannable
 WHERE meta_state = 'ok'
 GROUP BY meta_source
 ORDER BY stations DESC;

.print
.print 'Time since each scannable station was last checked (both strategies)'
WITH aged AS (
  SELECT meta_state,
         CASE
           WHEN meta_checked_at IS NULL THEN 0
           ELSE (SELECT CASE
                          WHEN m <= 5 THEN 1
                          WHEN m <= 60 THEN 2
                          WHEN m <= 360 THEN 3
                          WHEN m <= 1440 THEN 4
                          WHEN m <= 10080 THEN 5
                          ELSE 6
                        END
                   FROM (SELECT (julianday('now') - julianday(meta_checked_at)) * 1440 AS m))
         END AS bucket
    FROM scannable
)
SELECT CASE bucket
         WHEN 0 THEN 'never'
         WHEN 1 THEN 'within 5 min'
         WHEN 2 THEN 'within 1 h'
         WHEN 3 THEN 'within 6 h'
         WHEN 4 THEN 'within 1 day'
         WHEN 5 THEN 'within 7 days'
         ELSE 'longer'
       END AS last_checked,
       SUM(meta_state = 'ok') AS ok,
       SUM(meta_state = 'unknown') AS unknown,
       SUM(meta_state = 'no-metadata') AS no_metadata,
       SUM(meta_state = 'dead') AS dead,
       COUNT(*) AS total
  FROM aged
 GROUP BY bucket
 ORDER BY bucket;

.print
.print 'Lookahead: when scannable stations are due next (adaptive: every station; full-sweep: back-off retries only)'
WITH bucketed AS (
  SELECT meta_state,
         CASE
           WHEN meta_checked_at IS NULL THEN 0
           WHEN meta_next_check_at IS NULL THEN 1
           ELSE (SELECT CASE
                          WHEN m <= 1 THEN 1
                          WHEN m <= 5 THEN 2
                          WHEN m <= 30 THEN 3
                          WHEN m <= 120 THEN 4
                          WHEN m <= 1440 THEN 5
                          WHEN m <= 10080 THEN 6
                          ELSE 7
                        END
                   FROM (SELECT (julianday(meta_next_check_at) - julianday('now')) * 1440 AS m))
         END AS bucket
    FROM scannable
)
SELECT CASE bucket
         WHEN 0 THEN 'never scanned'
         WHEN 1 THEN 'due now'
         WHEN 2 THEN 'in 5 min'
         WHEN 3 THEN 'in 30 min'
         WHEN 4 THEN 'in 2 h'
         WHEN 5 THEN 'in 1 day'
         WHEN 6 THEN 'in 7 days'
         ELSE 'later'
       END AS due,
       SUM(meta_state = 'ok') AS ok,
       SUM(meta_state = 'unknown') AS unknown,
       SUM(meta_state = 'no-metadata') AS no_metadata,
       SUM(meta_state = 'dead') AS dead,
       COUNT(*) AS total
  FROM bucketed
 GROUP BY bucket
 ORDER BY bucket;

.print
.print 'Pace of the waves in the last 15 minutes (per minute of wave time)'
WITH waves AS (
  SELECT COUNT(*) AS waves,
         COALESCE(SUM(row_count), 0) AS scanned,
         COALESCE(SUM(inserted), 0) AS new_tracks,
         COALESCE(SUM(duration_ms), 0) / 60000.0 AS minutes
    FROM ingest_stats
   WHERE endpoint = 'track-wave'
     AND polled_at > strftime('%Y-%m-%dT%H:%M:%fZ', 'now', '-15 minutes')
),
backlog AS (
  SELECT SUM(meta_next_check_at IS NULL OR julianday(meta_next_check_at) <= julianday('now')) AS due_now,
         SUM(meta_source IS NULL
             AND (meta_next_check_at IS NULL OR julianday(meta_next_check_at) <= julianday('now'))) AS discovery_due
    FROM scannable
)
SELECT waves,
       CASE WHEN minutes > 0 THEN CAST(ROUND(scanned / minutes) AS INTEGER) END AS scans_per_min,
       CASE WHEN minutes > 0 THEN CAST(ROUND(new_tracks / minutes) AS INTEGER) END AS tracks_per_min,
       due_now,
       discovery_due
  FROM waves, backlog;
.print 'discovery_due clears at DISCOVERY_PER_WAVE (default 500) per minute; the rest of due_now goes in the next wave'

.print
.print 'Last 10 waves'
SELECT substr(polled_at, 1, 19) AS finished_utc,
       row_count AS scanned,
       inserted AS new_tracks,
       unchanged AS idle,
       printf('%.1f', duration_ms / 1000.0) AS secs,
       COALESCE(error, '') AS outcomes
  FROM ingest_stats
 WHERE endpoint = 'track-wave'
 ORDER BY id DESC
 LIMIT 10;

.print
.print 'Track observations'
SELECT (SELECT COUNT(*) FROM track_observations) AS total,
       (SELECT COUNT(*) FROM track_observations
         WHERE observed_at > strftime('%Y-%m-%dT%H:%M:%fZ', 'now', '-1 hour')) AS last_hour,
       (SELECT COUNT(DISTINCT stationuuid) FROM track_observations
         WHERE observed_at > strftime('%Y-%m-%dT%H:%M:%fZ', 'now', '-1 hour')) AS stations_last_hour,
       (SELECT COUNT(DISTINCT stationuuid) FROM track_observations) AS stations_ever;

.print
.print 'Last run of each collector'
SELECT endpoint,
       substr(polled_at, 1, 19) AS finished_utc,
       row_count AS rows,
       inserted,
       printf('%.1f', duration_ms / 1000.0) AS secs,
       COALESCE(error, '') AS error
  FROM ingest_stats
 WHERE id IN (SELECT MAX(id) FROM ingest_stats GROUP BY endpoint)
 ORDER BY endpoint;
