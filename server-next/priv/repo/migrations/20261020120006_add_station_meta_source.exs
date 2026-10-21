defmodule BBRF.Repo.Migrations.AddStationMetaSource do
  use Ecto.Migration

  def up do
    # Which method last produced a title: 'icecast' (status-json.xsl) or
    # 'icy' (in-band stream metadata); NULL until one has.
    alter table(:stations) do
      add :meta_source, :text
    end

    # before ICY every title came from status-json.xsl, and stations
    # without one only had that tried: make them due for an ICY probe
    execute "UPDATE stations SET meta_source = 'icecast' WHERE meta_state = 'ok'"

    execute "UPDATE stations SET meta_next_check_at = NULL, meta_idle_count = 0 WHERE meta_state = 'no-metadata'"
  end

  def down do
    alter table(:stations) do
      remove :meta_source
    end
  end
end
