defmodule BBRF.Metrics.ObscureTest do
  use ExUnit.Case, async: false

  alias BBRF.{Metatable, Repo, TrackObservation}
  alias BBRF.Metrics.{Obscure, Obscure500}

  @since "2026-10-01T00:00:00Z"

  setup do
    Metatable.reset_db!()
    System.put_env("METRICS_MIN_PLAYS", "4")
    on_exit(fn -> System.delete_env("METRICS_MIN_PLAYS") end)
  end

  defp insert(observations), do: Repo.insert_all(TrackObservation, List.flatten(observations))

  defp compute(top), do: Obscure.compute(["station-1"], @since, top)

  test "is distinct tracks outside the top over plays" do
    insert([
      Metatable.plays("station-1", "Hit", "One", 2),
      Metatable.plays("station-1", "Deep Cut", "Two"),
      Metatable.plays("station-1", "Deep Cut", "Three"),
      Metatable.plays("station-2", "Hit", "One")
    ])

    assert compute(1) == [{"station-1", 0.5, 4}]
  end

  test "ranks artists by the stations playing them before their plays" do
    insert([
      Metatable.plays("station-1", "Looped", "One", 3),
      Metatable.plays("station-1", "Everywhere", "Two"),
      Metatable.plays("station-2", "Everywhere", "Two")
    ])

    assert compute(1) == [{"station-1", 0.25, 4}]
  end

  test "counts a repeated track outside the top once" do
    insert([
      Metatable.plays("station-1", "Hit", "One"),
      Metatable.plays("station-1", "Station Name", "Live", 3),
      Metatable.plays("station-2", "Hit", "One")
    ])

    assert compute(1) == [{"station-1", 0.25, 4}]
  end

  test "is zero when every artist is in the top" do
    insert(Metatable.plays("station-1", "Hit", "One", 4))

    assert compute(1) == [{"station-1", 0.0, 4}]
  end

  test "leaves out ad breaks" do
    insert([
      Metatable.plays("station-1", "Deep Cut", "One", 4),
      Metatable.plays("station-1", "Advertisement", "Spot", 2)
    ])

    assert [{"station-1", _value, 4}] = compute(2)
  end

  test "leaves out stations with fewer plays than the minimum" do
    insert(Metatable.plays("station-1", "Deep Cut", "One", 3))

    assert compute(1) == []
  end

  test "names a metric after its top" do
    assert Obscure500.name() == "obscure_500"
  end
end
