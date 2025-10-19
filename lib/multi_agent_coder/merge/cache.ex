defmodule MultiAgentCoder.Merge.Cache do
  @moduledoc """
  High-performance caching system for AST and semantic analysis results.

  Uses ETS tables for fast in-memory caching with content-based hashing
  to invalidate cache entries when files change.

  ## Features
  - Content-hash based cache keys to detect changes
  - TTL support for automatic cache expiration
  - Memory-efficient storage
  - Thread-safe concurrent access
  - Metrics tracking for cache hit/miss rates
  """

  use GenServer
  require Logger

  @table_name :merge_cache
  @default_ttl_seconds 3600
  @cleanup_interval_ms 60_000

  defmodule CacheEntry do
    @moduledoc false
    defstruct [:value, :inserted_at, :ttl, :access_count]
  end

  defmodule Stats do
    @moduledoc false
    defstruct hits: 0, misses: 0, evictions: 0, total_entries: 0

    def hit_rate(%__MODULE__{hits: hits, misses: misses}) when hits + misses > 0 do
      hits / (hits + misses) * 100
    end

    def hit_rate(_), do: 0.0
  end

  # Client API

  @doc """
  Starts the cache server.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Gets a cached AST for the given content.

  Returns `{:ok, ast}` if found in cache, `:miss` otherwise.
  """
  @spec get_ast(String.t()) :: {:ok, any()} | :miss
  def get_ast(content) do
    key = {:ast, content_hash(content)}
    get(key)
  end

  @doc """
  Caches an AST for the given content.
  """
  @spec put_ast(String.t(), any(), non_neg_integer() | nil) :: :ok
  def put_ast(content, ast, ttl \\ nil) do
    key = {:ast, content_hash(content)}
    put(key, ast, ttl)
  end

  @doc """
  Gets cached semantic analysis results.
  """
  @spec get_analysis(String.t()) :: {:ok, map()} | :miss
  def get_analysis(content) do
    key = {:analysis, content_hash(content)}
    get(key)
  end

  @doc """
  Caches semantic analysis results.
  """
  @spec put_analysis(String.t(), map(), non_neg_integer() | nil) :: :ok
  def put_analysis(content, analysis, ttl \\ nil) do
    key = {:analysis, content_hash(content)}
    put(key, analysis, ttl)
  end

  @doc """
  Clears all cached entries.
  """
  @spec clear() :: :ok
  def clear() do
    GenServer.call(__MODULE__, :clear)
  end

  @doc """
  Gets cache statistics.
  """
  @spec stats() :: Stats.t()
  def stats() do
    GenServer.call(__MODULE__, :stats)
  end

  @doc """
  Gets the current number of entries in the cache.
  """
  @spec size() :: non_neg_integer()
  def size() do
    GenServer.call(__MODULE__, :size)
  end

  # Private API

  defp get(key) do
    case :ets.lookup(@table_name, key) do
      [{^key, entry}] ->
        if entry_valid?(entry) do
          GenServer.cast(__MODULE__, {:record_hit, key})
          {:ok, entry.value}
        else
          GenServer.cast(__MODULE__, {:evict, key})
          :miss
        end

      [] ->
        GenServer.cast(__MODULE__, :record_miss)
        :miss
    end
  end

  defp put(key, value, ttl) do
    GenServer.call(__MODULE__, {:put, key, value, ttl})
  end

  defp content_hash(content) when is_binary(content) do
    :crypto.hash(:sha256, content) |> Base.encode16(case: :lower)
  end

  defp entry_valid?(%CacheEntry{inserted_at: inserted_at, ttl: ttl}) do
    if ttl do
      now = System.system_time(:second)
      now - inserted_at < ttl
    else
      true
    end
  end

  # Server Callbacks

  @impl true
  def init(_opts) do
    # Create ETS table for cache storage
    :ets.new(@table_name, [:named_table, :set, :public, read_concurrency: true])

    # Schedule periodic cleanup
    schedule_cleanup()

    state = %{
      stats: %Stats{},
      ttl_default: @default_ttl_seconds
    }

    Logger.info("Cache system initialized with table: #{@table_name}")
    {:ok, state}
  end

  @impl true
  def handle_call({:put, key, value, ttl}, _from, state) do
    entry = %CacheEntry{
      value: value,
      inserted_at: System.system_time(:second),
      ttl: ttl || state.ttl_default,
      access_count: 0
    }

    :ets.insert(@table_name, {key, entry})

    new_stats = %Stats{state.stats | total_entries: :ets.info(@table_name, :size)}
    {:reply, :ok, %{state | stats: new_stats}}
  end

  @impl true
  def handle_call(:clear, _from, state) do
    :ets.delete_all_objects(@table_name)
    new_stats = %Stats{evictions: state.stats.evictions + state.stats.total_entries}
    Logger.info("Cache cleared")
    {:reply, :ok, %{state | stats: new_stats}}
  end

  @impl true
  def handle_call(:stats, _from, state) do
    {:reply, state.stats, state}
  end

  @impl true
  def handle_call(:size, _from, state) do
    size = :ets.info(@table_name, :size)
    {:reply, size, state}
  end

  @impl true
  def handle_cast({:record_hit, key}, state) do
    # Increment access count for the entry
    case :ets.lookup(@table_name, key) do
      [{^key, entry}] ->
        updated_entry = %{entry | access_count: entry.access_count + 1}
        :ets.insert(@table_name, {key, updated_entry})

      _ ->
        :ok
    end

    new_stats = %Stats{state.stats | hits: state.stats.hits + 1}
    {:noreply, %{state | stats: new_stats}}
  end

  @impl true
  def handle_cast(:record_miss, state) do
    new_stats = %Stats{state.stats | misses: state.stats.misses + 1}
    {:noreply, %{state | stats: new_stats}}
  end

  @impl true
  def handle_cast({:evict, key}, state) do
    :ets.delete(@table_name, key)
    new_stats = %Stats{state.stats | evictions: state.stats.evictions + 1}
    {:noreply, %{state | stats: new_stats}}
  end

  @impl true
  def handle_info(:cleanup, state) do
    evicted_count = cleanup_expired_entries()

    new_stats = %Stats{
      state.stats
      | evictions: state.stats.evictions + evicted_count,
        total_entries: :ets.info(@table_name, :size)
    }

    if evicted_count > 0 do
      Logger.debug("Cache cleanup: evicted #{evicted_count} expired entries")
    end

    schedule_cleanup()
    {:noreply, %{state | stats: new_stats}}
  end

  defp cleanup_expired_entries() do
    now = System.system_time(:second)

    expired_keys =
      :ets.tab2list(@table_name)
      |> Enum.filter(fn {_key, entry} ->
        entry.ttl && now - entry.inserted_at >= entry.ttl
      end)
      |> Enum.map(fn {key, _entry} -> key end)

    Enum.each(expired_keys, &:ets.delete(@table_name, &1))
    length(expired_keys)
  end

  defp schedule_cleanup() do
    Process.send_after(self(), :cleanup, @cleanup_interval_ms)
  end
end
