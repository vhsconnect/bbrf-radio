defmodule BBRF.Repo.Migrations.AddObservationOrigin do
  use Ecto.Migration

  def up do
    # The ingest nodes that have pushed to this hub, numbered by the hub.
    create table(:sync_origins) do
      add :node, :text, null: false
    end

    create unique_index(:sync_origins, [:node])

    # On a hub, where an observation came from: the sync_origins row of the
    # node that pushed it and its id there. NULL on an ingest node.
    alter table(:track_observations) do
      add :origin, :integer
      add :origin_id, :integer
    end

    flush()
    claim_legacy_rows()

    create unique_index(:track_observations, [:origin, :origin_id],
             name: :idx_track_obs_origin,
             where: "origin IS NOT NULL"
           )
  end

  def down do
    drop index(:track_observations, [:origin, :origin_id], name: :idx_track_obs_origin)

    alter table(:track_observations) do
      remove :origin
      remove :origin_id
    end

    drop table(:sync_origins)
  end

  # a hub's history so far came from its one ingest node with the ids it
  # has there; without this the node would send its whole history again
  defp claim_legacy_rows do
    with "hub" <- System.get_env("BBRF_ROLE"),
         [node | _] <- String.split(System.get_env("SYNC_INGEST_NODE", ""), ",", trim: true) do
      repo().query!("INSERT INTO sync_origins (id, node) VALUES (1, ?)", [String.trim(node)])
      repo().query!("UPDATE track_observations SET origin = 1, origin_id = id")
    end
  end
end
