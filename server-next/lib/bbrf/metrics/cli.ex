defmodule BBRF.Metrics.CLI do
  @moduledoc """
  Runs `BBRF.Metrics` once against the configured database (BBRF_DB) and
  exits, with neither the API nor the ingester:

      bin/bbrf eval "BBRF.Metrics.CLI.main()"                 # a release
      mix run --no-start -e "BBRF.Metrics.CLI.main()"         # the source tree

  It prints when it starts, each metric's progress by quarter of its
  chunks, each metric's outcome as it finishes, and the total time.

  It never migrates: a database behind the code stops it, so it cannot
  race the running node's own migration. It exits with 1 when the
  database is behind or a metric failed.
  """

  alias BBRF.{Metrics, Repo}

  @handler_id "bbrf-metrics-cli"

  def main do
    :ok = loaded(Application.load(:bbrf))
    {:ok, _} = Application.ensure_all_started(:ecto_sqlite3)
    {:ok, _} = Repo.start_link(pool_size: 1, log: false)

    case pending_migrations() do
      [] ->
        start = System.monotonic_time(:millisecond)
        attach()

        IO.puts(
          "metrics: computing #{Enum.map_join(Metrics.all(), ", ", & &1.name())} " <>
            "over the last #{Metrics.window_days()} days in #{database()}"
        )

        Metrics.run() |> report(start) |> System.halt()

      pending ->
        IO.puts(
          :stderr,
          "metrics: the database is missing migrations #{Enum.join(pending, ", ")}"
        )

        System.halt(1)
    end
  end

  @doc false
  def handle_event([:bbrf, :metrics, :chunk], %{done: done, total: total}, %{metric: name}, _) do
    if quarter(done, total) > quarter(done - 1, total),
      do: IO.puts("metrics: #{name} #{quarter(done, total) * 25}%")
  end

  def handle_event(
        [:bbrf, :ingest, :stat],
        _measurements,
        %{endpoint: "metric:" <> name} = meta,
        _
      ) do
    case meta.stats do
      %{error: nil} = stats ->
        IO.puts(
          "metrics: #{name} done, #{stats.inserted} of #{stats.row_count} stations scored " <>
            "in #{seconds(stats.duration_ms)}"
        )

      %{error: error} ->
        IO.puts(:stderr, "metrics: #{name} failed: #{error}")
    end
  end

  def handle_event([:bbrf, :ingest, :stat], _measurements, _meta, _config), do: :ok

  defp attach do
    :telemetry.attach_many(
      @handler_id,
      [[:bbrf, :metrics, :chunk], [:bbrf, :ingest, :stat]],
      &__MODULE__.handle_event/4,
      nil
    )
  end

  defp quarter(done, total), do: div(done * 4, total)

  defp loaded(:ok), do: :ok
  defp loaded({:error, {:already_loaded, :bbrf}}), do: :ok

  defp database, do: Application.get_env(:bbrf, Repo, [])[:database]

  defp pending_migrations do
    for {:down, version, _name} <- Ecto.Migrator.migrations(Repo), do: version
  end

  defp report(results, start) do
    took = seconds(System.monotonic_time(:millisecond) - start)

    if Enum.all?(results, &match?({_name, :ok}, &1)) do
      IO.puts("metrics: finished in #{took}")
      0
    else
      IO.puts(:stderr, "metrics: finished in #{took}, with failures")
      1
    end
  end

  defp seconds(ms), do: "#{Float.round(ms / 1000, 1)}s"
end
