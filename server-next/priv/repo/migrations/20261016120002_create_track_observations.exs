defmodule BBRF.Repo.Migrations.CreateTrackObservations do
  use Ecto.Migration

  def change do
    # Full accounting of currently-playing track observations: one row
    # per *track change* (deduped against stations.meta_last_title, not
    # per sample). raw_title is the title exactly as served (usually
    # "Artist - Title"); artist/title are the parsed halves when both
    # are derivable; metadata holds extra fields as JSON (listeners,
    # bitrate, ...).
    create table(:track_observations, primary_key: false) do
      add :id, :serial, primary_key: true
      add :stationuuid, :text, null: false
      add :observed_at, :text, null: false
      add :raw_title, :text
      add :artist, :text
      add :title, :text
      add :metadata, :text
    end

    create index(:track_observations, [:stationuuid, :observed_at],
             name: :idx_track_obs_station_time
           )

    # time-leading index: the retention pruner deletes by observed_at
    create index(:track_observations, [:observed_at], name: :idx_track_obs_time)
  end
end
