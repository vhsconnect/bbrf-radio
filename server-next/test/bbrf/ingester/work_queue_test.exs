defmodule BBRF.Ingester.WorkQueueTest do
  use ExUnit.Case, async: true

  alias BBRF.Ingester.WorkQueue

  defp start_queue(slots, lanes),
    do: start_supervised!({WorkQueue, name: nil, slots: slots, lanes: lanes})

  defp results(stream), do: stream |> Enum.to_list() |> Enum.sort()

  defp wait_until(condition) do
    unless condition.() do
      Process.sleep(5)
      wait_until(condition)
    end
  end

  # a job that holds its slot until the test sends it :open
  defp gate(test_pid) do
    fn item ->
      send(test_pid, {:started, item, self()})

      receive do
        :open -> item
      end
    end
  end

  test "returns every item's result" do
    queue = start_queue(2, work: [])

    assert queue |> WorkQueue.async_stream(:work, 1..5, &(&1 * 10)) |> results() ==
             [ok: 10, ok: 20, ok: 30, ok: 40, ok: 50]
  end

  test "a free slot goes to the higher-priority lane first" do
    queue = start_queue(1, high: [], low: [])
    test_pid = self()
    record = fn item -> send(test_pid, {:ran, item}) end

    low =
      Task.async(fn ->
        queue
        |> WorkQueue.async_stream(:low, [:gate, :low], fn
          :gate -> gate(test_pid).(:gate)
          item -> record.(item)
        end)
        |> Enum.to_list()
      end)

    assert_receive {:started, :gate, gate_pid}

    high =
      Task.async(fn ->
        queue |> WorkQueue.async_stream(:high, [:high], record) |> Enum.to_list()
      end)

    wait_until(fn -> WorkQueue.stats(queue).high.queued == 1 end)
    send(gate_pid, :open)

    Task.await_many([low, high])
    assert_received {:ran, first}
    assert_received {:ran, second}
    assert [first, second] == [:high, :low]
  end

  test "a lane never runs more jobs than its max_concurrency" do
    queue = start_queue(4, limited: [max_concurrency: 1], free: [])
    test_pid = self()

    Task.async(fn ->
      queue
      |> WorkQueue.async_stream(:limited, [:first, :second], gate(test_pid))
      |> Enum.to_list()
    end)

    assert_receive {:started, :first, first_pid}

    assert queue |> WorkQueue.async_stream(:free, [1, 2, 3], & &1) |> results() ==
             [ok: 1, ok: 2, ok: 3]

    assert WorkQueue.stats(queue).limited == %{queued: 1, running: 1}
    refute_received {:started, :second, _pid}

    send(first_pid, :open)
    assert_receive {:started, :second, _pid}
  end

  test "a lane starts at most one job per interval_ms" do
    queue = start_queue(4, paced: [interval_ms: 50])
    now = fn _item -> System.monotonic_time(:millisecond) end

    starts =
      for {:ok, started} <- queue |> WorkQueue.async_stream(:paced, 1..3, now) |> results(),
          do: started

    assert starts |> Enum.chunk_every(2, 1, :discard) |> Enum.all?(fn [a, b] -> b - a >= 50 end)
  end

  test "a lane waiting out its interval leaves the slot to the others" do
    queue = start_queue(1, paced: [interval_ms: 60_000], free: [])

    Task.async(fn -> queue |> WorkQueue.async_stream(:paced, [1, 2], & &1) |> Enum.to_list() end)
    wait_until(fn -> WorkQueue.stats(queue).paced == %{queued: 1, running: 0} end)

    assert queue |> WorkQueue.async_stream(:free, [:a], & &1) |> results() == [ok: :a]
    assert WorkQueue.stats(queue).paced == %{queued: 1, running: 0}
  end

  test "a job past its timeout is killed and reported as an exit" do
    queue = start_queue(2, work: [])

    stream =
      WorkQueue.async_stream(
        queue,
        :work,
        [:slow, :fast],
        fn
          :slow -> Process.sleep(:infinity)
          :fast -> :done
        end,
        timeout: 50
      )

    assert results(stream) == [exit: {:slow, :timeout}, ok: :done]
    assert WorkQueue.stats(queue).work == %{queued: 0, running: 0}
  end

  @tag :capture_log
  test "a crashing job is reported as an exit" do
    queue = start_queue(1, work: [])

    assert [exit: {:bad, {%RuntimeError{message: "boom"}, _stacktrace}}] =
             queue |> WorkQueue.async_stream(:work, [:bad], fn _ -> raise "boom" end) |> results()
  end

  test "halting the stream drops queued jobs and kills running ones" do
    queue = start_queue(1, work: [])
    test_pid = self()

    first =
      queue
      |> WorkQueue.async_stream(:work, [:a, :b, :c], fn
        :a -> :a
        item -> gate(test_pid).(item)
      end)
      |> Enum.take(1)

    assert first == [ok: :a]
    assert WorkQueue.stats(queue).work == %{queued: 0, running: 0}
    refute_received {:started, :c, _pid}
  end

  test "a caller that dies takes its jobs with it" do
    queue = start_queue(1, work: [])
    test_pid = self()

    caller =
      spawn(fn ->
        queue |> WorkQueue.async_stream(:work, [:a, :b], gate(test_pid)) |> Enum.to_list()
      end)

    assert_receive {:started, :a, job_pid}
    job = Process.monitor(job_pid)
    Process.exit(caller, :kill)

    assert_receive {:DOWN, ^job, :process, ^job_pid, :killed}
    assert WorkQueue.stats(queue).work == %{queued: 0, running: 0}
  end

  test "refuses a lane it does not have" do
    queue = start_queue(1, work: [])

    assert_raise ArgumentError, fn ->
      queue |> WorkQueue.async_stream(:other, [1], & &1) |> Enum.to_list()
    end
  end
end
