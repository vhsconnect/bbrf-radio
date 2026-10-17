defmodule RadioAnalyzer.Repo.Migrations.CreateIngestStats do
  use Ecto.Migration

  def change do
    # One row per endpoint poll: how much data was ingested, how long
    # it took, and any error that occurred. Track waves and prunes
    # record their outcome here too.
    create table(:ingest_stats, primary_key: false) do
      add :id, :serial, primary_key: true
      add :endpoint, :text, null: false
      add :polled_at, :text, null: false
      add :row_count, :integer
      add :inserted, :integer
      add :updated, :integer
      add :unchanged, :integer
      add :duration_ms, :integer
      add :error, :text
    end

    create index(:ingest_stats, [:endpoint, :polled_at], name: :idx_ingest_stats_endpoint)
  end
end
