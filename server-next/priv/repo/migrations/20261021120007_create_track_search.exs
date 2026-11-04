defmodule BBRF.Repo.Migrations.CreateTrackSearch do
  use Ecto.Migration

  def up do
    # Full-text index over the artist/title of every observation, kept in
    # sync by triggers so the ingester and the retention pruner need no
    # changes. External content: the index stores tokens only and reads
    # the text back from track_observations. remove_diacritics makes
    # "beyonce" match "Beyoncé".
    execute """
    CREATE VIRTUAL TABLE track_search USING fts5(
      artist,
      title,
      content = 'track_observations',
      content_rowid = 'id',
      tokenize = 'unicode61 remove_diacritics 2'
    )
    """

    execute """
    CREATE TRIGGER track_search_insert AFTER INSERT ON track_observations BEGIN
      INSERT INTO track_search (rowid, artist, title) VALUES (new.id, new.artist, new.title);
    END
    """

    execute """
    CREATE TRIGGER track_search_delete AFTER DELETE ON track_observations BEGIN
      INSERT INTO track_search (track_search, rowid, artist, title)
        VALUES ('delete', old.id, old.artist, old.title);
    END
    """

    execute """
    CREATE TRIGGER track_search_update AFTER UPDATE OF artist, title ON track_observations BEGIN
      INSERT INTO track_search (track_search, rowid, artist, title)
        VALUES ('delete', old.id, old.artist, old.title);
      INSERT INTO track_search (rowid, artist, title) VALUES (new.id, new.artist, new.title);
    END
    """

    execute "INSERT INTO track_search (track_search) VALUES ('rebuild')"
  end

  def down do
    execute "DROP TRIGGER track_search_update"
    execute "DROP TRIGGER track_search_delete"
    execute "DROP TRIGGER track_search_insert"
    execute "DROP TABLE track_search"
  end
end
