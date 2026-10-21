defmodule BBRF.Ingester.Track.StrategyTest do
  use ExUnit.Case, async: false

  alias BBRF.Ingester.Track.Strategy
  alias BBRF.Ingester.Track.Strategy.{Adaptive, FullSweep}

  setup do
    on_exit(fn -> System.delete_env("TRACK_STRATEGY") end)
    System.delete_env("TRACK_STRATEGY")
    :ok
  end

  test "names the available strategies" do
    assert Strategy.names() == ["adaptive", "full-sweep"]
  end

  test "builds a strategy by name with its options" do
    assert {FullSweep, %{cycle_minutes: 30}} = Strategy.new("full-sweep", cycle_minutes: 30)
    assert Strategy.name(Strategy.new("full-sweep")) == "full-sweep"
  end

  test "TRACK_STRATEGY picks the strategy, full-sweep when unset" do
    assert {FullSweep, _config} = Strategy.from_env()

    System.put_env("TRACK_STRATEGY", "adaptive")
    assert {Adaptive, _config} = Strategy.from_env()
  end

  test "an unknown name raises" do
    assert_raise ArgumentError, ~r/must be one of adaptive, full-sweep/, fn ->
      Strategy.new("round-robin")
    end
  end
end
