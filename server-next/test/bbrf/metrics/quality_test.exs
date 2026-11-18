defmodule BBRF.Metrics.QualityTest do
  use ExUnit.Case, async: false

  alias BBRF.Metatable
  alias BBRF.Ingester.Stations
  alias BBRF.Metrics.Quality

  setup do
    Metatable.reset_db!()
  end

  defp quality(codec, bitrate) do
    Stations.upsert([Metatable.station(%{"codec" => codec, "bitrate" => bitrate})])

    %{"station-1" => %{"hi_qlty" => %{"value" => value}}} = Quality.for_stations(["station-1"])
    value
  end

  test "is the bitrate for MP3" do
    assert quality("MP3", 128) == 128.0
  end

  test "gives AAC+ twice the MP3 kbps per kbps" do
    assert quality("AAC+", 64) == 128.0
  end

  test "puts FLAC at CD quality whatever it reports" do
    assert quality("FLAC", 0) == 1411.0
  end

  test "is unknown for an unreported or implausible bitrate" do
    assert quality("MP3", 0) == nil
    assert quality("MP3", 128_000) == nil
  end

  test "is unknown for video streams" do
    assert quality("AAC,H.264", 2600) == nil
  end

  test "carries the reported bitrate as the sample under both names" do
    Stations.upsert([Metatable.station(%{"codec" => "MP3", "bitrate" => 96})])

    assert Quality.for_stations(["station-1", "not-in-catalogue"]) == %{
             "station-1" => %{
               "hi_qlty" => %{"value" => 96.0, "sample" => 96},
               "lo_qlty" => %{"value" => 96.0, "sample" => 96}
             }
           }
  end
end
