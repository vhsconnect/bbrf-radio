defmodule BBRF.MusicBrainz do
  @moduledoc """
  HTTP access to the MusicBrainz web service (ws/2), read-only: lookups
  by MBID, browsing the entities linked to one, Lucene searches, and the
  lookups keyed by something else (disc id, ISRC, ISWC, url resource,
  the genre list). Writes (tags, ratings, collections) need a user login
  and are left out.

  MusicBrainz asks for a User-Agent with contact info and serves one
  request per second per IP, answering 503 past that. Every request
  here waits for its own slot, MUSICBRAINZ_INTERVAL_MS (1000) after the
  previous one, across all processes; requests are not retried.
  MUSICBRAINZ_BASE_URL points at a mirror instead.

  Entities are atoms, `:release_group` for `release-group`. Options
  become query params: `inc:` and the release `type:`/`status:`
  filters take lists, anything else (`limit:`, `offset:`, `dismax:`,
  `toc:`, ...) passes through as is.
  """

  alias BBRF.Env

  @user_agent "bbrf-radio/#{Mix.Project.config()[:version]} ( https://github.com/vhsconnect/bbrf-radio )"
  @default_base_url "https://musicbrainz.org/ws/2"
  @slot_key {__MODULE__, :slot}
  # an initial last-request time old enough that the first request goes
  # out right away
  @long_ago -(2 ** 62)

  @entities ~w(area artist collection event genre instrument label place recording release release_group series url work)a

  @searchable ~w(annotation area artist cdstub event instrument label place recording release release_group series tag url work)a

  # result entity => the entities it can be browsed by
  @browsable %{
    area: ~w(collection)a,
    artist: ~w(area collection recording release release_group work)a,
    collection: ~w(area artist editor event label place recording release release_group work)a,
    event: ~w(area artist collection place)a,
    instrument: ~w(collection)a,
    label: ~w(area collection release)a,
    place: ~w(area collection)a,
    recording: ~w(artist collection release work)a,
    release: ~w(area artist collection label recording release_group track track_artist)a,
    release_group: ~w(artist collection release)a,
    series: ~w(collection)a,
    work: ~w(artist collection)a
  }

  def user_agent, do: @user_agent

  def base_url, do: Env.str("MUSICBRAINZ_BASE_URL", @default_base_url)

  def interval_ms, do: Env.int("MUSICBRAINZ_INTERVAL_MS", 1_000)

  @doc """
  One entity by MBID, nil when MusicBrainz has none.

      lookup(:artist, "d1b3fbb6-…", inc: ~w(aliases tags genres url-rels))
  """
  def lookup(entity, mbid, opts \\ []) when entity in @entities do
    get_json("#{segment(entity)}/#{encode(mbid)}", opts)
  end

  @doc """
  The `entity` records linked to the `by` entity `id` (an MBID, the
  editor name for `:editor`), a page of `limit:` (25, at most 100) from
  `offset:`.

      browse(:release_group, :artist, mbid, type: ~w(album ep), limit: 100)
  """
  def browse(entity, by, id, opts \\ []) do
    unless by in Map.get(@browsable, entity, []) do
      raise ArgumentError, "#{inspect(entity)} cannot be browsed by #{inspect(by)}"
    end

    get_json(segment(entity), [{param(by), id} | opts])
  end

  @doc """
  A Lucene search over `entity`, best match first, each carrying a
  `"score"` out of 100. Build phrases from untrusted text with
  `phrase/1`.

      search(:artist, "artist:" <> phrase("Dur-Dur Band"), limit: 5)
  """
  def search(entity, query, opts \\ []) when entity in @searchable do
    get_json(segment(entity), [{:query, query} | opts])
  end

  @doc "The releases with a disc id; `toc:` falls back to a fuzzy toc match."
  def discid(id, opts \\ []), do: get_json("discid/#{encode(id)}", opts)

  @doc "The recordings with an ISRC."
  def isrc(code, opts \\ []), do: get_json("isrc/#{encode(code)}", opts)

  @doc "The works with an ISWC."
  def iswc(code, opts \\ []), do: get_json("iswc/#{encode(code)}", opts)

  @doc "The url entity for a resource such as an artist's homepage, nil when unknown."
  def url(resource, opts \\ []), do: get_json("url", [{:resource, resource} | opts])

  @doc "A page of every genre MusicBrainz knows."
  def genres(opts \\ []), do: get_json("genre/all", opts)

  @doc "`text` as a Lucene phrase: in double quotes, its quotes and backslashes escaped."
  def phrase(text), do: ~s("#{String.replace(text, ["\\", "\""], &("\\" <> &1))}")

  @doc "GET a ws/2 path as json; nil on 404, raises on any other failure."
  def get_json(path, opts \\ []) do
    url = "#{base_url()}/#{path}"
    wait_for_slot()

    case Req.get(url,
           params: [{:fmt, "json"} | Enum.map(opts, &query_param/1)],
           headers: [{"user-agent", @user_agent}, {"accept", "application/json"}],
           receive_timeout: 10_000,
           retry: false
         ) do
      {:ok, %Req.Response{status: 200, body: body}} when is_map(body) ->
        body

      {:ok, %Req.Response{status: 200, body: body}} when is_binary(body) ->
        case Jason.decode(body) do
          {:ok, decoded} -> decoded
          {:error, _} -> raise "#{url} returned invalid json"
        end

      {:ok, %Req.Response{status: 404}} ->
        nil

      {:ok, %Req.Response{status: status}} ->
        raise "#{url} returned HTTP #{status}"

      {:error, exception} ->
        raise "#{url} request failed: #{Exception.message(exception)}"
    end
  end

  # inc values are space separated, which the query string encodes as
  # the documented "+"
  defp query_param({:inc, values}), do: {:inc, Enum.join(List.wrap(values), " ")}

  defp query_param({key, values}) when key in [:type, :status],
    do: {key, Enum.join(List.wrap(values), "|")}

  defp query_param(other), do: other

  defp segment(entity), do: entity |> Atom.to_string() |> String.replace("_", "-")

  # track_artist is the one browse param MusicBrainz spells with an underscore
  defp param(:track_artist), do: :track_artist
  defp param(by), do: segment(by)

  defp encode(value), do: URI.encode(value, &URI.char_unreserved?/1)

  defp wait_for_slot do
    slot = claim_slot(slots(), interval_ms())
    Process.sleep(max(slot - System.monotonic_time(:millisecond), 0))
  end

  # compare-and-swap on the time of the last claimed slot, so concurrent
  # callers queue up one interval apart without a process to serialize them
  defp claim_slot(slots, interval) do
    last = :atomics.get(slots, 1)
    slot = max(System.monotonic_time(:millisecond), last + interval)

    case :atomics.compare_exchange(slots, 1, last, slot) do
      :ok -> slot
      _claimed_meanwhile -> claim_slot(slots, interval)
    end
  end

  defp slots do
    case :persistent_term.get(@slot_key, nil) do
      nil -> :global.trans({@slot_key, self()}, &create_slots/0, [node()])
      slots -> slots
    end
  end

  # under the lock, so concurrent first requests share one counter
  defp create_slots do
    case :persistent_term.get(@slot_key, nil) do
      nil ->
        slots = :atomics.new(1, signed: true)
        :atomics.put(slots, 1, @long_ago)
        :persistent_term.put(@slot_key, slots)
        slots

      slots ->
        slots
    end
  end
end
