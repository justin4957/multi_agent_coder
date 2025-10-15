defmodule MultiAgentCoder.Task.Tracker do
  @moduledoc """
  Tracks task execution progress across all providers.

  Provides real-time monitoring of:
  - Task status and progress per provider
  - Estimated completion times
  - Token usage per task per provider
  - Overall task statistics

  ## Examples

      iex> Tracker.start_tracking(task_id, :openai)
      :ok

      iex> Tracker.update_progress(task_id, tokens: 500, progress: 0.5)
      :ok

      iex> Tracker.get_status(task_id)
      {:ok, %{provider: :openai, progress: 0.5, tokens: 500, eta: 1200}}
  """

  use GenServer
  require Logger

  alias MultiAgentCoder.Task.Task

  defstruct tasks: %{},
            provider_stats: %{},
            global_stats: %{}

  @type task_tracking :: %{
          task: Task.t(),
          provider: atom(),
          started_at: DateTime.t(),
          tokens_used: integer(),
          progress: float(),
          estimated_completion: DateTime.t() | nil,
          last_update: DateTime.t()
        }

  @type provider_stats :: %{
          active_tasks: integer(),
          completed_tasks: integer(),
          failed_tasks: integer(),
          total_tokens: integer(),
          average_completion_time: float()
        }

  @type t :: %__MODULE__{
          tasks: map(),
          provider_stats: map(),
          global_stats: map()
        }

  # Client API

  @doc """
  Starts the task tracker GenServer.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Starts tracking a task for a specific provider.
  """
  @spec start_tracking(String.t(), atom()) :: :ok
  def start_tracking(task_id, provider) do
    GenServer.call(__MODULE__, {:start_tracking, task_id, provider})
  end

  @doc """
  Updates progress for a running task.

  ## Options
  - `:tokens` - Number of tokens used
  - `:progress` - Progress percentage (0.0 to 1.0)
  - `:metadata` - Additional tracking metadata
  """
  @spec update_progress(String.t(), keyword()) :: :ok | {:error, :not_found}
  def update_progress(task_id, opts \\ []) do
    GenServer.call(__MODULE__, {:update_progress, task_id, opts})
  end

  @doc """
  Marks a task as completed and updates statistics.
  """
  @spec complete_tracking(String.t()) :: :ok | {:error, :not_found}
  def complete_tracking(task_id) do
    GenServer.call(__MODULE__, {:complete_tracking, task_id})
  end

  @doc """
  Marks a task as failed and updates statistics.
  """
  @spec fail_tracking(String.t()) :: :ok | {:error, :not_found}
  def fail_tracking(task_id) do
    GenServer.call(__MODULE__, {:fail_tracking, task_id})
  end

  @doc """
  Gets current status for a specific task.
  """
  @spec get_status(String.t()) :: {:ok, task_tracking()} | {:error, :not_found}
  def get_status(task_id) do
    GenServer.call(__MODULE__, {:get_status, task_id})
  end

  @doc """
  Gets all currently tracked tasks.
  """
  @spec get_all_tasks() :: list(task_tracking())
  def get_all_tasks do
    GenServer.call(__MODULE__, :get_all_tasks)
  end

  @doc """
  Gets statistics for a specific provider.
  """
  @spec get_provider_stats(atom()) :: {:ok, provider_stats()} | {:error, :not_found}
  def get_provider_stats(provider) do
    GenServer.call(__MODULE__, {:get_provider_stats, provider})
  end

  @doc """
  Gets statistics for all providers.
  """
  @spec get_all_provider_stats() :: map()
  def get_all_provider_stats do
    GenServer.call(__MODULE__, :get_all_provider_stats)
  end

  @doc """
  Gets global task statistics.
  """
  @spec get_global_stats() :: map()
  def get_global_stats do
    GenServer.call(__MODULE__, :get_global_stats)
  end

  @doc """
  Clears all tracking data.
  """
  @spec clear() :: :ok
  def clear do
    GenServer.call(__MODULE__, :clear)
  end

  # Server Callbacks

  @impl true
  def init(_opts) do
    {:ok, %__MODULE__{}}
  end

  @impl true
  def handle_call({:start_tracking, task_id, provider}, _from, state) do
    tracking_info = %{
      task_id: task_id,
      provider: provider,
      started_at: DateTime.utc_now(),
      tokens_used: 0,
      progress: 0.0,
      estimated_completion: nil,
      last_update: DateTime.utc_now()
    }

    new_tasks = Map.put(state.tasks, task_id, tracking_info)
    new_state = %{state | tasks: new_tasks}
    new_state = increment_provider_stat(new_state, provider, :active_tasks)

    Logger.info("Started tracking task #{task_id} for provider #{provider}")

    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call({:update_progress, task_id, opts}, _from, state) do
    case Map.get(state.tasks, task_id) do
      nil ->
        {:reply, {:error, :not_found}, state}

      tracking_info ->
        tokens = Keyword.get(opts, :tokens, tracking_info.tokens_used)
        progress = Keyword.get(opts, :progress, tracking_info.progress)
        metadata = Keyword.get(opts, :metadata, %{})

        updated_tracking =
          tracking_info
          |> Map.put(:tokens_used, tokens)
          |> Map.put(:progress, progress)
          |> Map.put(:last_update, DateTime.utc_now())
          |> Map.put(:estimated_completion, estimate_completion(tracking_info, progress))
          |> Map.merge(metadata)

        new_tasks = Map.put(state.tasks, task_id, updated_tracking)

        # Update provider token stats
        new_state = update_provider_tokens(state, tracking_info.provider, tokens)
        new_state = %{new_state | tasks: new_tasks}

        {:reply, :ok, new_state}
    end
  end

  @impl true
  def handle_call({:complete_tracking, task_id}, _from, state) do
    case Map.get(state.tasks, task_id) do
      nil ->
        {:reply, {:error, :not_found}, state}

      tracking_info ->
        completion_time = calculate_completion_time(tracking_info)
        provider = tracking_info.provider

        # Remove from active tracking
        new_tasks = Map.delete(state.tasks, task_id)

        # Update provider statistics
        new_state = %{state | tasks: new_tasks}
        new_state = decrement_provider_stat(new_state, provider, :active_tasks)
        new_state = increment_provider_stat(new_state, provider, :completed_tasks)
        new_state = update_average_completion_time(new_state, provider, completion_time)

        # Update global statistics
        new_state = increment_global_stat(new_state, :total_completed)

        Logger.info("Completed tracking task #{task_id} (#{completion_time}ms)")

        {:reply, :ok, new_state}
    end
  end

  @impl true
  def handle_call({:fail_tracking, task_id}, _from, state) do
    case Map.get(state.tasks, task_id) do
      nil ->
        {:reply, {:error, :not_found}, state}

      tracking_info ->
        provider = tracking_info.provider

        # Remove from active tracking
        new_tasks = Map.delete(state.tasks, task_id)

        # Update provider statistics
        new_state = %{state | tasks: new_tasks}
        new_state = decrement_provider_stat(new_state, provider, :active_tasks)
        new_state = increment_provider_stat(new_state, provider, :failed_tasks)

        # Update global statistics
        new_state = increment_global_stat(new_state, :total_failed)

        Logger.info("Failed tracking task #{task_id}")

        {:reply, :ok, new_state}
    end
  end

  @impl true
  def handle_call({:get_status, task_id}, _from, state) do
    case Map.get(state.tasks, task_id) do
      nil -> {:reply, {:error, :not_found}, state}
      tracking_info -> {:reply, {:ok, tracking_info}, state}
    end
  end

  @impl true
  def handle_call(:get_all_tasks, _from, state) do
    tasks = Map.values(state.tasks)
    {:reply, tasks, state}
  end

  @impl true
  def handle_call({:get_provider_stats, provider}, _from, state) do
    case Map.get(state.provider_stats, provider) do
      nil -> {:reply, {:error, :not_found}, state}
      stats -> {:reply, {:ok, stats}, state}
    end
  end

  @impl true
  def handle_call(:get_all_provider_stats, _from, state) do
    {:reply, state.provider_stats, state}
  end

  @impl true
  def handle_call(:get_global_stats, _from, state) do
    stats =
      Map.merge(
        %{
          active_tasks: map_size(state.tasks),
          total_providers: map_size(state.provider_stats)
        },
        state.global_stats
      )

    {:reply, stats, state}
  end

  @impl true
  def handle_call(:clear, _from, _state) do
    {:reply, :ok, %__MODULE__{}}
  end

  # Private functions

  defp estimate_completion(tracking_info, progress) when progress > 0 do
    elapsed = DateTime.diff(DateTime.utc_now(), tracking_info.started_at, :millisecond)
    total_estimated_time = elapsed / progress
    remaining_time = total_estimated_time - elapsed

    DateTime.add(DateTime.utc_now(), round(remaining_time), :millisecond)
  end

  defp estimate_completion(_tracking_info, _progress), do: nil

  defp calculate_completion_time(tracking_info) do
    DateTime.diff(DateTime.utc_now(), tracking_info.started_at, :millisecond)
  end

  defp increment_provider_stat(state, provider, stat_key) do
    provider_stats = Map.get(state.provider_stats, provider, default_provider_stats())
    updated_stats = Map.update(provider_stats, stat_key, 1, &(&1 + 1))
    new_provider_stats = Map.put(state.provider_stats, provider, updated_stats)
    %{state | provider_stats: new_provider_stats}
  end

  defp decrement_provider_stat(state, provider, stat_key) do
    provider_stats = Map.get(state.provider_stats, provider, default_provider_stats())
    updated_stats = Map.update(provider_stats, stat_key, 0, &max(&1 - 1, 0))
    new_provider_stats = Map.put(state.provider_stats, provider, updated_stats)
    %{state | provider_stats: new_provider_stats}
  end

  defp update_provider_tokens(state, provider, tokens) do
    provider_stats = Map.get(state.provider_stats, provider, default_provider_stats())
    updated_stats = Map.put(provider_stats, :total_tokens, tokens)
    new_provider_stats = Map.put(state.provider_stats, provider, updated_stats)
    %{state | provider_stats: new_provider_stats}
  end

  defp update_average_completion_time(state, provider, completion_time) do
    provider_stats = Map.get(state.provider_stats, provider, default_provider_stats())
    completed_tasks = provider_stats.completed_tasks
    current_average = provider_stats.average_completion_time

    new_average =
      if completed_tasks == 0 do
        completion_time
      else
        (current_average * (completed_tasks - 1) + completion_time) / completed_tasks
      end

    updated_stats = Map.put(provider_stats, :average_completion_time, new_average)
    new_provider_stats = Map.put(state.provider_stats, provider, updated_stats)
    %{state | provider_stats: new_provider_stats}
  end

  defp increment_global_stat(state, stat_key) do
    global_stats = Map.update(state.global_stats, stat_key, 1, &(&1 + 1))
    %{state | global_stats: global_stats}
  end

  defp default_provider_stats do
    %{
      active_tasks: 0,
      completed_tasks: 0,
      failed_tasks: 0,
      total_tokens: 0,
      average_completion_time: 0.0
    }
  end
end
