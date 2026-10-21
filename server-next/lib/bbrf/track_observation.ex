defmodule BBRF.TrackObservation do
  @moduledoc """
  One row per *track change* (deduped against `stations.meta_last_title`,
  not per sample). `raw_title` is the title exactly as served (usually
  "Artist - Title"); `artist`/`title` are the parsed halves when both are
  derivable; `metadata` holds the per-sample extras worth keeping
  (listeners, bitrate, ...) as JSON.
  """

  use Ecto.Schema

  schema "track_observations" do
    field(:stationuuid, :string)
    field(:observed_at, :string)
    field(:raw_title, :string)
    field(:artist, :string)
    field(:title, :string)
    field(:metadata, :string)
  end
end
