defmodule RadioAnalyzer.Repo.Migrations.AddStationSchedule do
  use Ecto.Migration

  def change do
    # Per-station due time for track waves, replacing the ok-first,
    # least-recently-checked ordering. NULL means due now.
    # meta_idle_count counts consecutive checks without a new track (ok)
    # or without metadata (no-metadata) and drives their back-off.
    # synced_at is the start of the last full catalogue sync that saw
    # the station; stations a completed sync misses become 'removed'.
    alter table(:stations) do
      add :meta_next_check_at, :text
      add :meta_idle_count, :integer, null: false, default: 0
      add :synced_at, :text
    end

    create index(:stations, [:meta_next_check_at], name: :idx_stations_meta_next_check)
    drop index(:stations, [:meta_checked_at], name: :idx_stations_meta_checked)
  end
end
