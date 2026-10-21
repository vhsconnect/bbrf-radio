defmodule BBRF.Favorites do
  @moduledoc """
  Favorite stations, stored in the `favorites` table. Each favorite keeps
  the fields the frontend shows, and the table's `id` gives the order the
  user added them in.
  """

  alias BBRF.Repo

  @fields ~w(stationuuid url name countrycode bitrate)a

  def list do
    %{rows: rows} =
      Repo.query!(
        "SELECT stationuuid, url, name, countrycode, bitrate FROM favorites ORDER BY id"
      )

    Enum.map(rows, fn [stationuuid, url, name, countrycode, bitrate] ->
      %{
        stationuuid: stationuuid,
        url: url,
        name: name,
        countrycode: countrycode,
        bitrate: bitrate
      }
    end)
  end

  def count do
    %{rows: [[n]]} = Repo.query!("SELECT COUNT(*) FROM favorites")
    n
  end

  @doc "Add a favorite. Adding one that is already a favorite keeps its place."
  def add(attrs) do
    insert(attrs)
    list()
  end

  def remove(stationuuid) do
    Repo.query!("DELETE FROM favorites WHERE stationuuid = ?", [stationuuid])
    list()
  end

  @doc """
  Copy favorites from the bbrf-radio node server's `storage.json` into the
  table. Rows already present are left alone. Returns the number of
  favorites found in the file.
  """
  def import_json(path) do
    %{"favorites" => favorites} = path |> File.read!() |> Jason.decode!()

    Repo.transaction(fn ->
      Enum.each(favorites, &insert/1)
    end)

    length(favorites)
  end

  defp insert(attrs) do
    fav = Map.new(@fields, fn field -> {field, Map.get(attrs, to_string(field))} end)

    Repo.query!(
      """
      INSERT INTO favorites (stationuuid, url, name, countrycode, bitrate, added_at)
      VALUES (?, ?, ?, ?, ?, ?)
      ON CONFLICT(stationuuid) DO NOTHING
      """,
      [fav.stationuuid, fav.url, fav.name, fav.countrycode, fav.bitrate, now_iso()]
    )
  end

  defp now_iso, do: DateTime.to_iso8601(DateTime.utc_now())
end
