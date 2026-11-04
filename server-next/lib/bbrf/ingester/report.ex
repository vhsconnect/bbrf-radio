defmodule BBRF.Ingester.Report do
  @moduledoc """
  Every REPORT_SECONDS (default 10) log the observation/classification
  counters with deltas since the last report. The first report after
  startup is a baseline (raw counts, no deltas). What each wave, poll and
  prune did is logged as it happens, see `BBRF.Ingester.Log`.

  Observations are counted once at boot; after that each report adds
  the rows past the last seen id and subtracts what prunes deleted, so
  the table is never scanned in full again.
  """

  use GenServer
  require Logger
  alias BBRF.{Env, Repo}

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    Process.send_after(self(), :tick, interval_ms())

    {:ok,
     %{
       last_id: one("SELECT COALESCE(MAX(id), 0) FROM ingest_stats"),
       last_obs_id: one("SELECT COALESCE(MAX(id), 0) FROM track_observations"),
       obs: one("SELECT COUNT(*) FROM track_observations"),
       prev: nil
     }}
  end

  @impl true
  def handle_info(:tick, state) do
    {:noreply, report(state)}
  rescue
    exception ->
      Logger.error("report failed: #{Exception.message(exception)}")
      {:noreply, state}
  after
    Process.send_after(self(), :tick, interval_ms())
  end

  defp interval_ms, do: Env.int("REPORT_SECONDS", 10) * 1_000

  defp station_counts do
    Repo.query!("SELECT meta_state, COUNT(*) FROM stations GROUP BY meta_state").rows
    |> Map.new(fn [state, n] -> {state, n} end)
  end

  defp one(sql) do
    %{rows: [[n]]} = Repo.query!(sql)
    n
  end

  defp report(state) do
    {:ok, %{rows: rows}} =
      Repo.query(
        """
        SELECT id, endpoint, polled_at, row_count, inserted, unchanged, duration_ms, error
          FROM ingest_stats WHERE id > ? ORDER BY id
        """,
        [state.last_id]
      )

    %{rows: [[added, last_obs_id]]} =
      Repo.query!(
        "SELECT COUNT(*), COALESCE(MAX(id), ?) FROM track_observations WHERE id > ?",
        [state.last_obs_id, state.last_obs_id]
      )

    pruned =
      for [_id, "track-prune", _polled_at, row_count | _rest] <- rows,
          reduce: 0,
          do: (total -> total + (row_count || 0))

    snap = %{obs: state.obs + added - pruned, counts: station_counts()}

    last_id =
      case List.last(rows) do
        nil -> state.last_id
        [id | _rest] -> id
      end

    prev = state.prev || %{obs: nil, counts: %{}}

    delta = fn current, previous ->
      case previous do
        nil ->
          "#{current}"

        p ->
          d = current - p
          if d == 0, do: "#{current}", else: "#{current} (#{if d > 0, do: "+", else: ""}#{d})"
      end
    end

    count = fn state_name, s -> Map.get(s.counts, state_name, 0) end

    line =
      "obs=#{delta.(snap.obs, prev.obs)} " <>
        "ok=#{delta.(count.("ok", snap), count.("ok", prev))} " <>
        "unknown=#{delta.(count.("unknown", snap), count.("unknown", prev))} " <>
        "no-metadata=#{delta.(count.("no-metadata", snap), count.("no-metadata", prev))} " <>
        "dead=#{delta.(count.("dead", snap), count.("dead", prev))} " <>
        "removed=#{delta.(count.("removed", snap), count.("removed", prev))}"

    Logger.info("report #{line} | #{length(rows)} stats rows since last report")

    %{
      last_id: last_id,
      last_obs_id: last_obs_id,
      obs: snap.obs,
      prev: %{obs: snap.obs, counts: snap.counts}
    }
  end
end
