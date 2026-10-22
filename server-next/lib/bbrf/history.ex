defmodule BBRF.History do
  @moduledoc """
  Reads over the ingested track history (`track_observations`): the
  stations that played an artist or title, found through the
  `track_search` full-text index, and the plays themselves joined with
  the station that played them.
  """

  alias BBRF.Repo
  alias BBRF.Ingester.Stations

  # the station fields the frontend needs to show a play and tune in to it
  @track_station_columns [
    "stationuuid",
    "name",
    "url",
    "url_resolved",
    "countrycode",
    "bitrate",
    "tags"
  ]

  @track_orders %{
    "recent" => "o.observed_at DESC, o.id DESC",
    # stationuuid keeps same-named stations from interleaving
    "station" => "s.name COLLATE NOCASE, s.stationuuid, o.observed_at DESC, o.id DESC"
  }

  def track_orders, do: Map.keys(@track_orders)

  @doc """
  Plays joined with the station that played them, ordered by one of
  `track_orders/0`. `filters` narrows them to a `:countrycode` and to
  stations carrying a `:tag`, both ignoring case; nil or empty values
  do not filter. Plays on stations missing from the catalogue are left
  out.
  """
  @spec tracks(keyword(), String.t(), pos_integer(), non_neg_integer()) :: [map()]
  def tracks(filters, order, limit, offset) do
    {where, params} = track_filters(filters)

    %{rows: rows} =
      Repo.query!(
        """
        SELECT o.id, o.observed_at, o.raw_title, o.artist, o.title,
               #{Enum.map_join(@track_station_columns, ", ", &"s.#{&1}")}
          FROM track_observations o
          JOIN stations s ON s.stationuuid = o.stationuuid
         #{where}
         ORDER BY #{Map.fetch!(@track_orders, order)}
         LIMIT ? OFFSET ?
        """,
        params ++ [limit, offset]
      )

    Enum.map(rows, fn [id, observed_at, raw_title, artist, title | station] ->
      %{
        "id" => id,
        "observed_at" => observed_at,
        "raw_title" => raw_title,
        "artist" => artist,
        "title" => title,
        "station" => @track_station_columns |> Enum.zip(station) |> Map.new()
      }
    end)
  end

  defp track_filters(filters) do
    conditions =
      filters
      |> Enum.reject(fn {_, value} -> value in [nil, ""] end)
      |> Enum.map(&track_condition/1)

    case conditions do
      [] ->
        {"", []}

      _ ->
        {sql, params} = Enum.unzip(conditions)
        {"WHERE " <> Enum.join(sql, " AND "), params}
    end
  end

  defp track_condition({:countrycode, code}),
    do: {"s.countrycode = ?", String.upcase(code)}

  # tags is a comma-separated list, matched as whole tags
  defp track_condition({:tag, tag}),
    do:
      {"instr(',' || lower(replace(s.tags, ', ', ',')) || ',', ?) > 0",
       ",#{tag |> String.trim() |> String.downcase()},"}

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
