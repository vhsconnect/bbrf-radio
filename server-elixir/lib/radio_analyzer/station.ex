defmodule RadioAnalyzer.Station do
  @moduledoc """
  One row per station, unique on `stationuuid`. The full station struct
  as returned by the radio-browser API plus bookkeeping timestamps and
  the metadata-classification columns the wave poller maintains:

    meta_state        'unknown' | 'ok' | 'no-metadata' | 'dead'
    meta_checked_at   bumped every time a wave touches the station -
                      drives the fair least-recently-checked ordering
    meta_fail_count   consecutive fetch failures; 'dead' at 3
    meta_last_title   last observed raw_title - observations are only
                      stored when the title differs from this
  """

  use Ecto.Schema

  @primary_key {:stationuuid, :string, autogenerate: false}

  schema "stations" do
    field(:changeuuid, :string)
    field(:serveruuid, :string)
    field(:name, :string)
    field(:url, :string)
    field(:url_resolved, :string)
    field(:homepage, :string)
    field(:favicon, :string)
    field(:tags, :string)
    field(:country, :string)
    field(:countrycode, :string)
    field(:iso_3166_2, :string)
    field(:state, :string)
    field(:language, :string)
    field(:languagecodes, :string)
    field(:votes, :integer)
    field(:lastchangetime, :string)
    field(:lastchangetime_iso8601, :string)
    field(:codec, :string)
    field(:bitrate, :integer)
    field(:hls, :integer)
    field(:lastcheckok, :integer)
    field(:lastchecktime, :string)
    field(:lastchecktime_iso8601, :string)
    field(:lastcheckoktime, :string)
    field(:lastcheckoktime_iso8601, :string)
    field(:lastlocalchecktime, :string)
    field(:lastlocalchecktime_iso8601, :string)
    field(:clicktimestamp, :string)
    field(:clicktimestamp_iso8601, :string)
    field(:clickcount, :integer)
    field(:clicktrend, :integer)
    field(:ssl_error, :integer)
    field(:geo_lat, :float)
    field(:geo_long, :float)
    field(:geo_distance, :float)
    field(:has_extended_info, :integer)
    field(:first_seen_at, :string)
    field(:last_changed_at, :string)
    field(:meta_state, :string)
    field(:meta_checked_at, :string)
    field(:meta_fail_count, :integer)
    field(:meta_last_title, :string)
  end
end
