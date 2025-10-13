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
    local: [
      model: "codellama:latest",
      endpoint: "http://localhost:11434",
      temperature: 0.1
    ]
  ],
  default_strategy: :all,
  timeout: 120_000

# Configure PubSub for real-time updates
config :multi_agent_coder, MultiAgentCoder.PubSub,
  adapter: Phoenix.PubSub.PG2

# Import environment specific config
import_config "#{config_env()}.exs"
