defmodule BBRF.Metrics.AdsTest do
  use ExUnit.Case, async: false

  alias BBRF.{Metatable, Repo, TrackObservation}
  alias BBRF.Metrics.Ads

  @since "2026-10-01T00:00:00Z"

  setup do
    Metatable.reset_db!()
    System.put_env("METRICS_MIN_PLAYS", "4")
    on_exit(fn -> System.delete_env("METRICS_MIN_PLAYS") end)
  end

  defp insert(observations), do: Repo.insert_all(TrackObservation, List.flatten(observations))

  test "a station with three ad breaks airs ads" do
    insert([
      Metatable.plays("station-1", "Artist", "One", 2),
      Metatable.raw_plays("station-1", "Advertisement", 2),
      Metatable.raw_plays("station-1", "Reklama")
    ])

    assert Ads.compute(["station-1"], @since) == [{"station-1", 1.0, 3}]
  end

  test "fewer than three is not enough" do
    insert([
      Metatable.plays("station-1", "Artist", "One", 4),
      Metatable.raw_plays("station-1", "Advertisement", 2)
    ])

    assert Ads.compute(["station-1"], @since) == [{"station-1", 0.0, 2}]
  end

  test "leaves out stations with fewer observations than the minimum" do
    insert(Metatable.raw_plays("station-1", "Advertisement", 3))

    assert Ads.compute(["station-1"], @since) == []
  end
end
