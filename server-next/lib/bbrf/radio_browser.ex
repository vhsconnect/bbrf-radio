defmodule BBRF.RadioBrowser do
  @moduledoc """
  HTTP access to the community Radio Browser API, for the endpoints the
  ingester and the frontend need.

  The API asks for a descriptive User-Agent and for clients not to
  hammer it - the polls hit it every CHANGES_POLL_MINUTES and
  CLICKS_POLL_MINUTES with a bounded limit, and requests are not retried
  (a poll retries on its next tick).

  It also asks clients to pick a mirror from `all.api.radio-browser.info`
  rather than pin one: unless RADIO_BROWSER_BASE_URL is set, a mirror is
  picked on first use and kept until a request to it fails.
  """

  @user_agent "vhsconnect/bbrf-radio server-next/0.1.0"
  @mirrors_host ~c"all.api.radio-browser.info"
  @fallback_mirror "de1.api.radio-browser.info"
  @mirror_key {__MODULE__, :mirror}
  @dns_timeout_ms 5_000

  def user_agent, do: @user_agent

  def base_url do
    case System.get_env("RADIO_BROWSER_BASE_URL") do
      nil -> "https://" <> mirror()
      url -> url
    end
  end

  defp mirror do
    case :persistent_term.get(@mirror_key, nil) do
      nil ->
        picked = discover_mirror()
        :persistent_term.put(@mirror_key, picked)
        picked

      picked ->
        picked
    end
  end

  # forward lookup for the mirror ips, reverse lookup for their names
  # (tls needs the hostname)
  defp discover_mirror do
    with {:ok, ips} <- :inet.getaddrs(@mirrors_host, :inet, @dns_timeout_ms),
         [_ | _] = names <- Enum.flat_map(ips, &mirror_name/1) do
      Enum.random(names)
    else
      _ -> @fallback_mirror
    end
  end

  defp mirror_name(ip) do
    case :inet.gethostbyaddr(ip, @dns_timeout_ms) do
      {:ok, {:hostent, name, _aliases, _type, _length, _addrs}} -> [to_string(name)]
      _ -> []
    end
  end

  @doc """
  GET a json endpoint that returns a list of stations.

      api_get("stations/lastchange", limit: 1000)

  `receive_timeout:` (10s) overrides the read timeout for large pages.
  """
  def api_get(endpoint, params \\ [], opts \\ []) do
    case get_json(endpoint, params, opts) do
      stations when is_list(stations) -> stations
      other -> raise "#{endpoint} returned unexpected json: #{inspect(other, limit: 5)}"
    end
  end

  @doc "GET a json endpoint, returning the decoded body whatever its shape."
  def get_json(endpoint, params \\ [], opts \\ []) do
    url = "#{base_url()}/json/#{String.trim_leading(endpoint, "/")}"

    case Req.get(url,
           params: params,
           headers: [{"user-agent", @user_agent}, {"accept", "application/json"}],
           receive_timeout: Keyword.get(opts, :receive_timeout, 10_000),
           retry: false
         ) do
      {:ok, %Req.Response{status: 200, body: body}} ->
        case decode(body) do
          {:ok, decoded} -> decoded
          :error -> raise "#{url} returned invalid json"
        end

      {:ok, %Req.Response{status: status}} ->
        raise "#{url} returned HTTP #{status}"

      {:error, exception} ->
        :persistent_term.erase(@mirror_key)
        raise "#{url} request failed: #{Exception.message(exception)}"
    end
  end

  # servers are sloppy with content-type, so decode manually when the
  # body is still a binary
  defp decode(body) when is_list(body) or is_map(body), do: {:ok, body}

  defp decode(body) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, decoded} -> {:ok, decoded}
      {:error, _} -> :error
    end
  end

  defp decode(_other), do: :error
end
