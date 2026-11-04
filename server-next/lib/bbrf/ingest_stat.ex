defmodule BBRF.IngestStat do
  @moduledoc """
  One row per endpoint poll: how much data was ingested, how long it
  took, and any error that occurred. Track waves and prunes record their
  outcome here too (`track-wave`, `track-prune` endpoints). Powers the
  "how many stations were we able to capture" reporting.
  """

  use Ecto.Schema
  alias BBRF.Repo

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

  @doc "Insert one bookkeeping row for a poll, a wave, a sync or a prune."
  def record(endpoint, stats) do
    result =
      Repo.insert_all(__MODULE__, [
        %{
          endpoint: endpoint,
          polled_at: DateTime.to_iso8601(DateTime.utc_now()),
          row_count: stats.row_count,
          inserted: stats.inserted,
          updated: stats.updated,
          unchanged: stats.unchanged,
          duration_ms: stats.duration_ms,
          error: stats.error
        }
      ])

    :telemetry.execute([:bbrf, :ingest, :stat], %{}, %{endpoint: endpoint, stats: stats})
    result
  end
end
