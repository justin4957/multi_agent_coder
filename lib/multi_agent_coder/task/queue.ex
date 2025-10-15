defmodule MultiAgentCoder.Task.Queue do
  @moduledoc """
  Task queue management with priority ordering and dependency tracking.

  Manages a queue of coding tasks, handling:
  - Task queuing and dequeuing
  - Priority ordering
  - Dependency resolution
  - Task cancellation
  - Queue status and statistics

  ## Examples

      iex> Queue.enqueue(task)
      :ok

      iex> Queue.dequeue()
      {:ok, task}

      iex> Queue.status()
      %{pending: 3, running: 2, completed: 5}
  """

  use GenServer
  require Logger

  alias MultiAgentCoder.Task.Task

  defstruct pending: [],
            running: %{},
            completed: [],
            failed: [],
            cancelled: []

  @type t :: %__MODULE__{
          pending: list(Task.t()),
          running: map(),
          completed: list(Task.t()),
          failed: list(Task.t()),
          cancelled: list(Task.t())
        }

  # Client API

  @doc """
  Starts the task queue GenServer.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Enqueues a task for execution.
  """
  @spec enqueue(Task.t()) :: :ok
  def enqueue(task) do
    GenServer.call(__MODULE__, {:enqueue, task})
  end

  @doc """
  Dequeues the next available task.

  Returns the highest priority task that has all dependencies met.
  """
  @spec dequeue() :: {:ok, Task.t()} | {:error, :empty}
  def dequeue do
    GenServer.call(__MODULE__, :dequeue)
  end

  @doc """
  Gets a task by ID.
  """
  @spec get_task(String.t()) :: {:ok, Task.t()} | {:error, :not_found}
  def get_task(task_id) do
    GenServer.call(__MODULE__, {:get_task, task_id})
  end

  @doc """
  Updates a task's status.
  """
  @spec update_task(String.t(), Task.t()) :: :ok | {:error, :not_found}
  def update_task(task_id, updated_task) do
    GenServer.call(__MODULE__, {:update_task, task_id, updated_task})
  end

  @doc """
  Marks a task as completed.
  """
  @spec complete_task(String.t(), term()) :: :ok | {:error, :not_found}
  def complete_task(task_id, result) do
    GenServer.call(__MODULE__, {:complete_task, task_id, result})
  end

  @doc """
  Marks a task as failed.
  """
  @spec fail_task(String.t(), term()) :: :ok | {:error, :not_found}
  def fail_task(task_id, error) do
    GenServer.call(__MODULE__, {:fail_task, task_id, error})
  end

  @doc """
  Cancels a task.
  """
  @spec cancel_task(String.t()) :: :ok | {:error, :not_found}
  def cancel_task(task_id) do
    GenServer.call(__MODULE__, {:cancel_task, task_id})
  end

  @doc """
  Gets current queue status.
  """
  @spec status() :: map()
  def status do
    GenServer.call(__MODULE__, :status)
  end

  @doc """
  Lists all tasks in the queue.
  """
  @spec list_all() :: map()
  def list_all do
    GenServer.call(__MODULE__, :list_all)
  end

  @doc """
  Clears the entire queue.
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
  def handle_call({:enqueue, task}, _from, state) do
    # Add task to pending queue, sorted by priority (highest first)
    new_pending =
      [task | state.pending]
      |> Enum.sort_by(& &1.priority, :desc)

    Logger.info("Task enqueued: #{task.id} - #{task.description}")

    {:reply, :ok, %{state | pending: new_pending}}
  end

  @impl true
  def handle_call(:dequeue, _from, state) do
    completed_ids =
      state.completed
      |> Enum.map(& &1.id)
      |> MapSet.new()

    # Find next task with met dependencies
    case find_ready_task(state.pending, completed_ids) do
      nil ->
        {:reply, {:error, :empty}, state}

      {task, remaining_pending} ->
        # Move task to running
        updated_task = Task.start(task)
        new_running = Map.put(state.running, task.id, updated_task)

        Logger.info("Task dequeued: #{task.id}")

        {:reply, {:ok, updated_task}, %{state | pending: remaining_pending, running: new_running}}
    end
  end

  @impl true
  def handle_call({:get_task, task_id}, _from, state) do
    task =
      Enum.find(state.pending, &(&1.id == task_id)) ||
        Map.get(state.running, task_id) ||
        Enum.find(state.completed, &(&1.id == task_id)) ||
        Enum.find(state.failed, &(&1.id == task_id)) ||
        Enum.find(state.cancelled, &(&1.id == task_id))

    case task do
      nil -> {:reply, {:error, :not_found}, state}
      task -> {:reply, {:ok, task}, state}
    end
  end

  @impl true
  def handle_call({:update_task, task_id, updated_task}, _from, state) do
    cond do
      Enum.any?(state.pending, &(&1.id == task_id)) ->
        new_pending =
          Enum.map(state.pending, fn t ->
            if t.id == task_id, do: updated_task, else: t
          end)

        {:reply, :ok, %{state | pending: new_pending}}

      Map.has_key?(state.running, task_id) ->
        new_running = Map.put(state.running, task_id, updated_task)
        {:reply, :ok, %{state | running: new_running}}

      true ->
        {:reply, {:error, :not_found}, state}
    end
  end

  @impl true
  def handle_call({:complete_task, task_id, result}, _from, state) do
    case Map.get(state.running, task_id) do
      nil ->
        {:reply, {:error, :not_found}, state}

      task ->
        completed_task = Task.complete(task, result)
        new_running = Map.delete(state.running, task_id)
        new_completed = [completed_task | state.completed]

        Logger.info("Task completed: #{task_id}")

        {:reply, :ok, %{state | running: new_running, completed: new_completed}}
    end
  end

  @impl true
  def handle_call({:fail_task, task_id, error}, _from, state) do
    case Map.get(state.running, task_id) do
      nil ->
        {:reply, {:error, :not_found}, state}

      task ->
        failed_task = Task.fail(task, error)
        new_running = Map.delete(state.running, task_id)
        new_failed = [failed_task | state.failed]

        Logger.error("Task failed: #{task_id} - #{inspect(error)}")

        {:reply, :ok, %{state | running: new_running, failed: new_failed}}
    end
  end

  @impl true
  def handle_call({:cancel_task, task_id}, _from, state) do
    cond do
      # Cancel from pending
      Enum.any?(state.pending, &(&1.id == task_id)) ->
        {task, new_pending} =
          state.pending
          |> Enum.split_with(&(&1.id == task_id))

        cancelled_task = Task.cancel(List.first(task))
        new_cancelled = [cancelled_task | state.cancelled]

        Logger.info("Task cancelled: #{task_id}")

        {:reply, :ok, %{state | pending: new_pending, cancelled: new_cancelled}}

      # Cancel from running
      Map.has_key?(state.running, task_id) ->
        task = Map.get(state.running, task_id)
        cancelled_task = Task.cancel(task)
        new_running = Map.delete(state.running, task_id)
        new_cancelled = [cancelled_task | state.cancelled]

        Logger.info("Task cancelled: #{task_id}")

        {:reply, :ok, %{state | running: new_running, cancelled: new_cancelled}}

      true ->
        {:reply, {:error, :not_found}, state}
    end
  end

  @impl true
  def handle_call(:status, _from, state) do
    status = %{
      pending: length(state.pending),
      running: map_size(state.running),
      completed: length(state.completed),
      failed: length(state.failed),
      cancelled: length(state.cancelled),
      total:
        length(state.pending) + map_size(state.running) + length(state.completed) +
          length(state.failed) + length(state.cancelled)
    }

    {:reply, status, state}
  end

  @impl true
  def handle_call(:list_all, _from, state) do
    all_tasks = %{
      pending: state.pending,
      running: Map.values(state.running),
      completed: state.completed,
      failed: state.failed,
      cancelled: state.cancelled
    }

    {:reply, all_tasks, state}
  end

  @impl true
  def handle_call(:clear, _from, _state) do
    {:reply, :ok, %__MODULE__{}}
  end

  # Private functions

  defp find_ready_task(pending_tasks, completed_ids) do
    case Enum.find(pending_tasks, &Task.can_execute?(&1, completed_ids)) do
      nil ->
        nil

      task ->
        remaining = Enum.reject(pending_tasks, &(&1.id == task.id))
        {task, remaining}
    end
  end
end
