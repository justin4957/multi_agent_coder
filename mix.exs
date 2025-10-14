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
      {:excoveralls, "~> 0.18", only: :test}
    ]
  end
end
