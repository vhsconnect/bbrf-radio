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

  @track_sorts ~w(played country station)
  @track_directions ~w(asc desc)

  def track_sorts, do: @track_sorts
  def track_directions, do: @track_directions

  @doc """
  Plays joined with the station that played them, ordered by one of
  `track_sorts/0` in one of `track_directions/0`. `filters` narrows them
  to a `:countrycode`, to stations carrying a `:tag`, to stations whose
  name contains `:station`, and to plays whose artist/title match `:q`
  the way `search/3` does; nil or empty values do not filter. Plays on
  stations missing from the catalogue are left out.
  """
  @spec tracks(keyword(), String.t(), String.t(), pos_integer(), non_neg_integer()) :: [map()]
  def tracks(filters, sort, dir, limit, offset) do
    {where, params} = track_filters(filters)

    %{rows: rows} =
      Repo.query!(
        """
        SELECT o.id, o.observed_at, o.raw_title, o.artist, o.title,
               #{Enum.map_join(@track_station_columns, ", ", &"s.#{&1}")}
          FROM track_observations o
          JOIN stations s ON s.stationuuid = o.stationuuid
         #{where}
         ORDER BY #{track_order(sort, dir)}
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

  defp track_order("played", dir) when dir in @track_directions,
    do: "o.observed_at #{dir}, o.id #{dir}"

  # some stations store their countrycode lowercase or empty; the empty
  # ones go last either way
  defp track_order("country", dir) when dir in @track_directions,
    do:
      "coalesce(s.countrycode, '') = '', upper(s.countrycode) #{dir}, o.observed_at DESC, o.id DESC"

  # stationuuid keeps same-named stations from interleaving
  defp track_order("station", dir) when dir in @track_directions,
    do: "s.name COLLATE NOCASE #{dir}, s.stationuuid, o.observed_at DESC, o.id DESC"

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
        {"WHERE " <> Enum.join(sql, " AND "), Enum.concat(params)}
    end
  end

  defp track_condition({:countrycode, code}),
    do: {"upper(s.countrycode) = upper(?)", [String.trim(code)]}

  # tags is a comma-separated list, matched as whole tags. sqlite's
  # lower() only folds ASCII, so both sides go through it
  defp track_condition({:tag, tag}),
    do:
      {"instr(',' || lower(replace(s.tags, ', ', ',')) || ',', lower(?)) > 0",
       [",#{String.trim(tag)},"]}

  defp track_condition({:station, name}),
    do: {"instr(lower(s.name), lower(?)) > 0", [String.trim(name)]}

  defp track_condition({:q, query}) do
    case match_expression(query) do
      nil -> {"0", []}
      match -> {"o.id IN (SELECT rowid FROM track_search WHERE track_search MATCH ?)", [match]}
    end
  end

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
