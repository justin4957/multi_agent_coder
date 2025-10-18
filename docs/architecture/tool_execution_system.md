# Tool Execution System Architecture

**Issue**: #16 - Provider Tool Use and Command Execution Monitoring
**Status**: Architecture & Design Phase
**Author**: Architecture Team
**Date**: 2025-10-17

---

## Executive Summary

This document defines the architecture for a comprehensive tool execution system that enables AI providers to execute commands, interact with files, and use external tools while maintaining safety, monitoring, and concurrent execution capabilities.

### Key Requirements

1. **Tool Execution Framework**: Enable providers to execute bash commands, file operations, git commands, and web searches
2. **Real-time Monitoring**: Display command execution status, output, and results per provider
3. **Safety Controls**: Classify commands by danger level and implement approval workflows
4. **Concurrent Execution**: Allow multiple providers to execute tools simultaneously with conflict detection
5. **Result Handling**: Feed execution results back to providers for iterative workflows

---

## System Architecture

### High-Level Component Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                      Provider Layer                              │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐       │
│  │  OpenAI  │  │ Anthropic│  │ DeepSeek │  │  Local   │       │
│  └────┬─────┘  └────┬─────┘  └────┬─────┘  └────┬─────┘       │
└───────┼─────────────┼─────────────┼─────────────┼──────────────┘
        │             │             │             │
        └─────────────┴─────────────┴─────────────┘
                          │
                          ▼
        ┌─────────────────────────────────────────┐
        │      Tool Execution Coordinator         │
        │  (Multi_agent_coder.Tools.Coordinator)  │
        └─────────────────┬───────────────────────┘
                          │
          ┌───────────────┼───────────────┐
          │               │               │
          ▼               ▼               ▼
    ┌─────────┐    ┌──────────┐    ┌─────────┐
    │Executor │    │Classifier│    │Approver │
    └────┬────┘    └─────┬────┘    └────┬────┘
         │               │              │
         │               │              │
         ▼               ▼              ▼
    ┌─────────────────────────────────────────┐
    │           Sandbox Environment           │
    │  (Isolated process execution context)   │
    └─────────────────┬───────────────────────┘
                      │
          ┌───────────┼───────────┐
          │           │           │
          ▼           ▼           ▼
    ┌─────────┐ ┌─────────┐ ┌─────────┐
    │  Bash   │ │  File   │ │   Git   │
    │Commands │ │  Ops    │ │Commands │
    └─────────┘ └─────────┘ └─────────┘
          │           │           │
          └───────────┴───────────┘
                      │
                      ▼
        ┌─────────────────────────────────┐
        │      Monitor & Telemetry        │
        │  (Real-time status & metrics)   │
        └─────────────────────────────────┘
```

---

## Core Components

### 1. Tool Coordinator (`lib/multi_agent_coder/tools/coordinator.ex`)

**Responsibility**: Orchestrates tool execution requests from providers

**Key Functions**:
```elixir
@spec execute_tool(provider_id, tool_request) :: {:ok, result} | {:error, reason}
@spec queue_command(provider_id, command) :: {:ok, command_id}
@spec get_execution_status(command_id) :: status_info
@spec cancel_execution(command_id) :: :ok | {:error, reason}
```

**State Management**:
- Active command queue per provider
- Execution history and results cache
- Resource lock tracking (file locks, exclusive operations)

**Concurrency Handling**:
- Detects conflicting operations (e.g., two providers modifying same file)
- Queues conflicting commands automatically
- Releases locks upon completion

---

### 2. Command Executor (`lib/multi_agent_coder/tools/executor.ex`)

**Responsibility**: Executes commands in sandboxed environment

**Supported Tool Types**:

1. **Bash Commands**
   ```elixir
   %ToolRequest{
     type: :bash,
     command: "mix test",
     args: [],
     timeout: 60_000
   }
   ```

2. **File Operations**
   ```elixir
   %ToolRequest{
     type: :file_read,
     path: "lib/my_module.ex"
   }

   %ToolRequest{
     type: :file_write,
     path: "lib/new_module.ex",
     content: "defmodule..."
   }
   ```

3. **Git Commands**
   ```elixir
   %ToolRequest{
     type: :git,
     command: "status",
     args: []
   }
   ```

4. **Web Search** (future)
   ```elixir
   %ToolRequest{
     type: :web_search,
     query: "Elixir GenServer examples"
   }
   ```

**Execution Flow**:
```elixir
def execute(tool_request, opts \\ []) do
  with {:ok, classified} <- Classifier.classify(tool_request),
       {:ok, approved} <- Approver.check_approval(classified),
       {:ok, sandbox} <- Sandbox.prepare(),
       {:ok, result} <- run_in_sandbox(sandbox, approved) do
    Monitor.record_execution(result)
    {:ok, result}
  end
end
```

**Result Structure**:
```elixir
%ExecutionResult{
  command_id: "cmd_123",
  provider: :anthropic,
  tool_type: :bash,
  command: "mix test",
  status: :completed,  # :pending, :running, :completed, :failed, :denied
  exit_code: 0,
  stdout: "...",
  stderr: "",
  duration_ms: 3200,
  timestamp: ~U[2025-10-17 12:34:56Z],
  resource_usage: %{cpu: 45, memory: 120_000}
}
```

---

### 3. Command Classifier (`lib/multi_agent_coder/tools/classifier.ex`)

**Responsibility**: Classify commands by danger level

**Classification Levels**:

```elixir
@type danger_level :: :safe | :warning | :dangerous | :blocked

# Safe - Auto-approve
@safe_commands [
  ~r/^mix test/,
  ~r/^mix format --check-formatted/,
  ~r/^git status/,
  ~r/^git diff/,
  ~r/^git log/,
  ~r/^cat /,
  ~r/^ls /,
  ~r/^echo /,
  ~r/^mix compile/
]

# Warning - Prompt user
@warning_commands [
  ~r/^mix deps\.get/,
  ~r/^npm install/,
  ~r/^git commit/,
  ~r/^git add/,
  ~r/^mix format(?! --check)/  # mix format without --check
]

# Dangerous - Require explicit approval
@dangerous_commands [
  ~r/^rm -rf/,
  ~r/^mix ecto\.drop/,
  ~r/^mix ecto\.reset/,
  ~r/^git push --force/,
  ~r/^git push -f/,
  ~r/^mix release/,
  ~r/^mix deploy/
]

# Blocked - Never allow
@blocked_commands [
  ~r/^sudo/,
  ~r/^su /,
  ~r/^chmod 777/,
  ~r/^curl .* \| sh/,
  ~r/^wget .* \| bash/
]
```

**Classification Function**:
```elixir
@spec classify(command :: String.t()) ::
  {:ok, %{level: danger_level(), reason: String.t()}} |
  {:error, :blocked}

def classify(command) do
  cond do
    matches_pattern?(command, @blocked_commands) ->
      {:error, :blocked}

    matches_pattern?(command, @dangerous_commands) ->
      {:ok, %{level: :dangerous, reason: "High-risk operation"}}

    matches_pattern?(command, @warning_commands) ->
      {:ok, %{level: :warning, reason: "Modifying operation"}}

    matches_pattern?(command, @safe_commands) ->
      {:ok, %{level: :safe, reason: "Read-only or test operation"}}

    true ->
      {:ok, %{level: :warning, reason: "Unknown command"}}
  end
end
```

---

### 4. Command Approver (`lib/multi_agent_coder/tools/approver.ex`)

**Responsibility**: Handle approval workflows for commands

**Approval Modes**:

```elixir
@type approval_mode :: :auto | :prompt | :deny_all | :allow_all

config :multi_agent_coder, :tools,
  approval_mode: :auto,  # Default: auto-approve safe, prompt for others
  auto_approve_safe: true,
  prompt_on_warning: true,
  deny_dangerous: false
```

**Approval State Machine**:
```
                ┌──────────┐
                │ Submitted│
                └────┬─────┘
                     │
                     ▼
         ┌────────────────────────┐
         │  Classify Command      │
         └────┬───────────────┬───┘
              │               │
    ┌─────────▼─────┐   ┌────▼─────────┐
    │ Safe/Warning  │   │ Dangerous    │
    └───────┬───────┘   └────┬─────────┘
            │                │
            ▼                ▼
    ┌───────────────┐  ┌────────────────┐
    │ Auto-approve? │  │ Prompt User    │
    └───┬───────┬───┘  └───┬────────┬───┘
        │       │          │        │
       Yes      No         │        │
        │       │          │        │
        ▼       └──────────┘        │
    ┌──────────┐                    │
    │ Approved │                    │
    └────┬─────┘                    │
         │                          │
         └──────────┬───────────────┘
                    │
                    ▼
            ┌───────────────┐
            │   Execute     │
            └───────────────┘
```

**Interactive Approval UI**:
```elixir
def prompt_user(command_info) do
  IO.puts("""
  ⚠️  Command requires approval:

  Provider: #{command_info.provider}
  Command:  #{command_info.command}
  Danger:   #{command_info.danger_level}
  Reason:   #{command_info.reason}

  [A]pprove | [D]eny | [M]odify | [V]iew Details
  """)

  case IO.gets("> ") |> String.trim() |> String.downcase() do
    "a" -> {:ok, :approved}
    "d" -> {:error, :denied}
    "m" -> prompt_modification(command_info)
    "v" -> show_details(command_info) && prompt_user(command_info)
  end
end
```

---

### 5. Sandbox Environment (`lib/multi_agent_coder/tools/sandbox.ex`)

**Responsibility**: Provide isolated execution environment

**Isolation Strategies**:

1. **Process-level Isolation**
   - Execute commands in separate Erlang ports
   - Capture stdout/stderr streams
   - Enforce resource limits (CPU, memory, time)

2. **File System Restrictions**
   - Whitelist accessible directories
   - Prevent operations outside project root
   - Track file modifications

3. **Network Restrictions** (future)
   - Control outbound network access
   - Log all network operations

**Implementation**:
```elixir
defmodule MultiAgentCoder.Tools.Sandbox do
  @moduledoc """
  Sandboxed command execution environment.
  """

  @type sandbox_config :: %{
    working_dir: Path.t(),
    allowed_paths: [Path.t()],
    env_vars: %{String.t() => String.t()},
    resource_limits: %{
      max_memory_mb: integer(),
      max_cpu_percent: integer(),
      timeout_ms: integer()
    }
  }

  @spec execute(command :: String.t(), config :: sandbox_config()) ::
    {:ok, %{stdout: String.t(), stderr: String.t(), exit_code: integer()}} |
    {:error, reason}

  def execute(command, config) do
    with {:ok, validated} <- validate_command(command, config),
         {:ok, port} <- open_port(validated, config),
         {:ok, result} <- collect_output(port, config.resource_limits.timeout_ms) do
      {:ok, result}
    end
  end

  defp open_port(command, config) do
    port_opts = [
      {:cd, config.working_dir},
      {:env, config.env_vars |> Enum.to_list()},
      :binary,
      :exit_status,
      :stderr_to_stdout,
      {:line, 4096}
    ]

    port = Port.open({:spawn, command}, port_opts)
    {:ok, port}
  rescue
    e -> {:error, {:port_open_failed, e}}
  end
end
```

---

### 6. Execution Monitor (`lib/multi_agent_coder/tools/monitor.ex`)

**Responsibility**: Track and display tool execution in real-time

**Monitoring Features**:

1. **Real-time Status Updates**
   - Broadcast execution events via PubSub
   - Update provider-specific UI panels
   - Show command queue and active executions

2. **Metrics Collection**
   - Command success/failure rates per provider
   - Average execution times
   - Resource usage tracking
   - Most frequently used commands

3. **Execution History**
   - Store recent executions (last 1000)
   - Query by provider, status, time range
   - Export execution logs

**PubSub Events**:
```elixir
# Command submitted
Phoenix.PubSub.broadcast(
  MultiAgentCoder.PubSub,
  "tools:execution",
  {:command_submitted, %{
    command_id: "cmd_123",
    provider: :anthropic,
    command: "mix test",
    timestamp: now()
  }}
)

# Command started
{:command_started, %{command_id: "cmd_123", pid: pid}}

# Output received
{:command_output, %{command_id: "cmd_123", output: "....", type: :stdout}}

# Command completed
{:command_completed, %{command_id: "cmd_123", exit_code: 0, duration_ms: 3200}}

# Command failed
{:command_failed, %{command_id: "cmd_123", reason: "timeout"}}
```

**Monitoring UI Integration**:
```elixir
defmodule MultiAgentCoder.CLI.ToolMonitor do
  @moduledoc """
  Display tool execution status in CLI.
  """

  def display_execution(command_info) do
    IO.puts("""
    ┌─ #{command_info.provider |> provider_label()} ────────────────────┐
    │ 🔧 Running: #{command_info.command}
    │ Status: #{status_icon(command_info.status)} #{command_info.status}
    │ Duration: #{command_info.duration_ms}ms
    │
    │ Output:
    #{format_output(command_info.stdout)}
    └──────────────────────────────────────────────────────────────┘
    """)
  end

  defp status_icon(:running), do: "⚡"
  defp status_icon(:completed), do: "✓"
  defp status_icon(:failed), do: "✗"
  defp status_icon(:pending), do: "⏳"
end
```

---

## Data Flow

### 1. Command Execution Flow

```
Provider Request
      │
      ├─> Coordinator.execute_tool()
      │
      ├─> Classifier.classify()
      │     ├─> Safe? → Auto-approve
      │     ├─> Warning? → Prompt if configured
      │     └─> Dangerous? → Always prompt
      │
      ├─> Approver.check_approval()
      │     ├─> Approved? → Continue
      │     └─> Denied? → Return error
      │
      ├─> Check for conflicts
      │     ├─> No conflict? → Execute immediately
      │     └─> Conflict? → Queue for later
      │
      ├─> Executor.execute()
      │     ├─> Sandbox.prepare()
      │     ├─> Sandbox.execute()
      │     └─> Capture results
      │
      ├─> Monitor.record_execution()
      │     ├─> Store in history
      │     ├─> Update metrics
      │     └─> Broadcast events
      │
      └─> Return result to provider
```

### 2. Concurrent Execution with Conflict Detection

```
Provider A: Write file.ex        Provider B: Write file.ex
      │                                  │
      ├─────────────┬────────────────────┤
                    │
            Conflict Detector
                    │
      ┌─────────────┴─────────────┐
      │                           │
    Execute A                  Queue B
      │                           │
      └──────> A Completes        │
                  │               │
            Release Lock          │
                  │               │
                  └──────> Execute B
```

---

## Configuration

### Application Config

```elixir
# config/config.exs
config :multi_agent_coder, :tools,
  # Sandbox configuration
  sandbox_enabled: true,
  sandbox_working_dir: nil,  # nil = project root
  sandbox_allowed_paths: ["lib", "test", "config", "mix.exs"],
  sandbox_resource_limits: %{
    max_memory_mb: 512,
    max_cpu_percent: 80,
    timeout_ms: 300_000  # 5 minutes
  },

  # Approval configuration
  approval_mode: :auto,
  auto_approve_safe: true,
  prompt_on_warning: true,
  deny_dangerous: false,

  # Execution configuration
  max_concurrent_executions: 3,
  max_queue_size: 10,
  execution_history_limit: 1000,

  # Monitoring configuration
  enable_metrics: true,
  log_all_commands: true,
  pubsub_topic: "tools:execution"
```

---

## Integration Points

### 1. Provider Integration

Providers access tools through the Coordinator:

```elixir
defmodule MultiAgentCoder.Agent.Worker do
  alias MultiAgentCoder.Tools.Coordinator

  def execute_with_tools(task) do
    # Provider generates tool requests
    tool_requests = parse_tool_requests_from_response(response)

    # Execute tools
    results = Enum.map(tool_requests, fn request ->
      Coordinator.execute_tool(provider_id(), request)
    end)

    # Feed results back to provider for next iteration
    continue_with_results(results)
  end
end
```

### 2. CLI Integration

Add commands for tool management:

```elixir
# lib/multi_agent_coder/cli/command.ex

def handle_command("commands") do
  Coordinator.list_commands()
  |> format_command_list()
  |> IO.puts()
end

def handle_command("approve " <> command_id) do
  Coordinator.approve_command(command_id)
end

def handle_command("output " <> command_id) do
  Coordinator.get_command_output(command_id)
  |> IO.puts()
end
```

### 3. Real-time Display Integration

Subscribe to execution events:

```elixir
defmodule MultiAgentCoder.CLI.InteractiveSession do
  def init do
    Phoenix.PubSub.subscribe(MultiAgentCoder.PubSub, "tools:execution")
    # ...
  end

  def handle_info({:command_output, info}, state) do
    display_tool_output(info)
    {:noreply, state}
  end
end
```

---

## Security Considerations

### 1. Command Injection Prevention

```elixir
defp validate_command(command) do
  # Prevent shell injection
  if String.contains?(command, [";", "&&", "||", "|", "`", "$("]) do
    {:error, :shell_injection_detected}
  else
    {:ok, command}
  end
end
```

### 2. Path Traversal Prevention

```elixir
defp validate_file_path(path, config) do
  abs_path = Path.expand(path, config.working_dir)

  allowed = Enum.any?(config.allowed_paths, fn allowed_path ->
    String.starts_with?(abs_path, Path.expand(allowed_path, config.working_dir))
  end)

  if allowed do
    {:ok, abs_path}
  else
    {:error, :path_not_allowed}
  end
end
```

### 3. Resource Limit Enforcement

```elixir
defp enforce_limits(port, limits) do
  # Set OS-level limits using ulimit or cgroups
  # Monitor and kill if exceeded
end
```

---

## Testing Strategy

### 1. Unit Tests

```elixir
# test/multi_agent_coder/tools/classifier_test.exs
defmodule MultiAgentCoder.Tools.ClassifierTest do
  use ExUnit.Case

  test "classifies safe commands correctly" do
    assert {:ok, %{level: :safe}} = Classifier.classify("mix test")
    assert {:ok, %{level: :safe}} = Classifier.classify("git status")
  end

  test "classifies dangerous commands correctly" do
    assert {:ok, %{level: :dangerous}} = Classifier.classify("rm -rf /")
    assert {:ok, %{level: :dangerous}} = Classifier.classify("mix ecto.drop")
  end

  test "blocks prohibited commands" do
    assert {:error, :blocked} = Classifier.classify("sudo rm -rf /")
  end
end
```

### 2. Integration Tests

```elixir
# test/multi_agent_coder/tools/executor_test.exs
defmodule MultiAgentCoder.Tools.ExecutorTest do
  use ExUnit.Case

  test "executes safe command successfully" do
    request = %ToolRequest{type: :bash, command: "echo hello"}
    assert {:ok, result} = Executor.execute(request)
    assert result.exit_code == 0
    assert result.stdout =~ "hello"
  end

  test "captures stderr on command failure" do
    request = %ToolRequest{type: :bash, command: "mix test nonexistent"}
    assert {:ok, result} = Executor.execute(request)
    assert result.exit_code != 0
    assert result.stderr != ""
  end
end
```

### 3. Concurrency Tests

```elixir
test "detects file write conflicts" do
  request1 = %ToolRequest{type: :file_write, path: "test.txt", content: "A"}
  request2 = %ToolRequest{type: :file_write, path: "test.txt", content: "B"}

  # Start both concurrently
  task1 = Task.async(fn -> Coordinator.execute_tool(:provider1, request1) end)
  task2 = Task.async(fn -> Coordinator.execute_tool(:provider2, request2) end)

  # One should complete, one should queue
  results = Task.await_many([task1, task2])

  assert Enum.any?(results, fn r -> r.status == :completed end)
  assert Enum.any?(results, fn r -> r.status == :queued end)
end
```

---

## Performance Considerations

### 1. Command Queue Management

- Limit queue size per provider (default: 10)
- Implement priority-based execution
- Auto-cancel stale queued commands

### 2. Output Buffering

- Stream large outputs incrementally
- Limit stored output size (default: 100KB per command)
- Provide "view full output" command for large results

### 3. Metrics Storage

- Use ETS for in-memory metrics
- Rotate execution history (keep last 1000)
- Aggregate historical metrics periodically

---

## Future Enhancements

### Phase 2 Features

1. **Advanced Sandboxing**
   - Docker container isolation
   - Network access controls
   - Custom sandbox environments per provider

2. **Tool Plugins**
   - Extensible tool system
   - Custom tool definitions
   - Third-party tool integrations

3. **Collaborative Execution**
   - Providers can share tool results
   - Coordinated multi-provider workflows
   - Result caching and reuse

4. **Web Dashboard**
   - Visual execution monitoring
   - Command approval UI
   - Execution analytics

---

## Implementation Roadmap

This architecture will be implemented in phases:

1. **Phase 1**: Core Foundation (Issues #16.1-16.3)
   - Basic executor and sandbox
   - Command classifier and approver
   - Simple monitoring

2. **Phase 2**: Concurrency & Safety (Issues #16.4-16.6)
   - Conflict detection
   - Resource locking
   - Advanced approval workflows

3. **Phase 3**: Integration & Polish (Issues #16.7-16.9)
   - Provider integration
   - CLI commands
   - Real-time display

4. **Phase 4**: Advanced Features (Future)
   - Plugin system
   - Advanced sandboxing
   - Web dashboard

---

## Success Metrics

- ✅ Providers can execute commands successfully
- ✅ No command injection vulnerabilities
- ✅ Safe commands auto-approved in <10ms
- ✅ Concurrent executions work without conflicts
- ✅ Real-time monitoring displays accurately
- ✅ 100% test coverage on security-critical components

---

## Appendix: Example Workflows

### Workflow 1: Provider Runs Tests

```
1. Provider generates code
2. Provider requests: `mix test`
3. Classifier: SAFE → Auto-approve
4. Executor: Run in sandbox
5. Capture output and exit code
6. Feed results to provider
7. Provider fixes issues if tests fail
8. Repeat until tests pass
```

### Workflow 2: Provider Makes Database Changes

```
1. Provider requests: `mix ecto.drop`
2. Classifier: DANGEROUS
3. Approver: Prompt user
4. User approves
5. Executor: Run in sandbox
6. Monitor: Display confirmation
7. Provider continues with migration
```

### Workflow 3: Concurrent Providers

```
Provider A                    Provider B
    │                            │
    ├─> Read file.ex             ├─> Compile
    │   (No conflict)            │   (No conflict)
    │                            │
    ├─> Both execute ────────────┤
    │   concurrently              │
    │                            │
    ├─> Write file.ex            ├─> Write file.ex
    │   (Conflict detected!)     │   (Queued)
    │                            │
    └─> A completes              │
                                 │
                          └─> B executes now
```

---

**Document Version**: 1.0
**Next Review**: After Phase 1 implementation
**Maintained By**: Engineering Team
