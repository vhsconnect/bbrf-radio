defmodule BBRF.Metrics.BalanceTest do
  use ExUnit.Case, async: false

  alias BBRF.{Metatable, Repo, TrackObservation}
  alias BBRF.Metrics.Balance

  @since "2026-10-01T00:00:00Z"

  setup do
    Metatable.reset_db!()
    System.put_env("METRICS_MIN_PLAYS", "4")
    on_exit(fn -> System.delete_env("METRICS_MIN_PLAYS") end)
  end

  defp insert(observations), do: Repo.insert_all(TrackObservation, List.flatten(observations))

  test "is distinct tracks over plays" do
    insert([
      Metatable.plays("station-1", "Artist", "One", 2),
      Metatable.plays("station-1", "Artist", "Two"),
      Metatable.plays("station-1", "Other", "One")
    ])

    assert Balance.compute(["station-1"], @since) == [{"station-1", 0.75, 4}]
  end

  test "counts a track spelled in another case as the same track" do
    insert([
      Metatable.plays("station-1", "Artist", "One", 3),
      Metatable.plays("station-1", "ARTIST", " one ")
    ])

    assert Balance.compute(["station-1"], @since) == [{"station-1", 0.25, 4}]
  end

  test "leaves out ad breaks and unparsed titles" do
    insert([
      Metatable.plays("station-1", "Artist", "One"),
      Metatable.plays("station-1", "Artist", "Two"),
      Metatable.plays("station-1", "Artist", "Three"),
      Metatable.plays("station-1", "Artist", "Four"),
      Metatable.plays("station-1", "Advert:", "Advert:", 5),
      Metatable.raw_plays("station-1", "Example FM", 5)
    ])

    assert Balance.compute(["station-1"], @since) == [{"station-1", 1.0, 4}]
  end

  test "leaves out stations with fewer plays than the minimum in the window" do
    insert([
      Metatable.plays("station-1", "Artist", "One", 3),
      Metatable.plays("station-2", "Artist", "One", 3),
      Enum.map(
        Metatable.plays("station-2", "Artist", "Old"),
        &%{&1 | observed_at: "2026-09-01T00:00:00Z"}
      )
    ])

    assert Balance.compute(["station-1", "station-2"], @since) == []
  end
end
