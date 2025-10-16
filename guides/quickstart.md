# Quickstart Guide

Welcome to MultiAgent Coder! This guide will help you get started with the CLI and explore its current features.

## Table of Contents

- [Installation](#installation)
- [Initial Setup](#initial-setup)
- [Basic Usage](#basic-usage)
- [Interactive Mode](#interactive-mode)
- [Task Allocation](#task-allocation)
- [Session Management](#session-management)
- [Advanced Features](#advanced-features)

## Installation

### Prerequisites

- Elixir 1.18 or later
- Erlang/OTP 26 or later
- API keys for the providers you want to use (OpenAI, Anthropic, DeepSeek, Perplexity)

### Building the CLI

```bash
# Clone the repository
git clone https://github.com/justin4957/multi_agent_coder.git
cd multi_agent_coder

# Install dependencies
mix deps.get

# Build the escript executable
mix escript.build

# The executable will be at ./multi_agent_coder
```

## Initial Setup

Before using MultiAgent Coder, you need to configure your API keys:

```bash
./multi_agent_coder --setup
```

This will walk you through an interactive setup where you can:
- Configure API keys for OpenAI, Anthropic, DeepSeek, and Perplexity
- Set up a local Ollama endpoint (optional)
- Choose which providers to enable

API keys can be entered directly or referenced from environment variables:
```
Enter API key (or env:VAR_NAME): env:OPENAI_API_KEY
```

Configuration is stored in `~/.multi_agent_coder/config.json`.

## Basic Usage

### Single Query Mode

Execute a coding task and get responses from all configured providers:

```bash
./multi_agent_coder "Write a function to reverse a linked list in Elixir"
```

**Options:**

- `-s, --strategy STRATEGY` - Choose routing strategy
  - `all` - Query all providers concurrently (default)
  - `sequential` - Query providers one after another
  - `dialectical` - Run a dialectical process (providers critique each other)

- `-p, --providers LIST` - Use specific providers only
  ```bash
  ./multi_agent_coder -p openai,anthropic "Implement quicksort"
  ```

- `-c, --context JSON` - Provide additional context
  ```bash
  ./multi_agent_coder -c '{"language":"elixir"}' "Write a parser"
  ```

- `-o, --output FILE` - Save results to a file
  ```bash
  ./multi_agent_coder -o result.md "Explain monads"
  ```

### Example Workflow

```bash
# Query all providers
./multi_agent_coder "Implement bubble sort algorithm"

# Use only OpenAI and Anthropic
./multi_agent_coder -p openai,anthropic "Refactor this authentication code"

# Save output to file
./multi_agent_coder -o solution.md "Write a binary search tree in Elixir"
```

## Interactive Mode

Interactive mode provides a rich REPL experience with concurrent streaming, command history, and task management.

### Starting Interactive Mode

```bash
./multi_agent_coder -i
```

Or with specific providers:
```bash
./multi_agent_coder -i -p openai,anthropic
```

### Interactive Commands

#### Basic Commands

```
<your question>    Query all providers with concurrent streaming
help              Show help message
exit / quit / q   Exit interactive mode
```

#### Response Management

```
accept <n>        Accept and optionally save response from provider N
                 (1 = first provider, 2 = second, etc.)
compare           Show all responses side-by-side
save <name>       Save current session to sessions/<name>.json
```

#### History Commands

```
history                      Show recent command history
history search <pattern>     Search history for matching commands
history clear                Clear all history
```

History is persisted at `~/.multi_agent_coder/history`.

#### Task Allocation Commands

Manage a queue of coding tasks with intelligent provider routing:

```
task queue <desc>       Add task to allocation queue with auto-routing
task list              Show all tasks (pending, running, completed, failed)
task status            Show queue statistics
task track             Show detailed progress tracking for active tasks
task cancel <id>       Cancel a queued or running task
```

### Multi-line Input

The REPL supports multi-line input in two ways:

1. **Backslash continuation:**
   ```
   > Write a function to \
   ... parse CSV files
   ```

2. **Auto-detection:** Unclosed quotes and brackets automatically continue to next line
   ```
   > def hello do
   ... IO.puts("world")
   ... end
   ```

### Example Interactive Session

```
$ ./multi_agent_coder -i

Multi-Agent Coder - Interactive Streaming Mode
Active providers: openai, anthropic, deepseek
Display mode: stacked

> Write a function to check if a number is prime

[Concurrent display shows all providers streaming responses]

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
All providers completed!
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

> compare
[Shows side-by-side comparison of all responses]

> accept 2
[Displays Anthropic's response]
Would you like to save this to a file? (y/n)
> y
Enter filename:
> is_prime.ex
✓ Saved to is_prime.ex

> task queue "Implement bubble sort algorithm"
✓ Task queued: task_1234567890
  Description: Implement bubble sort algorithm
  Assigned to: openai
  Priority: 5

> task status
━━━━━━━━━━━━ Queue Status ━━━━━━━━━━━━
Pending:   1
Running:   0
Completed: 0
Failed:    0
Total:     1

> exit
Goodbye! 👋
```

## Task Allocation

The task allocation system intelligently routes coding tasks to the most appropriate AI providers based on their capabilities.

### Provider Capabilities

| Provider | Best For | Example Keywords |
|----------|----------|------------------|
| **OpenAI** | Algorithms, data structures, optimization | "algorithm", "sort", "optimize" |
| **Anthropic** | Refactoring, architecture, best practices | "refactor", "design", "architecture" |
| **DeepSeek** | Code completion, quick fixes, boilerplate | "complete", "quick fix", "typo" |
| **Perplexity** | Research, API usage, documentation | "research", "best practices", "api" |
| **Local** | Privacy-sensitive tasks, offline work | Custom models, offline |

### Auto-allocation Example

```
> task queue "Implement quicksort algorithm"
✓ Task queued: task_123
  Assigned to: openai
  Priority: 5

> task queue "Refactor authentication module"
✓ Task queued: task_124
  Assigned to: anthropic
  Priority: 5
```

Tasks are automatically routed based on keyword detection in the description.

### Manual Priority

Tasks can have priority levels 1-10 (higher = more urgent). By default, all tasks have priority 5.

### Task Dependencies

Tasks can depend on other tasks. Dependent tasks won't execute until their dependencies complete.

### Queue Management

View all tasks in the queue:
```
> task list

━━━━━━━━━━━━ Task Queue ━━━━━━━━━━━━

Pending Tasks:
  1. [task_123] Implement quicksort algorithm
     Priority: 5 | Assigned to: openai

Running Tasks:
  1. [task_122] Write unit tests
     Elapsed: 45s | Assigned to: deepseek

Completed: 3
```

Track active task progress:
```
> task track

━━━━━━━━━━━━ Task Tracking ━━━━━━━━━━━━
1. [task_122] deepseek
   Progress: 75.5%
   Elapsed: 48s
   Tokens: 1250
   ETA: 16s

Provider Statistics:

openai:
  Active: 0
  Completed: 2
  Failed: 0
  Tokens: 5400
  Avg completion: 62.5s
```

## Session Management

Sessions capture interactions with providers and can be saved for later review.

### Saving Sessions

In interactive mode:
```
> save my-session-name
✓ Session saved to sessions/my-session-name.json
```

Sessions include:
- The prompt/question
- All provider responses
- Provider list
- Timestamp

### Session Storage Location

- Interactive sessions: `./sessions/<name>.json`
- System sessions: `~/.multi_agent_coder/sessions/`

## Advanced Features

### Concurrent Display Modes

The interactive mode supports different display layouts:

- **Stacked** (default): Providers shown one after another
- **Split Horizontal**: Two providers side-by-side
- **Split Vertical**: Vertical split for two providers
- **Tiled**: Grid layout for multiple providers

Configure in `config.exs`:
```elixir
config :multi_agent_coder, :display,
  layout: :split_horizontal,
  show_timestamps: true,
  color_scheme: :provider
```

### Real-time Streaming

All providers support real-time streaming where responses appear character-by-character or line-by-line as they're generated.

Streaming events are broadcast via Phoenix PubSub, allowing:
- Live progress monitoring
- Concurrent display updates
- Event-driven architecture

### Token Tracking

Track token usage and costs per provider:
- View token counts in task tracking
- Monitor cumulative usage
- Estimate costs (when provider pricing available)

### REPL Features

The enhanced REPL includes:
- **Persistent command history** (`~/.multi_agent_coder/history`)
- **Tab completion** (coming soon)
- **Multi-line editing** with smart bracket detection
- **Search history** by pattern

### Strategies

Beyond the basic `all` strategy, you can use:

- **Sequential**: Query providers one by one
  ```bash
  ./multi_agent_coder -s sequential "Explain functional programming"
  ```

- **Dialectical**: Multi-round discussion where providers critique each other
  ```bash
  ./multi_agent_coder -s dialectical "Design a microservices architecture"
  ```

## Configuration Files

### System Configuration

`~/.multi_agent_coder/config.json`:
```json
{
  "providers": {
    "openai": {
      "api_key": "sk-...",
      "model": "gpt-4",
      "enabled": true
    },
    "anthropic": {
      "api_key": "sk-ant-...",
      "model": "claude-sonnet-4-5",
      "enabled": true
    }
  }
}
```

### Application Configuration

`config/config.exs`:
```elixir
config :multi_agent_coder,
  providers: [
    openai: [api_key: {:system, "OPENAI_API_KEY"}, model: "gpt-4"],
    anthropic: [api_key: {:system, "ANTHROPIC_API_KEY"}, model: "claude-sonnet-4-5"]
  ],
  default_strategy: :all,
  timeout: 120_000
```

## Troubleshooting

### API Key Issues

If you get authentication errors:
1. Run `./multi_agent_coder --setup` to reconfigure
2. Check environment variables are set correctly
3. Verify API keys are valid and have sufficient credits

### Provider Unavailable

If a provider fails:
- Other providers continue working (fault isolation)
- Check the logs for specific error messages
- Verify network connectivity
- Check provider status pages

### Slow Responses

- Increase timeout with `timeout: 180_000` in config
- Use faster models (e.g., `gpt-3.5-turbo` instead of `gpt-4`)
- Check your network connection

## Next Steps

- **Explore the API**: Run `mix docs` and browse the module documentation
- **Customize providers**: Edit `config/config.exs` to tune models and parameters
- **Try different strategies**: Experiment with sequential and dialectical modes
- **Build automations**: Use task allocation to queue up multiple coding tasks
- **Contribute**: Check out the [GitHub repository](https://github.com/justin4957/multi_agent_coder) for issues and contribution guidelines

## Getting Help

- Run `./multi_agent_coder -h` for command-line help
- Type `help` in interactive mode for command reference
- Check the [README](README.md) for architectural overview
- Browse module documentation: `mix docs`
- Report issues: [GitHub Issues](https://github.com/justin4957/multi_agent_coder/issues)

---

*Last updated: 2025-10-16*
