defmodule MultiAgentCoder.Agent.Supervisor do
  @moduledoc """
  Supervisor for all AI agent worker processes.

  Dynamically starts and monitors agent workers for each configured provider
  (OpenAI, Anthropic, DeepSeek, Perplexity, OCI, Local). Uses a one-for-one
  supervision strategy so that if one agent crashes, others continue working.
  """

  use Supervisor
  require Logger

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    provider_configs = Application.get_env(:multi_agent_coder, :providers, [])

    children =
      Enum.map(provider_configs, fn {provider, config} ->
        %{
          id: provider,
          start: {MultiAgentCoder.Agent.Worker, :start_link, [[provider: provider] ++ config]},
          restart: :permanent,
          type: :worker
        }
      end)

    Logger.info("Starting #{length(children)} agent workers")
    Supervisor.init(children, strategy: :one_for_one)
  end

  @doc """
  Lists all currently running agent workers.
  """
  def list_agents do
    __MODULE__
    |> Supervisor.which_children()
    |> Enum.map(fn {id, _pid, _type, _modules} -> id end)
  end
end
