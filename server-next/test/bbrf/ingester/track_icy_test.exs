defmodule BBRF.Ingester.TrackIcyTest do
  use ExUnit.Case, async: true

  import Plug.Conn
  alias BBRF.Metatable
  alias BBRF.Ingester.Track

  defmodule Stations do
    @moduledoc false
    import Plug.Conn

    def init(opts), do: opts

    def call(%Plug.Conn{request_path: "/status-json.xsl"} = conn, _opts) do
      case conn.private[:status_page] do
        nil ->
          send_resp(conn, 404, "")

        title ->
          conn
          |> put_resp_content_type("application/json")
          |> send_resp(200, Jason.encode!(%{icestats: %{source: %{title: title}}}))
      end
    end

    def call(%Plug.Conn{private: %{trickle: {headers, chunks}}} = conn, _opts) do
      conn =
        headers
        |> Enum.reduce(conn, fn {name, value}, conn -> put_resp_header(conn, name, value) end)
        |> send_chunked(200)

      Enum.reduce_while(chunks, conn, fn chunk, conn ->
        Process.sleep(200)

        case chunk(conn, chunk) do
          {:ok, conn} -> {:cont, conn}
          {:error, _closed} -> {:halt, conn}
        end
      end)
    end

    def call(conn, _opts) do
      {status, headers, body} = conn.private[:stream]

      headers
      |> Enum.reduce(conn, fn {name, value}, conn -> put_resp_header(conn, name, value) end)
      |> send_resp(status, body)
    end
  end

  setup do
    start_supervised!(Track.finch_child_spec())
    :ok
  end

  defp serve(private) do
    plug = fn conn, _opts ->
      conn |> merge_private(private) |> Stations.call([])
    end

    server = start_supervised!({Bandit, plug: plug, ip: :loopback, port: 0, startup_log: false})
    {:ok, {_ip, port}} = ThousandIsland.listener_info(server)
    Metatable.candidate(%{stream_url: "http://127.0.0.1:#{port}/live"})
  end

  defp icy_stream(metadata, opts \\ []) do
    metaint = Keyword.get(opts, :metaint, 32)
    padded = metadata <> :binary.copy(<<0>>, 16 - rem(byte_size(metadata), 16))
    audio = :binary.copy("a", metaint)
    headers = [{"icy-metaint", "#{metaint}"} | Keyword.get(opts, :headers, [])]

    {200, headers, audio <> <<div(byte_size(padded), 16)>> <> padded <> audio}
  end

  test "reads the title from the metadata block after icy-metaint bytes" do
    station =
      serve(%{
        stream:
          icy_stream("StreamTitle='Artist - Song';",
            headers: [{"icy-br", "128"}, {"icy-genre", "Jazz"}]
          )
      })

    assert {:ok, observation} = Track.fetch_icy(station)
    assert %{raw_title: "Artist - Song", artist: "Artist", title: "Song"} = observation
    assert Jason.decode!(observation.metadata) == %{"bitrate" => 128, "genre" => "Jazz"}
  end

  test "keeps apostrophes inside the title" do
    station = serve(%{stream: icy_stream("StreamTitle='Guns N' Roses - Don't Cry';")})

    assert {:ok, %{raw_title: "Guns N' Roses - Don't Cry"}} = Track.fetch_icy(station)
  end

  test "converts latin-1 titles to utf-8" do
    station = serve(%{stream: icy_stream("StreamTitle='Beyonc" <> <<0xE9>> <> " - Halo';")})

    assert {:ok, %{raw_title: "Beyoncé - Halo"}} = Track.fetch_icy(station)
  end

  test "an empty StreamTitle is an observation without a title" do
    station = serve(%{stream: icy_stream("StreamTitle='';")})

    assert {:ok, %{raw_title: nil}} = Track.fetch_icy(station)
  end

  test "a stream without icy-metaint has no source" do
    station = serve(%{stream: {200, [], "just audio"}})

    assert Track.fetch_icy(station) == :no_source
  end

  test "a stream too slow to reach its metadata within the budget has no source" do
    {200, headers, body} = icy_stream("StreamTitle='Too Late';", metaint: 64)
    chunks = for <<chunk::binary-size(16) <- body>>, do: chunk

    station = serve(%{trickle: {headers, chunks}})
    {elapsed_us, result} = :timer.tc(fn -> Track.fetch_icy(station, 500) end)

    assert result == :no_source
    assert elapsed_us < 1_000_000
  end

  test "falls back to ICY when there is no status page" do
    station = serve(%{stream: icy_stream("StreamTitle='From ICY';")})

    assert {"icy", {:ok, %{raw_title: "From ICY"}}} = Track.fetch_observation(station)
  end

  test "keeps the status page title when there is one" do
    station =
      serve(%{status_page: "From Status", stream: icy_stream("StreamTitle='From ICY';")})

    assert {"icecast", {:ok, %{raw_title: "From Status"}}} = Track.fetch_observation(station)
  end

  test "goes straight to ICY for stations known to only serve it" do
    station =
      serve(%{status_page: "From Status", stream: icy_stream("StreamTitle='From ICY';")})

    assert {"icy", {:ok, %{raw_title: "From ICY"}}} =
             Track.fetch_observation(%{station | meta_source: "icy"})
  end
end
