defmodule BBRF.Metrics.Balance do
  @moduledoc """
  How little a station repeats itself: distinct tracks over plays, from
  1.0 (nothing played twice) towards 0. A track is an artist credit and
  a title, case and outer spaces aside. Only plays with both count, and
  ad breaks (`BBRF.AdMarkers`) are left out, so a station is not marked
  down for announcing the same break every hour. `sample` is the plays.
  """

  @behaviour BBRF.Metrics.Metric

  alias BBRF.{AdMarkers, Metrics, Repo}

  @impl true
  def name, do: "balance"

  @impl true
  def compute(stationuuids, since) do
    %{rows: rows} =
      Repo.query!(
        """
        SELECT stationuuid, MIN(raw_title), COUNT(*)
          FROM track_observations
         WHERE stationuuid IN (#{Metrics.placeholders(stationuuids)})
           AND observed_at >= ?
           AND artist_credit_id IS NOT NULL
           AND title IS NOT NULL
         GROUP BY stationuuid, artist_credit_id, lower(trim(title))
        """,
        stationuuids ++ [since]
      )

    rows
    |> Enum.reject(fn [_stationuuid, raw_title, _plays] -> AdMarkers.ad?(raw_title) end)
    |> Enum.group_by(&hd/1, fn [_stationuuid, _raw_title, plays] -> plays end)
    |> Enum.flat_map(fn {stationuuid, track_plays} ->
      plays = Enum.sum(track_plays)

      if plays >= Metrics.min_plays(),
        do: [{stationuuid, length(track_plays) / plays, plays}],
        else: []
    end)
  end
end
