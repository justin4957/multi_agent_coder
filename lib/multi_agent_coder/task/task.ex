defmodule MultiAgentCoder.Task.Task do
  @moduledoc """
  Represents a coding task that can be allocated to AI providers.

  A task includes all information needed for execution, tracking,
  and result management.

  ## Fields
  - `id`: Unique task identifier
  - `description`: What the task should accomplish
  - `assigned_to`: Provider(s) assigned to this task
  - `status`: Current task status
  - `priority`: Task priority (1-10, higher is more urgent)
  - `dependencies`: List of task IDs this task depends on
  - `result`: Task execution result
  - `created_at`: Task creation timestamp
  - `started_at`: Task start timestamp
  - `completed_at`: Task completion timestamp
  - `metadata`: Additional task metadata

  ## Status Values
  - `:pending` - Task created but not started
  - `:queued` - Task in queue waiting for execution
  - `:running` - Task currently executing
  - `:completed` - Task successfully completed
  - `:failed` - Task execution failed
  - `:cancelled` - Task was cancelled

  ## Examples

      iex> task = Task.new("Implement user authentication")
      %Task{description: "Implement user authentication", status: :pending}

      iex> task |> Task.assign_to(:openai)
      %Task{assigned_to: [:openai], status: :queued}
  """

  @enforce_keys [:id, :description]
  defstruct [
    :id,
    :description,
    :assigned_to,
    :result,
    :created_at,
    :started_at,
    :completed_at,
    :error,
    status: :pending,
    priority: 5,
    dependencies: [],
    metadata: %{}
  ]

  @type status ::
          :pending | :queued | :running | :completed | :failed | :cancelled

  @type t :: %__MODULE__{
          id: String.t(),
          description: String.t(),
          assigned_to: list(atom()) | nil,
          status: status(),
          priority: integer(),
          dependencies: list(String.t()),
          result: term() | nil,
          created_at: DateTime.t(),
          started_at: DateTime.t() | nil,
          completed_at: DateTime.t() | nil,
          error: term() | nil,
          metadata: map()
        }

  @doc """
  Creates a new task with the given description.
  """
  @spec new(String.t(), keyword()) :: t()
  def new(description, opts \\ []) do
    %__MODULE__{
      id: generate_id(),
      description: description,
      status: Keyword.get(opts, :status, :pending),
      priority: Keyword.get(opts, :priority, 5),
      dependencies: Keyword.get(opts, :dependencies, []),
      metadata: Keyword.get(opts, :metadata, %{}),
      created_at: DateTime.utc_now()
    }
  end

  @doc """
  Assigns the task to one or more providers.
  """
  @spec assign_to(t(), atom() | list(atom())) :: t()
  def assign_to(task, provider) when is_atom(provider) do
    assign_to(task, [provider])
  end

  def assign_to(task, providers) when is_list(providers) do
    %{task | assigned_to: providers, status: :queued}
  end

  @doc """
  Marks the task as started.
  """
  @spec start(t()) :: t()
  def start(task) do
    %{task | status: :running, started_at: DateTime.utc_now()}
  end

  @doc """
  Marks the task as completed with a result.
  """
  @spec complete(t(), term()) :: t()
  def complete(task, result) do
    %{
      task
      | status: :completed,
        result: result,
        completed_at: DateTime.utc_now()
    }
  end

  @doc """
  Marks the task as failed with an error.
  """
  @spec fail(t(), term()) :: t()
  def fail(task, error) do
    %{
      task
      | status: :failed,
        error: error,
        completed_at: DateTime.utc_now()
    }
  end

  @doc """
  Cancels the task.
  """
  @spec cancel(t()) :: t()
  def cancel(task) do
    %{task | status: :cancelled, completed_at: DateTime.utc_now()}
  end

  @doc """
  Updates task metadata.
  """
  @spec update_metadata(t(), map()) :: t()
  def update_metadata(task, new_metadata) do
    %{task | metadata: Map.merge(task.metadata, new_metadata)}
  end

  @doc """
  Checks if task can be executed (all dependencies met).
  """
  @spec can_execute?(t(), MapSet.t(String.t())) :: boolean()
  def can_execute?(task, completed_task_ids) do
    Enum.all?(task.dependencies, &MapSet.member?(completed_task_ids, &1))
  end

  @doc """
  Returns elapsed time in milliseconds for the task.
  """
  @spec elapsed_time(t()) :: integer() | nil
  def elapsed_time(%{started_at: nil}), do: nil

  def elapsed_time(%{started_at: started_at, completed_at: nil}) do
    DateTime.diff(DateTime.utc_now(), started_at, :millisecond)
  end

  def elapsed_time(%{started_at: started_at, completed_at: completed_at}) do
    DateTime.diff(completed_at, started_at, :millisecond)
  end

  # Private functions

  defp generate_id do
    "task_#{:erlang.system_time(:nanosecond)}_#{:rand.uniform(10000)}"
  end
end
