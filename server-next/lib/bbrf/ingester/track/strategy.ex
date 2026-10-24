defmodule BBRF.Ingester.Track.Strategy do
  @moduledoc """
  How track waves cycle through the stations. A strategy answers two
  questions; fetching a station, classifying the result and storing it
  are shared and live in `BBRF.Ingester.Track`:

    * which stations go into the next wave, in fetch order - `c:select/3`
    * when a station that was just checked is due again - `c:next_check_at/5`

  TRACK_STRATEGY picks one by name (default `full-sweep`):

    * `adaptive` (`BBRF.Ingester.Track.Strategy.Adaptive`) - every station
      has its own due time, moved by what each check finds
    * `full-sweep` (`BBRF.Ingester.Track.Strategy.FullSweep`) - rotates
      through the catalogue, least recently checked first

  A strategy is carried around as `{module, config}` (`t:t/0`), built by
  `new/2` from the module's `c:init/1`. To add one, implement this
  behaviour, build its queries from `candidates/0` and `load/1`, and add
  it to `@strategies`. Stations that failed or found no metadata should
  follow `BBRF.Ingester.Track.Backoff`, as both built-in strategies do.
  """

  import Ecto.Query, except: [select: 3]
  alias BBRF.{Env, Repo, Station}
  alias BBRF.Ingester.Track.Strategy.{Adaptive, FullSweep}

  @typedoc "A strategy module and the config its `c:init/1` built."
  @type t :: {module(), config()}

  @type config :: term()

  @typedoc "A station as a wave sees it, loaded by `load/1`."
  @type candidate :: %{
          stationuuid: String.t(),
          changeuuid: String.t() | nil,
          stream_url: String.t(),
          meta_state: String.t(),
          meta_source: String.t() | nil,
          meta_checked_at: String.t() | nil,
          meta_next_check_at: String.t() | nil,
          fail_count: non_neg_integer(),
          idle_count: non_neg_integer(),
          last_title: String.t() | nil,
          clickcount: non_neg_integer()
        }

  @typedoc """
  What a check found, from `BBRF.Ingester.Track.classify/2`: a new title,
  no new title on an ok station, no metadata to be had, or a failure.
  """
  @type outcome :: {:changed, String.t(), map()} | :idle | :no_metadata | :fail

  @doc "Build the config from `opts`, falling back to the strategy's env vars."
  @callback init(opts :: keyword()) :: config()

  @doc "One line for the startup log."
  @callback describe(config()) :: String.t()

  @doc "The stations for the next wave at `now`, in fetch order, at most `limit`."
  @callback select(now :: DateTime.t(), limit :: pos_integer(), config()) :: [candidate()]

  @doc """
  When `station` is due again after `outcome`. `state` holds its columns
  after the check (`BBRF.Ingester.Track.next_state/4`). nil leaves its
  due time as it was, for a strategy that does not schedule by due time.
  """
  @callback next_check_at(
              station :: candidate(),
              outcome(),
              state :: map(),
              now :: DateTime.t(),
              config()
            ) :: DateTime.t() | nil

  @strategies %{"adaptive" => Adaptive, "full-sweep" => FullSweep}

  def names, do: @strategies |> Map.keys() |> Enum.sort()

  @doc "The strategy TRACK_STRATEGY names; an unknown name raises, so a typo stops the boot."
  @spec from_env() :: t()
  def from_env, do: new(Env.str("TRACK_STRATEGY", "full-sweep"))

  @spec new(String.t(), keyword()) :: t()
  def new(name, opts \\ []) do
    case Map.fetch(@strategies, name) do
      {:ok, module} ->
        {module, module.init(opts)}

      :error ->
        raise ArgumentError,
              "TRACK_STRATEGY must be one of #{Enum.join(names(), ", ")}, got #{inspect(name)}"
    end
  end

  @spec name(t()) :: String.t()
  def name({module, _config}) do
    Enum.find_value(@strategies, fn {name, strategy} -> if strategy == module, do: name end)
  end

  @spec describe(t()) :: String.t()
  def describe({module, config}), do: module.describe(config)

  @spec select(t(), DateTime.t(), pos_integer()) :: [candidate()]
  def select({module, config}, now, limit), do: module.select(now, limit, config)

  @spec next_check_at(t(), candidate(), outcome(), map(), DateTime.t()) :: DateTime.t() | nil
  def next_check_at({module, config}, station, outcome, state, now),
    do: module.next_check_at(station, outcome, state, now, config)

  @doc """
  Every station a wave may check: not removed, working according to
  radio-browser, not HLS, with a stream url. Strategies narrow, order and
  limit it, then run it with `load/1`.
  """
  def candidates do
    from(s in Station,
      where:
        s.meta_state != "removed" and
          s.lastcheckok == 1 and
          s.hls == 0 and
          not is_nil(fragment("COALESCE(NULLIF(?, ''), ?)", s.url_resolved, s.url)),
      select: %{
        stationuuid: s.stationuuid,
        changeuuid: s.changeuuid,
        stream_url: fragment("COALESCE(NULLIF(?, ''), ?)", s.url_resolved, s.url),
        meta_state: s.meta_state,
        meta_source: s.meta_source,
        meta_checked_at: s.meta_checked_at,
        meta_next_check_at: s.meta_next_check_at,
        fail_count: s.meta_fail_count,
        idle_count: s.meta_idle_count,
        last_title: s.meta_last_title,
        clickcount: fragment("COALESCE(?, 0)", s.clickcount)
      }
    )
  end

  @spec load(Ecto.Query.t()) :: [candidate()]
  def load(query), do: Repo.all(query)

  @doc "How many stations a `candidates/0` query covers."
  @spec count(Ecto.Query.t()) :: non_neg_integer()
  def count(query \\ candidates()) do
    query
    |> exclude(:select)
    |> Ecto.Query.select([s], count(s.stationuuid))
    |> Repo.one()
  end
end
