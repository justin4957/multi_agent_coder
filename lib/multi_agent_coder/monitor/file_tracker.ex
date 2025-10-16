defmodule MultiAgentCoder.Monitor.FileTracker do
  @moduledoc """
  Tracks file operations performed by providers.

  Monitors which files are being created, modified, or deleted
  by each provider, and detects potential conflicts when multiple
  providers access the same files.

  ## Features
  - Track file create/modify/delete operations
  - Associate file operations with specific providers
  - Detect concurrent file access conflicts
  - Calculate file-level statistics

  ## Events
  Subscribes to:
  - `provider:file_created`
  - `provider:file_modified`
  - `provider:file_deleted`
  """

  use GenServer
  require Logger

  defstruct [
    :operations,
    :provider_files,
    :file_providers,
    :conflicts
  ]

  @type operation :: :create | :modify | :delete
  @type file_operation :: %{
          provider: atom(),
          file: String.t(),
          operation: operation(),
          timestamp: integer(),
          lines_changed: integer() | nil
        }

  @type t :: %__MODULE__{
          operations: list(file_operation()),
          provider_files: %{atom() => MapSet.t(String.t())},
          file_providers: %{String.t() => MapSet.t(atom())},
          conflicts: list({String.t(), list(atom())})
        }

  # Public API

  @doc """
  Starts the file tracker GenServer.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Records a file operation by a provider.
  """
  @spec track_operation(atom(), String.t(), operation(), keyword()) :: :ok
  def track_operation(provider, file_path, operation, opts \\ []) do
    GenServer.cast(__MODULE__, {:track_operation, provider, file_path, operation, opts})
  end

  @doc """
  Gets all file operations for a specific provider.
  """
  @spec get_provider_operations(atom()) :: list(file_operation())
  def get_provider_operations(provider) do
    GenServer.call(__MODULE__, {:get_provider_operations, provider})
  end

  @doc """
  Gets all providers that have accessed a specific file.
  """
  @spec get_file_providers(String.t()) :: list(atom())
  def get_file_providers(file_path) do
    GenServer.call(__MODULE__, {:get_file_providers, file_path})
  end

  @doc """
  Gets all detected conflicts (files accessed by multiple providers).
  """
  @spec get_conflicts() :: list({String.t(), list(atom())})
  def get_conflicts do
    GenServer.call(__MODULE__, :get_conflicts)
  end

  @doc """
  Gets file operation statistics.
  """
  @spec get_stats() :: map()
  def get_stats do
    GenServer.call(__MODULE__, :get_stats)
  end

  @doc """
  Clears all tracked operations and resets state.
  """
  @spec reset() :: :ok
  def reset do
    GenServer.call(__MODULE__, :reset)
  end

  # GenServer Callbacks

  @impl true
  def init(_opts) do
    state = %__MODULE__{
      operations: [],
      provider_files: %{},
      file_providers: %{},
      conflicts: []
    }

    {:ok, state}
  end

  @impl true
  def handle_cast({:track_operation, provider, file_path, operation, opts}, state) do
    lines_changed = Keyword.get(opts, :lines_changed)

    file_operation = %{
      provider: provider,
      file: file_path,
      operation: operation,
      timestamp: System.monotonic_time(:millisecond),
      lines_changed: lines_changed
    }

    # Add to operations list
    updated_operations = [file_operation | state.operations]

    # Update provider_files tracking
    provider_files_set = Map.get(state.provider_files, provider, MapSet.new())

    updated_provider_files =
      Map.put(state.provider_files, provider, MapSet.put(provider_files_set, file_path))

    # Update file_providers tracking
    file_providers_set = Map.get(state.file_providers, file_path, MapSet.new())

    updated_file_providers =
      Map.put(state.file_providers, file_path, MapSet.put(file_providers_set, provider))

    # Check for conflicts (file accessed by multiple providers)
    updated_conflicts =
      if MapSet.size(updated_file_providers[file_path]) > 1 do
        providers_list = MapSet.to_list(updated_file_providers[file_path])

        if Enum.any?(state.conflicts, fn {f, _} -> f == file_path end) do
          # Update existing conflict
          Enum.map(state.conflicts, fn
            {^file_path, _} -> {file_path, providers_list}
            conflict -> conflict
          end)
        else
          # Add new conflict
          [{file_path, providers_list} | state.conflicts]
        end
      else
        state.conflicts
      end

    Logger.debug(
      "FileTracker: #{provider} #{operation} #{file_path}" <>
        if(lines_changed, do: " (#{lines_changed} lines)", else: "")
    )

    new_state = %{
      state
      | operations: updated_operations,
        provider_files: updated_provider_files,
        file_providers: updated_file_providers,
        conflicts: updated_conflicts
    }

    {:noreply, new_state}
  end

  @impl true
  def handle_call({:get_provider_operations, provider}, _from, state) do
    operations =
      state.operations
      |> Enum.filter(&(&1.provider == provider))
      |> Enum.reverse()

    {:reply, operations, state}
  end

  @impl true
  def handle_call({:get_file_providers, file_path}, _from, state) do
    providers =
      state.file_providers
      |> Map.get(file_path, MapSet.new())
      |> MapSet.to_list()

    {:reply, providers, state}
  end

  @impl true
  def handle_call(:get_conflicts, _from, state) do
    {:reply, state.conflicts, state}
  end

  @impl true
  def handle_call(:get_stats, _from, state) do
    stats = calculate_stats(state)
    {:reply, stats, state}
  end

  @impl true
  def handle_call(:reset, _from, _state) do
    new_state = %__MODULE__{
      operations: [],
      provider_files: %{},
      file_providers: %{},
      conflicts: []
    }

    {:reply, :ok, new_state}
  end

  # Private Functions

  defp calculate_stats(state) do
    operations_by_type =
      state.operations
      |> Enum.group_by(& &1.operation)
      |> Map.new(fn {op, ops} -> {op, length(ops)} end)

    operations_by_provider =
      state.operations
      |> Enum.group_by(& &1.provider)
      |> Map.new(fn {provider, ops} -> {provider, length(ops)} end)

    total_lines_changed =
      state.operations
      |> Enum.map(& &1.lines_changed)
      |> Enum.reject(&is_nil/1)
      |> Enum.sum()

    %{
      total_operations: length(state.operations),
      operations_by_type: operations_by_type,
      operations_by_provider: operations_by_provider,
      total_files_touched: map_size(state.file_providers),
      total_providers: map_size(state.provider_files),
      conflicts: length(state.conflicts),
      total_lines_changed: total_lines_changed
    }
  end
end
