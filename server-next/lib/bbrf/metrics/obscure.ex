defmodule BBRF.Metrics.Obscure do
  @moduledoc """
  How much of a station's music comes from outside the most played
  artists: distinct tracks by artists outside the top N over plays, so
  1.0 is all plays outside the top N and never a repeat. Counting
  distinct tracks rather than plays marks down what a station repeats,
  which is where junk metadata (show names, station IDs) ends up: it is
  never in the top N but sends the same few strings over and over.

  The top N are the artist credits played on the most stations in the
  window, then the most plays. Tracks and plays are counted like
  `BBRF.Metrics.Balance` counts them, ad breaks left out. `sample` is
  the plays. Each top is its own metric (`use BBRF.Metrics.Obscure, top: n`).
  """

  alias BBRF.{AdMarkers, Metrics, Repo}

  @deepest 2500

  defmacro __using__(top: top) do
    if top > @deepest, do: raise(ArgumentError, "top #{top} is deeper than #{@deepest}")

    quote do
      @behaviour BBRF.Metrics.Metric

      @impl true
      def name, do: "obscure_#{unquote(top)}"

      @impl true
      def compute(stationuuids, since),
        do: BBRF.Metrics.Obscure.compute(stationuuids, since, unquote(top))
    end
  end

  @spec compute([String.t()], String.t(), pos_integer()) :: [BBRF.Metrics.Metric.row()]
  def compute(stationuuids, since, top) do
    top_credits = since |> ranked() |> Enum.take(top)

    %{rows: rows} =
      Repo.query!(
        """
        SELECT stationuuid,
               MIN(raw_title),
               artist_credit_id IN (SELECT value FROM json_each(?)),
               COUNT(*)
          FROM track_observations
         WHERE stationuuid IN (#{Metrics.placeholders(stationuuids)})
           AND observed_at >= ?
           AND artist_credit_id IS NOT NULL
           AND title IS NOT NULL
         GROUP BY stationuuid, artist_credit_id, lower(trim(title))
        """,
        [Jason.encode!(top_credits) | stationuuids] ++ [since]
      )

    rows
    |> Enum.reject(fn [_stationuuid, raw_title, _top, _plays] -> AdMarkers.ad?(raw_title) end)
    |> Enum.group_by(&hd/1, fn [_stationuuid, _raw_title, top, plays] -> {top == 1, plays} end)
    |> Enum.flat_map(fn {stationuuid, tracks} ->
      plays = tracks |> Enum.map(&elem(&1, 1)) |> Enum.sum()
      obscure = Enum.count(tracks, fn {top, _plays} -> not top end)

      if plays >= Metrics.min_plays(),
        do: [{stationuuid, obscure / plays, plays}],
        else: []
    end)
  end

  # every obscure metric of a run shares one ranking, kept in the process
  # under the run's `since`: ranking scans the whole window
  defp ranked(since) do
    key = {__MODULE__, since}

    case Process.get(key) do
      nil ->
        credits = rank(since)
        Process.put(key, credits)
        credits

      credits ->
        credits
    end
  end

  defp rank(since) do
    %{rows: rows} =
      Repo.query!(
        """
        SELECT artist_credit_id
          FROM track_observations
         WHERE observed_at >= ?
           AND artist_credit_id IS NOT NULL
           AND title IS NOT NULL
         GROUP BY artist_credit_id
         ORDER BY COUNT(DISTINCT stationuuid) DESC, COUNT(*) DESC, artist_credit_id
         LIMIT ?
        """,
        [since, @deepest]
      )

    List.flatten(rows)
  end
end

defmodule BBRF.Metrics.Obscure500 do
  @moduledoc "`BBRF.Metrics.Obscure` outside the top 500."
  use BBRF.Metrics.Obscure, top: 500
end

defmodule BBRF.Metrics.Obscure1500 do
  @moduledoc "`BBRF.Metrics.Obscure` outside the top 1500."
  use BBRF.Metrics.Obscure, top: 1500
end

defmodule BBRF.Metrics.Obscure2500 do
  @moduledoc "`BBRF.Metrics.Obscure` outside the top 2500."
  use BBRF.Metrics.Obscure, top: 2500
end
