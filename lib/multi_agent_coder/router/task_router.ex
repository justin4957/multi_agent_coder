defmodule MultiAgentCoder.Router.TaskRouter do
  @moduledoc """
  Routes tasks to AI agents using various strategies.

  Supported routing strategies:
  - `:all` - Query all providers concurrently
  - `:parallel` - Same as `:all` with streaming updates
  - `:sequential` - Chain results (each agent sees previous outputs)
  - `:dialectical` - Thesis/Antithesis/Synthesis workflow
  - `[:provider1, :provider2]` - Custom provider list
  """

  use GenServer
  require Logger

  alias MultiAgentCoder.Agent.{ProviderHealth, Worker}

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Routes a task to agents using the specified strategy.

  ## Parameters
    * `prompt` - The task/prompt to execute
    * `strategy` - Routing strategy (default: `:all`)
    * `opts` - Additional options (context, etc.)

  ## Returns
    Map of results keyed by provider name, or dialectical result structure
  """
  def route_task(prompt, strategy \\ :all, opts \\ []) do
    GenServer.call(__MODULE__, {:route, prompt, strategy, opts}, 180_000)
  end

  @impl true
  def init(_opts) do
    {:ok, %{}}
  end

  @impl true
  def handle_call({:route, prompt, strategy, opts}, _from, state) do
    context = Keyword.get(opts, :context, %{})
    skip_health_check = Keyword.get(opts, :skip_health_check, false)

    Logger.info("Routing task with strategy: #{inspect(strategy)}")

    # Perform health check unless explicitly skipped
    unless skip_health_check do
      perform_health_check(strategy)
    end

    result =
      case strategy do
        :all -> route_to_all(prompt, context)
        :parallel -> route_parallel(prompt, context)
        :sequential -> route_sequential(prompt, context)
        :dialectical -> route_dialectical(prompt, context)
        providers when is_list(providers) -> route_to_specific(providers, prompt, context)
      end

    {:reply, result, state}
  end

  # Private Functions

  defp perform_health_check(strategy) do
    providers = get_requested_providers(strategy)
    health_status = ProviderHealth.check_all_providers()

    {healthy, failed} = ProviderHealth.filter_healthy_providers(providers, health_status)

    if length(failed) > 0 do
      Logger.warning("Provider health check found issues:")

      Enum.each(failed, fn provider ->
        error_reason = health_status[provider]
        message = ProviderHealth.get_error_guidance(provider, elem(error_reason, 1))
        Logger.warning(message)
      end)

      if length(healthy) == 0 do
        Logger.error("No healthy providers available for routing!")
      else
        Logger.info("Continuing with #{length(healthy)} healthy provider(s): #{inspect(healthy)}")
      end
    else
      Logger.info("All #{length(healthy)} provider(s) are healthy")
    end
  end

  defp get_requested_providers(:all), do: get_active_providers()
  defp get_requested_providers(:parallel), do: get_active_providers()
  defp get_requested_providers(:sequential), do: get_active_providers()
  defp get_requested_providers(:dialectical), do: get_active_providers()
  defp get_requested_providers(providers) when is_list(providers), do: providers

  defp route_to_all(prompt, context) do
    providers = get_active_providers()

    tasks =
      Enum.map(providers, fn provider ->
        Task.async(fn ->
          {provider, Worker.execute_task(provider, prompt, context)}
        end)
      end)

    results = Task.await_many(tasks, 120_000)
    Map.new(results)
  end

  defp route_parallel(prompt, context) do
    # Same as route_to_all but with streaming updates
    # In a full implementation, this would use streaming APIs
    route_to_all(prompt, context)
  end

  defp route_sequential(prompt, context) do
    providers = get_active_providers()

    Enum.reduce(providers, %{}, fn provider, acc ->
      # Each subsequent agent gets previous results as context
      enhanced_context = Map.put(context, :previous_results, acc)

      Logger.info("Sequential routing to #{provider}")
      result = Worker.execute_task(provider, prompt, enhanced_context)
      Map.put(acc, provider, result)
    end)
  end

  defp route_dialectical(prompt, context) do
    Logger.info("Starting dialectical workflow")

    # Thesis: Get initial solutions from all agents
    Logger.info("Phase 1: Thesis - gathering initial solutions")
    thesis = route_to_all(prompt, context)

    # Antithesis: Each model critiques the others
    Logger.info("Phase 2: Antithesis - generating critiques")

    critique_prompt = """
    Review these alternative solutions and provide constructive criticism:
    #{format_solutions(thesis)}

    Original task: #{prompt}

    Provide specific feedback on:
    - Potential issues or edge cases
    - Code quality and maintainability
    - Better approaches or optimizations
    """

    antithesis = route_to_all(critique_prompt, Map.put(context, :thesis, thesis))

    # Synthesis: Generate final improved solution
    Logger.info("Phase 3: Synthesis - creating improved solution")

    synthesis_prompt = """
    Based on the original solutions and critiques, provide an improved solution:

    Original task: #{prompt}

    Initial solutions:
    #{format_solutions(thesis)}

    Critiques:
    #{format_solutions(antithesis)}

    Create a final solution that incorporates the best ideas and addresses the critiques.
    """

    synthesis =
      route_to_all(synthesis_prompt, %{
        context
        | thesis: thesis,
          antithesis: antithesis
      })

    %{
      thesis: thesis,
      antithesis: antithesis,
      synthesis: synthesis
    }
  end

  defp route_to_specific(providers, prompt, context) do
    Logger.info("Routing to specific providers: #{inspect(providers)}")

    tasks =
      Enum.map(providers, fn provider ->
        Task.async(fn ->
          {provider, Worker.execute_task(provider, prompt, context)}
        end)
      end)

    results = Task.await_many(tasks, 120_000)
    Map.new(results)
  end

  defp format_solutions(results) do
    Enum.map_join(results, "\n\n", fn
      {provider, {:ok, solution}} ->
        """
        === #{String.upcase(to_string(provider))} ===
        #{solution}
        """

      {provider, {:error, reason}} ->
        """
        === #{String.upcase(to_string(provider))} ===
        [Error: #{inspect(reason)}]
        """
    end)
  end

  defp get_active_providers do
    Application.get_env(:multi_agent_coder, :providers, [])
    |> Keyword.keys()
  end
end
