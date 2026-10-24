defmodule BBRF.Repo.Migrations.CreateFavorites do
  use Ecto.Migration

  def change do
    # The bbrf user's favorite stations, keyed by stationuuid. `id` keeps
    # the order the user added them in.
    create table(:favorites) do
      add(:stationuuid, :text, null: false)
      add(:url, :text)
      add(:name, :text)
      add(:countrycode, :text)
      add(:bitrate, :integer)
      add(:added_at, :text, null: false)
    end

    create(unique_index(:favorites, [:stationuuid], name: :idx_favorites_stationuuid))
  end
end
