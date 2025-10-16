# MultiAgent Coder
![](https://media.giphy.com/media/v1.Y2lkPTc5MGI3NjExcXBxenlwbHF4cGMwbjc4NGE2bTNiaWIzODlhanYxamlnOTB1dWtjbSZlcD12MV9naWZzX3NlYXJjaCZjdD1n/H7Fbn0QHGDWW4/giphy.gif)

![](https://media.giphy.com/media/v1.Y2lkPTc5MGI3NjExdmJ1cjY4MnVxbzZvZHR1ZWxxemEyZ3BrdHM2OTdhZW5lZzMwN3RmcyZlcD12MV9naWZzX3NlYXJjaCZjdD1n/2UlsTILSK3axi/giphy.gif)

> Concurrent multi-provider command-line interface for AI-powered coding

MultiAgent Coder is an **interactive CLI** that orchestrates multiple AI providers (OpenAI, Anthropic, DeepSeek, Perplexity AI, Local LLMs) working **concurrently** on coding tasks. Allocate different parts of your project to different providers, monitor their progress in real-time, merge their code intelligently, and watch as multiple AI agents build your software simultaneously. Built with Elixir's robust concurrency model for true parallelism, fault tolerance, and real-time monitoring.

## Features

### Concurrent Coding Task Management
- **Task Allocation**: Break down coding projects and allocate subtasks to different providers
- **Concurrent Execution**: Multiple providers work on different parts of your codebase simultaneously
- **Real-time Monitoring**: Live dashboard showing what each provider is working on, files being modified, and code being generated
- **Smart Task Distribution**: Auto-assign tasks based on provider strengths and capabilities

### Interactive CLI Experience
- **Rich REPL Interface**: Command history, multi-line input, tab completion, and readline editing
- **Comprehensive Commands**: Control tasks (pause/resume/cancel), inspect progress, manage files, resolve conflicts
- **Live Progress Display**: See code generation streaming in real-time with status indicators per provider
- **File Operation Tracking**: Monitor all file creates/reads/writes with conflict detection

### Code Quality & Merging
- **Intelligent Code Merging**: Automatically merge code from multiple providers with semantic understanding
- **Conflict Resolution**: Interactive UI for resolving conflicting implementations
- **Concurrent Build & Test**: Run builds and tests for each provider's code, compare results
- **Automated Feedback Loop**: Send test results back to providers for iterative improvement

### Provider Integration
- **Multiple Providers**: OpenAI (GPT-4), Anthropic (Claude), DeepSeek (DeepSeek Coder), Perplexity AI (with web search), Local LLMs (via Ollama)
- **Web Search**: Perplexity AI provides real-time web search capabilities with source citations
- **Tool Use**: Providers can execute bash commands, run tests, install dependencies
- **Safety Controls**: Command approval workflows for dangerous operations
- **Fault Tolerance**: Supervision trees ensure if one provider fails, others continue

### Routing Strategies
- `all` - All providers work on the same task in parallel
- `sequential` - Chain results (each provider sees previous outputs)
- `dialectical` - Thesis/Antithesis/Synthesis workflow for iterative refinement
- Custom task allocation and provider selection

## Quick Start

Get started with concurrent multi-provider coding in **2 simple steps**:

```bash
# 1. Clone and build
git clone https://github.com/justin4957/multi_agent_coder.git
cd multi_agent_coder
mix deps.get
mix escript.build

# 2. Run the CLI (interactive setup on first run)
./multi_agent_coder -i
```

The CLI will automatically prompt you for API keys on first run:
- Checks for existing keys in environment variables
- Interactively asks for missing keys
- Saves configuration to `~/.multi_agent_coder/config.exs`
- Validates and starts providers

**That's it!** No manual configuration needed.

### Example: Concurrent Coding Session

```bash
> allocate "Build a Phoenix API with authentication" to anthropic,openai

Task decomposed into:
  1. Create Phoenix project structure → anthropic
  2. Implement user schema and migrations → openai
  3. Add authentication logic → anthropic
  4. Create API endpoints → openai
  5. Write tests → all

> start

═══════════════════════════════════════════════════════════════════════
┌─ Anthropic ─────────────────────────── ⚡ ACTIVE (Task 1, 85%) ──────┐
│ File: lib/my_app/accounts/user.ex                                    │
│ Status: Writing schema definition...                                 │
│ Stats: 147 lines | $0.03 | 1m 23s                                   │
└───────────────────────────────────────────────────────────────────────┘

┌─ OpenAI ────────────────────────────── ⚡ ACTIVE (Task 2, 45%) ──────┐
│ File: priv/repo/migrations/20250101_create_users.exs                │
│ Status: Creating migration...                                        │
│ Stats: 89 lines | $0.05 | 1m 45s                                    │
└───────────────────────────────────────────────────────────────────────┘

Overall: 55% complete | 2/5 tasks done | $0.08 total

> status
┌─────────────────────────────────────────────────────────────┐
│ Anthropic: ✓ Task 1 complete | OpenAI: ⚡ Working on Task 2 │
│ Files: 3 created, 5 modified | 0 conflicts                  │
└─────────────────────────────────────────────────────────────┘

> build

Running builds for all providers...
  ✓ Anthropic: Build passed, 15/15 tests passed
  ⚠️  OpenAI: Build passed, 13/15 tests passed (2 failures)

> merge auto

Merging code from all providers...
  ✓ Auto-merged 7 files
  ⚠️  1 conflict in lib/my_app/auth.ex

> conflicts

Found 1 conflict in lib/my_app/auth.ex
Use 'merge interactive' to resolve

> merge interactive
[Interactive conflict resolution...]

> test

All tests passing! ✓ 15/15

> save auth-project
Session saved ✓
```

## Architecture

```
┌─────────────────────────────────────────────┐
│         MultiAgentCoder.Application         │
│              (OTP Supervisor)               │
└──────────────┬──────────────────────────────┘
               │
    ┌──────────┼───────────┬─────────────┐
    │          │           │             │
    ▼          ▼           ▼             ▼
┌────────┐ ┌────────┐ ┌─────────┐  ┌─────────┐
│PubSub  │ │Registry│ │ Task    │  │Monitor  │
│        │ │        │ │ Router  │  │Realtime │
└────────┘ └───┬────┘ └─────────┘  └─────────┘
               │
               ▼
       ┌───────────────┐
       │ Agent.Supervisor│
       └───────┬─────────┘
               │
     ┌─────────┼─────────┐
     ▼         ▼         ▼
  ┌─────┐  ┌─────┐  ┌─────┐
  │OpenAI│ │Claude│ │Local│
  │Agent │ │Agent │ │Agent│
  └─────┘  └─────┘  └─────┘
```

## Installation

### Prerequisites

- Elixir 1.18+ and Erlang/OTP 26+
- API keys for at least one provider (OpenAI or Anthropic recommended)
- (Optional) [Ollama](https://ollama.ai/) for local LLM support

### Setup

1. Clone and build:
```bash
git clone https://github.com/justin4957/multi_agent_coder.git
cd multi_agent_coder
mix deps.get
mix escript.build
```

2. Run and configure interactively:
```bash
./multi_agent_coder --setup
```

The setup wizard will:
- Check for existing API keys in your environment variables
- Prompt you for any missing keys
- Let you select models for each provider
- Save configuration to `~/.multi_agent_coder/config.exs`
- Encrypt and secure your API keys (file permissions set to 0600)

**Or** you can set environment variables (optional):
```bash
export OPENAI_API_KEY="your-openai-key"
export ANTHROPIC_API_KEY="your-anthropic-key"
export DEEPSEEK_API_KEY="your-deepseek-key"
export PERPLEXITY_API_KEY="your-perplexity-key"
```

The CLI will detect these automatically and use them on first run.

## Usage

### Interactive Mode (Recommended)

The interactive mode provides the full concurrent coding experience:

```bash
./multi_agent_coder -i
```

#### Core Commands

**Task Allocation & Control**
```bash
> allocate "Build authentication system" to anthropic,openai
> start                          # Start allocated tasks
> pause openai                   # Pause specific provider
> resume openai                  # Resume provider
> cancel task-1                  # Cancel a task
> tasks                          # List all tasks and status
```

**Monitoring & Inspection**
```bash
> status                         # Overall system status
> providers                      # Show provider status
> files                          # List all tracked files
> logs anthropic                 # View provider logs
> watch task-1                   # Watch task in real-time
```

**Code Management**
```bash
> diff lib/my_app/auth.ex       # Show file changes
> conflicts                      # List conflicts
> merge auto                     # Auto-merge code
> merge interactive              # Resolve conflicts interactively
> revert lib/auth.ex openai     # Revert provider's changes
```

**Build & Test**
```bash
> build                          # Build all providers' code
> test                           # Run all tests
> quality                        # Run quality checks
> failures                       # Show test failures
```

**Session Management**
```bash
> save my-project                # Save session
> load my-project                # Load session
> sessions                       # List saved sessions
```

### Single Command Mode

For quick one-off tasks:

```bash
# Query all providers
./multi_agent_coder "Write a function to reverse a linked list in Elixir"

# Use specific strategy
./multi_agent_coder -s dialectical "Implement quicksort in Elixir"

# Select specific providers
./multi_agent_coder -p openai,anthropic "Create a GenServer for rate limiting"

# Save output to file
./multi_agent_coder -o solution.ex "Write a binary search tree module"
```

### Programmatic API

Use MultiAgent Coder from within your Elixir applications:

```elixir
# Start the application
{:ok, _} = Application.ensure_all_started(:multi_agent_coder)

# Query all agents
results = MultiAgentCoder.Router.TaskRouter.route_task(
  "Write a function to parse CSV files",
  :all
)

# Use dialectical workflow
dialectical_results = MultiAgentCoder.Router.TaskRouter.route_task(
  "Implement a caching layer with TTL",
  :dialectical
)

# Sequential with context
results = MultiAgentCoder.Router.TaskRouter.route_task(
  "Add error handling to the previous function",
  :sequential,
  context: %{previous_code: "..."}
)
```

## Session Persistence and Multipath Exploration

MultiAgent Coder provides powerful session management with ETS-based storage, file persistence, and multipath exploration capabilities inspired by distributed graph database patterns.

### Core Features

- **🔥 ETS Hot Storage**: Sub-millisecond session access for active conversations
- **💾 File Persistence**: Durable storage with JSON export/import
- **🌲 Session Forking**: Branch conversations to explore alternative solutions
- **🔍 Tag-based Search**: Find sessions by tags, dates, or metadata
- **📊 Usage Tracking**: Monitor tokens, costs, and provider usage
- **🎯 Graph-Ready**: Compatible with future Grapple integration

### Basic Session Operations

```elixir
# Create a session with metadata
{:ok, session_id} = MultiAgentCoder.Session.Storage.create_session(%{
  tags: ["feature", "authentication"],
  description: "Building auth system"
})

# Add messages to the session
MultiAgentCoder.Session.Storage.add_message(session_id, %{
  role: :user,
  content: "How should I implement JWT authentication?",
  provider: :openai,
  tokens: 15
})

# Save session to disk
{:ok, file_path} = MultiAgentCoder.Session.Storage.save_session_to_disk(session_id)

# Export as JSON
MultiAgentCoder.Session.Storage.export_session(session_id, "/path/to/export.json")
```

### Multipath Exploration

Fork sessions to explore different solution approaches:

```elixir
# Main conversation about implementing a cache
{:ok, session_id} = Storage.create_session(%{tags: ["caching"]})
Storage.add_message(session_id, %{role: :user, content: "I need a caching layer"})
Storage.add_message(session_id, %{role: :assistant, content: "I recommend ETS..."})

# Fork to explore alternative approach
{:ok, fork1} = Storage.fork_session(session_id,
  at_message: 1,
  metadata: %{
    fork_reason: "exploring Redis alternative",
    strategy: :comparison
  }
)

# Another fork for GenServer-based solution
{:ok, fork2} = Storage.fork_session(session_id,
  at_message: 1,
  metadata: %{
    fork_reason: "GenServer state approach",
    strategy: :comparison
  }
)

# Continue different paths independently
Storage.add_message(fork1, %{role: :assistant, content: "Redis provides..."})
Storage.add_message(fork2, %{role: :assistant, content: "GenServer caching..."})

# Compare results
{:ok, forks} = Storage.get_session_forks(session_id)  # => [fork1, fork2]
```

### Session Tree Navigation

```elixir
# Get all forks of a session
{:ok, child_sessions} = Storage.get_session_forks(parent_id)

# Get parent of a fork
{:ok, parent_id} = Storage.get_session_parent(fork_id)

# Navigate the session tree
{:ok, session} = Storage.get_session(session_id)
IO.inspect(session.parent_id)      # => parent session ID or nil
IO.inspect(session.fork_point)     # => message index where fork occurred
```

### Search and Discovery

```elixir
# Find sessions by tag
{:ok, auth_sessions} = Storage.find_sessions_by_tag("authentication")

# Find sessions by date range
{:ok, recent} = Storage.find_sessions_by_date_range(
  ~U[2025-10-01 00:00:00Z],
  ~U[2025-10-14 23:59:59Z]
)

# List all sessions
{:ok, all_sessions} = Storage.list_sessions()

# Get storage statistics
stats = Storage.get_stats()
# => %{
#   total_sessions: 42,
#   total_forks: 15,
#   memory_usage: %{sessions: 1024000, indexes: 512000, forks: 256000}
# }
```

### Session Metadata and Tracking

Each session automatically tracks:

```elixir
%Session{
  id: "session_1_1234567890",
  parent_id: nil,                    # For forked sessions
  fork_point: nil,                   # Message index of fork
  created_at: ~U[2025-10-14 08:00:00Z],
  last_accessed_at: ~U[2025-10-14 10:30:00Z],
  access_count: 42,
  messages: [...],                   # Full conversation history
  metadata: %{tags: ["feature"], description: "..."},
  providers_used: [:openai, :anthropic],
  total_tokens: 1500,
  estimated_cost: 0.045,
  retention_policy: :standard
}
```

### Future: Grapple Integration

The session storage is designed to be compatible with Grapple's graph database:

- **Graph Structure**: Sessions and forks form a natural graph
- **Tiered Storage**: Easy migration to ETS → Mnesia → DETS tiers
- **Query Patterns**: Tag-based indexing maps to graph queries
- **Scalability**: Ready for distributed session storage

This allows for future features like:
- Distributed session replication
- Complex graph queries across session trees
- Advanced analytics on conversation patterns
- Session clustering and recommendation

## Concurrent Coding Workflows

### Workflow 1: Parallel Feature Development

Develop multiple features simultaneously with different providers:

```bash
> allocate "Implement user registration" to anthropic
> allocate "Add login functionality" to openai
> allocate "Create password reset" to local
> start

# Monitor progress
> status
┌──────────────────────────────────────────────────────┐
│ 3 tasks running | Anthropic: 65% | OpenAI: 45% ...  │
└──────────────────────────────────────────────────────┘

# Check files being created
> files
lib/my_app/registration.ex    anthropic  ⚡ ACTIVE
lib/my_app/login.ex           openai     ⚡ ACTIVE
lib/my_app/password.ex        local      ⚡ ACTIVE

# Build and test as they complete
> build
> test

# Merge when all complete
> merge auto
✓ All features merged successfully
```

### Workflow 2: Code Review & Comparison

Have multiple providers implement the same feature, then compare:

```bash
> allocate "Implement rate limiter GenServer" to all
> start

# Wait for completion
> compare
┌─ Anthropic ──────────────┬─ OpenAI ────────────────┬─ Local ─────────┐
│ Uses ETS for storage     │ Uses Agent for state    │ Token bucket    │
│ Sliding window algorithm │ Fixed window            │ Leaky bucket    │
│ ...                      │ ...                     │ ...             │
└──────────────────────────┴─────────────────────────┴─────────────────┘

# Build and test all versions
> build
> test

Results:
  Anthropic: 100% tests passed, high performance
  OpenAI: 95% tests passed, simpler code
  Local: 100% tests passed, most memory efficient

# Accept best implementation
> merge accept --provider anthropic
```

### Workflow 3: Iterative Development with Feedback

Use automated feedback loops to improve code quality:

```bash
> allocate "Create REST API client" to openai
> start

# Auto-build and test triggers
[Build completed with warnings...]
[2 tests failed]

# System sends feedback to provider
Sending feedback to OpenAI: "Fix failing tests and warnings"

# Provider iterates
[OpenAI fixing issues...]
[Build completed successfully]
[All tests passed ✓]

> merge auto
✓ Code merged successfully
```

### Workflow 4: Complex Project Development

Decompose large projects into concurrent subtasks:

```bash
> allocate "Build e-commerce platform" to all

Task automatically decomposed:
  1. Database schema & migrations  → anthropic
  2. Product catalog API           → openai
  3. Shopping cart logic           → anthropic
  4. Payment integration           → openai
  5. Admin dashboard               → local
  6. Tests for all modules         → all

> start

# Real-time monitoring shows all providers working
> watch

# Handle conflicts as they arise
> conflicts
Conflict in lib/my_app/product.ex
> merge interactive
[Resolve conflict...]

# Continuous integration
> build
> test
> quality

# Final merge and verification
> merge auto
> test
✓ All 47 tests passed

> save ecommerce-project
```

## Configuration

Edit `config/config.exs` to customize providers and settings:

```elixir
config :multi_agent_coder,
  # Provider configuration
  providers: [
    openai: [
      model: "gpt-4",
      api_key: {:system, "OPENAI_API_KEY"},
      temperature: 0.1,
      max_tokens: 4096
    ],
    anthropic: [
      model: "claude-sonnet-4-5",
      api_key: {:system, "ANTHROPIC_API_KEY"},
      temperature: 0.1,
      max_tokens: 4096
    ],
    deepseek: [
      model: "deepseek-coder",           # or "deepseek-chat"
      api_key: {:system, "DEEPSEEK_API_KEY"},
      temperature: 0.1,
      max_tokens: 4096
    ],
    perplexity: [
      model: "sonar",                    # or "sonar-pro", "codellama", "mixtral"
      api_key: {:system, "PERPLEXITY_API_KEY"},
      temperature: 0.1,
      max_tokens: 4096
    ],
    local: [
      model: "codellama:latest",
      endpoint: "http://localhost:11434",
      temperature: 0.1
    ]
  ],
  default_strategy: :all,
  timeout: 120_000,

  # Concurrent coding settings
  task_allocation: [
    auto_decompose: true,          # Automatically break down complex tasks
    max_concurrent_tasks: 10,      # Max tasks running simultaneously
    task_timeout: 600_000          # 10 minutes per task
  ],

  # Build and test configuration
  build: [
    auto_build: true,              # Auto-build on code generation
    auto_test: true,               # Auto-test after build
    parallel_test_execution: true,
    test_timeout: 60_000,
    quality_checks: [:format, :credo, :dialyzer],
    min_coverage: 80
  ],

  # File operations
  file_tracking: [
    track_all_operations: true,    # Track all file ops
    conflict_detection: true,      # Auto-detect conflicts
    auto_snapshot: true            # Snapshot before modifications
  ],

  # Code merging
  merge: [
    strategy: :semantic,           # :semantic | :textual
    auto_merge_safe: true,         # Auto-merge non-conflicting
    feedback_loop_iterations: 3    # Max iterations for feedback
  ],

  # Tool execution
  tools: [
    sandbox_enabled: true,
    auto_approve_safe: true,
    prompt_on_warning: true,
    block_dangerous: false,
    max_concurrent: 3
  ]
```

## Routing Strategies

### All (`:all`)
Queries all providers concurrently and returns all results. Fastest for getting multiple perspectives.

### Sequential (`:sequential`)
Each agent receives previous agents' responses as context. Useful for iterative refinement.

### Dialectical (`:dialectical`)
Three-phase workflow:
1. **Thesis**: All agents provide initial solutions
2. **Antithesis**: Agents critique each other's solutions
3. **Synthesis**: Agents create improved solutions incorporating critiques

Great for complex problems requiring deep analysis.

## Development

### Running Tests
```bash
mix test
```

### Start IEx with application
```bash
iex -S mix
```

### Format code
```bash
mix format
```

### Generate documentation
```bash
mix docs
```

## Project Structure

```
lib/
├── multi_agent_coder/
│   ├── application.ex              # OTP Application
│   │
│   ├── agent/                      # AI Provider Integration
│   │   ├── supervisor.ex           # Supervises all agents
│   │   ├── worker.ex               # Generic agent worker
│   │   ├── openai.ex               # OpenAI integration
│   │   ├── anthropic.ex            # Anthropic integration
│   │   └── local.ex                # Local LLM integration
│   │
│   ├── task/                       # Task Management
│   │   ├── allocator.ex            # Task allocation logic
│   │   ├── decomposer.ex           # Break down complex tasks
│   │   ├── queue.ex                # Task queue management
│   │   └── tracker.ex              # Track task progress
│   │
│   ├── router/                     # Routing & Strategy
│   │   ├── task_router.ex          # Task routing logic
│   │   └── strategy.ex             # Routing strategies
│   │
│   ├── file_ops/                   # File Operations
│   │   ├── tracker.ex              # Track file operations
│   │   ├── conflict_detector.ex    # Detect conflicts
│   │   ├── ownership.ex            # File ownership tracking
│   │   ├── history.ex              # Change history
│   │   └── diff.ex                 # Diff generation
│   │
│   ├── merge/                      # Code Merging
│   │   ├── engine.ex               # Core merge logic
│   │   ├── conflict_resolver.ex    # Conflict resolution
│   │   ├── strategy.ex             # Merge strategies
│   │   └── semantic_analyzer.ex    # Semantic analysis
│   │
│   ├── build/                      # Build & Test
│   │   ├── monitor.ex              # Monitor builds
│   │   └── runner.ex               # Build execution
│   │
│   ├── test/                       # Testing
│   │   ├── runner.ex               # Run tests
│   │   └── comparator.ex           # Compare results
│   │
│   ├── quality/                    # Code Quality
│   │   └── checker.ex              # Quality checks
│   │
│   ├── tools/                      # Tool Execution
│   │   ├── executor.ex             # Execute commands
│   │   ├── sandbox.ex              # Sandboxed execution
│   │   ├── approver.ex             # Command approval
│   │   └── monitor.ex              # Tool monitoring
│   │
│   ├── monitor/                    # Real-time Monitoring
│   │   ├── realtime.ex             # Real-time updates
│   │   ├── dashboard.ex            # Monitoring dashboard
│   │   ├── provider_panel.ex       # Per-provider display
│   │   └── collector.ex            # Result aggregation
│   │
│   ├── session/                    # Session Management
│   │   ├── manager.ex              # Session state
│   │   └── storage.ex              # Persistence
│   │
│   ├── feedback/                   # Feedback Loop
│   │   └── loop.ex                 # Feedback to providers
│   │
│   └── cli/                        # CLI Interface
│       ├── command.ex              # Command handling
│       ├── command_parser.ex       # Parse commands
│       ├── repl.ex                 # REPL interface
│       ├── formatter.ex            # Output formatting
│       ├── display_manager.ex      # Concurrent display
│       └── help.ex                 # Help system
│
└── multi_agent_coder.ex            # Main module
```

## Contributing

We welcome contributions! Please see our contributing guidelines and code of conduct.

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## Roadmap

We're actively developing features to enhance the concurrent coding experience. Key areas:

### Phase 1: Interactive Foundation
- [#10](https://github.com/justin4957/multi_agent_coder/issues/10) Rich Interactive REPL Experience
- [#12](https://github.com/justin4957/multi_agent_coder/issues/12) Concurrent Coding Task Allocation
- [#17](https://github.com/justin4957/multi_agent_coder/issues/17) Interactive Task Control Commands

### Phase 2: Monitoring & Visualization
- [#13](https://github.com/justin4957/multi_agent_coder/issues/13) Real-time Coding Progress Monitor
- [#14](https://github.com/justin4957/multi_agent_coder/issues/14) File Operations and Code Generation Tracking
- [#11](https://github.com/justin4957/multi_agent_coder/issues/11) Concurrent Provider Display with Split View

### Phase 3: Code Quality & Integration
- [#15](https://github.com/justin4957/multi_agent_coder/issues/15) Intelligent Code Merging and Conflict Resolution
- [#18](https://github.com/justin4957/multi_agent_coder/issues/18) Concurrent Build and Test Monitoring
- [#16](https://github.com/justin4957/multi_agent_coder/issues/16) Provider Tool Use and Execution Monitoring

See all [open issues](https://github.com/justin4957/multi_agent_coder/issues) for planned features and known issues.

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Acknowledgments

- Built with [Elixir](https://elixir-lang.org/) and the BEAM VM
- Uses [Phoenix.PubSub](https://hexdocs.pm/phoenix_pubsub/) for real-time updates
- Integrates with leading AI providers: OpenAI, Anthropic, DeepSeek, Perplexity AI, and Ollama

---

**Made with Elixir and the power of concurrent AI agents**

*Build software faster with multiple AI providers working in parallel*
