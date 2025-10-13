defmodule MultiAgentCoder.Monitor.Realtime do
  @moduledoc """
  Real-time monitoring of agent status and progress.

  Subscribes to agent events via PubSub and provides
  live updates during task execution.
  """

  use GenServer
  require Logger

  defstruct [:start_time, :active_agents, :results]

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Subscribes to updates from a specific agent.
  """
  def subscribe(provider) do
    Phoenix.PubSub.subscribe(MultiAgentCoder.PubSub, "agent:#{provider}")
  end

  @doc """
  Subscribes to all agent updates.
  """
  def subscribe_all do
    providers = get_active_providers()
    Enum.each(providers, &subscribe/1)
    {:ok, providers}
  end

  @doc """
  Unsubscribes from agent updates.
  """
  def unsubscribe(provider) do
    Phoenix.PubSub.unsubscribe(MultiAgentCoder.PubSub, "agent:#{provider}")
  end

  @impl true
  def init(_opts) do
    state = %__MODULE__{
      start_time: nil,
      active_agents: MapSet.new(),
      results: %{}
    }

    {:ok, state}
  end

  @impl true
  def handle_info({:status_change, status}, state) do
    # Handle status updates from agents
    Logger.debug("Agent status changed: #{status}")
    {:noreply, state}
  end

  @impl true
  def handle_info({:task_complete, result}, state) do
    # Handle task completion
    Logger.debug("Agent task completed: #{inspect(result)}")
    {:noreply, state}
  end

  @impl true
  def handle_info(_msg, state) do
    {:noreply, state}
  end

  defp get_active_providers do
    Application.get_env(:multi_agent_coder, :providers, [])
    |> Keyword.keys()
  end
end
