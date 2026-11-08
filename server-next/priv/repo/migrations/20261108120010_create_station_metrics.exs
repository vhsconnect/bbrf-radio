defmodule BBRF.Repo.Migrations.CreateStationMetrics do
  use Ecto.Migration

  def change do
    # One row per station and metric, written by BBRF.Metrics. A metric
    # dropped from the code loses its rows on the next run, so adding or
    # removing one needs no migration.
    create table(:station_metrics, primary_key: false) do
      add :stationuuid, :text, primary_key: true
      # BBRF.Metrics.Metric name/0
      add :metric, :text, primary_key: true
      # NULL when the station has the plays but not enough of what the
      # metric needs (e.g. too few artists with a country)
      add :value, :real
      # what the value rests on, in the metric's own unit (plays, coverage %, matches)
      add :sample, :integer, null: false
      # the start of the run that wrote it, the same for every row of a run
      add :computed_at, :text, null: false
    end

    create index(:station_metrics, [:metric, :value])
  end
end
