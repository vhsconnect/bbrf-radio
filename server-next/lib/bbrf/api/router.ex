defmodule BBRF.API.Router do
  @moduledoc """
  HTTP for the bbrf frontend: the built bundle (from STATIC_DIR) and the
  JSON API its server mode calls. Paths and response shapes match the
  bbrf-radio node server, so the frontend does not change.

  Radio-browser calls go through `BBRF.RadioBrowser`, the same
  client the ingester uses. Favorites live in SQLite (`BBRF.Favorites`).
  `/bytrack` and `/tracks` have no node counterpart: they read the
  ingested track history (`BBRF.History`) and page like the other
  `/by*` routes.
  """

  use Plug.Router

  require Logger
  alias BBRF.{Env, Favorites, History, RadioBrowser}

  @static_files ["index.html", "index.js", "styles.css", "favicon-16x16.png"]

  plug(:match)
  plug(:dispatch)

  get "/" do
    serve_static(conn, "index.html")
  end

  get "/favorites" do
    json(conn, Favorites.list())
  end

  get "/fader" do
    json(conn, %{value: Env.int("FADER_VALUE", 25)})
  end

  get "/radio-server" do
    json(conn, %{server: URI.parse(RadioBrowser.base_url()).host})
  end

  get "/bytag/:tag" do
    search(conn, "stations/bytagexact/#{segment(tag)}")
  end

  get "/bycountrycode/:cc" do
    search(conn, "stations/bycountrycodeexact/#{segment(cc)}")
  end

  get "/byname/:name" do
    search(conn, "stations/byname/#{segment(name)}")
  end

  get "/bytrack/:query" do
    paged(conn, fn offset, limit -> History.search(query, limit, offset) end)
  end

  get "/tracks" do
    conn = fetch_query_params(conn)
    params = conn.query_params
    sort = Map.get(params, "sort", "played")
    dir = Map.get(params, "dir", "desc")

    cond do
      sort not in History.track_sorts() ->
        bad_param(conn, "sort", sort, History.track_sorts())

      dir not in History.track_directions() ->
        bad_param(conn, "dir", dir, History.track_directions())

      true ->
        filters = for key <- ~w(countrycode tag station q)a, do: {key, params[to_string(key)]}

        paged(conn, Env.int("TRACKS_PER_PAGE", 200), fn offset, limit ->
          History.tracks(filters, sort, dir, limit, offset)
        end)
    end
  end

  get "/clicked/:uuid" do
    respond(conn, fn -> RadioBrowser.get_json("url/#{segment(uuid)}") end)
  end

  post "/write/addStation/:uuid" do
    {:ok, raw, conn} = read_body(conn)

    respond(conn, fn ->
      raw
      |> Jason.decode!()
      |> Map.put("stationuuid", uuid)
      |> Favorites.add()
    end)
  end

  post "/write/removeStation/:uuid" do
    respond(conn, fn -> Favorites.remove(uuid) end)
  end

  get "/:file" do
    serve_static(conn, file)
  end

  match _ do
    send_resp(conn, 404, "not found")
  end

  defp search(conn, endpoint) do
    paged(conn, fn offset, limit ->
      RadioBrowser.get_json(endpoint, offset: offset, limit: limit)
    end)
  end

  defp paged(conn, fetch), do: paged(conn, Env.int("ITEMS_PER_PAGE", 5000), fetch)

  defp paged(conn, limit, fetch) do
    conn = fetch_query_params(conn)
    offset = page_offset(conn.query_params) * limit

    respond(conn, fn -> fetch.(offset, limit) end)
  end

  defp page_offset(params) do
    case Integer.parse(Map.get(params, "offset", "0")) do
      {n, _} when n > 0 -> n
      _ -> 0
    end
  end

  defp bad_param(conn, name, value, allowed) do
    json(conn, 400, %{
      error: "unknown #{name} #{value}",
      message: "#{name} must be one of #{Enum.join(allowed, ", ")}"
    })
  end

  defp segment(value), do: URI.encode(value, &URI.char_unreserved?/1)

  defp respond(conn, fun) do
    json(conn, fun.())
  rescue
    exception ->
      Logger.error("request #{conn.request_path} failed: #{Exception.message(exception)}")
      json(conn, 500, %{error: Exception.message(exception), message: "something went wrong"})
  end

  defp json(conn, body), do: json(conn, 200, body)

  defp json(conn, status, body) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(body))
  end

  defp serve_static(conn, file) do
    path = Path.join(Env.str("STATIC_DIR", "static"), file)

    if file in @static_files and File.regular?(path) do
      conn
      |> put_resp_content_type(MIME.from_path(file))
      |> send_file(200, path)
    else
      send_resp(conn, 404, "not found")
    end
  end
end
