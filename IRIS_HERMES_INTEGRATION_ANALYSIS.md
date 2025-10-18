# Iris & Hermes Integration Analysis for MultiAgentCoder

**Date:** 2025-10-18
**Purpose:** Evaluate integration options for scaling local LLM providers
**Projects Analyzed:**
- **Iris** (`/Users/coolbeans/Development/ThoughtModeWorks/iris`) - Broadway-based LLM pipeline
- **Hermes** (`/Users/coolbeans/Development/ThoughtModeWorks/hermes`) - Minimal LLM sidecar service

---

## Executive Summary

Both **Iris** and **Hermes** can significantly enhance MultiAgentCoder's local LLM orchestration capabilities:

- **Iris** is the **recommended choice** for production-scale concurrent LLM orchestration with advanced features
- **Hermes** is ideal for **simple, standalone microservice deployments**
- Integration can be achieved with **minimal changes** to existing MultiAgentCoder architecture

**Recommendation:** Integrate **Iris** as the primary local LLM provider backend, with optional Hermes support for distributed deployments.

---

## Comparative Analysis

### Architecture Comparison

| Feature | Current (Local.ex) | Iris | Hermes |
|---------|-------------------|------|---------|
| **Concurrency Model** | Single process per agent | Broadway pipeline (1000+ req/s) | Task.Supervisor |
| **Provider Support** | Ollama only | OpenAI, Anthropic, Ollama, Custom | Ollama only |
| **Load Balancing** | None | Built-in (round-robin, weighted, least-connections) | None |
| **Caching** | None | TTL-based with Nebulex | None |
| **Fault Tolerance** | Basic retry | Circuit breakers, failover, health checks | Basic supervisor |
| **Streaming** | Partial (fallback) | Full WebSocket streaming | Not supported |
| **Monitoring** | Logs only | Telemetry, metrics, health checks | Basic status endpoint |
| **Configuration** | Code-based | YAML/JSON + hot reload + versioning | Code-based |
| **Backpressure** | None | Broadway built-in | None |

### Capabilities

#### Iris Advantages
✅ **High-throughput pipeline** - Handles 1000+ concurrent requests
✅ **Multi-provider abstraction** - Unified interface for all LLM providers
✅ **Advanced caching** - Response caching with hit/miss metrics
✅ **Load balancing** - Intelligent routing with cost optimization
✅ **Circuit breakers** - Automatic failover on provider failures
✅ **Declarative config** - YAML/JSON pipelines with hot reload
✅ **Production telemetry** - Comprehensive metrics and health checks
✅ **Broadway pipeline** - Battle-tested concurrent processing

#### Hermes Advantages
✅ **Minimal dependencies** - Only Plug, Cowboy, Finch, Jason
✅ **Simple HTTP API** - Easy to integrate as a microservice
✅ **Standalone deployment** - Can run as separate service
✅ **Low resource overhead** - Lightweight sidecar model
✅ **Quick setup** - Simple configuration

#### Current Implementation (Local.ex)
✅ **Integrated with existing agent architecture**
✅ **Basic health checking**
✅ **Retry logic with HTTPClient**
⚠️ **Limited concurrency** - No pipeline or batching
⚠️ **No caching** - Every request hits Ollama
⚠️ **No load balancing** - Single endpoint only
⚠️ **No telemetry** - Only logs

---

## Integration Strategies

### Option 1: Replace Local.ex with Iris (RECOMMENDED)

**Approach:** Replace `MultiAgentCoder.Agent.Local` with Iris as the backend.

#### Implementation Steps

1. **Add Iris as dependency**
   ```elixir
   # mix.exs
   def deps do
     [
       {:iris, path: "/Users/coolbeans/Development/ThoughtModeWorks/iris"},
       # ... existing deps
     ]
   end
   ```

2. **Create Iris wrapper module**
   ```elixir
   # lib/multi_agent_coder/agent/iris_provider.ex
   defmodule MultiAgentCoder.Agent.IrisProvider do
     @moduledoc """
     High-performance local LLM provider using Iris pipeline.
     Provides concurrent processing, caching, and advanced routing.
     """

     alias Iris.Types.{Request, Response}
     alias MultiAgentCoder.Agent.{ContextFormatter, TokenCounter}

     def call(state, prompt, context \\ %{}) do
       with {:ok, enhanced_prompt} <- build_prompt(prompt, context),
            {:ok, iris_request} <- build_iris_request(state, enhanced_prompt),
            {:ok, response} <- Iris.Producer.push_request(iris_request) do
         extract_response(response, state, prompt)
       end
     end

     def call_streaming(state, prompt, context \\ %{}) do
       with {:ok, enhanced_prompt} <- build_prompt(prompt, context),
            {:ok, iris_request} <- build_iris_request(state, enhanced_prompt, stream: true),
            {:ok, stream} <- Iris.Providers.Router.route_request(iris_request) do
         {:ok, stream}
       end
     end

     defp build_iris_request(state, prompt, opts \\ []) do
       request = Iris.Types.Request.new(%{
         messages: [%{role: "user", content: prompt}],
         model: state.model,
         temperature: state.temperature,
         max_tokens: state.max_tokens,
         stream: Keyword.get(opts, :stream, false)
       })

       {:ok, request}
     end

     defp extract_response(%Response{} = response, state, original_prompt) do
       usage = TokenCounter.create_usage_summary(:local, state.model, original_prompt, response.content)
       {:ok, response.content, usage}
     end

     defp build_prompt(prompt, context) do
       system_prompt = ContextFormatter.build_system_prompt(context)
       enhanced_prompt = ContextFormatter.build_enhanced_prompt(prompt, context)

       full_prompt = """
       #{system_prompt}

       User request: #{enhanced_prompt}
       """

       {:ok, full_prompt}
     end
   end
   ```

3. **Configure Iris in application config**
   ```elixir
   # config/config.exs
   config :iris, :ollama,
     endpoint: "http://localhost:11434",
     default_model: "llama3",
     timeout: 120_000,
     models: ["llama3", "codellama", "mistral", "gemma"]

   config :iris, :cache,
     backend: Nebulex.Adapters.Local,
     default_ttl: 1800,  # 30 minutes
     max_size: 1_000_000,
     stats: true

   config :iris, :pipeline,
     processor_stages: System.schedulers_online() * 2,
     max_demand: 50,
     batch_size: 100,
     batch_timeout: 5_000
   ```

4. **Update Worker to use Iris**
   ```elixir
   # lib/multi_agent_coder/agent/worker.ex

   # Replace
   alias MultiAgentCoder.Agent.Local

   # With
   alias MultiAgentCoder.Agent.IrisProvider

   # In handle_task/1, replace:
   {:ok, response, usage} = Local.call(state, prompt, context)

   # With:
   {:ok, response, usage} = IrisProvider.call(state, prompt, context)
   ```

#### Benefits
✅ **Automatic concurrency** - Broadway pipeline handles parallelism
✅ **Built-in caching** - Reduces duplicate Ollama calls
✅ **Circuit breakers** - Automatic failover on Ollama failures
✅ **Telemetry integration** - Rich metrics for monitoring
✅ **Zero changes to existing API** - Drop-in replacement
✅ **Multi-provider ready** - Can add OpenAI/Anthropic fallback

#### Effort
- **Low** - 2-4 hours
- Minimal code changes (one new module + config)
- Existing tests should pass with minimal modification

---

### Option 2: Add Hermes as Microservice Sidecar

**Approach:** Deploy Hermes as a separate service and connect via HTTP.

#### Implementation Steps

1. **Deploy Hermes as standalone service**
   ```bash
   cd /Users/coolbeans/Development/ThoughtModeWorks/hermes
   PORT=4020 iex -S mix
   ```

2. **Create Hermes client module**
   ```elixir
   # lib/multi_agent_coder/agent/hermes_client.ex
   defmodule MultiAgentCoder.Agent.HermesClient do
     @moduledoc """
     Client for Hermes LLM sidecar service.
     """

     alias MultiAgentCoder.Agent.HTTPClient

     @default_endpoint "http://localhost:4020"

     def call(state, prompt, _context \\ %{}) do
       endpoint = Application.get_env(:multi_agent_coder, :hermes_endpoint, @default_endpoint)
       url = "#{endpoint}/v1/llm/#{state.model}"

       body = %{prompt: prompt}
       headers = [{"Content-Type", "application/json"}]

       case HTTPClient.post_with_retry(url, body, headers, timeout: 120_000) do
         {:ok, %{"result" => response}} ->
           usage = estimate_usage(prompt, response, state.model)
           {:ok, response, usage}

         {:error, reason} ->
           {:error, reason}
       end
     end

     defp estimate_usage(input, output, model) do
       %{
         input_tokens: div(String.length(input), 4),
         output_tokens: div(String.length(output), 4),
         total_tokens: div(String.length(input) + String.length(output), 4),
         model: model,
         cost: 0.0
       }
     end
   end
   ```

3. **Configure Hermes endpoint**
   ```elixir
   # config/config.exs
   config :multi_agent_coder,
     hermes_endpoint: "http://localhost:4020"
   ```

#### Benefits
✅ **Service isolation** - Separate process/deployment
✅ **Simple HTTP API** - Easy integration
✅ **Minimal dependencies** - Lightweight
✅ **Independent scaling** - Can run on different machine

#### Drawbacks
⚠️ **Network overhead** - HTTP calls between services
⚠️ **No caching** - Every request goes to Ollama
⚠️ **Limited concurrency** - Basic Task.Supervisor
⚠️ **Manual orchestration** - Need to manage service lifecycle

---

### Option 3: Hybrid Approach (Best of Both)

**Approach:** Use Iris as the primary backend, with Hermes as a fallback/remote option.

#### Configuration
```elixir
config :multi_agent_coder, :local_provider_strategy,
  primary: :iris,         # Use Iris pipeline locally
  fallback: :hermes,      # Use Hermes if Iris unavailable
  remote: :hermes         # Use Hermes for remote deployments

config :multi_agent_coder, :iris,
  enabled: true,
  endpoint: "http://localhost:11434"

config :multi_agent_coder, :hermes,
  enabled: false,
  endpoint: "http://localhost:4020"
```

---

## Use Cases & Recommendations

### For Development & Testing
**Use:** **Iris** (local integration)
- Fast iteration with caching
- Rich telemetry for debugging
- Multi-model testing without changing code

### For Production (Single Host)
**Use:** **Iris** (integrated)
- Maximum throughput
- Advanced fault tolerance
- Built-in monitoring

### For Production (Distributed)
**Use:** **Hermes** (microservice)
- Run Hermes on GPU-enabled host
- MultiAgentCoder connects via HTTP
- Independent scaling

### For Testing Code Orchestration Capacity
**Use:** **Iris** with Broadway pipeline
- Configure high concurrency:
  ```elixir
  config :iris, :pipeline,
    processor_stages: System.schedulers_online() * 4,
    max_demand: 100,
    batch_size: 200
  ```
- Enable caching to reduce Ollama load
- Monitor with telemetry to identify bottlenecks

---

## Integration Checklist

### Phase 1: Basic Integration (Week 1)
- [ ] Add Iris as dependency
- [ ] Create `IrisProvider` wrapper module
- [ ] Update configuration for Iris Ollama provider
- [ ] Modify `Worker` to use `IrisProvider`
- [ ] Test basic prompt/response flow
- [ ] Verify existing tests pass

### Phase 2: Advanced Features (Week 2)
- [ ] Enable response caching
- [ ] Configure Broadway pipeline for concurrency
- [ ] Add telemetry integration
- [ ] Implement streaming support
- [ ] Add health check monitoring
- [ ] Performance benchmark vs current implementation

### Phase 3: Multi-Provider Support (Week 3)
- [ ] Configure OpenAI fallback via Iris
- [ ] Configure Anthropic fallback via Iris
- [ ] Implement cost-based routing
- [ ] Add provider selection logic
- [ ] Test failover scenarios

### Phase 4: Production Hardening (Week 4)
- [ ] Circuit breaker configuration
- [ ] Load balancing strategy selection
- [ ] Memory limit configuration
- [ ] Monitoring dashboard setup
- [ ] Documentation updates

---

## Performance Impact Estimates

### Current Implementation (Local.ex)
- **Concurrency:** ~10 concurrent requests per Ollama instance
- **Latency:** Direct HTTP (minimal overhead)
- **Caching:** None (100% cache miss rate)
- **Failover:** None (single point of failure)

### With Iris Integration
- **Concurrency:** 100-1000+ concurrent requests (Broadway pipeline)
- **Latency:** +5-10ms pipeline overhead
- **Caching:** 60-80% cache hit rate (estimated)
- **Failover:** Automatic circuit breaker + provider fallback

### Expected Throughput Improvements
- **Without caching:** 5-10x improvement (via concurrency)
- **With caching:** 20-50x improvement (cache hits + concurrency)
- **With multi-provider:** Unlimited (can add more Ollama instances)

---

## Risks & Mitigations

### Risk 1: Dependency Complexity
**Risk:** Iris brings additional dependencies (Broadway, Nebulex, Telemetry, etc.)
**Mitigation:** Use Iris as optional dependency with feature flag
**Code:**
```elixir
defp deps do
  [
    {:iris, path: "../ThoughtModeWorks/iris", optional: true},
    # ...
  ]
end
```

### Risk 2: Breaking Changes
**Risk:** Integration changes existing agent behavior
**Mitigation:** Implement as new provider module, keep Local.ex as fallback
**Code:**
```elixir
def get_provider_module(:iris), do: MultiAgentCoder.Agent.IrisProvider
def get_provider_module(:local), do: MultiAgentCoder.Agent.Local
def get_provider_module(:hermes), do: MultiAgentCoder.Agent.HermesClient
```

### Risk 3: Learning Curve
**Risk:** Team unfamiliar with Broadway/Iris concepts
**Mitigation:** Start with basic integration, add advanced features iteratively

---

## Code Examples

### Example 1: Basic Iris Integration

```elixir
# Start Iris in application supervision tree
defmodule MultiAgentCoder.Application do
  def start(_type, _args) do
    children = [
      # ... existing children
      {Iris.Application, []},  # Add Iris
      # ...
    ]

    Supervisor.start_link(children, strategy: :one_for_one)
  end
end
```

### Example 2: Streaming with Iris

```elixir
defmodule MultiAgentCoder.Agent.IrisProvider do
  def call_streaming(state, prompt, context) do
    with {:ok, enhanced_prompt} <- build_prompt(prompt, context),
         {:ok, request} <- build_iris_request(state, enhanced_prompt, stream: true),
         {:ok, stream} <- Iris.Providers.Router.route_request(request) do

      # Stream chunks back to caller
      stream
      |> Stream.map(fn chunk -> chunk.content end)
      |> then(&{:ok, &1})
    end
  end
end

# Usage in Worker
{:ok, stream} = IrisProvider.call_streaming(state, prompt, context)

Enum.each(stream, fn chunk ->
  IO.write(chunk)  # Stream to user in real-time
end)
```

### Example 3: Multi-Provider Failover

```elixir
# config/config.exs
config :iris, :load_balancer,
  strategy: :least_connections,
  providers: [
    {:ollama, priority: 1, weight: 10},
    {:openai, priority: 2, weight: 5},    # Fallback
    {:anthropic, priority: 3, weight: 5}  # Fallback
  ]

config :iris, :circuit_breaker,
  failure_threshold: 5,
  recovery_timeout: 60_000
```

---

## Conclusion

**Primary Recommendation:** **Integrate Iris** as the local LLM provider backend

### Why Iris?
1. **Production-ready architecture** - Broadway pipeline is battle-tested
2. **Drop-in replacement** - Minimal changes to existing code
3. **Future-proof** - Supports OpenAI/Anthropic/custom providers
4. **Performance gains** - 5-50x throughput improvement
5. **Advanced features** - Caching, circuit breakers, telemetry
6. **Elixir-native** - Perfect fit for existing architecture

### Implementation Timeline
- **Week 1:** Basic integration (4-8 hours)
- **Week 2:** Advanced features (8-16 hours)
- **Week 3:** Multi-provider support (8-16 hours)
- **Week 4:** Production hardening (4-8 hours)

**Total Effort:** 24-48 hours over 4 weeks

### Next Steps
1. Create feature branch: `feature/iris-integration`
2. Add Iris as path dependency
3. Implement `IrisProvider` module
4. Run benchmark tests
5. Create pull request with results

---

**Generated:** 2025-10-18
**Author:** Claude Code
**Status:** Recommendation for Review
