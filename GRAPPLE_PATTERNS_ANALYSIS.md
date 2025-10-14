# Grapple Patterns Analysis for Session Persistence (Issue #5)

## Overview
Analysis of [Grapple](../grapple) distributed graph database patterns applicable to multi_agent_coder session persistence and multipath exploration.

## Key Grapple Patterns Applicable to Sessions

### 1. **Tiered Storage Architecture** ⭐⭐⭐
**Source**: `grapple/lib/grapple/distributed/persistence_manager.ex`

Grapple uses a three-tier storage system that maps perfectly to session lifecycle:

```elixir
# Grapple's tiers
:ets     -> Hot tier (ephemeral, fast access, limited capacity)
:mnesia  -> Warm tier (replicated, persistent, medium access)
:dets    -> Cold tier (disk-persisted, archival, large capacity)
```

**Application to Sessions**:
```elixir
# Active sessions (currently being used)
:ets -> For active conversation sessions
  - Sub-millisecond access
  - Concurrent read/write
  - Perfect for real-time interactions

# Recent sessions (accessed within last N days)
:mnesia -> For recent session history
  - Persistent across restarts
  - Replicated across nodes (if distributed)
  - Fast enough for "resume session" feature

# Archived sessions (older conversations)
:dets -> For long-term storage
  - Disk-based persistence
  - Lower cost, slower access
  - Perfect for audit trails and analytics
```

**Key Code Pattern**:
```elixir
# From persistence_manager.ex:182-226
defp initialize_default_policies do
  %{
    hot_data: %{
      primary_tier: :ets,
      access_threshold: 50,  # accesses per hour
      migration_triggers: [:high_access, :low_latency_required]
    },
    warm_data: %{
      primary_tier: :mnesia,
      access_threshold: 10,
      migration_triggers: [:medium_access, :balanced_performance]
    },
    cold_data: %{
      primary_tier: :dets,
      access_threshold: 1,
      migration_triggers: [:low_access, :cost_optimization]
    }
  }
end
```

### 2. **Automatic Data Migration** ⭐⭐⭐
**Source**: `grapple/lib/grapple/distributed/persistence_manager.ex:378-414`

Grapple automatically moves data between tiers based on access patterns.

**Application to Sessions**:
- Active sessions stay in ETS for fast access
- Sessions inactive for 1 hour → migrate to Mnesia
- Sessions inactive for 7 days → migrate to DETS
- Frequently accessed old sessions → promote back to ETS

**Key Code Pattern**:
```elixir
defp execute_tier_migration(data_key, target_tier, reason, state) do
  case get_data_from_current_tier(data_key) do
    {:ok, data, current_tier} ->
      case store_data_in_tier(data_key, data, target_tier) do
        :ok ->
          if current_tier != target_tier do
            remove_data_from_tier(data_key, current_tier)
          end

          migration_result = %{
            data_key: data_key,
            from_tier: current_tier,
            to_tier: target_tier,
            reason: reason,
            timestamp: System.system_time(:second)
          }
          {:ok, migration_result, new_state}
      end
  end
end
```

### 3. **ETS Table Organization** ⭐⭐⭐
**Source**: `grapple/lib/grapple/storage/ets_graph_store.ex:10-28`

Grapple uses multiple specialized ETS tables with different access patterns:

```elixir
defstruct [
  :nodes_table,              # Main data
  :edges_table,              # Relationships
  :node_edges_out_table,     # Outgoing connections
  :node_edges_in_table,      # Incoming connections
  :property_index_table,     # Property lookups
  :label_index_table         # Label/tag lookups
]
```

**Application to Sessions**:
```elixir
defmodule MultiAgentCoder.Session.Storage do
  defstruct [
    :sessions_table,           # Main session data
    :session_index_table,      # Tag/metadata index
    :session_timeline_table,   # Chronological access
    :session_forks_table,      # Session branching/forking
    :message_index_table       # Fast message lookup
  ]
end
```

**Benefits**:
- O(1) session lookup by ID
- O(1) search by tags/metadata
- Efficient multipath exploration via forks table
- Fast message search across sessions

### 4. **Concurrent Access Patterns** ⭐⭐
**Source**: `grapple/lib/grapple/storage/ets_graph_store.ex:34-51`

```elixir
# Optimized for concurrent reads
create_table(@nodes_table, [
  :set,
  :named_table,
  :public,
  {:read_concurrency, true}
])

# For indexing (multiple entries per key)
create_table(@property_index_table, [
  :bag,  # Multiple values per key
  :named_table,
  :public,
  {:read_concurrency, true}
])
```

**Application**: Perfect for multi-user environments where multiple users might be browsing sessions concurrently.

### 5. **Access Pattern Tracking** ⭐⭐
**Source**: `grapple/lib/grapple/distributed/persistence_manager.ex:315-368`

Grapple tracks usage patterns to optimize storage decisions:

```elixir
defp create_adaptive_policy(data_key, usage_patterns, state) do
  access_frequency = Map.get(usage_patterns, :access_frequency, 0)
  data_size = Map.get(usage_patterns, :data_size, 0)
  access_pattern = Map.get(usage_patterns, :access_pattern, :random)
  retention_requirement = Map.get(usage_patterns, :retention_requirement, :standard)

  classification = classify_data_by_patterns(
    access_frequency,
    data_size,
    access_pattern
  )
end
```

**Application to Sessions**:
```elixir
# Track session access patterns
%Session{
  id: "abc123",
  created_at: ~U[2025-10-14 08:00:00Z],
  last_accessed_at: ~U[2025-10-14 10:30:00Z],
  access_count: 15,
  access_frequency: 5.0,  # accesses per hour
  estimated_size_bytes: 24_576,
  storage_tier: :ets,
  tags: ["feature-development", "bug-fix"],
  retention_policy: :standard
}
```

### 6. **Branching/Graph Structure** ⭐⭐⭐
**Source**: `grapple/lib/grapple/storage/ets_graph_store.ex:92-131`

Grapple's edge tracking is perfect for session forking/branching:

```elixir
# Track outgoing edges (session forks)
def get_edges_from(node_id) do
  case :ets.lookup(@node_edges_out_table, node_id) do
    [{^node_id, edge_ids}] ->
      edges = Enum.map(edge_ids, fn edge_id ->
        {:ok, edge_data} = get_edge(edge_id)
        edge_data
      end)
      {:ok, edges}
  end
end

# Track incoming edges (parent sessions)
def get_edges_to(node_id) do
  # Similar pattern for parent tracking
end
```

**Application to Multipath Exploration**:
```elixir
# Fork a session at a specific point
{:ok, fork_id} = MultiAgentCoder.Session.Storage.fork_session(
  parent_session_id,
  at_message: 42,
  metadata: %{
    fork_reason: "exploring alternative solution",
    strategy: :dialectical
  }
)

# Navigate session tree
{:ok, forks} = get_session_forks(parent_session_id)
{:ok, parent} = get_session_parent(fork_id)
{:ok, siblings} = get_session_siblings(fork_id)
```

## Recommended Session Storage Schema

### Core Session Structure
```elixir
defmodule MultiAgentCoder.Session.Storage do
  @moduledoc """
  Persistent session storage with tiered architecture.

  Inspired by Grapple's distributed persistence patterns.
  """

  use GenServer

  defstruct [
    # ETS Tables
    :active_sessions_table,     # Hot tier - active sessions
    :session_index_table,       # Metadata/tag indexing
    :session_forks_table,       # Session branching
    :message_index_table,       # Fast message search

    # Mnesia Tables (persistent)
    :recent_sessions,           # Warm tier

    # DETS (disk-based archive)
    :archived_sessions,         # Cold tier

    # Tracking
    :access_tracker,            # Session access patterns
    :migration_queue,           # Pending tier migrations

    # Counters
    :session_id_counter,
    :message_id_counter
  ]

  # Session data structure
  defmodule Session do
    defstruct [
      :id,
      :parent_id,              # For forked sessions
      :fork_point,             # Message index where fork occurred
      :created_at,
      :last_accessed_at,
      :access_count,
      :storage_tier,           # :ets, :mnesia, :dets
      :messages,               # List of messages
      :metadata,               # Tags, labels, custom data
      :providers_used,         # Which AI providers were used
      :total_tokens,           # Token usage tracking
      :estimated_cost,         # Cost tracking
      :retention_policy        # :standard, :critical, :temporary
    ]
  end

  defmodule Message do
    defstruct [
      :id,
      :session_id,
      :role,                   # :user, :assistant, :system
      :content,
      :provider,               # Which AI provider generated this
      :timestamp,
      :tokens,
      :metadata
    ]
  end
end
```

### Session Operations

```elixir
# Create new session
{:ok, session_id} = Storage.create_session(%{
  metadata: %{tags: ["feature", "refactoring"]},
  retention_policy: :standard
})

# Fork session (multipath exploration)
{:ok, fork_id} = Storage.fork_session(parent_id,
  at_message: 10,
  metadata: %{strategy: :alternative_approach}
)

# Save/Load sessions
:ok = Storage.save_session_to_disk(session_id, "/path/to/export.json")
{:ok, session} = Storage.load_session_from_disk("/path/to/export.json")

# Session search
{:ok, sessions} = Storage.find_sessions_by_tag("refactoring")
{:ok, sessions} = Storage.find_sessions_by_date_range(start_date, end_date)
{:ok, sessions} = Storage.search_sessions_by_content("authentication bug")

# Session cleanup
:ok = Storage.archive_old_sessions(older_than: days(30))
:ok = Storage.delete_temporary_sessions()

# Tier management
:ok = Storage.migrate_to_tier(session_id, :mnesia, reason: :inactivity)
{:ok, stats} = Storage.get_tier_statistics()
```

### Multipath Session Exploration

```elixir
defmodule MultiAgentCoder.Session.Multipath do
  @moduledoc """
  Support for exploring multiple solution paths from a single conversation.
  """

  # Create multiple forks to explore different strategies
  def explore_multiple_strategies(session_id, at_message, strategies) do
    Enum.map(strategies, fn strategy ->
      {:ok, fork_id} = Storage.fork_session(
        session_id,
        at_message: at_message,
        metadata: %{strategy: strategy}
      )

      # Execute strategy in fork
      execute_strategy_in_fork(fork_id, strategy)

      fork_id
    end)
  end

  # Compare results across forks
  def compare_fork_results(fork_ids) do
    forks = Enum.map(fork_ids, &Storage.get_session/1)

    %{
      total_forks: length(forks),
      comparison: compare_outcomes(forks),
      best_fork: select_best_fork(forks)
    }
  end

  # Merge successful fork back to main session
  def merge_fork(parent_id, fork_id, options \\ []) do
    {:ok, parent} = Storage.get_session(parent_id)
    {:ok, fork} = Storage.get_session(fork_id)

    # Append fork messages to parent
    merged_messages = parent.messages ++ fork.messages

    Storage.update_session(parent_id, messages: merged_messages)
  end

  # Visualize session tree
  def visualize_session_tree(root_session_id) do
    tree = build_session_tree(root_session_id)
    render_tree_ascii(tree)
  end
end
```

## Implementation Recommendations

### Phase 1: Basic Persistence
1. ✅ Create `Session.Storage` module with ETS tables
2. ✅ Implement save/load to disk (JSON format)
3. ✅ Add session listing and search
4. ✅ Basic cleanup policies

### Phase 2: Tiered Storage
1. ✅ Implement hot tier (ETS) for active sessions
2. ✅ Add warm tier (Mnesia) for recent sessions
3. ✅ Add cold tier (DETS) for archive
4. ✅ Automatic migration based on access patterns

### Phase 3: Multipath Exploration
1. ✅ Session forking/branching
2. ✅ Session tree navigation
3. ✅ Fork comparison and merging
4. ✅ Visual tree representation

### Phase 4: Advanced Features
1. ✅ Encryption for sensitive data
2. ✅ Session templates
3. ✅ Export formats (JSON, Markdown, HTML)
4. ✅ Session analytics and insights

## File Structure

```
lib/multi_agent_coder/session/
├── manager.ex           # Existing - basic session management
├── storage.ex           # NEW - Grapple-inspired persistent storage
├── persistence.ex       # NEW - Tiered storage manager
├── multipath.ex         # NEW - Forking and branching support
├── search.ex            # NEW - Session search and indexing
├── export.ex            # NEW - Export/import functionality
└── encryption.ex        # NEW - Sensitive data encryption

test/multi_agent_coder/session/
├── storage_test.exs
├── persistence_test.exs
├── multipath_test.exs
└── integration_test.exs
```

## Key Benefits from Grapple Patterns

1. **Performance**: ETS hot tier provides sub-millisecond session access
2. **Scalability**: Tiered storage handles unlimited session history
3. **Flexibility**: Easy to add new storage tiers or policies
4. **Resilience**: Mnesia replication provides fault tolerance
5. **Graph Structure**: Perfect for session forking/branching
6. **Production Ready**: Patterns proven in Grapple's production use

## Code Examples from Grapple to Adapt

### 1. ETS Table Setup
**Source**: `grapple/lib/grapple/storage/ets_graph_store.ex:34-51`
- Use `:set` for sessions table (unique IDs)
- Use `:bag` for tag index (multiple sessions per tag)
- Enable `{:read_concurrency, true}` for performance

### 2. Persistence Policies
**Source**: `grapple/lib/grapple/distributed/persistence_manager.ex:182-226`
- Define policies for different session types
- Critical sessions always stay in warm tier
- Temporary sessions auto-delete after N days

### 3. Migration Logic
**Source**: `grapple/lib/grapple/distributed/persistence_manager.ex:378-414`
- Check access patterns periodically
- Queue migrations to avoid blocking
- Track migration history for analytics

### 4. Monitoring
**Source**: `grapple/lib/grapple/distributed/persistence_manager.ex:593-655`
- Track tier utilization
- Monitor access rates
- Cost/performance optimization

## Conclusion

Grapple's patterns provide an excellent foundation for implementing sophisticated session persistence in multi_agent_coder. The tiered storage architecture, automatic migration, and graph-based structure are directly applicable to:

- **Persistent Sessions**: Store conversation history reliably
- **Multipath Exploration**: Fork sessions to explore alternatives
- **Performance**: Fast access to active sessions
- **Scalability**: Handle unlimited session history
- **User Experience**: Resume conversations, search history, compare alternatives

These patterns are production-tested in Grapple and can be adapted with minimal changes for multi_agent_coder's needs.
