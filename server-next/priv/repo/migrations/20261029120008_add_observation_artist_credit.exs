defmodule BBRF.Repo.Migrations.AddObservationArtistCredit do
  use Ecto.Migration

  @chunk 5_000

  def up do
    # BBRF.ArtistCredit.id/1 of the artist: a hash, the same on every node,
    # and no row in artist_credits until the artist resolver gets to it
    alter table(:track_observations) do
      add :artist_credit_id, :integer
    end

    flush()
    backfill(0)

    create index(:track_observations, [:artist_credit_id, :observed_at],
             name: :idx_track_obs_artist_credit
           )
  end

  def down do
    drop index(:track_observations, [:artist_credit_id, :observed_at],
           name: :idx_track_obs_artist_credit
         )

    alter table(:track_observations) do
      remove :artist_credit_id
    end
  end

  defp backfill(after_id) do
    %{rows: rows} =
      repo().query!(
        "SELECT id, artist FROM track_observations WHERE id > ? AND artist IS NOT NULL ORDER BY id LIMIT ?",
        [after_id, @chunk]
      )

    case rows do
      [] ->
        :ok

      rows ->
        values = Enum.map_join(rows, ", ", fn _ -> "(?, ?)" end)
        params = Enum.flat_map(rows, fn [id, artist] -> [id, BBRF.ArtistCredit.id(artist)] end)

        repo().query!(
          """
          WITH v(id, credit) AS (VALUES #{values})
          UPDATE track_observations SET artist_credit_id = v.credit
            FROM v
           WHERE track_observations.id = v.id
          """,
          params
        )

        rows |> List.last() |> hd() |> backfill()
    end
  end
end
