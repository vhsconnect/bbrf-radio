defmodule BBRF.Metrics.InternationalTest do
  use ExUnit.Case, async: false

  alias BBRF.{Metatable, Repo, TrackObservation}
  alias BBRF.Metrics.International

  @since "2026-10-01T00:00:00Z"

  setup do
    Metatable.reset_db!()
    System.put_env("METRICS_MIN_PLAYS", "4")
    on_exit(fn -> System.delete_env("METRICS_MIN_PLAYS") end)

    Metatable.resolve!("Beyoncé", "US")
    Metatable.resolve!("Robyn", "SE")
    Metatable.resolve!("Aya Nakamura", "FR")
    Metatable.resolve!("Nowhere Band", nil)
  end

  defp insert(observations), do: Repo.insert_all(TrackObservation, List.flatten(observations))

  defp compute, do: International.compute(["station-1"], @since)

  test "two countries played equally count as two" do
    insert([
      Metatable.plays("station-1", "Beyoncé", "Halo", 2),
      Metatable.plays("station-1", "Robyn", "Dancing On My Own", 2)
    ])

    assert [{"station-1", value, 100}] = compute()
    assert_in_delta value, 2.0, 1.0e-9
  end

  test "one country counts as one, however many artists" do
    insert(Metatable.plays("station-1", "Beyoncé", "Halo", 4))

    assert [{"station-1", value, 100}] = compute()
    assert_in_delta value, 1.0, 1.0e-9
  end

  test "an uneven mix counts as fewer countries than it has" do
    insert([
      Metatable.plays("station-1", "Beyoncé", "Halo", 6),
      Metatable.plays("station-1", "Robyn", "Dancing On My Own"),
      Metatable.plays("station-1", "Aya Nakamura", "Djadja")
    ])

    assert [{"station-1", value, 100}] = compute()
    assert value > 1.0 and value < 3.0
  end

  test "counts plays without a country towards the coverage only" do
    insert([
      Metatable.plays("station-1", "Beyoncé", "Halo", 2),
      Metatable.plays("station-1", "Robyn", "Dancing On My Own", 2),
      Metatable.plays("station-1", "Nowhere Band", "Somewhere"),
      Metatable.plays("station-1", "Never Resolved", "Song")
    ])

    assert [{"station-1", value, 66}] = compute()
    assert_in_delta value, 2.0, 1.0e-9
  end

  test "is NULL below the coverage threshold" do
    insert([
      Metatable.plays("station-1", "Beyoncé", "Halo"),
      Metatable.plays("station-1", "Never Resolved", "Song", 3)
    ])

    assert compute() == [{"station-1", nil, 25}]
  end

  test "leaves out stations with fewer plays than the minimum" do
    insert(Metatable.plays("station-1", "Beyoncé", "Halo", 3))

    assert compute() == []
  end
end
