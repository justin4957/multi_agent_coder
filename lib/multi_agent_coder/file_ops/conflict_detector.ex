defmodule MultiAgentCoder.FileOps.ConflictDetector do
  @moduledoc """
  Detects and manages file access conflicts between providers.

  Identifies when multiple providers attempt to modify the same file
  or same lines within a file, and provides conflict resolution strategies.
  """

  use GenServer
  require Logger

  alias MultiAgentCoder.FileOps.{Diff, History, Ownership}

  defstruct [
    :pending_operations,
    :active_operations,
    :conflicts,
    :resolutions
  ]

  @type conflict_type :: :file_level | :line_level

  @type conflict :: %{
          id: String.t(),
          file: String.t(),
          providers: list(atom()),
          type: conflict_type(),
          details: map(),
          detected_at: integer(),
          resolved: boolean(),
          resolution: map() | nil
        }

  @type pending_operation :: %{
          provider: atom(),
          file: String.t(),
          operation: :create | :modify | :delete,
          line_ranges: list({non_neg_integer(), non_neg_integer()}) | nil
        }

  @type t :: %__MODULE__{
          pending_operations: list(pending_operation()),
          active_operations: %{String.t() => list(atom())},
          conflicts: list(conflict()),
          resolutions: %{String.t() => map()}
        }

  # Public API

  @doc """
  Starts the conflict detector GenServer.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Checks if an operation would cause a conflict.

  Returns `:ok` if safe to proceed, or `{:conflict, details}` if conflict detected.
  """
  @spec check_operation(atom(), String.t(), :create | :modify | :delete, keyword()) ::
          :ok | {:conflict, conflict()}
  def check_operation(provider, file_path, operation, opts \\ []) do
    GenServer.call(__MODULE__, {:check_operation, provider, file_path, operation, opts})
  end

  @doc """
  Registers the start of a file operation.

  Should be called before modifying a file.
  """
  @spec start_operation(atom(), String.t(), :create | :modify | :delete, keyword()) :: :ok
  def start_operation(provider, file_path, operation, opts \\ []) do
    GenServer.cast(__MODULE__, {:start_operation, provider, file_path, operation, opts})
  end

  @doc """
  Registers the completion of a file operation.

  Should be called after successfully modifying a file.
  """
  @spec complete_operation(atom(), String.t()) :: :ok
  def complete_operation(provider, file_path) do
    GenServer.cast(__MODULE__, {:complete_operation, provider, file_path})
  end

  @doc """
  Gets all detected conflicts.
  """
  @spec get_conflicts() :: list(conflict())
  def get_conflicts do
    GenServer.call(__MODULE__, :get_conflicts)
  end

  @doc """
  Gets unresolved conflicts only.
  """
  @spec get_unresolved_conflicts() :: list(conflict())
  def get_unresolved_conflicts do
    GenServer.call(__MODULE__, :get_unresolved_conflicts)
  end

  @doc """
  Gets conflicts for a specific file.
  """
  @spec get_file_conflicts(String.t()) :: list(conflict())
  def get_file_conflicts(file_path) do
    GenServer.call(__MODULE__, {:get_file_conflicts, file_path})
  end

  @doc """
  Resolves a conflict with a specific resolution strategy.

  Resolution strategies:
  - `:accept_first` - Accept changes from the first provider
  - `:accept_last` - Accept changes from the last provider
  - `:merge` - Attempt to merge both changes
  - `:manual` - User will manually resolve
  """
  @spec resolve_conflict(String.t(), atom(), keyword()) :: :ok | {:error, :not_found}
  def resolve_conflict(conflict_id, strategy, opts \\ []) do
    GenServer.call(__MODULE__, {:resolve_conflict, conflict_id, strategy, opts})
  end

  @doc """
  Pauses all operations for providers involved in a conflict.
  """
  @spec pause_conflicting_providers(String.t()) :: :ok
  def pause_conflicting_providers(conflict_id) do
    GenServer.cast(__MODULE__, {:pause_conflicting_providers, conflict_id})
  end

  @doc """
  Gets statistics about conflicts.
  """
  @spec get_stats() :: map()
  def get_stats do
    GenServer.call(__MODULE__, :get_stats)
  end

  @doc """
  Clears all conflict data.
  """
  @spec reset() :: :ok
  def reset do
    GenServer.call(__MODULE__, :reset)
  end

  # GenServer Callbacks

  @impl true
  def init(_opts) do
    state = %__MODULE__{
      pending_operations: [],
      active_operations: %{},
      conflicts: [],
      resolutions: %{}
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:check_operation, provider, file_path, operation, opts}, _from, state) do
    line_ranges = Keyword.get(opts, :line_ranges)

    # Check if file is locked by another provider
    locked_by = Ownership.get_lock_holder(file_path)
    file_level_conflict? = locked_by != nil && locked_by != provider

    # Check if another provider is actively working on the file
    active_providers = Map.get(state.active_operations, file_path, [])
    concurrent_access? = provider not in active_providers && length(active_providers) > 0

    # Check for line-level conflicts if line ranges provided
    line_conflict? =
      if line_ranges && concurrent_access? do
        detect_line_conflicts(file_path, provider, line_ranges, state)
      else
        false
      end

    result =
      cond do
        file_level_conflict? ->
          conflict =
            create_conflict(
              file_path,
              [locked_by, provider],
              :file_level,
              %{locked_by: locked_by, reason: "File is locked"}
            )

          {:conflict, conflict}

        line_conflict? ->
          conflict =
            create_conflict(
              file_path,
              [provider | active_providers],
              :line_level,
              %{line_ranges: line_ranges, reason: "Overlapping line modifications"}
            )

          {:conflict, conflict}

        concurrent_access? && operation == :create ->
          conflict =
            create_conflict(
              file_path,
              [provider | active_providers],
              :file_level,
              %{reason: "Multiple providers trying to create same file"}
            )

          {:conflict, conflict}

        true ->
          :ok
      end

    case result do
      {:conflict, conflict} ->
        new_conflicts = [conflict | state.conflicts]
        Logger.warning("Conflict detected: #{inspect(conflict)}")
        {:reply, result, %{state | conflicts: new_conflicts}}

      :ok ->
        {:reply, :ok, state}
    end
  end

  @impl true
  def handle_call(:get_conflicts, _from, state) do
    {:reply, state.conflicts, state}
  end

  @impl true
  def handle_call(:get_unresolved_conflicts, _from, state) do
    unresolved = Enum.filter(state.conflicts, &(!&1.resolved))
    {:reply, unresolved, state}
  end

  @impl true
  def handle_call({:get_file_conflicts, file_path}, _from, state) do
    conflicts = Enum.filter(state.conflicts, &(&1.file == file_path))
    {:reply, conflicts, state}
  end

  @impl true
  def handle_call({:resolve_conflict, conflict_id, strategy, opts}, _from, state) do
    case Enum.find_index(state.conflicts, &(&1.id == conflict_id)) do
      nil ->
        {:reply, {:error, :not_found}, state}

      index ->
        conflict = Enum.at(state.conflicts, index)

        resolution = %{
          strategy: strategy,
          resolved_at: System.monotonic_time(:millisecond),
          resolved_by: Keyword.get(opts, :resolved_by, :system),
          notes: Keyword.get(opts, :notes)
        }

        updated_conflict = %{conflict | resolved: true, resolution: resolution}
        new_conflicts = List.replace_at(state.conflicts, index, updated_conflict)
        new_resolutions = Map.put(state.resolutions, conflict_id, resolution)

        Logger.info("Conflict #{conflict_id} resolved using strategy: #{strategy}")

        {:reply, :ok, %{state | conflicts: new_conflicts, resolutions: new_resolutions}}
    end
  end

  @impl true
  def handle_call(:get_stats, _from, state) do
    stats = %{
      total_conflicts: length(state.conflicts),
      unresolved_conflicts: Enum.count(state.conflicts, &(!&1.resolved)),
      resolved_conflicts: Enum.count(state.conflicts, & &1.resolved),
      conflicts_by_type: count_by_type(state.conflicts),
      active_operations: map_size(state.active_operations)
    }

    {:reply, stats, state}
  end

  @impl true
  def handle_call(:reset, _from, _state) do
    new_state = %__MODULE__{
      pending_operations: [],
      active_operations: %{},
      conflicts: [],
      resolutions: %{}
    }

    {:reply, :ok, new_state}
  end

  @impl true
  def handle_cast({:start_operation, provider, file_path, operation, _opts}, state) do
    active = Map.get(state.active_operations, file_path, [])
    new_active = [provider | active] |> Enum.uniq()
    new_active_operations = Map.put(state.active_operations, file_path, new_active)

    Logger.debug("ConflictDetector: #{provider} started #{operation} on #{file_path}")

    {:noreply, %{state | active_operations: new_active_operations}}
  end

  @impl true
  def handle_cast({:complete_operation, provider, file_path}, state) do
    active = Map.get(state.active_operations, file_path, [])
    new_active = List.delete(active, provider)

    new_active_operations =
      if new_active == [] do
        Map.delete(state.active_operations, file_path)
      else
        Map.put(state.active_operations, file_path, new_active)
      end

    Logger.debug("ConflictDetector: #{provider} completed operation on #{file_path}")

    {:noreply, %{state | active_operations: new_active_operations}}
  end

  @impl true
  def handle_cast({:pause_conflicting_providers, conflict_id}, state) do
    conflict = Enum.find(state.conflicts, &(&1.id == conflict_id))

    if conflict do
      Enum.each(conflict.providers, fn provider ->
        Phoenix.PubSub.broadcast(
          MultiAgentCoder.PubSub,
          "agent:#{provider}",
          {:pause, :conflict_detected, conflict}
        )
      end)

      Logger.info(
        "Paused providers involved in conflict #{conflict_id}: #{inspect(conflict.providers)}"
      )
    end

    {:noreply, state}
  end

  # Private Functions

  defp create_conflict(file_path, providers, type, details) do
    %{
      id: generate_conflict_id(),
      file: file_path,
      providers: providers,
      type: type,
      details: details,
      detected_at: System.monotonic_time(:millisecond),
      resolved: false,
      resolution: nil
    }
  end

  defp generate_conflict_id do
    :crypto.strong_rand_bytes(8) |> Base.url_encode64(padding: false)
  end

  defp detect_line_conflicts(_file_path, _provider, _line_ranges, _state) do
    # Simplified implementation - in production, would analyze actual line ranges
    # being modified by concurrent providers
    false
  end

  defp count_by_type(conflicts) do
    conflicts
    |> Enum.group_by(& &1.type)
    |> Map.new(fn {type, cs} -> {type, length(cs)} end)
  end
end
