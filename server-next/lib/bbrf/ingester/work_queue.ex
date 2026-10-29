defmodule BBRF.Ingester.WorkQueue do
  @moduledoc """
  A fixed number of slots (WORK_SLOTS, default 56) shared by every
  workload the ingester runs, each job one process under the queue's
  task supervisor.

  Work is submitted to a lane. Lanes are listed in priority order, and a
  free slot goes to the first lane that has work queued, runs fewer jobs
  than its `max_concurrency` and started its last job at least
  `interval_ms` ago; within a lane, jobs start in the order they were
  submitted. A lane held back by either leaves the free slots to the
  lanes after it, so a rate-limited workload never holds a slot just
  waiting for its turn.

  A running job is never preempted: a slot a low-priority job holds
  frees only when that job ends, so the lanes below the first should be
  given short jobs and a short timeout. Nothing guarantees a lower lane
  a share; it waits for as long as the lanes above keep it busy.

      WorkQueue.start_link(lanes: [wave: [], musicbrainz: [max_concurrency: 1, interval_ms: 1_000]])
  """

  use GenServer
  alias BBRF.Env

  def slots, do: Env.int("WORK_SLOTS", 56)

  @doc """
  Options: `:lanes`, a keyword list of lane name to lane options in
  priority order; `:slots` (`slots/0`); `:name` (`#{inspect(__MODULE__)}`,
  nil for none). Lane options:

    * `:max_concurrency` - jobs the lane runs at once, unlimited by default
    * `:interval_ms` - least time between two job starts in the lane, 0 by default
  """
  def start_link(opts) do
    {name, opts} = Keyword.pop(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Run `fun` on every item of `enumerable` in `lane`, as a stream of the
  results in the order they finish: `{:ok, result}`, or
  `{:exit, {item, reason}}` for a job that crashed or ran past `:timeout`
  (ms from when it started, default 5000), with reason `:timeout`.

  The items are queued when the stream is first pulled, and halting it
  drops what is still queued and kills what is running.
  """
  def async_stream(server, lane, enumerable, fun, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, 5_000)

    Stream.resource(
      fn ->
        items = Enum.to_list(enumerable)

        case GenServer.call(server, {:submit, lane, items, fun, timeout}) do
          {:ok, ref} -> {ref, length(items)}
          :unknown_lane -> raise ArgumentError, "no lane #{inspect(lane)} in the work queue"
        end
      end,
      fn
        {_ref, 0} = acc ->
          {:halt, acc}

        {ref, left} ->
          receive do
            {^ref, element} -> {[element], {ref, left - 1}}
          end
      end,
      fn {ref, _left} -> cancel(server, ref) end
    )
  end

  @doc "Per lane, how many jobs are queued and how many are running."
  def stats(server \\ __MODULE__), do: GenServer.call(server, :stats)

  defp cancel(server, ref) do
    :ok = GenServer.call(server, {:cancel, ref})
    flush(ref)
  end

  # results sent before the cancel landed
  defp flush(ref) do
    receive do
      {^ref, _element} -> flush(ref)
    after
      0 -> :ok
    end
  end

  @impl true
  def init(opts) do
    lanes = Keyword.fetch!(opts, :lanes)
    {:ok, tasks} = Task.Supervisor.start_link()
    now = System.monotonic_time(:millisecond)

    {:ok,
     %{
       slots: Keyword.get_lazy(opts, :slots, &slots/0),
       tasks: tasks,
       lanes: Keyword.keys(lanes),
       # an integer always sorts below :infinity
       limits:
         Map.new(lanes, fn {lane, o} -> {lane, Keyword.get(o, :max_concurrency, :infinity)} end),
       intervals: Map.new(lanes, fn {lane, o} -> {lane, Keyword.get(o, :interval_ms, 0)} end),
       # monotonic ms from which the lane may start its next job
       next_start: Map.new(lanes, fn {lane, _o} -> {lane, now} end),
       # lane => the timer that retries a lane held back by its interval
       wakeups: Map.new(lanes, fn {lane, _o} -> {lane, nil} end),
       queues: Map.new(lanes, fn {lane, _o} -> {lane, :queue.new()} end),
       running: Map.new(lanes, fn {lane, _o} -> {lane, 0} end),
       # task ref => %{stream, lane, item, pid, timer}
       jobs: %{},
       # stream ref => %{caller, monitor, fun, timeout, pending}
       streams: %{}
     }}
  end

  @impl true
  def handle_call({:submit, lane, items, fun, timeout}, {caller, _tag}, state) do
    case state.queues do
      %{^lane => queue} ->
        ref = make_ref()

        stream = %{
          caller: caller,
          monitor: Process.monitor(caller),
          fun: fun,
          timeout: timeout,
          pending: length(items)
        }

        queue = Enum.reduce(items, queue, &:queue.in({ref, &1}, &2))

        state = %{
          state
          | streams: Map.put(state.streams, ref, stream),
            queues: Map.put(state.queues, lane, queue)
        }

        {:reply, {:ok, ref}, dispatch(state)}

      _no_such_lane ->
        {:reply, :unknown_lane, state}
    end
  end

  def handle_call({:cancel, ref}, _from, state), do: {:reply, :ok, drop_stream(state, ref)}

  def handle_call(:stats, _from, state) do
    stats =
      Map.new(state.lanes, fn lane ->
        {lane, %{queued: :queue.len(state.queues[lane]), running: state.running[lane]}}
      end)

    {:reply, stats, state}
  end

  @impl true
  def handle_info({task_ref, result}, %{jobs: jobs} = state) when is_map_key(jobs, task_ref),
    do: {:noreply, complete(state, task_ref, {:ok, result})}

  def handle_info({:DOWN, task_ref, :process, _pid, reason}, %{jobs: jobs} = state)
      when is_map_key(jobs, task_ref),
      do: {:noreply, complete(state, task_ref, {:exit, {jobs[task_ref].item, reason}})}

  def handle_info({:timeout, task_ref}, %{jobs: jobs} = state) when is_map_key(jobs, task_ref) do
    Process.exit(jobs[task_ref].pid, :kill)
    {:noreply, complete(state, task_ref, {:exit, {jobs[task_ref].item, :timeout}})}
  end

  def handle_info({:wake, lane}, state),
    do: {:noreply, dispatch(%{state | wakeups: Map.put(state.wakeups, lane, nil)})}

  def handle_info({:DOWN, monitor, :process, _caller, _reason}, state) do
    case Enum.find(state.streams, fn {_ref, stream} -> stream.monitor == monitor end) do
      {ref, _stream} -> {:noreply, drop_stream(state, ref)}
      nil -> {:noreply, state}
    end
  end

  # replies and timeouts of jobs already completed or cancelled
  def handle_info(_stale, state), do: {:noreply, state}

  defp dispatch(state) do
    now = System.monotonic_time(:millisecond)

    with true <- map_size(state.jobs) < state.slots,
         lane when lane != nil <- Enum.find(state.lanes, &ready?(state, &1, now)) do
      {{:value, {ref, item}}, queue} = :queue.out(state.queues[lane])
      %{fun: fun, timeout: timeout} = state.streams[ref]
      task = Task.Supervisor.async_nolink(state.tasks, fn -> fun.(item) end)

      job = %{
        stream: ref,
        lane: lane,
        item: item,
        pid: task.pid,
        timer: Process.send_after(self(), {:timeout, task.ref}, timeout)
      }

      dispatch(%{
        state
        | queues: Map.put(state.queues, lane, queue),
          running: Map.update!(state.running, lane, &(&1 + 1)),
          next_start: Map.put(state.next_start, lane, now + state.intervals[lane]),
          jobs: Map.put(state.jobs, task.ref, job)
      })
    else
      _full_or_nothing_ready -> schedule_wakeups(state, now)
    end
  end

  defp ready?(state, lane, now), do: waiting?(state, lane) and state.next_start[lane] <= now

  defp waiting?(state, lane),
    do: not :queue.is_empty(state.queues[lane]) and state.running[lane] < state.limits[lane]

  defp schedule_wakeups(state, now) do
    wakeups =
      Map.new(state.wakeups, fn
        {lane, nil} = idle ->
          if waiting?(state, lane) and state.next_start[lane] > now,
            do: {lane, Process.send_after(self(), {:wake, lane}, state.next_start[lane] - now)},
            else: idle

        scheduled ->
          scheduled
      end)

    %{state | wakeups: wakeups}
  end

  defp complete(state, task_ref, element) do
    {job, jobs} = Map.pop!(state.jobs, task_ref)
    release(task_ref, job)
    stream = state.streams[job.stream]
    send(stream.caller, {job.stream, element})

    streams =
      case stream.pending - 1 do
        0 ->
          Process.demonitor(stream.monitor, [:flush])
          Map.delete(state.streams, job.stream)

        pending ->
          Map.put(state.streams, job.stream, %{stream | pending: pending})
      end

    dispatch(%{
      state
      | jobs: jobs,
        streams: streams,
        running: Map.update!(state.running, job.lane, &(&1 - 1))
    })
  end

  defp drop_stream(state, ref) do
    case Map.pop(state.streams, ref) do
      {nil, _streams} ->
        state

      {stream, streams} ->
        Process.demonitor(stream.monitor, [:flush])
        {dropped, jobs} = Map.split_with(state.jobs, fn {_task_ref, job} -> job.stream == ref end)

        running =
          Enum.reduce(dropped, state.running, fn {task_ref, job}, running ->
            Process.exit(job.pid, :kill)
            release(task_ref, job)
            Map.update!(running, job.lane, &(&1 - 1))
          end)

        queues =
          Map.new(state.queues, fn {lane, queue} ->
            {lane, :queue.filter(fn {job_ref, _item} -> job_ref != ref end, queue)}
          end)

        dispatch(%{state | streams: streams, jobs: jobs, running: running, queues: queues})
    end
  end

  defp release(task_ref, job) do
    Process.demonitor(task_ref, [:flush])
    Process.cancel_timer(job.timer)
  end
end
