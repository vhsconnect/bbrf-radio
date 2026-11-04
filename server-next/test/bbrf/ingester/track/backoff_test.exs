defmodule BBRF.Ingester.Track.BackoffTest do
  use ExUnit.Case, async: true

  alias BBRF.Metatable
  alias BBRF.Ingester.Track.Backoff

  defp due_in_minutes(outcome, state) do
    outcome
    |> Backoff.next_check_at(state, Metatable.now())
    |> DateTime.diff(Metatable.now(), :minute)
  end

  test "failures back off from 15 minutes, doubling, capped at 30 days" do
    minutes = for fails <- 1..4, do: due_in_minutes(:fail, %{meta_fail_count: fails})

    assert minutes == [15, 30, 60, 120]
    assert due_in_minutes(:fail, %{meta_fail_count: 40}) == 30 * 24 * 60
  end

  test "no metadata is rechecked after 7 days, then every 30" do
    assert due_in_minutes(:no_metadata, %{meta_idle_count: 1}) == 7 * 24 * 60
    assert due_in_minutes(:no_metadata, %{meta_idle_count: 2}) == 30 * 24 * 60
    assert due_in_minutes(:no_metadata, %{meta_idle_count: 5}) == 30 * 24 * 60
  end

  test "outcomes that read the station leave scheduling to the strategy" do
    assert Backoff.next_check_at(:idle, %{}, Metatable.now()) == nil
    assert Backoff.next_check_at({:changed, "t", %{}}, %{}, Metatable.now()) == nil
  end
end
