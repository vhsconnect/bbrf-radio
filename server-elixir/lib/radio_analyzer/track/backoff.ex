defmodule RadioAnalyzer.Track.Backoff do
  @moduledoc """
  Retries for stations whose last check failed or found no metadata,
  whatever the strategy. Such a station is backing off: it is checked
  again only when its due time (`meta_next_check_at`) comes up.

      failure       -> 15 min, doubling up to 30 days ('dead' after 3 in a row)
      no metadata   -> 7 days, then every 30

  A station backs off while `meta_fail_count > 0` or its state is
  'no-metadata': a failure counts up the first, no metadata sets the
  second, and any check that reads the station clears both.
  """

  import Ecto.Query

  @no_metadata_minutes [7 * 24 * 60, 30 * 24 * 60]
  @fail_base_minutes 15
  @fail_max_minutes 30 * 24 * 60

  @doc """
  When a station is due again after a failure or no metadata, from its
  `state` after the check; nil for the outcomes that read the station.
  """
  @spec next_check_at(RadioAnalyzer.Track.Strategy.outcome(), map(), DateTime.t()) ::
          DateTime.t() | nil
  def next_check_at(:fail, state, now) do
    minutes = @fail_base_minutes * 2 ** (state.meta_fail_count - 1)
    in_minutes(now, min(minutes, @fail_max_minutes))
  end

  def next_check_at(:no_metadata, state, now),
    do: in_minutes(now, step(@no_metadata_minutes, state.meta_idle_count))

  def next_check_at(_read, _state, _now), do: nil

  @doc "Narrow a candidates query to the stations backing off."
  def backing_off(query),
    do: where(query, [s], s.meta_fail_count > 0 or s.meta_state == "no-metadata")

  @doc "Narrow a candidates query to the stations not backing off."
  def not_backing_off(query),
    do: where(query, [s], s.meta_fail_count == 0 and s.meta_state != "no-metadata")

  @doc "Narrow a query to the stations due at `now` (an ISO 8601 string); NULL is due."
  def due(query, now),
    do: where(query, [s], is_nil(s.meta_next_check_at) or s.meta_next_check_at <= ^now)

  defp in_minutes(now, minutes), do: DateTime.add(now, minutes * 60, :second)

  # nth step of a back-off ladder, staying on the last step
  defp step(ladder, n), do: Enum.at(ladder, min(n, length(ladder)) - 1)
end
