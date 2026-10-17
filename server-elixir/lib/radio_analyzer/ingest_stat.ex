defmodule RadioAnalyzer.IngestStat do
  @moduledoc """
  One row per endpoint poll: how much data was ingested, how long it
  took, and any error that occurred. Track waves and prunes record their
  outcome here too (`track-wave`, `track-prune` endpoints). Powers the
  "how many stations were we able to capture" reporting.
  """

  use Ecto.Schema

  schema "ingest_stats" do
    field(:endpoint, :string)
    field(:polled_at, :string)
    field(:row_count, :integer)
    field(:inserted, :integer)
    field(:updated, :integer)
    field(:unchanged, :integer)
    field(:duration_ms, :integer)
    field(:error, :string)
  end
end
