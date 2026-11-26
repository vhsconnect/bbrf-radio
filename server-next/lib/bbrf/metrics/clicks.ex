defmodule BBRF.Metrics.Clicks do
  @moduledoc """
  How much a station is listened to: the clicks radio-browser counted for
  it in the 24 hours before the last catalogue sync. `hi_clicks` sorts
  most first and `lo_clicks` least first. A station without a click is
  unknown rather than 0, and sorts last either way: it is often one
  nobody can find or play, so `lo_clicks` starts with the least listened
  stations someone still listens to. `sample` is the click count, 0
  included.

  radio-browser's `clicktrend` is left out: it serves the same number as
  `clickcount`.
  """

  @behaviour BBRF.Metrics.Catalogue

  @impl true
  def sorts, do: [{"hi_clicks", "DESC"}, {"lo_clicks", "ASC"}]

  @impl true
  def sql, do: "NULLIF(s.clickcount, 0)"

  @impl true
  def sample_sql, do: "COALESCE(s.clickcount, 0)"
end
