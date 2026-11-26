defmodule BBRF.Metrics.Catalogue do
  @moduledoc """
  A sort read from the `stations` catalogue on every request rather than
  stored by `BBRF.Metrics.run/2`, so it covers every station and follows
  the catalogue sync. Each of its names sorts in its own direction, the
  unknown (NULL) last either way.
  """

  alias BBRF.Metrics.{Clicks, Quality}

  @doc "Its names, each with the direction it sorts in, `\"ASC\"` or `\"DESC\"`."
  @callback sorts() :: [{String.t(), String.t()}]

  @doc "SQL for the value of the `stations` row aliased `s`, NULL when unknown."
  @callback sql() :: String.t()

  @doc "SQL for the sample of the `stations` row aliased `s`."
  @callback sample_sql() :: String.t()

  def all, do: [Quality, Clicks]

  def names, do: for(module <- all(), {name, _direction} <- module.sorts(), do: name)

  @doc "The value SQL and direction `name` sorts by, nil when it is no catalogue sort."
  def sort(name) do
    Enum.find_value(all(), fn module ->
      case List.keyfind(module.sorts(), name, 0) do
        {_name, direction} -> {module.sql(), direction}
        nil -> nil
      end
    end)
  end

  @doc "`stationuuids` in the catalogue, each with every catalogue sort by name."
  def for_stations(stationuuids) do
    columns = Enum.map_join(all(), ", ", &"(#{&1.sql()}), (#{&1.sample_sql()})")

    %{rows: rows} =
      BBRF.Repo.query!(
        """
        SELECT s.stationuuid, #{columns}
          FROM stations s
         WHERE s.stationuuid IN (SELECT value FROM json_each(?))
        """,
        [Jason.encode!(stationuuids)]
      )

    Map.new(rows, fn [stationuuid | values] ->
      metrics =
        for {module, [value, sample]} <- Enum.zip(all(), Enum.chunk_every(values, 2)),
            {name, _direction} <- module.sorts(),
            into: %{},
            do: {name, %{"value" => value, "sample" => sample}}

      {stationuuid, metrics}
    end)
  end
end
