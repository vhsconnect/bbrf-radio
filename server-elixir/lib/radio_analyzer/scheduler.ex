defmodule RadioAnalyzer.Scheduler do
  @moduledoc """
  The OTP replacement for chime: a GenServer that runs `job` (a
  `{module, function, args}` triple) every `interval_ms` milliseconds.

  The first tick fires right after startup - like chime's periodic-seq
  starting at "now", the immediate catalogue tick does the initial
  station load (a track wave racing an empty stations table just records
  a zero row). The next tick is scheduled only after the previous job
  returned, so overlapping runs are structurally impossible; it is due
  `interval_ms` after the previous run started, or right away when that
  run took longer.
  """

  use GenServer
  require Logger

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.fetch!(opts, :name))
  end

  # one instance per loop lives in the tree - the supervisor id is the name
  def child_spec(opts) do
    %{
      id: Keyword.fetch!(opts, :name),
      start: {__MODULE__, :start_link, [opts]}
    }
  end

  @impl true
  def init(opts) do
    state = %{
      label: Keyword.fetch!(opts, :label),
      interval_ms: Keyword.fetch!(opts, :interval_ms),
      job: Keyword.fetch!(opts, :job)
    }

    Process.send_after(self(), :tick, 0)
    {:ok, state}
  end

  @impl true
  def handle_info(:tick, state) do
    started = System.monotonic_time(:millisecond)
    run(state)
    elapsed = System.monotonic_time(:millisecond) - started
    Process.send_after(self(), :tick, max(state.interval_ms - elapsed, 0))
    {:noreply, state}
  end

  # jobs swallow their own errors by design; this is the last resort so
  # a surprise never crash-loops the scheduler
  defp run(%{label: label, job: {module, fun, args}}) do
    result = apply(module, fun, args)
    Logger.info("#{label} #{inspect(result)}")
  rescue
    exception ->
      Logger.error(
        "#{label} job crashed:\n" <>
          Exception.format(:error, exception, __STACKTRACE__)
      )
  end
end
