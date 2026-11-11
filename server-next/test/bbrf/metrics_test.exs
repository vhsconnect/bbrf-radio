defmodule BBRF.MetricsTest do
  use ExUnit.Case, async: false

  @moduletag :capture_log

  alias BBRF.{Metatable, Metrics, Repo, TrackObservation}
  alias BBRF.Metrics.{Balance, NoSsAds}

  defmodule Broken do
    @behaviour BBRF.Metrics.Metric

    @impl true
    def name, do: "broken"

    @impl true
    def compute(_stationuuids, _since), do: raise("no luck")
  end

  @first_run ~U[2026-10-20 12:00:00.000000Z]
  @second_run ~U[2026-10-21 12:00:00.000000Z]

  setup do
    Metatable.reset_db!()
    System.put_env("METRICS_MIN_PLAYS", "4")
    on_exit(fn -> System.delete_env("METRICS_MIN_PLAYS") end)

    Repo.insert_all(
      TrackObservation,
      Metatable.plays("station-1", "Artist", "One", 2) ++
        Metatable.plays("station-1", "Artist", "Two", 2) ++
        Metatable.plays("station-2", "Artist", "One", 4)
    )

    :ok
  end

  defp rows do
    Repo.query!(
      "SELECT metric, stationuuid, value, sample, computed_at FROM station_metrics ORDER BY metric, stationuuid"
    ).rows
  end

  test "stores a row per station and metric, stamped with the run's start" do
    assert Metrics.run([Balance, NoSsAds], @first_run) == [{"balance", :ok}, {"no_ss_ads", :ok}]

    at = DateTime.to_iso8601(@first_run)

    assert rows() == [
             ["balance", "station-1", 0.5, 4, at],
             ["balance", "station-2", 0.25, 4, at],
             ["no_ss_ads", "station-1", 1.0, 0, at],
             ["no_ss_ads", "station-2", 1.0, 0, at]
           ]
  end

  test "records each metric in ingest_stats" do
    Metrics.run([Balance], @first_run)

    assert Repo.query!(
             "SELECT endpoint, row_count, inserted, error FROM ingest_stats ORDER BY endpoint"
           ).rows == [["metric:balance", 2, 2, nil]]
  end

  test "drops the rows of stations a later run no longer scores" do
    Metrics.run([Balance], @first_run)
    Repo.query!("DELETE FROM track_observations WHERE stationuuid = 'station-2'")
    Metrics.run([Balance], @second_run)

    assert Enum.map(rows(), &Enum.take(&1, 2)) == [["balance", "station-1"]]
  end

  test "drops the rows of metrics no longer listed" do
    Metrics.run([Balance, NoSsAds], @first_run)
    Metrics.run([Balance], @second_run)

    assert rows() |> Enum.map(&hd/1) |> Enum.uniq() == ["balance"]
  end

  test "a metric that raises keeps its previous rows and the others still run" do
    Metrics.run([Balance], @first_run)
    Repo.query!("UPDATE station_metrics SET metric = 'broken'")

    assert Metrics.run([Broken, Balance], @second_run) ==
             [{"broken", {:error, "no luck"}}, {"balance", :ok}]

    assert rows() |> Enum.map(&{hd(&1), List.last(&1)}) |> Enum.uniq() == [
             {"balance", DateTime.to_iso8601(@second_run)},
             {"broken", DateTime.to_iso8601(@first_run)}
           ]

    assert Repo.query!("SELECT error FROM ingest_stats WHERE endpoint = 'metric:broken'").rows ==
             [["no luck"]]
  end

  test "enrich/1 puts each station's stored metrics on it by stationuuid" do
    Metrics.run([Balance, NoSsAds], @first_run)

    assert Metrics.enrich([
             %{"stationuuid" => "station-1", "name" => "Example FM"},
             %{"stationuuid" => "unscored"}
           ]) == [
             %{
               "stationuuid" => "station-1",
               "name" => "Example FM",
               "metrics" => %{
                 "balance" => %{"value" => 0.5, "sample" => 4},
                 "no_ss_ads" => %{"value" => 1.0, "sample" => 0}
               }
             },
             %{"stationuuid" => "unscored", "metrics" => %{}}
           ]
  end

  test "enrich/1 of no stations is empty" do
    assert Metrics.enrich([]) == []
  end
end
