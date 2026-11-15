defmodule BBRF.Ingester.NetworkLog do
  @moduledoc """
  LOG_NETWORK_STATS=1 logs every request the ingester makes, one `:info`
  line each, with a bar of how long it took (one `#` per 200ms, full at
  6s):

    * every request a track wave makes for a station's title, from
      `[:bbrf, :track, :fetch]`, after the station's name and country
      code (`--` when unknown)
    * every MusicBrainz request, retries of a 503 included, from
      `[:bbrf, :musicbrainz, :request]`, with how long it waited for its
      slot first
    * every artist credit the resolver tries, from
      `[:bbrf, :artists, :resolve]`, with its attempt, what came of it
      and the artists MusicBrainz credits

  ```
  KCRW                     US [##                            ] icecast success        0.4 seconds | Artist - Song
  Oldies FM                GB [#####                         ] icy     success        1.0 seconds | Artist - Song
  Dead Air                 -- [##############################] -       fail           6.0 seconds | timeout
  musicbrainz recording       [##                            ] search  success        0.4 seconds, waited 1.1 | recording:"Halo" AND artist:(beyonce)
  musicbrainz artist          [###                           ] lookup  success        0.6 seconds, waited 0.8 | mbid-beyonce
  artist credit               [##############                ] try 1   resolved       2.9 seconds | Beyoncé - Halo => Beyoncé
  ```

  A station whose status page has no title shows twice: the icecast
  request, then the ICY read. A check killed at the cap shows the method
  it was known to use, `-` when none. A wave of thousands of stations
  logs thousands of lines.
  """

  require Logger
  alias BBRF.Env

  @handler_id "bbrf-network-log"
  @events [
    [:bbrf, :track, :fetch],
    [:bbrf, :musicbrainz, :request],
    [:bbrf, :artists, :resolve]
  ]
  @name_width 24
  @label_width @name_width + 3
  @status_width 14
  @method_width 7
  @bar_ms 200
  @bar_width 30
  @detail_max 80

  def enabled?, do: Env.flag("LOG_NETWORK_STATS", false)

  def attach do
    :telemetry.detach(@handler_id)
    :telemetry.attach_many(@handler_id, @events, &__MODULE__.handle_event/4, nil)
  end

  def handle_event([:bbrf, :track, :fetch], %{duration: duration}, meta, _config) do
    Logger.info(fn -> line(meta.station, meta.method, meta.result, ms(duration)) end)
  end

  def handle_event([:bbrf, :musicbrainz, :request], %{duration: duration, wait: wait}, meta, _) do
    Logger.info(fn ->
      request_line(meta.path, meta.params, meta.result, ms(duration), ms(wait))
    end)
  end

  def handle_event([:bbrf, :artists, :resolve], %{duration: duration}, meta, _config) do
    Logger.info(fn -> credit_line(meta.credit, meta.result, ms(duration)) end)
  end

  @spec line(map(), String.t() | nil, term(), non_neg_integer()) :: String.t()
  def line(station, method, result, ms) do
    {status, detail} = station_status(result)
    name = station |> label() |> String.slice(0, @name_width) |> String.pad_trailing(@name_width)

    row(name <> " " <> country(station), method || "-", status, ms, detail)
  end

  @spec request_line(String.t(), list(), term(), non_neg_integer(), non_neg_integer()) ::
          String.t()
  def request_line(path, params, result, ms, wait_ms) do
    [entity | rest] = String.split(path, "/", parts: 2)
    {method, detail} = request_detail(rest, params)

    row(
      "musicbrainz " <> entity,
      method,
      request_status(result),
      ms,
      request_failure(result) || detail,
      wait_ms
    )
  end

  @spec credit_line(map(), term(), non_neg_integer()) :: String.t()
  def credit_line(credit, result, ms) do
    played = credit.name <> " - " <> credit.title

    {status, detail} =
      case result do
        {:resolved, artists, _profiles} -> {"resolved", played <> " => " <> credited(artists)}
        :unresolved -> {"unresolved", played}
        :failed -> {"fail", played}
        :timeout -> {"timeout", played}
      end

    row("artist credit", "try #{credit.attempts + 1}", status, ms, detail)
  end

  defp row(label, method, status, ms, detail, wait_ms \\ nil) do
    [
      String.pad_trailing(label, @label_width),
      " [",
      bar(ms),
      "] ",
      String.pad_trailing(method, @method_width),
      " ",
      String.pad_trailing(status, @status_width),
      " ",
      decimal(ms),
      " seconds",
      if(wait_ms, do: ", waited " <> decimal(wait_ms), else: ""),
      if(detail, do: " | " <> String.slice(detail, 0, @detail_max), else: "")
    ]
    |> IO.iodata_to_binary()
  end

  defp ms(native), do: System.convert_time_unit(native, :native, :millisecond)

  defp decimal(ms), do: :erlang.float_to_binary(ms / 1000, decimals: 1)

  defp label(%{name: name} = station) when is_binary(name) do
    case String.trim(name) do
      "" -> station.stationuuid
      trimmed -> trimmed
    end
  end

  defp label(station), do: station.stationuuid

  defp country(%{countrycode: <<code::binary-size(2)>>}), do: String.upcase(code)
  defp country(_station), do: "--"

  defp bar(ms) do
    filled = min(round(ms / @bar_ms), @bar_width)
    String.duplicate("#", filled) <> String.duplicate(" ", @bar_width - filled)
  end

  defp station_status({:ok, %{raw_title: title}}) when is_binary(title), do: {"success", title}
  defp station_status({:ok, _observation}), do: {"no-title", nil}
  defp station_status(:no_source), do: {"no-source", nil}
  defp station_status(:no_status_page), do: {"no-status-page", nil}
  defp station_status(:no_status_url), do: {"no-status-url", nil}
  defp station_status({:unreachable, detail}), do: {"fail", detail}
  defp station_status({:error, detail}), do: {"fail", detail}

  defp request_detail(rest, params) do
    case List.keyfind(params, :query, 0) do
      {:query, query} ->
        {"search", query}

      nil ->
        by = for {key, value} <- params, key not in [:fmt, :inc], do: "#{key}=#{value}"

        method =
          if rest != [] or List.keymember?(params, :resource, 0), do: "lookup", else: "browse"

        {method, Enum.join(rest ++ by, " ")}
    end
  end

  defp request_status({:ok, 200}), do: "success"
  defp request_status({:ok, 404}), do: "not-found"
  defp request_status({:ok, 503}), do: "busy"
  defp request_status({:ok, status}), do: "http #{status}"
  defp request_status({:error, _message}), do: "fail"

  defp request_failure({:error, message}), do: message
  defp request_failure(_result), do: nil

  defp credited(artists) do
    Enum.map_join(artists, &((&1.credited_as || &1.artist_mbid) <> (&1.join_phrase || "")))
  end
end
