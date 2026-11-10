defmodule BBRF.Repo.Migrations.AddTrackObsTitledArtistCreditIndex do
  use Ecto.Migration

  # lets BBRF.Ingester.Artists.due/2 count plays per credit from the index
  # alone; with title outside the index it read every observation and held
  # the read lock long enough to fail the ingester's writes
  def change do
    create index(:track_observations, [:artist_credit_id],
             name: :idx_track_obs_titled_artist_credit,
             where: "title IS NOT NULL"
           )
  end
end
