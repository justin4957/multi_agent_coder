defmodule MultiAgentCoder.Agent.Worker do
  @moduledoc """
  Generic AI agent worker process.

  Each agent runs as a separate GenServer, providing:
  - Concurrent task execution
  - Status tracking and monitoring
  - Automatic retry logic
  - Real-time progress updates via PubSub
  """

  use GenServer
  require Logger

  defstruct [
    :provider,
    :model,
    :api_key,
    :endpoint,
    :status,
    :current_task,
    :temperature,
    :max_tokens
  ]

  # Client API

  @doc """
  Starts an agent worker process.

  ## Options
    * `:provider` - The provider name (`:openai`, `:anthropic`, `:local`)
    * `:model` - The model to use
    * `:api_key` - API key (optional for local)
    * `:endpoint` - API endpoint (for local providers)
    * `:temperature` - Sampling temperature (default: 0.1)
    * `:max_tokens` - Maximum tokens in response (default: 4096)
  """
  def start_link(opts) do
    provider = Keyword.fetch!(opts, :provider)
    name = via_tuple(provider)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Executes a task with the specified agent.

  Returns the agent's response or an error tuple.
  """
  def execute_task(provider, prompt, context \\ %{}) do
    GenServer.call(via_tuple(provider), {:execute, prompt, context}, 120_000)
  end

  @doc """
  Gets the current status of an agent.
  """
  def get_status(provider) do
    GenServer.call(via_tuple(provider), :status)
  end

  # Server Callbacks

  @impl true
  def init(opts) do
    state = %__MODULE__{
      provider: Keyword.fetch!(opts, :provider),
      model: Keyword.fetch!(opts, :model),
      api_key: resolve_api_key(Keyword.get(opts, :api_key)),
      endpoint: Keyword.get(opts, :endpoint),
      status: :idle,
      temperature: Keyword.get(opts, :temperature, 0.1),
      max_tokens: Keyword.get(opts, :max_tokens, 4096)
    }

    Logger.info("Initialized #{state.provider} agent with model #{state.model}")
    {:ok, state}
  end

  @impl true
  def handle_call({:execute, prompt, context}, _from, state) do
    Logger.info("#{state.provider}: Starting task execution")

    new_state = %{state | status: :working, current_task: prompt}

    # Broadcast status update
    broadcast_status(state.provider, :working)

    # Execute based on provider
    result =
      case state.provider do
        :openai -> MultiAgentCoder.Agent.OpenAI.call(state, prompt, context)
        :anthropic -> MultiAgentCoder.Agent.Anthropic.call(state, prompt, context)
        :local -> MultiAgentCoder.Agent.Local.call(state, prompt, context)
      end

    final_state = %{new_state | status: :idle, current_task: nil}

    # Broadcast completion
    broadcast_complete(state.provider, result)

    {:reply, result, final_state}
  end

  @impl true
  def handle_call(:status, _from, state) do
    {:reply, %{status: state.status, current_task: state.current_task}, state}
  end

  # Private Functions

  defp via_tuple(provider) do
    {:via, Registry, {MultiAgentCoder.Agent.Registry, provider}}
  end

  defp resolve_api_key({:system, env_var}), do: System.get_env(env_var)
  defp resolve_api_key(api_key), do: api_key

  defp broadcast_status(provider, status) do
    Phoenix.PubSub.broadcast(
      MultiAgentCoder.PubSub,
      "agent:#{provider}",
      {:status_change, status}
    )
  end

  defp broadcast_complete(provider, result) do
    Phoenix.PubSub.broadcast(
      MultiAgentCoder.PubSub,
      "agent:#{provider}",
      {:task_complete, result}
    )
  end
end
