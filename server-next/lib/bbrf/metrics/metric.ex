defmodule BBRF.Metrics.Metric do
  @moduledoc """
  A metric scores stations on one aspect of what they play. `compute/2`
  gets a chunk of stations and the start of the window, and returns a
  row for each station it can judge; stations left out get no row.

  A higher value is always the better one: clients sort on it without
  knowing what a metric measures, so a metric about something to avoid
  scores its absence (`BBRF.Metrics.NoSsAds`).
  """

  @type row :: {stationuuid :: String.t(), value :: float() | nil, sample :: non_neg_integer()}

  @doc "The name its rows are stored under."
  @callback name() :: String.t()

  @callback compute(stationuuids :: [String.t()], since :: String.t()) :: [row()]
end
