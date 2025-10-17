defmodule MultiAgentCoder.FileOps.History do
  @moduledoc """
  Maintains complete change history for files.

  Stores snapshots of file content before and after each modification,
  enabling viewing of diffs between versions and reverting changes
  by specific providers.
  """

  use GenServer
  require Logger

  alias MultiAgentCoder.FileOps.Diff

  defstruct [
    :entries,
    :file_versions
  ]

  @type operation :: :create | :modify | :delete

  @type history_entry :: %{
          id: String.t(),
          file: String.t(),
          provider: atom(),
          operation: operation(),
          timestamp: integer(),
          before_content: String.t() | nil,
          after_content: String.t() | nil,
          diff: Diff.diff(),
          lines_changed: non_neg_integer(),
          metadata: map()
        }

  @type t :: %__MODULE__{
          entries: list(history_entry()),
          file_versions: %{String.t() => list(history_entry())}
        }

  # Public API

  @doc """
  Starts the history tracker GenServer.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Records a file operation in history.

  Stores before/after snapshots and generates a diff.
  """
  @spec record(String.t(), atom(), operation(), String.t() | nil, String.t() | nil, keyword()) ::
          :ok
  def record(file_path, provider, operation, before_content, after_content, opts \\ []) do
    GenServer.cast(
      __MODULE__,
      {:record, file_path, provider, operation, before_content, after_content, opts}
    )
  end

  @doc """
  Gets the complete history for a file.

  Returns entries in reverse chronological order (most recent first).
  """
  @spec get_file_history(String.t()) :: list(history_entry())
  def get_file_history(file_path) do
    GenServer.call(__MODULE__, {:get_file_history, file_path})
  end

  @doc """
  Gets all history entries for a specific provider.
  """
  @spec get_provider_history(atom()) :: list(history_entry())
  def get_provider_history(provider) do
    GenServer.call(__MODULE__, {:get_provider_history, provider})
  end

  @doc """
  Gets a specific history entry by ID.
  """
  @spec get_entry(String.t()) :: history_entry() | nil
  def get_entry(entry_id) do
    GenServer.call(__MODULE__, {:get_entry, entry_id})
  end

  @doc """
  Gets the diff between two versions of a file.

  Versions are identified by history entry IDs.
  """
  @spec get_diff_between(String.t(), String.t()) :: Diff.diff() | {:error, :not_found}
  def get_diff_between(entry_id_1, entry_id_2) do
    GenServer.call(__MODULE__, {:get_diff_between, entry_id_1, entry_id_2})
  end

  @doc """
  Gets the current (latest) version of a file from history.

  Returns `nil` if no history exists for the file.
  """
  @spec get_current_version(String.t()) :: String.t() | nil
  def get_current_version(file_path) do
    GenServer.call(__MODULE__, {:get_current_version, file_path})
  end

  @doc """
  Reverts a file to a previous version.

  Returns the content at that version.
  """
  @spec revert_to_version(String.t(), String.t()) :: {:ok, String.t()} | {:error, :not_found}
  def revert_to_version(file_path, entry_id) do
    GenServer.call(__MODULE__, {:revert_to_version, file_path, entry_id})
  end

  @doc """
  Removes all changes by a specific provider for a file.

  Reconstructs the file as if the provider never modified it.
  This is a complex operation that may not always be possible if
  other providers have built on top of the changes.
  """
  @spec revert_provider_changes(String.t(), atom()) :: {:ok, String.t()} | {:error, :not_possible}
  def revert_provider_changes(file_path, provider) do
    GenServer.call(__MODULE__, {:revert_provider_changes, file_path, provider})
  end

  @doc """
  Gets statistics about the history.
  """
  @spec get_stats() :: map()
  def get_stats do
    GenServer.call(__MODULE__, :get_stats)
  end

  @doc """
  Clears all history.
  """
  @spec reset() :: :ok
  def reset do
    GenServer.call(__MODULE__, :reset)
  end

  # GenServer Callbacks

  @impl true
  def init(_opts) do
    state = %__MODULE__{
      entries: [],
      file_versions: %{}
    }

    {:ok, state}
  end

  @impl true
  def handle_cast(
        {:record, file_path, provider, operation, before_content, after_content, opts},
        state
      ) do
    entry_id = generate_entry_id()
    metadata = Keyword.get(opts, :metadata, %{})

    diff = Diff.generate(file_path, before_content, after_content)
    lines_changed = diff.stats.additions + diff.stats.deletions + diff.stats.modifications

    entry = %{
      id: entry_id,
      file: file_path,
      provider: provider,
      operation: operation,
      timestamp: System.monotonic_time(:millisecond),
      before_content: before_content,
      after_content: after_content,
      diff: diff,
      lines_changed: lines_changed,
      metadata: metadata
    }

    new_entries = [entry | state.entries]

    file_history = Map.get(state.file_versions, file_path, [])
    new_file_history = [entry | file_history]
    new_file_versions = Map.put(state.file_versions, file_path, new_file_history)

    Logger.debug(
      "History: recorded #{operation} of #{file_path} by #{provider} (#{lines_changed} lines changed)"
    )

    {:noreply, %{state | entries: new_entries, file_versions: new_file_versions}}
  end

  @impl true
  def handle_call({:get_file_history, file_path}, _from, state) do
    history = Map.get(state.file_versions, file_path, [])
    {:reply, history, state}
  end

  @impl true
  def handle_call({:get_provider_history, provider}, _from, state) do
    history =
      state.entries
      |> Enum.filter(&(&1.provider == provider))
      |> Enum.reverse()

    {:reply, history, state}
  end

  @impl true
  def handle_call({:get_entry, entry_id}, _from, state) do
    entry = Enum.find(state.entries, &(&1.id == entry_id))
    {:reply, entry, state}
  end

  @impl true
  def handle_call({:get_diff_between, entry_id_1, entry_id_2}, _from, state) do
    entry1 = Enum.find(state.entries, &(&1.id == entry_id_1))
    entry2 = Enum.find(state.entries, &(&1.id == entry_id_2))

    result =
      case {entry1, entry2} do
        {%{after_content: content1, file: file}, %{after_content: content2, file: file}} ->
          Diff.generate(file, content1, content2)

        _ ->
          {:error, :not_found}
      end

    {:reply, result, state}
  end

  @impl true
  def handle_call({:get_current_version, file_path}, _from, state) do
    version =
      case Map.get(state.file_versions, file_path, []) do
        [latest | _] -> latest.after_content
        [] -> nil
      end

    {:reply, version, state}
  end

  @impl true
  def handle_call({:revert_to_version, file_path, entry_id}, _from, state) do
    result =
      state.file_versions
      |> Map.get(file_path, [])
      |> Enum.find(&(&1.id == entry_id))
      |> case do
        nil -> {:error, :not_found}
        entry -> {:ok, entry.after_content}
      end

    {:reply, result, state}
  end

  @impl true
  def handle_call({:revert_provider_changes, file_path, provider}, _from, state) do
    history = Map.get(state.file_versions, file_path, [])

    # Get all entries not by this provider, in reverse order (oldest first)
    entries_without_provider =
      history
      |> Enum.reverse()
      |> Enum.reject(&(&1.provider == provider))

    result =
      case entries_without_provider do
        [] ->
          # Provider created the file, reverting means deleting
          {:ok, nil}

        entries ->
          # Reconstruct from remaining entries
          latest = List.last(entries)
          {:ok, latest.after_content}
      end

    {:reply, result, state}
  end

  @impl true
  def handle_call(:get_stats, _from, state) do
    stats = %{
      total_entries: length(state.entries),
      files_tracked: map_size(state.file_versions),
      operations_by_type: count_by_operation(state.entries),
      operations_by_provider: count_by_provider(state.entries),
      total_lines_changed: sum_lines_changed(state.entries)
    }

    {:reply, stats, state}
  end

  @impl true
  def handle_call(:reset, _from, _state) do
    new_state = %__MODULE__{
      entries: [],
      file_versions: %{}
    }

    {:reply, :ok, new_state}
  end

  # Private Functions

  defp generate_entry_id do
    :crypto.strong_rand_bytes(8) |> Base.url_encode64(padding: false)
  end

  defp count_by_operation(entries) do
    entries
    |> Enum.group_by(& &1.operation)
    |> Map.new(fn {op, ops} -> {op, length(ops)} end)
  end

  defp count_by_provider(entries) do
    entries
    |> Enum.group_by(& &1.provider)
    |> Map.new(fn {provider, ops} -> {provider, length(ops)} end)
  end

  defp sum_lines_changed(entries) do
    Enum.reduce(entries, 0, fn entry, acc -> acc + entry.lines_changed end)
  end
end
