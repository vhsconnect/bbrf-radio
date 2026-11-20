defmodule BBRF.Repo.Migrations.AddArtistCreditResolvedBy do
  use Ecto.Migration

  def up do
    # On a hub, the sync_origins row of the ingest node whose resolution of
    # the credit it keeps; the first one it receives wins. NULL on an ingest
    # node, and for a credit no node has resolved yet.
    alter table(:artist_credits) do
      add :resolved_by, :integer
    end

    flush()

    # a hub's resolutions so far came from the ingest node its history was
    # handed to (AddObservationOrigin)
    repo().query!("""
    UPDATE artist_credits SET resolved_by = 1
     WHERE status = 'resolved' AND EXISTS (SELECT 1 FROM sync_origins WHERE id = 1)
    """)
  end

  def down do
    alter table(:artist_credits) do
      remove :resolved_by
    end
  end
end
