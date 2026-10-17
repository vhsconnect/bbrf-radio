defmodule RadioAnalyzer.Repo.Migrations.CreateStations do
  use Ecto.Migration

  def change do
    # Full station struct as returned by the radio-browser API plus the
    # bookkeeping timestamps and metadata-classification columns. Mirrors
    # the schema of the clojure original after all its migrations,
    # minus the deprecated `last_polled_at` column (never written since
    # its wave redesign).
    create table(:stations, primary_key: false) do
      add :stationuuid, :text, primary_key: true
      add :changeuuid, :text
      add :serveruuid, :text
      add :name, :text
      add :url, :text
      add :url_resolved, :text
      add :homepage, :text
      add :favicon, :text
      add :tags, :text
      add :country, :text
      add :countrycode, :text
      add :iso_3166_2, :text
      add :state, :text
      add :language, :text
      add :languagecodes, :text
      add :votes, :integer
      add :lastchangetime, :text
      add :lastchangetime_iso8601, :text
      add :codec, :text
      add :bitrate, :integer
      add :hls, :integer
      add :lastcheckok, :integer
      add :lastchecktime, :text
      add :lastchecktime_iso8601, :text
      add :lastcheckoktime, :text
      add :lastcheckoktime_iso8601, :text
      add :lastlocalchecktime, :text
      add :lastlocalchecktime_iso8601, :text
      add :clicktimestamp, :text
      add :clicktimestamp_iso8601, :text
      add :clickcount, :integer
      add :clicktrend, :integer
      add :ssl_error, :integer
      add :geo_lat, :real
      add :geo_long, :real
      add :geo_distance, :real
      add :has_extended_info, :integer
      add :first_seen_at, :text, null: false
      add :last_changed_at, :text, null: false
      add :meta_state, :text, null: false, default: "unknown"
      add :meta_checked_at, :text
      add :meta_fail_count, :integer, null: false, default: 0
      add :meta_last_title, :text
    end

    create index(:stations, [:last_changed_at], name: :idx_stations_last_changed)
    create index(:stations, [:lastcheckok], name: :idx_stations_lastcheckok)
    create index(:stations, [:meta_state], name: :idx_stations_meta_state)
    create index(:stations, [:meta_checked_at], name: :idx_stations_meta_checked)
  end
end
