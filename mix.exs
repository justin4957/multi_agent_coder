defmodule MultiAgentCoder.MixProject do
  use Mix.Project

  def project do
    [
      app: :multi_agent_coder,
      version: "0.1.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      escript: escript()
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
      {:req, "~> 0.4"},                # HTTP client for API calls
      {:jason, "~> 1.4"},              # JSON parsing
      {:phoenix_pubsub, "~> 2.1"},     # Real-time updates and event broadcasting
      {:table_rex, "~> 4.0"},          # Pretty table formatting for CLI
      {:progress_bar, "~> 3.0"}        # Progress indication for long-running tasks
    ]
  end
end
