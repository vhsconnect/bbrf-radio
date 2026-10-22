defmodule BBRF.History do
  @moduledoc """
  Reads over the ingested track history (`track_observations`): the
  stations that played an artist or title, found through the
  `track_search` full-text index.
  """

  alias BBRF.Repo
  alias BBRF.Ingester.Stations

  @doc """
  Stations that played a track whose artist/title match every word of
  `query`, each word as a prefix, ignoring case and diacritics. Each
  station appears once, most recent matching play first, in the
  radio-browser station shape the other station endpoints return. A
  query without words matches nothing.
  """
  @spec search(String.t(), pos_integer(), non_neg_integer()) :: [map()]
  def search(query, limit, offset) do
    case match_expression(query) do
      nil ->
        []

      match ->
        %{rows: rows} =
          Repo.query!(
            """
            SELECT #{Enum.map_join(Stations.api_columns(), ", ", &"s.#{&1}")}
              FROM (SELECT o.stationuuid, MAX(track_search.rowid) AS last_play
                      FROM track_search
                      JOIN track_observations o ON o.id = track_search.rowid
                     WHERE track_search MATCH ?
                     GROUP BY o.stationuuid) plays
              JOIN stations s ON s.stationuuid = plays.stationuuid
             ORDER BY plays.last_play DESC
             LIMIT ? OFFSET ?
            """,
            [match, limit, offset]
          )

        Enum.map(rows, fn row ->
          Stations.api_columns()
          |> Enum.zip(row)
          |> Map.new()
          # stored as 0/1, radio-browser serves it as a boolean
          |> Map.update!("has_extended_info", &(&1 == 1))
        end)
    end
  end

  @doc """
  The FTS5 MATCH expression for `query`: its words quoted as prefix
  terms. Only letters and digits survive, so user input cannot inject
  FTS5 syntax.
  """
  @spec match_expression(String.t()) :: String.t() | nil
  def match_expression(query) do
    case Regex.scan(~r/[\p{L}\p{N}]+/u, query) do
      [] -> nil
      words -> Enum.map_join(words, " ", fn [word] -> ~s("#{word}"*) end)
    end
  end
end
