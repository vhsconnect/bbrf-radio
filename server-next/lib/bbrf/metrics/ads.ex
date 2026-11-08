defmodule BBRF.Metrics.Ads do
  @moduledoc """
  Whether a station airs ads: 1.0 when at least three of its titles in the
  window are ad breaks (`BBRF.AdMarkers`), else 0.0. Every observation
  counts, parsed or not. `sample` is the ad break titles seen.
  """

  @behaviour BBRF.Metrics.Metric

  alias BBRF.{AdMarkers, Metrics, Repo}

  # one stray match (a song named like a marker) is not enough
  @min_matches 3

  @impl true
  def name, do: "ads"

  @impl true
  def compute(stationuuids, since) do
    %{rows: rows} =
      Repo.query!(
        """
        SELECT stationuuid, raw_title, COUNT(*)
          FROM track_observations
         WHERE stationuuid IN (#{Metrics.placeholders(stationuuids)})
           AND observed_at >= ?
         GROUP BY stationuuid, raw_title
        """,
        stationuuids ++ [since]
      )

    rows
    |> Enum.group_by(&hd/1, fn [_stationuuid, raw_title, n] -> {AdMarkers.ad?(raw_title), n} end)
    |> Enum.flat_map(fn {stationuuid, titles} ->
      plays = titles |> Enum.map(&elem(&1, 1)) |> Enum.sum()
      matches = for {true, n} <- titles, reduce: 0, do: (acc -> acc + n)

      if plays >= Metrics.min_plays(),
        do: [{stationuuid, if(matches >= @min_matches, do: 1.0, else: 0.0), matches}],
        else: []
    end)
  end
end
