defmodule MultiAgentCoder.FileOps.Tracker do
  @moduledoc """
  Comprehensive file operations tracking system.

  Coordinates between Ownership, History, and ConflictDetector to provide
  a complete view of file operations across multiple providers. This is the
  main entry point for file operation tracking.

  ## Features
  - Track all file operations (create, read, write, delete) per provider
  - Detect concurrent file access and potential conflicts
  - Maintain file ownership and modification history
  - Provide detailed diffs and change visualization
  - Support rollback of provider-specific changes

  ## Usage

      # Track a file creation
      Tracker.track_file_operation(:openai, "lib/my_file.ex", :create,
        after_content: "defmodule MyFile do\\nend"
      )

      # Get file status
      Tracker.get_file_status("lib/my_file.ex")

      # List all tracked files
      Tracker.list_files()
  """

  use GenServer
  require Logger

  alias MultiAgentCoder.FileOps.{ConflictDetector, Diff, History, Ownership}
  alias MultiAgentCoder.Monitor.FileTracker

  defstruct [
    :file_statuses,
    :provider_activity,
    :snapshots
  ]

  @type file_status :: :new | :modified | :deleted | :active | :locked | :conflict

  @type file_info :: %{
          path: String.t(),
          status: file_status(),
          owner: atom() | nil,
          contributors: list(atom()),
          current_editor: atom() | nil,
          locked_by: atom() | nil,
          has_conflicts: boolean(),
          last_modified: integer(),
          lines: non_neg_integer()
        }

  @type t :: %__MODULE__{
          file_statuses: %{String.t() => file_status()},
          provider_activity: %{atom() => list(String.t())},
          snapshots: %{String.t() => String.t()}
        }

  # Public API

  @doc """
  Starts the file operations tracker GenServer.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Tracks a file operation by a provider.

  ## Options
  - `:before_content` - Content before the operation
  - `:after_content` - Content after the operation
  - `:lines_changed` - Number of lines changed
  - `:metadata` - Additional metadata to store

  ## Examples

      Tracker.track_file_operation(:openai, "lib/file.ex", :create,
        after_content: "defmodule File do\\nend"
      )

      Tracker.track_file_operation(:anthropic, "lib/file.ex", :modify,
        before_content: old_content,
        after_content: new_content
      )
  """
  @spec track_file_operation(atom(), String.t(), :create | :modify | :delete, keyword()) ::
          :ok | {:error, term()}
  def track_file_operation(provider, file_path, operation, opts \\ []) do
    GenServer.call(__MODULE__, {:track_operation, provider, file_path, operation, opts})
  end

  @doc """
  Gets comprehensive status information for a file.
  """
  @spec get_file_status(String.t()) :: file_info() | nil
  def get_file_status(file_path) do
    GenServer.call(__MODULE__, {:get_file_status, file_path})
  end

  @doc """
  Lists all tracked files with their statuses.

  ## Options
  - `:status` - Filter by status (:new, :modified, :active, etc.)
  - `:provider` - Filter by provider
  - `:conflicts_only` - Show only files with conflicts (boolean)
  """
  @spec list_files(keyword()) :: list(file_info())
  def list_files(opts \\ []) do
    GenServer.call(__MODULE__, {:list_files, opts})
  end

  @doc """
  Gets all files currently being worked on (active).
  """
  @spec get_active_files() :: list({String.t(), atom()})
  def get_active_files do
    GenServer.call(__MODULE__, :get_active_files)
  end

  @doc """
  Gets all files with conflicts.
  """
  @spec get_conflicted_files() :: list(file_info())
  def get_conflicted_files do
    GenServer.call(__MODULE__, :get_conflicted_files)
  end

  @doc """
  Gets the diff for a specific file.

  Returns the diff between the current version and the previous version.
  """
  @spec get_file_diff(String.t()) :: Diff.diff() | {:error, :not_found}
  def get_file_diff(file_path) do
    history = History.get_file_history(file_path)

    case history do
      [latest | _] -> {:ok, latest.diff}
      [] -> {:error, :not_found}
    end
  end

  @doc """
  Gets the complete modification history for a file.
  """
  @spec get_file_history(String.t()) :: list(History.history_entry())
  def get_file_history(file_path) do
    History.get_file_history(file_path)
  end

  @doc """
  Reverts a file to a previous version by entry ID.
  """
  @spec revert_file(String.t(), String.t()) :: {:ok, String.t()} | {:error, term()}
  def revert_file(file_path, entry_id) do
    History.revert_to_version(file_path, entry_id)
  end

  @doc """
  Reverts all changes made by a specific provider to a file.
  """
  @spec revert_provider_changes(String.t(), atom()) :: {:ok, String.t() | nil} | {:error, term()}
  def revert_provider_changes(file_path, provider) do
    History.revert_provider_changes(file_path, provider)
  end

  @doc """
  Locks a file for exclusive access.
  """
  @spec lock_file(String.t(), atom()) :: :ok | {:error, :locked}
  def lock_file(file_path, provider) do
    Ownership.lock_file(file_path, provider)
  end

  @doc """
  Unlocks a file.
  """
  @spec unlock_file(String.t(), atom()) :: :ok | {:error, :not_locked | :wrong_owner}
  def unlock_file(file_path, provider) do
    Ownership.unlock_file(file_path, provider)
  end

  @doc """
  Gets comprehensive statistics about file operations.
  """
  @spec get_stats() :: map()
  def get_stats do
    GenServer.call(__MODULE__, :get_stats)
  end

  @doc """
  Resets all file operation tracking data.
  """
  @spec reset() :: :ok
  def reset do
    GenServer.call(__MODULE__, :reset)
  end

  # GenServer Callbacks

  @impl true
  def init(_opts) do
    state = %__MODULE__{
      file_statuses: %{},
      provider_activity: %{},
      snapshots: %{}
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:track_operation, provider, file_path, operation, opts}, _from, state) do
    before_content = Keyword.get(opts, :before_content)
    after_content = Keyword.get(opts, :after_content)
    lines_changed = Keyword.get(opts, :lines_changed)
    metadata = Keyword.get(opts, :metadata, %{})

    # Check for conflicts before proceeding
    case ConflictDetector.check_operation(provider, file_path, operation) do
      :ok ->
        # Start the operation
        ConflictDetector.start_operation(provider, file_path, operation)

        # Handle ownership
        case operation do
          :create ->
            Ownership.assign_owner(file_path, provider)

          :modify ->
            Ownership.add_contributor(file_path, provider)

          :delete ->
            :ok
        end

        # Record in history
        History.record(file_path, provider, operation, before_content, after_content,
          metadata: metadata
        )

        # Track in existing FileTracker for dashboard integration
        FileTracker.track_operation(provider, file_path, operation, lines_changed: lines_changed)

        # Update our state
        new_status = determine_status(operation)
        new_file_statuses = Map.put(state.file_statuses, file_path, new_status)

        provider_files = Map.get(state.provider_activity, provider, [])
        new_provider_files = [file_path | provider_files] |> Enum.uniq()
        new_provider_activity = Map.put(state.provider_activity, provider, new_provider_files)

        new_snapshots =
          if after_content do
            Map.put(state.snapshots, file_path, after_content)
          else
            state.snapshots
          end

        new_state = %{
          state
          | file_statuses: new_file_statuses,
            provider_activity: new_provider_activity,
            snapshots: new_snapshots
        }

        # Complete the operation
        ConflictDetector.complete_operation(provider, file_path)

        Logger.info("Tracked #{operation} of #{file_path} by #{provider}")

        {:reply, :ok, new_state}

      {:conflict, conflict} ->
        Logger.warning("Operation blocked due to conflict: #{inspect(conflict)}")
        {:reply, {:error, {:conflict, conflict}}, state}
    end
  end

  @impl true
  def handle_call({:get_file_status, file_path}, _from, state) do
    status = build_file_info(file_path, state)
    {:reply, status, state}
  end

  @impl true
  def handle_call({:list_files, opts}, _from, state) do
    files =
      state.file_statuses
      |> Map.keys()
      |> Enum.map(&build_file_info(&1, state))
      |> apply_filters(opts)

    {:reply, files, state}
  end

  @impl true
  def handle_call(:get_active_files, _from, state) do
    active =
      state.provider_activity
      |> Enum.flat_map(fn {provider, files} ->
        Enum.map(files, &{&1, provider})
      end)
      |> Enum.uniq()

    {:reply, active, state}
  end

  @impl true
  def handle_call(:get_conflicted_files, _from, state) do
    conflicts = ConflictDetector.get_unresolved_conflicts()
    conflicted_paths = Enum.map(conflicts, & &1.file) |> Enum.uniq()

    files =
      conflicted_paths
      |> Enum.map(&build_file_info(&1, state))

    {:reply, files, state}
  end

  @impl true
  def handle_call(:get_stats, _from, state) do
    history_stats = History.get_stats()
    conflict_stats = ConflictDetector.get_stats()

    stats = %{
      total_files: map_size(state.file_statuses),
      files_by_status: count_by_status(state.file_statuses),
      active_providers: map_size(state.provider_activity),
      history: history_stats,
      conflicts: conflict_stats
    }

    {:reply, stats, state}
  end

  @impl true
  def handle_call(:reset, _from, _state) do
    # Reset all subsystems
    Ownership.reset()
    History.reset()
    ConflictDetector.reset()

    # Reset FileTracker only if it's running
    if Process.whereis(FileTracker) do
      FileTracker.reset()
    end

    new_state = %__MODULE__{
      file_statuses: %{},
      provider_activity: %{},
      snapshots: %{}
    }

    {:reply, :ok, new_state}
  end

  # Private Functions

  defp determine_status(:create), do: :new
  defp determine_status(:modify), do: :modified
  defp determine_status(:delete), do: :deleted

  defp build_file_info(file_path, state) do
    owner = Ownership.get_owner(file_path)
    contributors = Ownership.get_contributors(file_path)
    locked_by = Ownership.get_lock_holder(file_path)
    conflicts = ConflictDetector.get_file_conflicts(file_path)
    has_conflicts = length(conflicts) > 0

    history = History.get_file_history(file_path)

    last_modified =
      case history do
        [latest | _] -> latest.timestamp
        [] -> 0
      end

    current_content = Map.get(state.snapshots, file_path, "")
    lines = length(String.split(current_content, "\n"))

    status = Map.get(state.file_statuses, file_path, :unknown)

    status =
      cond do
        has_conflicts -> :conflict
        locked_by != nil -> :locked
        true -> status
      end

    %{
      path: file_path,
      status: status,
      owner: owner,
      contributors: contributors,
      current_editor: nil,
      locked_by: locked_by,
      has_conflicts: has_conflicts,
      last_modified: last_modified,
      lines: lines
    }
  end

  defp apply_filters(files, opts) do
    files
    |> filter_by_status(Keyword.get(opts, :status))
    |> filter_by_provider(Keyword.get(opts, :provider))
    |> filter_conflicts_only(Keyword.get(opts, :conflicts_only, false))
  end

  defp filter_by_status(files, nil), do: files
  defp filter_by_status(files, status), do: Enum.filter(files, &(&1.status == status))

  defp filter_by_provider(files, nil), do: files

  defp filter_by_provider(files, provider) do
    Enum.filter(files, fn file ->
      file.owner == provider || provider in file.contributors
    end)
  end

  defp filter_conflicts_only(files, false), do: files
  defp filter_conflicts_only(files, true), do: Enum.filter(files, & &1.has_conflicts)

  defp count_by_status(file_statuses) do
    file_statuses
    |> Map.values()
    |> Enum.frequencies()
  end
end
