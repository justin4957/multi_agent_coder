defmodule MultiAgentCoder.Merge.PerformanceMonitor do
  @moduledoc """
  Tracks and reports performance metrics for merge operations.

  Monitors:
  - Time spent in each merge phase
  - Memory usage during operations
  - File processing throughput
  - Bottleneck identification
  """

  use GenServer
  require Logger

  defmodule Metrics do
    @moduledoc false
    defstruct phase: nil,
              start_time: nil,
              end_time: nil,
              duration_ms: nil,
              memory_before: nil,
              memory_after: nil,
              memory_delta: nil,
              metadata: %{}
  end

  defmodule Report do
    @moduledoc false
    defstruct total_duration_ms: 0,
              phases: [],
              total_memory_mb: 0,
              files_processed: 0,
              throughput_files_per_sec: 0,
              slowest_phase: nil,
              cache_stats: nil

    def format(%__MODULE__{} = report) do
      """
      Performance Report
      ==================
      Total Duration: #{format_duration(report.total_duration_ms)}
      Files Processed: #{report.files_processed}
      Throughput: #{Float.round(report.throughput_files_per_sec, 2)} files/sec
      Memory Usage: #{Float.round(report.total_memory_mb, 2)} MB
      Slowest Phase: #{report.slowest_phase}

      Phase Breakdown:
      #{format_phases(report.phases)}

      #{format_cache_stats(report.cache_stats)}
      """
    end

    defp format_duration(ms) when ms < 1000, do: "#{ms}ms"
    defp format_duration(ms), do: "#{Float.round(ms / 1000, 2)}s"

    defp format_phases(phases) do
      phases
      |> Enum.map(fn metric ->
        "  - #{metric.phase}: #{format_duration(metric.duration_ms)} (#{format_memory(metric.memory_delta)})"
      end)
      |> Enum.join("\n")
    end

    defp format_memory(bytes) when is_nil(bytes), do: "N/A"

    defp format_memory(bytes) when bytes < 1024 * 1024,
      do: "#{Float.round(bytes / 1024, 2)} KB"

    defp format_memory(bytes), do: "#{Float.round(bytes / 1024 / 1024, 2)} MB"

    defp format_cache_stats(nil), do: ""

    defp format_cache_stats(stats) do
      """
      Cache Performance:
        - Hit Rate: #{Float.round(stats.hit_rate, 2)}%
        - Hits: #{stats.hits}
        - Misses: #{stats.misses}
        - Total Entries: #{stats.total_entries}
      """
    end
  end

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Starts tracking a new merge operation.
  """
  @spec start_operation(String.t()) :: :ok
  def start_operation(operation_id) do
    GenServer.call(__MODULE__, {:start_operation, operation_id})
  end

  @doc """
  Starts tracking a specific phase within an operation.
  """
  @spec start_phase(String.t(), atom(), map()) :: :ok
  def start_phase(operation_id, phase_name, metadata \\ %{}) do
    GenServer.call(__MODULE__, {:start_phase, operation_id, phase_name, metadata})
  end

  @doc """
  Ends tracking of a specific phase.
  """
  @spec end_phase(String.t(), atom()) :: :ok
  def end_phase(operation_id, phase_name) do
    GenServer.call(__MODULE__, {:end_phase, operation_id, phase_name})
  end

  @doc """
  Completes an operation and generates a performance report.
  """
  @spec complete_operation(String.t(), map()) :: Report.t()
  def complete_operation(operation_id, metadata \\ %{}) do
    GenServer.call(__MODULE__, {:complete_operation, operation_id, metadata})
  end

  @doc """
  Tracks a complete phase with automatic timing.
  """
  def track_phase(operation_id, phase_name, metadata \\ %{}, func) do
    start_phase(operation_id, phase_name, metadata)

    try do
      result = func.()
      end_phase(operation_id, phase_name)
      result
    rescue
      error ->
        end_phase(operation_id, phase_name)
        reraise error, __STACKTRACE__
    end
  end

  @doc """
  Gets the current performance metrics for an operation.
  """
  @spec get_metrics(String.t()) :: {:ok, list(Metrics.t())} | {:error, :not_found}
  def get_metrics(operation_id) do
    GenServer.call(__MODULE__, {:get_metrics, operation_id})
  end

  # Server Callbacks

  @impl true
  def init(_opts) do
    state = %{
      operations: %{},
      active_phases: %{}
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:start_operation, operation_id}, _from, state) do
    new_operations =
      Map.put(state.operations, operation_id, %{
        start_time: System.monotonic_time(:millisecond),
        phases: [],
        metadata: %{}
      })

    {:reply, :ok, %{state | operations: new_operations}}
  end

  @impl true
  def handle_call({:start_phase, operation_id, phase_name, metadata}, _from, state) do
    phase_key = {operation_id, phase_name}
    memory_info = :erlang.memory()

    phase_data = %{
      phase: phase_name,
      start_time: System.monotonic_time(:millisecond),
      memory_before: memory_info[:total],
      metadata: metadata
    }

    new_active_phases = Map.put(state.active_phases, phase_key, phase_data)
    {:reply, :ok, %{state | active_phases: new_active_phases}}
  end

  @impl true
  def handle_call({:end_phase, operation_id, phase_name}, _from, state) do
    phase_key = {operation_id, phase_name}

    case Map.pop(state.active_phases, phase_key) do
      {nil, _} ->
        Logger.warning("Attempted to end phase that wasn't started: #{phase_name}")
        {:reply, {:error, :not_found}, state}

      {phase_data, new_active_phases} ->
        end_time = System.monotonic_time(:millisecond)
        memory_info = :erlang.memory()

        metrics = %Metrics{
          phase: phase_name,
          start_time: phase_data.start_time,
          end_time: end_time,
          duration_ms: end_time - phase_data.start_time,
          memory_before: phase_data.memory_before,
          memory_after: memory_info[:total],
          memory_delta: memory_info[:total] - phase_data.memory_before,
          metadata: phase_data.metadata
        }

        # Add metrics to operation
        new_operations =
          Map.update(state.operations, operation_id, %{phases: [metrics]}, fn op ->
            %{op | phases: [metrics | op.phases]}
          end)

        {:reply, :ok, %{state | operations: new_operations, active_phases: new_active_phases}}
    end
  end

  @impl true
  def handle_call({:complete_operation, operation_id, metadata}, _from, state) do
    case Map.pop(state.operations, operation_id) do
      {nil, _} ->
        {:reply, {:error, :not_found}, state}

      {operation, new_operations} ->
        end_time = System.monotonic_time(:millisecond)
        total_duration = end_time - operation.start_time

        # Reverse phases to get chronological order
        phases = Enum.reverse(operation.phases)

        # Get cache stats if available
        cache_stats =
          try do
            stats = MultiAgentCoder.Merge.Cache.stats()

            %{
              hits: stats.hits,
              misses: stats.misses,
              hit_rate: MultiAgentCoder.Merge.Cache.Stats.hit_rate(stats),
              total_entries: stats.total_entries
            }
          rescue
            _ -> nil
          end

        # Calculate slowest phase
        slowest_phase =
          if Enum.empty?(phases) do
            nil
          else
            phases
            |> Enum.max_by(& &1.duration_ms)
            |> Map.get(:phase)
          end

        # Calculate memory usage
        total_memory_bytes =
          phases
          |> Enum.map(& &1.memory_delta)
          |> Enum.reject(&is_nil/1)
          |> Enum.sum()

        total_memory_mb = total_memory_bytes / 1024 / 1024

        # Calculate throughput
        files_processed = metadata[:files_processed] || 0

        throughput =
          if total_duration > 0 do
            files_processed / (total_duration / 1000)
          else
            0
          end

        report = %Report{
          total_duration_ms: total_duration,
          phases: phases,
          total_memory_mb: total_memory_mb,
          files_processed: files_processed,
          throughput_files_per_sec: throughput,
          slowest_phase: slowest_phase,
          cache_stats: cache_stats
        }

        Logger.info("Operation #{operation_id} completed in #{total_duration}ms")
        {:reply, report, %{state | operations: new_operations}}
    end
  end

  @impl true
  def handle_call({:get_metrics, operation_id}, _from, state) do
    case Map.get(state.operations, operation_id) do
      nil -> {:reply, {:error, :not_found}, state}
      operation -> {:reply, {:ok, operation.phases}, state}
    end
  end
end
