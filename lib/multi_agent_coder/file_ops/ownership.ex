defmodule MultiAgentCoder.FileOps.Ownership do
  @moduledoc """
  Tracks file ownership and contributors.

  Manages which provider "owns" each file (primary author) and tracks
  all contributors (providers that have modified the file). Supports
  file locking to prevent concurrent modifications.
  """

  use GenServer
  require Logger

  defstruct [
    :owners,
    :contributors,
    :locks,
    :lock_timestamps
  ]

  @type t :: %__MODULE__{
          owners: %{String.t() => atom()},
          contributors: %{String.t() => MapSet.t(atom())},
          locks: %{String.t() => atom()},
          lock_timestamps: %{String.t() => integer()}
        }

  # Public API

  @doc """
  Starts the ownership tracker GenServer.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Assigns ownership of a file to a provider.

  The first provider to create a file becomes its owner.
  """
  @spec assign_owner(String.t(), atom()) :: :ok | {:error, :already_owned}
  def assign_owner(file_path, provider) do
    GenServer.call(__MODULE__, {:assign_owner, file_path, provider})
  end

  @doc """
  Adds a provider as a contributor to a file.

  Contributors are providers that have modified but don't own the file.
  """
  @spec add_contributor(String.t(), atom()) :: :ok
  def add_contributor(file_path, provider) do
    GenServer.cast(__MODULE__, {:add_contributor, file_path, provider})
  end

  @doc """
  Gets the owner of a file.

  Returns `nil` if the file has no owner.
  """
  @spec get_owner(String.t()) :: atom() | nil
  def get_owner(file_path) do
    GenServer.call(__MODULE__, {:get_owner, file_path})
  end

  @doc """
  Gets all contributors to a file.
  """
  @spec get_contributors(String.t()) :: list(atom())
  def get_contributors(file_path) do
    GenServer.call(__MODULE__, {:get_contributors, file_path})
  end

  @doc """
  Gets all files owned by a provider.
  """
  @spec get_owned_files(atom()) :: list(String.t())
  def get_owned_files(provider) do
    GenServer.call(__MODULE__, {:get_owned_files, provider})
  end

  @doc """
  Locks a file for exclusive access by a provider.

  Returns `:ok` if lock acquired, `{:error, :locked}` if already locked.
  """
  @spec lock_file(String.t(), atom()) :: :ok | {:error, :locked}
  def lock_file(file_path, provider) do
    GenServer.call(__MODULE__, {:lock_file, file_path, provider})
  end

  @doc """
  Unlocks a file.

  Only the provider that locked the file can unlock it.
  """
  @spec unlock_file(String.t(), atom()) :: :ok | {:error, :not_locked | :wrong_owner}
  def unlock_file(file_path, provider) do
    GenServer.call(__MODULE__, {:unlock_file, file_path, provider})
  end

  @doc """
  Checks if a file is locked.
  """
  @spec is_locked?(String.t()) :: boolean()
  def is_locked?(file_path) do
    GenServer.call(__MODULE__, {:is_locked, file_path})
  end

  @doc """
  Gets the provider that has locked a file.

  Returns `nil` if not locked.
  """
  @spec get_lock_holder(String.t()) :: atom() | nil
  def get_lock_holder(file_path) do
    GenServer.call(__MODULE__, {:get_lock_holder, file_path})
  end

  @doc """
  Gets all currently locked files.
  """
  @spec get_locked_files() :: list({String.t(), atom()})
  def get_locked_files do
    GenServer.call(__MODULE__, :get_locked_files)
  end

  @doc """
  Transfers ownership of a file to another provider.
  """
  @spec transfer_ownership(String.t(), atom()) :: :ok | {:error, :not_found}
  def transfer_ownership(file_path, new_owner) do
    GenServer.call(__MODULE__, {:transfer_ownership, file_path, new_owner})
  end

  @doc """
  Clears all ownership data.
  """
  @spec reset() :: :ok
  def reset do
    GenServer.call(__MODULE__, :reset)
  end

  # GenServer Callbacks

  @impl true
  def init(_opts) do
    state = %__MODULE__{
      owners: %{},
      contributors: %{},
      locks: %{},
      lock_timestamps: %{}
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:assign_owner, file_path, provider}, _from, state) do
    case Map.get(state.owners, file_path) do
      nil ->
        new_owners = Map.put(state.owners, file_path, provider)
        Logger.debug("Ownership: #{provider} now owns #{file_path}")
        {:reply, :ok, %{state | owners: new_owners}}

      _existing_owner ->
        {:reply, {:error, :already_owned}, state}
    end
  end

  @impl true
  def handle_call({:get_owner, file_path}, _from, state) do
    owner = Map.get(state.owners, file_path)
    {:reply, owner, state}
  end

  @impl true
  def handle_call({:get_contributors, file_path}, _from, state) do
    contributors =
      state.contributors
      |> Map.get(file_path, MapSet.new())
      |> MapSet.to_list()

    {:reply, contributors, state}
  end

  @impl true
  def handle_call({:get_owned_files, provider}, _from, state) do
    files =
      state.owners
      |> Enum.filter(fn {_file, owner} -> owner == provider end)
      |> Enum.map(fn {file, _owner} -> file end)

    {:reply, files, state}
  end

  @impl true
  def handle_call({:lock_file, file_path, provider}, _from, state) do
    case Map.get(state.locks, file_path) do
      nil ->
        new_locks = Map.put(state.locks, file_path, provider)

        new_timestamps =
          Map.put(state.lock_timestamps, file_path, System.monotonic_time(:millisecond))

        Logger.debug("Ownership: #{provider} locked #{file_path}")
        {:reply, :ok, %{state | locks: new_locks, lock_timestamps: new_timestamps}}

      _holder ->
        {:reply, {:error, :locked}, state}
    end
  end

  @impl true
  def handle_call({:unlock_file, file_path, provider}, _from, state) do
    case Map.get(state.locks, file_path) do
      nil ->
        {:reply, {:error, :not_locked}, state}

      ^provider ->
        new_locks = Map.delete(state.locks, file_path)
        new_timestamps = Map.delete(state.lock_timestamps, file_path)
        Logger.debug("Ownership: #{provider} unlocked #{file_path}")
        {:reply, :ok, %{state | locks: new_locks, lock_timestamps: new_timestamps}}

      _other ->
        {:reply, {:error, :wrong_owner}, state}
    end
  end

  @impl true
  def handle_call({:is_locked, file_path}, _from, state) do
    locked = Map.has_key?(state.locks, file_path)
    {:reply, locked, state}
  end

  @impl true
  def handle_call({:get_lock_holder, file_path}, _from, state) do
    holder = Map.get(state.locks, file_path)
    {:reply, holder, state}
  end

  @impl true
  def handle_call(:get_locked_files, _from, state) do
    files = Enum.to_list(state.locks)
    {:reply, files, state}
  end

  @impl true
  def handle_call({:transfer_ownership, file_path, new_owner}, _from, state) do
    case Map.get(state.owners, file_path) do
      nil ->
        {:reply, {:error, :not_found}, state}

      old_owner ->
        new_owners = Map.put(state.owners, file_path, new_owner)

        # Add old owner as contributor
        contributors_set = Map.get(state.contributors, file_path, MapSet.new())
        new_contributors_set = MapSet.put(contributors_set, old_owner)
        new_contributors = Map.put(state.contributors, file_path, new_contributors_set)

        Logger.info("Ownership: transferred #{file_path} from #{old_owner} to #{new_owner}")
        {:reply, :ok, %{state | owners: new_owners, contributors: new_contributors}}
    end
  end

  @impl true
  def handle_call(:reset, _from, _state) do
    new_state = %__MODULE__{
      owners: %{},
      contributors: %{},
      locks: %{},
      lock_timestamps: %{}
    }

    {:reply, :ok, new_state}
  end

  @impl true
  def handle_cast({:add_contributor, file_path, provider}, state) do
    # Don't add owner as contributor
    owner = Map.get(state.owners, file_path)

    new_contributors =
      if provider != owner do
        contributors_set = Map.get(state.contributors, file_path, MapSet.new())
        new_set = MapSet.put(contributors_set, provider)
        Map.put(state.contributors, file_path, new_set)
      else
        state.contributors
      end

    {:noreply, %{state | contributors: new_contributors}}
  end
end
