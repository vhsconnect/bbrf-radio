defmodule RadioAnalyzer.RadioBrowser do
  @moduledoc """
  HTTP access to the community Radio Browser API (the clojure original
  keeps a full endpoint catalog; only the two "recent stations"
  endpoints the poller needs are ported).

  The API asks for a descriptive User-Agent and for clients not to
  hammer it - the poller hits it twice every POLL_MINUTES with a
  bounded limit, and `retry: false` mirrors the original's
  no-in-request-retries policy (the poll loop retries on its next
  tick).
  """

  alias RadioAnalyzer.Env

  @user_agent "radio-analyzer-elixir/0.1.0"

  def user_agent, do: @user_agent

  def base_url, do: Env.str("RADIO_BROWSER_BASE_URL", "https://de1.api.radio-browser.info")

  @doc """
  GET a json endpoint that returns a list of stations.

      api_get("stations/lastchange", limit: 1000)
  """
  def api_get(endpoint, params \\ []) do
    case get_json(endpoint, params) do
      stations when is_list(stations) -> stations
      other -> raise "#{endpoint} returned unexpected json: #{inspect(other, limit: 5)}"
    end
  end

  @doc "GET a json endpoint, returning the decoded body whatever its shape."
  def get_json(endpoint, params \\ []) do
    url = "#{base_url()}/json/#{String.trim_leading(endpoint, "/")}"

    case Req.get(url,
           params: params,
           headers: [{"user-agent", @user_agent}, {"accept", "application/json"}],
           receive_timeout: 10_000,
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
