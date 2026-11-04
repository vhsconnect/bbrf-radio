defmodule BBRF.Repo.Migrations.CreateArtists do
  use Ecto.Migration

  def change do
    # A MusicBrainz artist profile, flattened: the scalar fields here, the
    # lists in the artist_* tables below.
    create table(:artists, primary_key: false) do
      add :mbid, :text, primary_key: true
      add :name, :text, null: false
      add :sort_name, :text
      # Person, Group, Orchestra, Choir, Character, Other
      add :type, :text
      add :gender, :text
      # ISO 3166-1 code
      add :country, :text
      add :area, :text
      add :begin_area, :text
      add :end_area, :text
      # YYYY, YYYY-MM or YYYY-MM-DD, as precise as MusicBrainz knows it
      add :begin_date, :text
      add :end_date, :text
      add :ended, :boolean
      add :disambiguation, :text
      add :fetched_at, :text, null: false
    end

    # tags and genres together; genres are MusicBrainz's curated subset
    create table(:artist_tags, primary_key: false) do
      add :artist_mbid, references(:artists, column: :mbid, type: :text, on_delete: :delete_all),
        primary_key: true

      add :tag, :text, primary_key: true
      add :votes, :integer, null: false
      add :genre, :boolean, null: false
    end

    create table(:artist_aliases, primary_key: false) do
      add :artist_mbid, references(:artists, column: :mbid, type: :text, on_delete: :delete_all),
        primary_key: true

      add :alias, :text, primary_key: true
      add :locale, :text
      add :primary_alias, :boolean, null: false
    end

    create table(:artist_links, primary_key: false) do
      add :artist_mbid, references(:artists, column: :mbid, type: :text, on_delete: :delete_all),
        primary_key: true

      add :url, :text, primary_key: true
      # the relation type: official homepage, wikidata, bandcamp, ...
      add :kind, :text
    end

    # One row per credit the resolver has tried. id is BBRF.ArtistCredit.id/1,
    # the artist_credit_id observations carry.
    create table(:artist_credits, primary_key: false) do
      add :id, :integer, primary_key: true
      # the spelling the resolver searched for
      add :name, :text, null: false
      # resolved or unresolved
      add :status, :text, null: false
      add :attempts, :integer, null: false
      add :checked_at, :text, null: false
      # when an unresolved credit is tried again
      add :next_check_at, :text
    end

    create table(:artist_credit_artists, primary_key: false) do
      add :artist_credit_id, references(:artist_credits, on_delete: :delete_all),
        primary_key: true

      # order within the credit, from 0
      add :position, :integer, primary_key: true
      add :artist_mbid, references(:artists, column: :mbid, type: :text), null: false
      # the name the credit gives the artist, which can differ from its own
      add :credited_as, :text
      # what joins it to the next artist, e.g. " & " or " feat. "
      add :join_phrase, :text
    end

    create index(:artist_credit_artists, [:artist_mbid])
  end
end
