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
# Note: Iris configuration is done at runtime in IrisProvider module when Iris is available
config :multi_agent_coder,
  # Options: :iris or :direct (defaults to :direct if Iris unavailable)
  local_provider_backend: :iris,
  iris_enabled: true

# Configure PubSub for real-time updates
config :multi_agent_coder, MultiAgentCoder.PubSub, adapter: Phoenix.PubSub.PG2

# Configure tool execution and command approval
config :multi_agent_coder, :tools,
  # Approval mode: :auto | :prompt | :deny_all | :allow_all
  approval_mode: :auto,
  # Auto-approve safe commands (tests, git status, etc.)
  auto_approve_safe: true,
  # Prompt for warning commands (installs, commits)
  prompt_on_warning: true,
  # Always prompt for dangerous commands
  always_prompt_dangerous: true,
  # Remember approvals for the session
  trust_for_session: true,
  # Custom danger patterns (optional)
  custom_safe_patterns: [],
  custom_warning_patterns: [],
  custom_dangerous_patterns: [],
  custom_blocked_patterns: []

# Import environment specific config
import_config "#{config_env()}.exs"
