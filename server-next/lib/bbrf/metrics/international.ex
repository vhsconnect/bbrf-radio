defmodule BBRF.Metrics.International do
  @moduledoc """
  How many countries a station's music comes from, as the effective
  number of countries: e^entropy of the plays per artist country, so 4.0
  is as diverse as four countries played equally, and 1.0 one country.

  A play's country is that of the first artist of its credit, known once
  `BBRF.Ingester.Artists` resolved the credit and when MusicBrainz has a
  country for the artist. Plays are counted like `BBRF.Metrics.Balance`
  counts them. `sample` is the coverage: the share of plays, in %, with
  a country. Below INTERNATIONAL_MIN_COVERAGE (default 50) the value is
  NULL: the resolver goes most played first, so a station's known plays
  would lean towards its hits.
  """

  @behaviour BBRF.Metrics.Metric

  alias BBRF.{AdMarkers, Env, Metrics, Repo}

  def min_coverage, do: Env.int("INTERNATIONAL_MIN_COVERAGE", 50)

  @impl true
  def name, do: "international"

  @impl true
  def compute(stationuuids, since) do
    %{rows: rows} =
      Repo.query!(
        """
        SELECT o.stationuuid, MIN(o.raw_title), a.country, COUNT(*)
          FROM track_observations o
          LEFT JOIN artist_credit_artists ca
                 ON ca.artist_credit_id = o.artist_credit_id AND ca.position = 0
          LEFT JOIN artists a ON a.mbid = ca.artist_mbid
         WHERE o.stationuuid IN (#{Metrics.placeholders(stationuuids)})
           AND o.observed_at >= ?
           AND o.artist_credit_id IS NOT NULL
           AND o.title IS NOT NULL
         GROUP BY o.stationuuid, o.artist_credit_id, lower(trim(o.title))
        """,
        stationuuids ++ [since]
      )

    rows
    |> Enum.reject(fn [_stationuuid, raw_title, _country, _plays] -> AdMarkers.ad?(raw_title) end)
    |> Enum.group_by(&hd/1, fn [_stationuuid, _raw_title, country, plays] -> {country, plays} end)
    |> Enum.flat_map(fn {stationuuid, tracks} -> score(stationuuid, tracks) end)
  end

  defp score(stationuuid, tracks) do
    plays = tracks |> Enum.map(&elem(&1, 1)) |> Enum.sum()

    per_country =
      for {country, n} <- tracks, country != nil, reduce: %{} do
        acc -> Map.update(acc, country, n, &(&1 + n))
      end

    known = per_country |> Map.values() |> Enum.sum()
    coverage = div(known * 100, max(plays, 1))

    cond do
      plays < Metrics.min_plays() -> []
      coverage < min_coverage() -> [{stationuuid, nil, coverage}]
      true -> [{stationuuid, effective_countries(Map.values(per_country), known), coverage}]
    end
  end

  defp effective_countries(counts, total) do
    counts
    |> Enum.map(fn n -> n / total * :math.log(n / total) end)
    |> Enum.sum()
    |> Kernel.-()
    |> :math.exp()
  end
end
