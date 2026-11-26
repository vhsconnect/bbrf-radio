defmodule BBRF.Metrics.ClicksTest do
  use ExUnit.Case, async: false

  alias BBRF.Metatable
  alias BBRF.Ingester.Stations
  alias BBRF.Metrics.Catalogue

  setup do
    Metatable.reset_db!()
  end

  defp clicks(clickcount) do
    Stations.upsert([Metatable.station(%{"clickcount" => clickcount})])

    %{"station-1" => %{"hi_clicks" => metric}} = Catalogue.for_stations(["station-1"])
    metric
  end

  test "is the click count" do
    assert clicks(37) == %{"value" => 37, "sample" => 37}
  end

  test "is unknown without a click, with a sample of 0" do
    assert clicks(0) == %{"value" => nil, "sample" => 0}
    assert clicks(nil) == %{"value" => nil, "sample" => 0}
  end

  test "carries the same value under both names" do
    Stations.upsert([Metatable.station(%{"clickcount" => 5})])

    assert %{"station-1" => %{"hi_clicks" => same, "lo_clicks" => same}} =
             Catalogue.for_stations(["station-1"])
  end
end
