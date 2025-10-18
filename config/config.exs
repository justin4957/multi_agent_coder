import Config

# Configure AI providers
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
    deepseek: [
      model: "deepseek-coder",
      api_key: {:system, "DEEPSEEK_API_KEY"},
      temperature: 0.1,
      max_tokens: 4096
    ],
    perplexity: [
      model: "sonar",
      api_key: {:system, "PERPLEXITY_API_KEY"},
      temperature: 0.1,
      max_tokens: 4096
    ],
    local: [
      model: "codellama:latest",
      endpoint: "http://localhost:11434",
      temperature: 0.1
    ],
    oci: [
      model: "cohere.command-r-plus",
      api_key: {:system, "OCI_API_KEY"},
      compartment_id: {:system, "OCI_COMPARTMENT_ID"},
      region: {:system, "OCI_REGION"},
      temperature: 0.1,
      max_tokens: 4096
    ]
  ],
  default_strategy: :all,
  timeout: 120_000

# Configure local provider backend (use :iris for high-performance pipeline, :direct for basic)
config :multi_agent_coder,
  # Options: :iris or :direct
  local_provider_backend: :iris,
  iris_enabled: true

# Configure Iris LLM Pipeline (if enabled)
config :iris, :ollama,
  endpoint: "http://localhost:11434",
  default_model: "codellama:latest",
  timeout: 120_000,
  models: ["codellama:latest", "llama3", "mistral", "gemma"]

config :iris, :cache,
  backend: Nebulex.Adapters.Local,
  default_ttl: 1800,
  # 30 minutes cache
  max_size: 1_000_000,
  stats: true

config :iris, :pipeline,
  processor_stages: System.schedulers_online() * 2,
  max_demand: 50,
  batch_size: 100,
  batch_timeout: 5_000

config :iris, :load_balancer,
  strategy: :round_robin,
  # Options: :round_robin, :least_connections, :weighted
  health_check_interval: 30_000

# Configure PubSub for real-time updates
config :multi_agent_coder, MultiAgentCoder.PubSub, adapter: Phoenix.PubSub.PG2

# Import environment specific config
import_config "#{config_env()}.exs"
