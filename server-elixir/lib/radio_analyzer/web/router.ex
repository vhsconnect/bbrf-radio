defmodule RadioAnalyzer.Web.Router do
  @moduledoc """
  HTTP for the bbrf frontend: the built bundle (from STATIC_DIR) and the
  JSON API its server mode calls. Paths and response shapes match the
  bbrf-radio node server, so the frontend does not change.

  Radio-browser calls go through `RadioAnalyzer.RadioBrowser`, the same
  client the collectors use. Favorites live in SQLite (`RadioAnalyzer.Favorites`).
  """

  use Plug.Router

  require Logger
  alias RadioAnalyzer.{Env, Favorites, RadioBrowser}

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
    conn = fetch_query_params(conn)
    offset = page_offset(conn.query_params)
    limit = Env.int("ITEMS_PER_PAGE", 5000)

    respond(conn, fn ->
      RadioBrowser.get_json(endpoint, offset: offset * limit, limit: limit)
    end)
  end

  defp page_offset(params) do
    case Integer.parse(Map.get(params, "offset", "0")) do
      {n, _} -> n
      :error -> 0
    end
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
