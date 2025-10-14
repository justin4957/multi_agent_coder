defmodule MultiAgentCoder.Session.Storage do
  @moduledoc """
  Persistent session storage with ETS backend.

  Provides:
  - ETS-based hot storage for active sessions
  - File-based persistence for durability
  - Session forking for multipath exploration
  - Tag-based indexing and search
  - Graph-ready structure (compatible with future Grapple integration)

  Inspired by Grapple's tiered storage architecture.
  """

  use GenServer
  require Logger

  alias MultiAgentCoder.Session.Storage.{Session, Message}

  defstruct [
    # Main session storage
    :sessions_table,
    # Tag and metadata indexing
    :session_index_table,
    # Session forking relationships
    :session_forks_table,
    # Access pattern tracking
    :access_tracker_table,
    :session_id_counter,
    :message_id_counter,
    :storage_dir
  ]

  @sessions_table :mac_sessions
  @session_index_table :mac_session_index
  @session_forks_table :mac_session_forks
  @access_tracker_table :mac_access_tracker

  @default_storage_dir Path.expand("~/.multi_agent_coder/sessions")

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Creates a new session with optional metadata.
  """
  def create_session(metadata \\ %{}) do
    GenServer.call(__MODULE__, {:create_session, metadata})
  end

  @doc """
  Forks an existing session at a specific message index.
  Returns the new session ID.
  """
  def fork_session(parent_id, opts \\ []) do
    GenServer.call(__MODULE__, {:fork_session, parent_id, opts})
  end

  @doc """
  Gets a session by ID.
  """
  def get_session(session_id) do
    case :ets.lookup(@sessions_table, session_id) do
      [{^session_id, session}] ->
        # Track access
        track_access(session_id)
        {:ok, session}

      [] ->
        # Try loading from disk
        load_session_from_disk(session_id)
    end
  end

  @doc """
  Updates a session.
  """
  def update_session(session_id, updates) do
    GenServer.call(__MODULE__, {:update_session, session_id, updates})
  end

  @doc """
  Adds a message to a session.
  """
  def add_message(session_id, message_params) do
    GenServer.call(__MODULE__, {:add_message, session_id, message_params})
  end

  @doc """
  Lists all active sessions.
  """
  def list_sessions do
    sessions =
      :ets.tab2list(@sessions_table)
      |> Enum.map(fn {_id, session} -> session end)
      |> Enum.sort_by(& &1.last_accessed_at, {:desc, DateTime})

    {:ok, sessions}
  end

  @doc """
  Finds sessions by tag.
  """
  def find_sessions_by_tag(tag) do
    case :ets.lookup(@session_index_table, {:tag, tag}) do
      objects ->
        session_ids = Enum.map(objects, fn {{:tag, _tag}, session_id} -> session_id end)

        sessions =
          Enum.map(session_ids, fn id ->
            case get_session(id) do
              {:ok, session} -> session
              _ -> nil
            end
          end)
          |> Enum.reject(&is_nil/1)

        {:ok, sessions}
    end
  end

  @doc """
  Finds sessions by date range.
  """
  def find_sessions_by_date_range(start_date, end_date) do
    {:ok, sessions} = list_sessions()

    filtered =
      Enum.filter(sessions, fn session ->
        DateTime.compare(session.created_at, start_date) in [:gt, :eq] and
          DateTime.compare(session.created_at, end_date) in [:lt, :eq]
      end)

    {:ok, filtered}
  end

  @doc """
  Gets all forks of a session.
  """
  def get_session_forks(session_id) do
    objects = :ets.lookup(@session_forks_table, {:parent, session_id})
    fork_ids = Enum.map(objects, fn {{:parent, _}, fork_id} -> fork_id end)
    {:ok, fork_ids}
  end

  @doc """
  Gets the parent session of a fork.
  """
  def get_session_parent(session_id) do
    case :ets.lookup(@session_forks_table, {:child, session_id}) do
      [{{:child, _}, parent_id}] -> {:ok, parent_id}
      [] -> {:ok, nil}
    end
  end

  @doc """
  Saves a session to disk.
  """
  def save_session_to_disk(session_id) do
    GenServer.call(__MODULE__, {:save_to_disk, session_id})
  end

  @doc """
  Loads a session from disk.
  """
  def load_session_from_disk(session_id) do
    GenServer.call(__MODULE__, {:load_from_disk, session_id})
  end

  @doc """
  Exports a session to JSON file.
  """
  def export_session(session_id, file_path) do
    GenServer.call(__MODULE__, {:export_session, session_id, file_path})
  end

  @doc """
  Imports a session from JSON file.
  """
  def import_session(file_path) do
    GenServer.call(__MODULE__, {:import_session, file_path})
  end

  @doc """
  Deletes a session and all its forks.
  """
  def delete_session(session_id, opts \\ []) do
    GenServer.call(__MODULE__, {:delete_session, session_id, opts})
  end

  @doc """
  Gets storage statistics.
  """
  def get_stats do
    %{
      total_sessions: :ets.info(@sessions_table, :size),
      total_forks: :ets.info(@session_forks_table, :size) || 0,
      memory_usage: %{
        sessions: :ets.info(@sessions_table, :memory),
        indexes: :ets.info(@session_index_table, :memory),
        forks: :ets.info(@session_forks_table, :memory) || 0
      }
    }
  end

  # Server Callbacks

  @impl true
  def init(opts) do
    storage_dir = Keyword.get(opts, :storage_dir, @default_storage_dir)
    File.mkdir_p!(storage_dir)

    # Create ETS tables
    sessions_table =
      create_table(@sessions_table, [:set, :named_table, :public, {:read_concurrency, true}])

    session_index_table =
      create_table(@session_index_table, [:bag, :named_table, :public, {:read_concurrency, true}])

    session_forks_table =
      create_table(@session_forks_table, [:bag, :named_table, :public, {:read_concurrency, true}])

    access_tracker_table =
      create_table(@access_tracker_table, [
        :set,
        :named_table,
        :public,
        {:write_concurrency, true}
      ])

    state = %__MODULE__{
      sessions_table: sessions_table,
      session_index_table: session_index_table,
      session_forks_table: session_forks_table,
      access_tracker_table: access_tracker_table,
      session_id_counter: 1,
      message_id_counter: 1,
      storage_dir: storage_dir
    }

    Logger.info("Session storage initialized at #{storage_dir}")

    {:ok, state}
  end

  @impl true
  def handle_call({:create_session, metadata}, _from, state) do
    session_id = generate_session_id(state.session_id_counter)

    session = %Session{
      id: session_id,
      parent_id: nil,
      fork_point: nil,
      created_at: DateTime.utc_now(),
      last_accessed_at: DateTime.utc_now(),
      access_count: 0,
      messages: [],
      metadata: metadata,
      providers_used: [],
      total_tokens: 0,
      estimated_cost: 0.0,
      retention_policy: Map.get(metadata, :retention_policy, :standard)
    }

    # Store session
    :ets.insert(state.sessions_table, {session_id, session})

    # Index tags
    tags = Map.get(metadata, :tags, [])

    Enum.each(tags, fn tag ->
      :ets.insert(state.session_index_table, {{:tag, tag}, session_id})
    end)

    # Initialize access tracking
    :ets.insert(
      state.access_tracker_table,
      {session_id, %{access_count: 0, last_access: DateTime.utc_now()}}
    )

    new_state = %{state | session_id_counter: state.session_id_counter + 1}

    {:reply, {:ok, session_id}, new_state}
  end

  @impl true
  def handle_call({:fork_session, parent_id, opts}, _from, state) do
    case get_session(parent_id) do
      {:ok, parent_session} ->
        fork_id = generate_session_id(state.session_id_counter)
        fork_point = Keyword.get(opts, :at_message, length(parent_session.messages))
        fork_metadata = Keyword.get(opts, :metadata, %{})

        # Create forked session with messages up to fork point
        messages_to_fork = Enum.take(parent_session.messages, fork_point)

        fork_session = %Session{
          id: fork_id,
          parent_id: parent_id,
          fork_point: fork_point,
          created_at: DateTime.utc_now(),
          last_accessed_at: DateTime.utc_now(),
          access_count: 0,
          messages: messages_to_fork,
          metadata: Map.merge(parent_session.metadata, fork_metadata),
          providers_used: parent_session.providers_used,
          total_tokens: parent_session.total_tokens,
          estimated_cost: parent_session.estimated_cost,
          retention_policy: parent_session.retention_policy
        }

        # Store fork
        :ets.insert(state.sessions_table, {fork_id, fork_session})

        # Record fork relationship
        :ets.insert(state.session_forks_table, {{:parent, parent_id}, fork_id})
        :ets.insert(state.session_forks_table, {{:child, fork_id}, parent_id})

        # Index tags
        tags = Map.get(fork_session.metadata, :tags, [])

        Enum.each(tags, fn tag ->
          :ets.insert(state.session_index_table, {{:tag, tag}, fork_id})
        end)

        new_state = %{state | session_id_counter: state.session_id_counter + 1}

        {:reply, {:ok, fork_id}, new_state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:update_session, session_id, updates}, _from, state) do
    case :ets.lookup(state.sessions_table, session_id) do
      [{^session_id, session}] ->
        updated_session = struct(session, updates)
        :ets.insert(state.sessions_table, {session_id, updated_session})
        {:reply, :ok, state}

      [] ->
        {:reply, {:error, :session_not_found}, state}
    end
  end

  @impl true
  def handle_call({:add_message, session_id, message_params}, _from, state) do
    case :ets.lookup(state.sessions_table, session_id) do
      [{^session_id, session}] ->
        message_id = generate_message_id(state.message_id_counter)

        message = %Message{
          id: message_id,
          session_id: session_id,
          role: Map.get(message_params, :role),
          content: Map.get(message_params, :content),
          provider: Map.get(message_params, :provider),
          timestamp: DateTime.utc_now(),
          tokens: Map.get(message_params, :tokens, 0),
          metadata: Map.get(message_params, :metadata, %{})
        }

        updated_session = %{
          session
          | messages: session.messages ++ [message],
            last_accessed_at: DateTime.utc_now(),
            total_tokens: session.total_tokens + message.tokens,
            providers_used: Enum.uniq(session.providers_used ++ [message.provider])
        }

        :ets.insert(state.sessions_table, {session_id, updated_session})

        new_state = %{state | message_id_counter: state.message_id_counter + 1}

        {:reply, {:ok, message_id}, new_state}

      [] ->
        {:reply, {:error, :session_not_found}, state}
    end
  end

  @impl true
  def handle_call({:save_to_disk, session_id}, _from, state) do
    case get_session(session_id) do
      {:ok, session} ->
        file_path = Path.join(state.storage_dir, "#{session_id}.json")

        case Jason.encode(session) do
          {:ok, json} ->
            case File.write(file_path, json) do
              :ok -> {:reply, {:ok, file_path}, state}
              {:error, reason} -> {:reply, {:error, reason}, state}
            end

          {:error, reason} ->
            {:reply, {:error, reason}, state}
        end

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:load_from_disk, session_id}, _from, state) do
    file_path = Path.join(state.storage_dir, "#{session_id}.json")

    case File.read(file_path) do
      {:ok, json} ->
        case Jason.decode(json, keys: :atoms) do
          {:ok, session_data} ->
            session = deserialize_session(session_data)
            :ets.insert(state.sessions_table, {session_id, session})
            {:reply, {:ok, session}, state}

          {:error, reason} ->
            {:reply, {:error, reason}, state}
        end

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:export_session, session_id, file_path}, _from, state) do
    case get_session(session_id) do
      {:ok, session} ->
        case Jason.encode(session, pretty: true) do
          {:ok, json} ->
            case File.write(file_path, json) do
              :ok -> {:reply, {:ok, file_path}, state}
              {:error, reason} -> {:reply, {:error, reason}, state}
            end

          {:error, reason} ->
            {:reply, {:error, reason}, state}
        end

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:import_session, file_path}, _from, state) do
    case File.read(file_path) do
      {:ok, json} ->
        case Jason.decode(json, keys: :atoms) do
          {:ok, session_data} ->
            # Generate new ID to avoid conflicts
            new_id = generate_session_id(state.session_id_counter)
            session = deserialize_session(Map.put(session_data, :id, new_id))

            :ets.insert(state.sessions_table, {new_id, session})

            # Re-index tags
            tags = Map.get(session.metadata, :tags, [])

            Enum.each(tags, fn tag ->
              :ets.insert(state.session_index_table, {{:tag, tag}, new_id})
            end)

            new_state = %{state | session_id_counter: state.session_id_counter + 1}

            {:reply, {:ok, new_id}, new_state}

          {:error, reason} ->
            {:reply, {:error, reason}, state}
        end

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:delete_session, session_id, opts}, _from, state) do
    delete_forks = Keyword.get(opts, :delete_forks, false)

    # Optionally delete forks
    if delete_forks do
      {:ok, fork_ids} = get_session_forks(session_id)

      Enum.each(fork_ids, fn fork_id ->
        delete_session_internal(fork_id, state)
      end)
    end

    result = delete_session_internal(session_id, state)
    {:reply, result, state}
  end

  # Private Functions

  defp create_table(name, opts) do
    case :ets.info(name) do
      :undefined ->
        :ets.new(name, opts)

      _ ->
        # Table already exists, return reference
        name
    end
  end

  defp generate_session_id(counter) do
    timestamp = System.system_time(:microsecond)
    "session_#{counter}_#{timestamp}"
  end

  defp generate_message_id(counter) do
    timestamp = System.system_time(:microsecond)
    "msg_#{counter}_#{timestamp}"
  end

  defp track_access(session_id) do
    case :ets.lookup(@access_tracker_table, session_id) do
      [{^session_id, tracker}] ->
        updated_tracker = %{
          access_count: tracker.access_count + 1,
          last_access: DateTime.utc_now()
        }

        :ets.insert(@access_tracker_table, {session_id, updated_tracker})

      [] ->
        :ets.insert(
          @access_tracker_table,
          {session_id, %{access_count: 1, last_access: DateTime.utc_now()}}
        )
    end
  end

  defp delete_session_internal(session_id, state) do
    case :ets.lookup(state.sessions_table, session_id) do
      [{^session_id, session}] ->
        # Remove from sessions table
        :ets.delete(state.sessions_table, session_id)

        # Remove from indexes
        tags = Map.get(session.metadata, :tags, [])

        Enum.each(tags, fn tag ->
          :ets.delete_object(state.session_index_table, {{:tag, tag}, session_id})
        end)

        # Remove fork relationships
        :ets.delete_object(state.session_forks_table, {{:child, session_id}, session.parent_id})

        case :ets.lookup(state.session_forks_table, {:parent, session_id}) do
          objects ->
            Enum.each(objects, fn obj -> :ets.delete_object(state.session_forks_table, obj) end)
        end

        # Remove access tracking
        :ets.delete(state.access_tracker_table, session_id)

        # Delete from disk
        file_path = Path.join(state.storage_dir, "#{session_id}.json")
        File.rm(file_path)

        :ok

      [] ->
        {:error, :session_not_found}
    end
  end

  defp deserialize_session(session_data) do
    # Convert datetime strings to DateTime structs
    session_data =
      session_data
      |> Map.update(:created_at, nil, &parse_datetime/1)
      |> Map.update(:last_accessed_at, nil, &parse_datetime/1)

    # Convert messages
    messages =
      session_data
      |> Map.get(:messages, [])
      |> Enum.map(&deserialize_message/1)

    session_data = Map.put(session_data, :messages, messages)

    struct(Session, session_data)
  end

  defp deserialize_message(message_data) when is_map(message_data) do
    message_data = Map.update(message_data, :timestamp, nil, &parse_datetime/1)
    struct(Message, message_data)
  end

  defp parse_datetime(nil), do: nil
  defp parse_datetime(%DateTime{} = dt), do: dt

  defp parse_datetime(string) when is_binary(string) do
    case DateTime.from_iso8601(string) do
      {:ok, datetime, _offset} -> datetime
      {:error, _} -> nil
    end
  end
end
