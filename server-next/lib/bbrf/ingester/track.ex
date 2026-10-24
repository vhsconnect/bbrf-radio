defmodule BBRF.Ingester.Track do
  @moduledoc """
  Step 2: poll the stations' now-playing titles, in waves.

  Two methods, cheapest first: the icecast status page
  (`status-json.xsl`, a few KB), and when that yields no title, the
  in-band ICY metadata of the stream itself (one metadata interval of
  audio, typically 16 KB). The method that produced a title is kept in
  `meta_source` and used directly on later checks.

  Every TRACK_CYCLE_MINUTES a wave asks the configured
  `BBRF.Ingester.Track.Strategy` which stations to check, fetches them
  with bounded concurrency and one shared deadline, classifies each
  result and stores it, asking the strategy when each station is due
  again. Stations the deadline cuts off are left untouched.

  Every fetch is one lightweight BEAM process under the wave's task
  supervisor; a host that hangs past the per-check cap is killed and
  counted as a failure.

  What a check finds sets the station's state, whichever strategy runs:

      ok, title changed         -> 'ok', observation stored
      ok, same title or none    -> 'ok'
      no title (not yet ok),
      no status page, no mount  -> 'no-metadata'
      unreachable / error       -> meta_fail_count++, 'dead' at 3
  """

  require Logger
  alias BBRF.{Env, IngestStat, RadioBrowser, Repo, TrackObservation}
  alias BBRF.Ingester.Track.Strategy

  @fail_threshold 3
  @connect_timeout_ms 2_000
  @receive_timeout_ms 3_000
  # an ICY read stops at this point whatever it has: a stream that trickles
  # slower than that cannot be read within our budget
  @icy_budget_ms 4_000
  # hard cap per check, status page and ICY read together
  @task_timeout_ms 6_000

  # enough for the largest icy-metaint seen in the wild (32 KB) plus a
  # full metadata block; streams announcing more are treated as no metadata
  @icy_max_bytes 65_536

  # pool config for the BBRF.Ingester.Finch instance each wave runs (see
  # with_finch/1). Every request sends `connection: close`: a station host
  # is not asked again for minutes, and an idle keep-alive (often tls)
  # would only hold memory.
  @finch_pool [
    protocols: [:http1],
    # no tls session resumption: otp's client session cache holds 1000
    # sessions and waves reach ~12k https hosts, so sessions are evicted
    # constantly, and when one goes between offering it and the server
    # accepting it, ssl crashes deriving keys from the missing session
    conn_opts: [timeout: @connect_timeout_ms, transport_opts: [reuse_sessions: false]]
  ]

  @title_keys ["title", "yp_currently_playing"]

  # per-observation fields worth keeping alongside the track: audience
  # and stream quality at sample time. everything else in the icecast
  # source object is static, already stored on the stations row, or
  # per-sample noise.
  @metadata_keys ["listeners", "listener_peak", "bitrate", "genre"]

  @title_splitter ~r/^(.+?)\s+[-–—]\s+(.+)$/u

  # answers meaning the host has no icecast status page, not that it is down
  @no_status_page_codes [403, 404]

  def wave_interval_minutes, do: Env.int("TRACK_CYCLE_MINUTES", 1)
  def wave_concurrency, do: Env.int("WAVE_CONCURRENCY", 56)
  def wave_deadline_seconds, do: Env.int("WAVE_DEADLINE_SECONDS", 60)
  def wave_max_stations, do: Env.int("WAVE_MAX_STATIONS", 10_000)

  def finch_child_spec do
    {Finch, name: BBRF.Ingester.Finch, pools: %{default: @finch_pool}}
  end

  @doc """
  Run `fun` with the BBRF.Ingester.Finch instance the station fetches
  use, stopping it afterwards. Finch keeps a pool per host and a wave
  reaches thousands of hosts; its idle-pool reaping only fires through a
  pooled connection, which `connection: close` never leaves, so the
  pools are dropped with the instance at the end of every wave instead.
  """
  def with_finch(fun) do
    {:ok, finch} = Supervisor.start_link([finch_child_spec()], strategy: :one_for_one)

    try do
      fun.()
    after
      Supervisor.stop(finch)
    end
  end

  def retention_days, do: Env.int("RETENTION_DAYS", 365)

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
  Fetch the now-playing title of one station, as `{method, result}` where
  method is the one that produced the result: 'icy' straight away for
  stations known to only serve ICY, otherwise 'icecast', falling back to
  'icy' when the status page was reachable but gave no title.
  """
  def fetch_observation(%{meta_source: "icy"} = station), do: {"icy", fetch_icy(station)}

  def fetch_observation(station) do
    case fetch_status(station) do
      {:ok, %{raw_title: title}} = result when title != nil -> {"icecast", result}
      # host down or url unusable: the stream would fail the same way
      {:error, _detail} = result -> {"icecast", result}
      :no_status_url -> {"icecast", :no_status_url}
      _no_title -> {"icy", fetch_icy(station)}
    end
  end

  @doc """
  Fetch icecast status for one station. Returns:

      {:ok, observation}                    track info captured
      :no_source                            reachable, no mount info
      :no_status_url                        stream url unparseable
      :no_status_page                       403 / 404: no icecast status page
      {:unreachable, detail}                any other non-200
      {:error, detail}                      transport error / bad json
  """
  def fetch_status(%{stationuuid: stationuuid, stream_url: stream_url}) do
    case status_url(stream_url) do
      nil ->
        :no_status_url

      status_url ->
        case Req.get(status_url,
               headers: [
                 {"user-agent", RadioBrowser.user_agent()},
                 {"accept", "application/json"},
                 {"connection", "close"}
               ],
               finch: [name: BBRF.Ingester.Finch],
               receive_timeout: @receive_timeout_ms,
               retry: false
             ) do
          {:ok, %Req.Response{status: 200, body: body}} ->
            case body |> fetch_source(stream_url) do
              nil -> :no_source
              source -> {:ok, build_observation(stationuuid, source)}
            end

          {:ok, %Req.Response{status: status}} when status in @no_status_page_codes ->
            :no_status_page

          {:ok, %Req.Response{status: status}} ->
            {:unreachable, "HTTP #{status}"}

          {:error, exception} ->
            {:error, Exception.message(exception)}
        end
    end
  rescue
    exception -> {:error, Exception.message(exception)}
  end

  @doc """
  Read the in-band ICY metadata of the stream: request it with
  `Icy-MetaData: 1`, skip `icy-metaint` bytes of audio and decode the
  `StreamTitle` of the metadata block that follows, then hang up.
  Returns the same shapes as `fetch_status/1`; a stream without
  `icy-metaint`, or too slow to reach its metadata within `budget_ms`,
  is `:no_source`.
  """
  def fetch_icy(%{stationuuid: stationuuid, stream_url: stream_url}, budget_ms \\ @icy_budget_ms) do
    deadline = System.monotonic_time(:millisecond) + budget_ms

    case Req.get(stream_url,
           headers: [
             {"user-agent", RadioBrowser.user_agent()},
             {"icy-metadata", "1"},
             {"connection", "close"}
           ],
           finch: [name: BBRF.Ingester.Finch],
           receive_timeout: min(@receive_timeout_ms, budget_ms),
           retry: false,
           raw: true,
           into: &collect_icy(&1, &2, deadline)
         ) do
      {:ok, %Req.Response{status: 200} = response} ->
        icy_result(stationuuid, response)

      {:ok, %Req.Response{status: status}} ->
        {:unreachable, "HTTP #{status}"}

      {:error, exception} ->
        {:error, Exception.message(exception)}
    end
  rescue
    exception -> {:error, Exception.message(exception)}
  end

  defp collect_icy({:data, data}, {request, response}, deadline) do
    buffer = Req.Response.get_private(response, :icy, "") <> data
    response = Req.Response.put_private(response, :icy, buffer)

    if icy_complete?(response, buffer) or System.monotonic_time(:millisecond) >= deadline,
      do: {:halt, {request, response}},
      else: {:cont, {request, response}}
  end

  defp icy_complete?(response, buffer) do
    case metaint(response) do
      nil -> true
      metaint -> byte_size(buffer) >= min(icy_needed(metaint, buffer), @icy_max_bytes)
    end
  end

  # the audio, the length byte, then length * 16 bytes of metadata
  defp icy_needed(metaint, buffer) when byte_size(buffer) > metaint,
    do: metaint + 1 + :binary.at(buffer, metaint) * 16

  defp icy_needed(metaint, _buffer), do: metaint + 1

  defp icy_result(stationuuid, response) do
    buffer = Req.Response.get_private(response, :icy, "")

    with metaint when is_integer(metaint) <- metaint(response),
         <<_audio::binary-size(metaint), length, block::binary>> <- buffer,
         <<metadata::binary-size(length * 16), _rest::binary>> <- block do
      {:ok, build_observation(stationuuid, icy_source(metadata, response))}
    else
      _incomplete -> :no_source
    end
  end

  defp metaint(response) do
    with [value | _] <- Req.Response.get_header(response, "icy-metaint"),
         {metaint, ""} when metaint > 0 <- Integer.parse(String.trim(value)) do
      metaint
    else
      _ -> nil
    end
  end

  @doc """
  The icecast-source-shaped map for an ICY metadata block, so it builds
  an observation like a status page mount does.
  """
  def icy_source(metadata, response) do
    title =
      case Regex.run(~r/StreamTitle='(.*?)';/s, metadata) do
        [_, title] -> utf8(title)
        nil -> nil
      end

    bitrate =
      with [value | _] <- Req.Response.get_header(response, "icy-br"),
           {bitrate, _rest} <- Integer.parse(value) do
        bitrate
      else
        _ -> nil
      end

    genre =
      case Req.Response.get_header(response, "icy-genre") do
        [value | _] -> utf8(value)
        [] -> nil
      end

    %{"title" => title, "bitrate" => bitrate, "genre" => genre}
  end

  # ICY metadata has no declared charset; older servers send latin-1
  defp utf8(text) do
    if String.valid?(text), do: text, else: :unicode.characters_to_binary(text, :latin1)
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
  Pick the mount matching the station's stream url by path. A server with
  a single mount is taken as the station's; with several and no match
  there is no way to tell which one it is.
  """
  def match_source(_stream_url, nil), do: nil
  def match_source(_stream_url, [only]), do: only

  def match_source(stream_url, sources) do
    case uri_path(stream_url) do
      nil -> nil
      path -> Enum.find(sources, &(uri_path(&1["listenurl"]) == path))
    end
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
  Map a fetch result to an outcome (`t:BBRF.Ingester.Track.Strategy.outcome/0`)
  for `station`:

      {:changed, title, observation}   new track
      :idle                            ok station, no new track
      :no_metadata                     will not serve track metadata
      :fail                            down or broken
  """
  def classify(%{meta_state: "ok"}, {:ok, %{raw_title: nil}}), do: :idle
  def classify(_station, {:ok, %{raw_title: nil}}), do: :no_metadata

  def classify(%{last_title: title}, {:ok, %{raw_title: title}}), do: :idle

  def classify(_station, {:ok, %{raw_title: title} = observation}),
    do: {:changed, title, observation}

  def classify(_station, :no_source), do: :no_metadata
  def classify(_station, :no_status_url), do: :no_metadata
  def classify(_station, :no_status_page), do: :no_metadata
  def classify(_station, {:unreachable, _detail}), do: :fail
  def classify(_station, {:error, _detail}), do: :fail

  @doc """
  The station columns after `outcome`, checked at `now` (a DateTime),
  except its due time, which is the strategy's call. `method` is the one
  that produced the outcome ('icecast' or 'icy').
  """
  def next_state(station, outcome, now, method \\ nil)

  def next_state(station, {:changed, title, _observation}, now, method) do
    checked(now, %{
      meta_state: "ok",
      meta_fail_count: 0,
      meta_idle_count: 0,
      meta_last_title: title,
      meta_source: method || station.meta_source
    })
  end

  def next_state(station, :idle, now, method) do
    checked(now, %{
      meta_state: "ok",
      meta_fail_count: 0,
      meta_idle_count: station.idle_count + 1,
      meta_last_title: station.last_title,
      meta_source: method || station.meta_source
    })
  end

  # both methods came up empty, so the next check tries both again
  def next_state(station, :no_metadata, now, _method) do
    checked(now, %{
      meta_state: "no-metadata",
      meta_fail_count: 0,
      meta_idle_count:
        if(station.meta_state == "no-metadata", do: station.idle_count + 1, else: 1),
      meta_last_title: station.last_title,
      meta_source: nil
    })
  end

  def next_state(station, :fail, now, _method) do
    fails = station.fail_count + 1

    checked(now, %{
      meta_state: if(fails >= @fail_threshold, do: "dead", else: station.meta_state),
      meta_fail_count: fails,
      meta_idle_count: station.idle_count,
      meta_last_title: station.last_title,
      meta_source: station.meta_source
    })
  end

  defp checked(now, state), do: Map.put(state, :meta_checked_at, DateTime.to_iso8601(now))

  # ---------------------------------------------------------------------------
  # Wave persistence
  # ---------------------------------------------------------------------------

  @state_columns ~w(meta_state meta_fail_count meta_idle_count meta_last_title meta_source meta_checked_at meta_next_check_at)a

  @update_row "(" <> Enum.map_join(1..(length(@state_columns) + 2), ", ", fn _ -> "?" end) <> ")"

  # rows per UPDATE; 9 parameters each
  @update_chunk 500

  # the changeuuid guard skips stations edited while the wave ran: the
  # upsert already made them due again with their new url. A NULL due
  # time from the strategy keeps the station's current one.
  @update_sql_head """
  WITH v(stationuuid, changeuuid, #{Enum.join(@state_columns, ", ")}) AS (VALUES
  """
  @update_sql_tail """
  )
  UPDATE stations
     SET #{@state_columns |> List.delete(:meta_next_check_at) |> Enum.map_join(", ", &"#{&1} = v.#{&1}")},
         meta_next_check_at = COALESCE(v.meta_next_check_at, stations.meta_next_check_at)
    FROM v
   WHERE stations.stationuuid = v.stationuuid
     AND stations.changeuuid IS v.changeuuid
  """

  @doc """
  Store a wave's `{station, {method, fetch_result}}` pairs: one
  observation per title change, and every station's new state and the
  due time `strategy` gives it. Returns counts per outcome, plus `:icy`
  for the titles read over ICY.
  """
  def persist_wave(results, now, strategy) do
    outcomes =
      Enum.map(results, fn {station, {method, result}} ->
        outcome = classify(station, result)
        state = next_state(station, outcome, now, method)
        next = Strategy.next_check_at(strategy, station, outcome, state, now)

        {station, outcome, Map.put(state, :meta_next_check_at, next && DateTime.to_iso8601(next))}
      end)

    observations =
      for {_station, {:changed, _title, observation}, _state} <- outcomes, do: observation

    {:ok, _} =
      Repo.transaction(fn ->
        observations
        |> Enum.chunk_every(@update_chunk)
        |> Enum.each(&Repo.insert_all(TrackObservation, &1))

        outcomes
        |> Enum.chunk_every(@update_chunk)
        |> Enum.each(&update_stations/1)
      end)

    results
    |> Enum.zip(outcomes)
    |> Enum.each(fn {{station, {method, result}}, {_station, outcome, _state}} ->
      :telemetry.execute([:bbrf, :track, :check], %{}, %{
        station: station,
        method: method,
        outcome: outcome_tag(outcome),
        title: outcome_title(station, outcome),
        reason: reason(result)
      })
    end)

    outcomes
    |> Enum.frequencies_by(fn {_station, outcome, _state} -> outcome_tag(outcome) end)
    |> Map.put(
      :icy,
      Enum.count(outcomes, fn {_station, _outcome, state} ->
        state.meta_state == "ok" and state.meta_source == "icy"
      end)
    )
  end

  defp update_stations(chunk) do
    rows = Enum.map_join(chunk, ", ", fn _ -> @update_row end)

    params =
      Enum.flat_map(chunk, fn {station, _outcome, state} ->
        [
          station.stationuuid,
          station.changeuuid | Enum.map(@state_columns, &Map.fetch!(state, &1))
        ]
      end)

    Repo.query!(@update_sql_head <> rows <> @update_sql_tail, params)
  end

  defp outcome_tag({:changed, _title, _observation}), do: :changed
  defp outcome_tag(tag), do: tag

  defp outcome_title(_station, {:changed, title, _observation}), do: title
  defp outcome_title(station, :idle), do: station.last_title
  defp outcome_title(_station, _outcome), do: nil

  defp reason({:unreachable, detail}), do: detail
  defp reason({:error, detail}), do: detail
  defp reason(result) when is_atom(result), do: Atom.to_string(result)
  defp reason(_result), do: nil

  defp failure_reasons(results) do
    for {station, {_method, result}} <- results,
        classify(station, result) == :fail,
        reduce: %{} do
      reasons -> Map.update(reasons, String.slice(reason(result), 0, 60), 1, &(&1 + 1))
    end
  end

  # ---------------------------------------------------------------------------
  # Wave execution
  # ---------------------------------------------------------------------------

  # one process per fetch; nolink so a crashing fetch surfaces as
  # {:exit, {station, reason}} instead of taking down the wave. Results
  # arrive as they finish; once the deadline passes, consuming stops and
  # async_stream kills whatever is still in flight.
  defp run_wave(batch, deadline_ms) do
    Task.Supervisor.async_stream_nolink(
      BBRF.Ingester.WaveSup,
      batch,
      fn station -> {station, fetch_observation(station)} end,
      max_concurrency: wave_concurrency(),
      timeout: @task_timeout_ms,
      on_timeout: :kill_task,
      shutdown: :brutal_kill,
      ordered: false,
      zip_input_on_exit: true
    )
    |> Enum.reduce_while([], fn element, results ->
      results = [wave_result(element) | results]

      if System.monotonic_time(:millisecond) >= deadline_ms,
        do: {:halt, results},
        else: {:cont, results}
    end)
  end

  defp wave_result({:ok, {station, fetched}}), do: {station, fetched}

  defp wave_result({:exit, {station, :timeout}}),
    do: {station, {station.meta_source, {:error, "timeout"}}}

  defp wave_result({:exit, {station, reason}}),
    do: {station, {station.meta_source, {:error, "task crashed: " <> inspect(reason)}}}

  @doc """
  One wave over the stations `strategy` selects. Records stats in
  ingest_stats under 'track-wave'; never throws.
  """
  def poll_wave(strategy \\ Strategy.from_env()) do
    try do
      start = System.monotonic_time(:millisecond)
      deadline = start + wave_deadline_seconds() * 1000
      batch = Strategy.select(strategy, DateTime.utc_now(), wave_max_stations())
      results = if batch == [], do: [], else: with_finch(fn -> run_wave(batch, deadline) end)
      counts = persist_wave(results, DateTime.utc_now(), strategy)
      count = &Map.get(counts, &1, 0)
      cut = length(batch) - length(results)

      stats = %{
        row_count: length(results),
        inserted: count.(:changed),
        updated: 0,
        unchanged: count.(:idle),
        duration_ms: System.monotonic_time(:millisecond) - start,
        error:
          "#{Strategy.name(strategy)}: changed=#{count.(:changed)} idle=#{count.(:idle)} " <>
            "via-icy=#{count.(:icy)} no-metadata=#{count.(:no_metadata)} " <>
            "fail=#{count.(:fail)} cut=#{cut}"
      }

      IngestStat.record("track-wave", stats)

      :telemetry.execute([:bbrf, :track, :wave], %{checked: length(results), cut: cut}, %{
        strategy: Strategy.name(strategy),
        failures: failure_reasons(results)
      })

      stats
    rescue
      exception ->
        Logger.error("track wave failed: #{Exception.message(exception)}")
        nil
    end
  end

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

        IngestStat.record("track-prune", stats)
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
