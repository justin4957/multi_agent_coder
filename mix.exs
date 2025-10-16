defmodule MultiAgentCoder.MixProject do
  use Mix.Project

  def project do
    [
      app: :multi_agent_coder,
      version: "0.1.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      escript: escript(),
      test_coverage: [tool: ExCoveralls],
      preferred_cli_env: [
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.post": :test,
        "coveralls.html": :test,
        "coveralls.json": :test
      ],

      # Docs
      name: "MultiAgent Coder",
      source_url: "https://github.com/justin4957/multi_agent_coder",
      homepage_url: "https://github.com/justin4957/multi_agent_coder",
      docs: [
        main: "quickstart",
        extras: [
          "guides/quickstart.md",
          "README.md"
        ],
        groups_for_extras: [
          Guides: ~r/guides\/.?/
        ],
        groups_for_modules: [
          "Agent Providers": [
            MultiAgentCoder.Agent.Worker,
            MultiAgentCoder.Agent.OpenAI,
            MultiAgentCoder.Agent.Anthropic,
            MultiAgentCoder.Agent.DeepSeek,
            MultiAgentCoder.Agent.Perplexity,
            MultiAgentCoder.Agent.Local,
            MultiAgentCoder.Agent.HTTPClient,
            MultiAgentCoder.Agent.TokenCounter,
            MultiAgentCoder.Agent.ContextFormatter
          ],
          "Router & Strategy": [
            MultiAgentCoder.Router.TaskRouter,
            MultiAgentCoder.Router.Strategy
          ],
          "Session Management": [
            MultiAgentCoder.Session.Manager,
            MultiAgentCoder.Session.Storage,
            MultiAgentCoder.Session.Message,
            MultiAgentCoder.Session.Session
          ],
          "CLI Interface": [
            MultiAgentCoder.CLI.Command,
            MultiAgentCoder.CLI.InteractiveSession,
            MultiAgentCoder.CLI.Formatter,
            MultiAgentCoder.CLI.ConfigSetup,
            MultiAgentCoder.CLI.REPL,
            MultiAgentCoder.CLI.History,
            MultiAgentCoder.CLI.Completion,
            MultiAgentCoder.CLI.ConcurrentDisplay,
            MultiAgentCoder.CLI.DisplayConfig
          ],
          "Task Management": [
            MultiAgentCoder.Task.Task,
            MultiAgentCoder.Task.Queue,
            MultiAgentCoder.Task.Allocator,
            MultiAgentCoder.Task.Tracker
          ],
          Monitoring: [
            MultiAgentCoder.Monitor.Realtime,
            MultiAgentCoder.Monitor.Collector,
            MultiAgentCoder.Monitor.Streaming
          ]
        ]
      ],

      # Dialyzer
      dialyzer: [
        plt_add_apps: [:mix, :ex_unit],
        plt_file: {:no_warn, "priv/plts/dialyzer.plt"},
        flags: [:unmatched_returns, :error_handling, :underspecs]
      ]
    ]
  end

  defp escript do
    [
      main_module: MultiAgentCoder.CLI.Command
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {MultiAgentCoder.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      # HTTP client for API calls
      {:req, "~> 0.4"},
      # JSON parsing
      {:jason, "~> 1.4"},
      # Real-time updates and event broadcasting
      {:phoenix_pubsub, "~> 2.1"},
      # Pretty table formatting for CLI
      {:table_rex, "~> 4.0"},
      # Progress indication for long-running tasks
      {:progress_bar, "~> 3.0"},
      # Code coverage reporting
      {:excoveralls, "~> 0.18", only: :test},
      # Property-based testing
      {:stream_data, "~> 1.0", only: :test},
      # Documentation generation
      {:ex_doc, "~> 0.31", only: :dev, runtime: false},
      # Code quality and static analysis
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      # Type checking with Dialyzer
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false}
    ]
  end
end
