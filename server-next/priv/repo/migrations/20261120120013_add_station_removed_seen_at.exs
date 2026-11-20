defmodule BBRF.Repo.Migrations.AddStationRemovedSeenAt do
  use Ecto.Migration

  def change do
    # On a hub, the last time an ingest node sent the station as
    # 'removed'; it stays removed until REMOVED_TTL_DAYS after that.
    # NULL on an ingest node.
    alter table(:stations) do
      add :removed_seen_at, :text
    end
  end
end
