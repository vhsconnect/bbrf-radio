defmodule RadioAnalyzer.CatalogueTest do
  use ExUnit.Case, async: false

  alias RadioAnalyzer.{Catalogue, Ingest, Metatable, Repo}

  setup do
    Metatable.reset_db!()
    :ok
  end

  defp upstream(n), do: for(i <- 1..n, do: Metatable.station(%{"stationuuid" => "s#{i}"}))

  defp pages(stations), do: fn offset, limit -> Enum.slice(stations, offset, limit) end

  defp sync(stations),
    do: Catalogue.full_sync(fetch_page: pages(stations), page_size: 4, overlap: 1)

  defp states do
    Repo.query!("SELECT stationuuid, meta_state FROM stations ORDER BY stationuuid").rows
    |> Map.new(fn [uuid, state] -> {uuid, state} end)
  end

  test "pages through every station with overlapping pages" do
    stats = sync(upstream(10))

    assert %{row_count: 10, inserted: 10, unchanged: 0, removed: 0, error: nil} = stats
    assert map_size(states()) == 10
  end

  test "marks stations a completed sync did not see as removed" do
    sync(upstream(10))
    stats = sync(upstream(9))

    assert stats.removed == 1
    assert states()["s10"] == "removed"
    assert states()["s9"] == "unknown"
  end

  @tag :capture_log
  test "keeps everything when a sync sees too few stations" do
    sync(upstream(10))
    stats = sync(upstream(3))

    assert stats.error =~ "not marking any removed"
    refute "removed" in Map.values(states())
  end

  test "is due until a sync succeeds within FULL_SYNC_HOURS" do
    assert Catalogue.due?()

    Ingest.record_stats("stations-full", %{
      row_count: 0,
      inserted: 0,
      updated: 0,
      unchanged: 0,
      duration_ms: 0,
      error: "boom"
    })

    assert Catalogue.due?()

    sync(upstream(2))
    refute Catalogue.due?()
  end
end
