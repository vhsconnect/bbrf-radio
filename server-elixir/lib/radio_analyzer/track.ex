defmodule RadioAnalyzer.Track do
  @moduledoc """
  Step 2: poll icecast status pages of the stations that serve metadata.

  Polling runs in waves: every TRACK_CYCLE_MINUTES the whole working set
  (meta_state IN ('ok','unknown')) is polled with bounded concurrency
  and a single shared deadline for the wave.

  Concurrency is where the port earns its keep: every station fetch is
  one lightweight BEAM process under the wave's task supervisor
  (max_concurrency bounds the parallel fetches), hung hosts are killed
  by the per-task timeout instead of pinning a thread pool, and DNS
  resolution runs on the emulator's async thread pool - the 2026-10-13
  "every lookup hangs" failure mode of the JVM original cannot stall a
  wave beyond its deadline. Everything beyond the deadline is dropped,
  not failed: dropped stations are only touched (meta_checked_at = now)
  so they rotate to the back of the fair least-recently-checked ordering
  and are retried next wave.

  Every fetch result classifies the station:

      ok + title            -> 'ok', observation stored on change
      ok w/o title,
      no-source,
      no-status-url         -> 'no-metadata' (leaves the working set)
      unreachable / error   -> meta_fail_count++, 'dead' after 3 in a row
      task timeout          -> dropped (touched, no failure count)
  """

  import Ecto.Query
  require Logger
  alias RadioAnalyzer.{Env, Ingest, RadioBrowser, Repo, Station, TrackObservation}

  @fail_threshold 3
  @connect_timeout_ms 3_000
  @receive_timeout_ms 5_000

  @title_keys ["title", "yp_currently_playing"]

  # per-observation fields worth keeping alongside the track: audience
  # and stream quality at sample time. everything else in the icecast
  # source object is static, already stored on the stations row, or
  # per-sample noise.
  @metadata_keys ["listeners", "listener_peak", "bitrate", "genre"]

  @title_splitter ~r/^(.+?)\s+[-–—]\s+(.+)$/u

  @working_states ["ok", "unknown"]

  def wave_concurrency, do: Env.int("WAVE_CONCURRENCY", 56)
  def wave_deadline_seconds, do: Env.int("WAVE_DEADLINE_SECONDS", 240)
  def wave_max_stations, do: Env.int("WAVE_MAX_STATIONS", 10_000)
  def fetch_timeout_seconds, do: Env.int("TRACK_FETCH_TIMEOUT_SECONDS", 2)
  def retention_days, do: Env.int("RETENTION_DAYS", 365)

  # ---------------------------------------------------------------------------
  # Wave selection
  # ---------------------------------------------------------------------------

  @doc """
  The stations for the next wave: the working set (ok + unknown), ok
  stations first (product beats bootstrap), then least-recently-checked
  first - never-checked (NULL) sort to the front, so every wave makes
  guaranteed progress through untouched stations and dropped stations
  rotate to the back. Capped at limit (WAVE_MAX_STATIONS).
  """
  def select_wave(limit) do
    from(s in Station,
      where:
        s.meta_state in ^@working_states and
          s.lastcheckok == 1 and
          s.hls == 0 and
          not is_nil(fragment("COALESCE(NULLIF(?, ''), ?)", s.url_resolved, s.url)),
      order_by: [
        desc: fragment("meta_state = 'ok'"),
        asc: s.meta_checked_at,
        asc: s.stationuuid
      ],
      limit: ^limit,
      select: %{
        stationuuid: s.stationuuid,
        stream_url: fragment("COALESCE(NULLIF(?, ''), ?)", s.url_resolved, s.url),
        last_title: s.meta_last_title
      }
    )
    |> Repo.all()
  end

  # ---------------------------------------------------------------------------
  # Icecast status fetching
  # ---------------------------------------------------------------------------

  @doc """
  Derive the icecast status URL scheme://host[:port]/status-json.xsl
  from a stream URL, or nil if the stream URL is unparseable.
  """
  def status_url(stream_url) when is_binary(stream_url) do
    case URI.new(stream_url) do
      {:ok, %URI{scheme: scheme, host: host, port: port}}
      when scheme != nil and host != nil ->
        # like java's getAuthority: only keep the port when it was
        # explicit (URI.new normalizes http:80 / https:443)
        port_suffix =
          cond do
            is_nil(port) -> ""
            scheme == "http" and port == 80 -> ""
            scheme == "https" and port == 443 -> ""
            true -> ":#{port}"
          end

        "#{scheme}://#{host}#{port_suffix}/status-json.xsl"

      _ ->
        nil
    end
  end

  def status_url(_other), do: nil

  @doc """
  Fetch icecast status for one station. Returns:

      {:ok, observation}                    track info captured
      :no_source                            reachable, no mount info
      :no_status_url                        stream url unparseable
      {:unreachable, detail}                non-200
      {:error, detail}                      transport error / bad json
  """
  def fetch_observation(%{stationuuid: stationuuid, stream_url: stream_url}) do
    case status_url(stream_url) do
      nil ->
        :no_status_url

      status_url ->
        case Req.get(status_url,
               headers: [
                 {"user-agent", RadioBrowser.user_agent()},
                 {"accept", "application/json"}
               ],
               finch: [
                 # http/1.1 only (req's own default) and a 3s connect cap;
                 # reap idle per-host finch pools so ~7.7k unique icecast
                 # hosts per wave don't accumulate (they idle out between
                 # waves anyway); all fetches share one finch instance
                 protocols: [:http1],
                 pool_max_idle_time: 60_000,
                 conn_opts: [timeout: @connect_timeout_ms]
               ],
               receive_timeout: @receive_timeout_ms,
               retry: false
             ) do
          {:ok, %Req.Response{status: 200, body: body}} ->
            case body |> fetch_source(stream_url) do
              nil -> :no_source
              source -> {:ok, build_observation(stationuuid, source)}
            end

          {:ok, %Req.Response{status: status}} ->
            {:unreachable, "HTTP #{status}"}

          {:error, exception} ->
            {:error, Exception.message(exception)}
        end
    end
  rescue
    exception -> {:error, Exception.message(exception)}
  end

  defp fetch_source(body, stream_url) do
    icestats = if is_map(body), do: body["icestats"], else: nil
    match_source(stream_url, sources(icestats))
  end

  @doc "icestats source is a single map or an array of mounts."
  def sources(nil), do: nil

  def sources(icestats) when is_map(icestats) do
    case icestats["source"] do
      %{} = source -> [source]
      [_ | _] = sources -> sources
      _ -> nil
    end
  end

  def sources(_other), do: nil

  @doc """
  Pick the mount matching the station's stream url by path; fall back to
  the single/first source.
  """
  def match_source(_stream_url, nil), do: nil

  def match_source(stream_url, sources) do
    path = uri_path(stream_url)

    matched =
      path &&
        Enum.find(sources, fn source ->
          case uri_path(source["listenurl"]) do
            nil -> false
            listen_path -> listen_path == path
          end
        end)

    matched || hd(sources)
  end

  defp uri_path(url) when is_binary(url) do
    case URI.new(url) do
      {:ok, %URI{path: path}} -> path
      _ -> nil
    end
  end

  defp uri_path(_other), do: nil

  @doc "Split a raw 'Artist - Title' string into parts when possible."
  def parse_title(nil), do: %{}

  def parse_title(raw_title) do
    case Regex.run(@title_splitter, raw_title) do
      [_, artist, title] -> %{artist: artist, title: title}
      nil -> %{title: raw_title}
    end
  end

  defp build_observation(stationuuid, source) do
    raw_title = source |> title_from() |> trimmed_or_nil()
    icecast_artist = source |> Map.get("artist") |> trimmed_or_nil()
    parsed = parse_title(raw_title)

    metadata =
      source
      |> Map.take(@metadata_keys)
      |> Enum.reject(fn {_key, value} -> is_nil(value) end)
      |> Map.new()
      |> case do
        empty when map_size(empty) == 0 -> nil
        kept -> Jason.encode!(kept)
      end

    %{
      stationuuid: stationuuid,
      observed_at: DateTime.to_iso8601(DateTime.utc_now()),
      raw_title: raw_title,
      artist: icecast_artist || parsed[:artist],
      title: parsed[:title],
      metadata: metadata
    }
  end

  defp title_from(source) do
    Enum.find_value(@title_keys, &Map.get(source, &1))
  end

  defp trimmed_or_nil(nil), do: nil

  defp trimmed_or_nil(value) do
    case String.trim(to_string(value)) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  # ---------------------------------------------------------------------------
  # Classification
  # ---------------------------------------------------------------------------

  @doc """
  Map a fetch result to a persistence action. `last_title` is the
  station's stored meta_last_title (dedupe: only title changes produce
  observations).
  """
  def classify(_last_title, {:ok, %{raw_title: nil}}) do
    # reachable, serves status-json.xsl, but no title field: never going
    # to produce track data
    :no_metadata
  end

  def classify(last_title, {:ok, %{raw_title: title} = observation}) do
    observation = if title == last_title, do: nil, else: observation
    {:ok, title, observation}
  end

  def classify(_last_title, :no_source), do: :no_metadata
  def classify(_last_title, :no_status_url), do: :no_metadata
  def classify(_last_title, {:unreachable, _detail}), do: :fail
  def classify(_last_title, {:error, _detail}), do: :fail

  # ---------------------------------------------------------------------------
  # Wave persistence
  # ---------------------------------------------------------------------------

  defp persist_wave(results, dropped_uuids, now) do
    classified =
      Enum.map(results, fn {station, result} ->
        {station.stationuuid, classify(station.last_title, result)}
      end)

    ok_entries =
      for {uuid, {:ok, title, observation}} <- classified, do: {uuid, title, observation}

    no_metadata_uuids = for {uuid, :no_metadata} <- classified, do: uuid
    fail_uuids = for {uuid, :fail} <- classified, do: uuid

    {:ok, _} =
      Repo.transaction(fn ->
        # title observations + ok-updates (title differs per station)
        Enum.each(ok_entries, fn {uuid, title, observation} ->
          if observation, do: Repo.insert_all(TrackObservation, [observation])

          Repo.query!(
            """
            UPDATE stations
               SET meta_state = 'ok', meta_fail_count = 0,
                   meta_checked_at = ?, meta_last_title = ?
             WHERE stationuuid = ?
            """,
            [now, title, uuid]
          )
        end)

        # reachable but will never serve track metadata
        chunked_update(
          """
          UPDATE stations
             SET meta_state = 'no-metadata', meta_checked_at = ?
           WHERE stationuuid IN
          """,
          [now],
          no_metadata_uuids
        )

        # transient failures; the CASE sees the pre-update meta_fail_count
        # (SQLite SET expressions read old values), so the threshold-th
        # consecutive failure demotes to 'dead'
        chunked_update(
          """
          UPDATE stations
             SET meta_fail_count = meta_fail_count + 1,
                 meta_checked_at = ?,
                 meta_state = CASE WHEN meta_fail_count + 1 >= ? THEN 'dead'
                                   ELSE meta_state END
           WHERE stationuuid IN
          """,
          [now, @fail_threshold],
          fail_uuids
        )

        # dropped by the deadline: touch only, so the LRU ordering rotates
        # them to the back without counting the miss against them
        chunked_update(
          """
          UPDATE stations SET meta_checked_at = ? WHERE stationuuid IN
          """,
          [now],
          dropped_uuids
        )
      end)

    inserted = Enum.count(ok_entries, fn {_uuid, _title, observation} -> observation != nil end)

    %{
      ok: length(ok_entries),
      no_metadata: length(no_metadata_uuids),
      fail: length(fail_uuids),
      inserted: inserted
    }
  end

  defp chunked_update(sql, prefix_params, uuids) do
    Enum.each(Enum.chunk_every(uuids, 500), fn chunk ->
      placeholders = Enum.map_join(chunk, ", ", fn _ -> "?" end)
      Repo.query!("#{sql} (#{placeholders})", prefix_params ++ chunk)
    end)
  end

  # ---------------------------------------------------------------------------
  # Wave execution
  # ---------------------------------------------------------------------------

  defp run_wave(batch, deadline_ms) do
    # one lightweight process per station fetch under the wave task
    # supervisor; nolink so a crashing fetch surfaces as {:exit, reason}
    # instead of taking down the wave (and with it the scheduler).
    # results stream in input order, so zip against the batch to know
    # which station each element (or task exit) belongs to
    Task.Supervisor.async_stream_nolink(
      RadioAnalyzer.WaveSup,
      batch,
      &fetch_observation/1,
      max_concurrency: wave_concurrency(),
      timeout: fetch_timeout_seconds() * 1000,
      on_timeout: :kill_task,
      shutdown: :brutal_kill
    )
    |> Stream.zip(batch)
    |> Enum.reduce_while({[], MapSet.new(), 0}, fn {element, station},
                                                   {results, seen, timed_out} ->
      if System.monotonic_time(:millisecond) >= deadline_ms do
        # shed the tail: consuming stops, async_stream kills whatever is
        # in flight - those stations are dropped, not failed
        {:halt, {results, seen, timed_out}}
      else
        case element do
          {:ok, result} ->
            {:cont,
             {[{station, result} | results], MapSet.put(seen, station.stationuuid), timed_out}}

          # hung host, killed by the per-task timeout: dropped, not failed
          {:exit, :timeout} ->
            {:cont, {results, MapSet.put(seen, station.stationuuid), timed_out + 1}}

          # the task itself died - count it as a station failure
          {:exit, reason} ->
            {:cont,
             {[{station, {:error, "task crashed: " <> inspect(reason)}} | results],
              MapSet.put(seen, station.stationuuid), timed_out}}
        end
      end
    end)
  end

  @doc """
  One polling wave: bounded-concurrency fetches, one shared deadline,
  results classified and persisted in a single transaction. Records
  stats in ingest_stats under 'track-wave'; never throws.
  """
  def poll_wave do
    try do
      start = System.monotonic_time(:millisecond)
      deadline = start + wave_deadline_seconds() * 1000
      batch = select_wave(wave_max_stations())

      if batch == [] do
        stats = %{row_count: 0, inserted: 0, updated: 0, unchanged: 0, duration_ms: 0, error: nil}
        Ingest.record_stats("track-wave", stats)
        stats
      else
        {results, seen, timed_out} = run_wave(batch, deadline)

        dropped_uuids =
          for station <- batch,
              not MapSet.member?(seen, station.stationuuid),
              do: station.stationuuid

        counts = persist_wave(results, dropped_uuids, DateTime.to_iso8601(DateTime.utc_now()))

        ok = counts.ok
        inserted = counts.inserted
        unchanged = ok - inserted

        status_counts =
          Enum.frequencies_by(results, fn {_station, result} -> result_tag(result) end)

        failed = Map.get(status_counts, :unreachable, 0) + Map.get(status_counts, :error, 0)
        dropped_n = length(dropped_uuids) + timed_out

        stats = %{
          row_count: length(results),
          inserted: inserted,
          updated: 0,
          unchanged: unchanged,
          duration_ms: System.monotonic_time(:millisecond) - start,
          error:
            if failed > 0 or dropped_n > 0 do
              "ok=#{ok} no-source=#{Map.get(status_counts, :no_source, 0)} failed=#{failed} dropped=#{dropped_n}"
            else
              nil
            end
        }

        Ingest.record_stats("track-wave", stats)
        stats
      end
    rescue
      exception ->
        Logger.error("track wave failed: #{Exception.message(exception)}")
        nil
    end
  end

  defp result_tag({tag, _detail}), do: tag
  defp result_tag(tag) when is_atom(tag), do: tag

  # ---------------------------------------------------------------------------
  # Retention
  # ---------------------------------------------------------------------------

  @doc """
  Delete observations older than retention-days, return the freed pages
  to the OS (auto_vacuum=INCREMENTAL is enabled at startup), and record
  stats under the 'track-prune' endpoint. Returns %{deleted: n, ...};
  never throws.
  """
  def prune_observations do
    try do
      if retention_days() > 0 do
        start = System.monotonic_time(:millisecond)

        cutoff =
          DateTime.utc_now() |> DateTime.add(-retention_days(), :day) |> DateTime.to_iso8601()

        %{num_rows: deleted} =
          Repo.query!("DELETE FROM track_observations WHERE observed_at < ?", [cutoff])

        incremental_vacuum()

        stats = %{
          row_count: deleted,
          inserted: 0,
          updated: 0,
          unchanged: 0,
          duration_ms: System.monotonic_time(:millisecond) - start,
          error: nil
        }

        Ingest.record_stats("track-prune", stats)
        Map.put(stats, :deleted, deleted)
      else
        %{
          row_count: 0,
          inserted: 0,
          updated: 0,
          unchanged: 0,
          duration_ms: 0,
          error: nil,
          deleted: 0
        }
      end
    rescue
      exception ->
        Logger.error("prune failed: #{Exception.message(exception)}")
        nil
    end
  end

  # exqlite only relocates about one page per invocation, so loop while
  # the freelist keeps shrinking - each pass is cheap, and the loop is
  # bounded by the initial freelist size
  defp incremental_vacuum do
    %{rows: [[free]]} = Repo.query!("PRAGMA freelist_count")
    do_incremental_vacuum(free, -1)
  end

  defp do_incremental_vacuum(free, _prev) when free > 0 do
    Repo.query!("PRAGMA incremental_vacuum")
    %{rows: [[new_free]]} = Repo.query!("PRAGMA freelist_count")
    if new_free > 0 and new_free != free, do: do_incremental_vacuum(new_free, free)
  end

  defp do_incremental_vacuum(_free, _prev), do: :ok
end
