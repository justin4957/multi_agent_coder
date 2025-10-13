# MultiAgent Coder

> Elixir-based multi-agent AI coding CLI with concurrent agent orchestration

MultiAgent Coder is a powerful command-line tool that harnesses multiple AI providers (OpenAI, Anthropic, Local LLMs) concurrently to solve coding problems. Built with Elixir's robust concurrency model, it offers true parallelism, fault tolerance through supervision trees, and real-time progress monitoring.

## Features

- **Concurrent Execution**: Query multiple AI providers simultaneously using Elixir's lightweight processes
- **Multiple Routing Strategies**:
  - `all` - Query all providers in parallel
  - `sequential` - Chain results (each agent sees previous outputs)
  - `dialectical` - Thesis/Antithesis/Synthesis workflow for iterative refinement
  - Custom provider selection
- **Real-time Monitoring**: Live progress updates via Phoenix.PubSub
- **Fault Tolerance**: Supervision trees ensure reliability - if one agent crashes, others continue
- **Provider Support**:
  - OpenAI (GPT-4, GPT-3.5)
  - Anthropic (Claude Sonnet, Claude Opus)
  - Local LLMs (via Ollama)
- **Interactive Mode**: Continuous conversation with context awareness
- **CLI & Programmatic APIs**: Use as a command-line tool or integrate into your applications

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
- API keys for desired providers:
  - `OPENAI_API_KEY` for OpenAI
  - `ANTHROPIC_API_KEY` for Anthropic
- (Optional) [Ollama](https://ollama.ai/) for local LLM support

### Setup

1. Clone the repository:
```bash
git clone https://github.com/justin4957/multi_agent_coder.git
cd multi_agent_coder
```

2. Install dependencies:
```bash
mix deps.get
```

3. Configure your API keys:
```bash
export OPENAI_API_KEY="your-openai-key"
export ANTHROPIC_API_KEY="your-anthropic-key"
```

4. Compile and build the CLI:
```bash
mix escript.build
```

This creates an executable `multi_agent_coder` in the project root.

## Usage

### Command-Line Interface

**Basic usage** - Query all providers:
```bash
./multi_agent_coder "Write a function to reverse a linked list in Elixir"
```

**Specify a routing strategy**:
```bash
# Dialectical workflow (thesis → critique → synthesis)
./multi_agent_coder -s dialectical "Implement quicksort in Elixir"

# Sequential (each agent sees previous results)
./multi_agent_coder -s sequential "Optimize this database query"
```

**Select specific providers**:
```bash
./multi_agent_coder -p openai,anthropic "Create a GenServer for rate limiting"
```

**Save output to file**:
```bash
./multi_agent_coder -o solution.ex "Write a binary search tree module"
```

**Interactive mode**:
```bash
./multi_agent_coder -i
> ask Write a function to calculate Fibonacci numbers
> compare Implement a REST API client
> dialectic Create a distributed task queue
> exit
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

## Configuration

Edit `config/config.exs` to customize providers and settings:

```elixir
config :multi_agent_coder,
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
    local: [
      model: "codellama:latest",
      endpoint: "http://localhost:11434",
      temperature: 0.1
    ]
  ],
  default_strategy: :all,
  timeout: 120_000
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
│   ├── application.ex           # OTP Application
│   ├── agent/
│   │   ├── supervisor.ex        # Supervises all agents
│   │   ├── worker.ex            # Generic agent worker
│   │   ├── openai.ex            # OpenAI integration
│   │   ├── anthropic.ex         # Anthropic integration
│   │   └── local.ex             # Local LLM integration
│   ├── router/
│   │   └── task_router.ex       # Task routing logic
│   ├── session/
│   │   └── manager.ex           # Session state management
│   ├── monitor/
│   │   ├── realtime.ex          # Real-time monitoring
│   │   └── collector.ex         # Result aggregation
│   └── cli/
│       ├── command.ex           # CLI command handling
│       └── formatter.ex         # Output formatting
└── multi_agent_coder.ex         # Main module
```

## Contributing

We welcome contributions! Please see our contributing guidelines and code of conduct.

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## Roadmap

See the [open issues](https://github.com/justin4957/multi_agent_coder/issues) for planned features and known issues.

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Acknowledgments

- Built with [Elixir](https://elixir-lang.org/) and the BEAM VM
- Uses [Phoenix.PubSub](https://hexdocs.pm/phoenix_pubsub/) for real-time updates
- Integrates with leading AI providers: OpenAI, Anthropic, and Ollama

---

**Made with Elixir and the power of concurrent AI agents**
