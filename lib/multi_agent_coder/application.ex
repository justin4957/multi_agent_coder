defmodule MultiAgentCoder.Application do
  @moduledoc """
  Main OTP Application for MultiAgentCoder.

  Starts and supervises all core components including:
  - Agent supervisor for managing AI provider workers
  - Session manager for conversation state
  - Task router for distributing work
  - Real-time monitor for progress updates
  - Agent registry for discovery
  - PubSub for event broadcasting
  - Merge optimization (cache and performance monitoring)
  - ML-based pattern learning
  """

  use Application
  require Logger

  @impl true
  def start(_type, _args) do
    Logger.info("Starting MultiAgentCoder application...")

    children = [
      # PubSub for real-time event broadcasting
      {Phoenix.PubSub, name: MultiAgentCoder.PubSub},

      # Registry for agent discovery
      {Registry, keys: :unique, name: MultiAgentCoder.Agent.Registry},

      # Agent supervisor - manages all AI agent processes
      MultiAgentCoder.Agent.Supervisor,

      # Session storage - persistent session management
      MultiAgentCoder.Session.Storage,

      # Session manager - maintains conversation state
      MultiAgentCoder.Session.Manager,

      # Task router - distributes work to agents
      MultiAgentCoder.Router.TaskRouter,

      # Real-time monitor - streams progress updates
      MultiAgentCoder.Monitor.Realtime,

      # File operations tracking system
      MultiAgentCoder.FileOps.Ownership,
      MultiAgentCoder.FileOps.History,
      MultiAgentCoder.FileOps.ConflictDetector,
      MultiAgentCoder.FileOps.Tracker,

      # Merge optimization components
      MultiAgentCoder.Merge.Cache,
      MultiAgentCoder.Merge.PerformanceMonitor,

      # ML-based conflict resolution learning
      MultiAgentCoder.Merge.PatternLearner
    ]

    opts = [strategy: :one_for_one, name: MultiAgentCoder.Supervisor]

    case Supervisor.start_link(children, opts) do
      {:ok, pid} ->
        Logger.info("MultiAgentCoder application started successfully")
        {:ok, pid}

      {:error, reason} ->
        Logger.error("Failed to start MultiAgentCoder: #{inspect(reason)}")
        {:error, reason}
    end
  end
end
