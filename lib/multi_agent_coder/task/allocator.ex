defmodule MultiAgentCoder.Task.Allocator do
  @moduledoc """
  Intelligent task allocation to AI providers based on capabilities.

  Provides algorithms for:
  - Auto-allocation based on task type and provider strengths
  - Manual task assignment
  - Load balancing across providers
  - Capability matching

  ## Provider Capabilities

  Each provider has strengths in different areas:
  - **OpenAI**: Algorithms, data structures, performance optimization
  - **Anthropic**: Code refactoring, architecture, best practices
  - **DeepSeek**: Code completion, quick fixes, simple implementations
  - **Perplexity**: Research-heavy tasks, documentation, API usage
  - **Local**: Privacy-sensitive tasks, offline work

  ## Examples

      iex> Allocator.auto_allocate("Implement quicksort algorithm")
      {:ok, [:openai]}

      iex> Allocator.auto_allocate("Refactor authentication module")
      {:ok, [:anthropic]}

      iex> Allocator.distribute_load(tasks, [:openai, :anthropic])
      {:ok, allocated_tasks}
  """

  alias MultiAgentCoder.Task.Task

  @provider_capabilities %{
    openai: [
      :algorithms,
      :data_structures,
      :optimization,
      :complex_logic,
      :mathematical_computation
    ],
    anthropic: [
      :refactoring,
      :architecture,
      :best_practices,
      :code_review,
      :documentation
    ],
    deepseek: [
      :code_completion,
      :quick_fixes,
      :simple_implementation,
      :boilerplate
    ],
    perplexity: [
      :research,
      :api_usage,
      :library_integration,
      :documentation_search
    ],
    local: [
      :privacy_sensitive,
      :offline_work,
      :custom_models
    ]
  }

  @task_keywords %{
    algorithms: ["algorithm", "sort", "search", "optimize", "complexity"],
    refactoring: ["refactor", "improve", "clean", "restructure"],
    architecture: ["design", "architecture", "structure", "pattern"],
    testing: ["test", "spec", "unittest", "integration"],
    documentation: ["document", "docs", "readme", "comment"],
    api: ["api", "endpoint", "rest", "graphql"],
    api_usage: ["api", "endpoint", "integrate"],
    database: ["database", "sql", "query", "migration"],
    authentication: ["auth", "login", "security", "permission"],
    research: ["research", "best practices", "investigate"],
    quick_fixes: ["quick fix", "typo", "fix typo"],
    simple_implementation: ["simple", "basic"],
    code_completion: ["complete", "autocomplete", "boilerplate"]
  }

  @doc """
  Automatically allocates a task to the best provider(s) based on description.

  Returns `{:ok, [providers]}` with recommended providers.
  """
  @spec auto_allocate(String.t() | Task.t()) :: {:ok, list(atom())} | {:error, term()}
  def auto_allocate(description) when is_binary(description) do
    task = Task.new(description)
    auto_allocate(task)
  end

  def auto_allocate(%Task{} = task) do
    capabilities = detect_required_capabilities(task.description)
    providers = match_providers(capabilities)

    case providers do
      [] ->
        # Default to all available providers if no match
        {:ok, get_available_providers()}

      providers ->
        {:ok, providers}
    end
  end

  @doc """
  Distributes tasks across providers for load balancing.

  Attempts to balance workload while respecting capabilities.
  """
  @spec distribute_load(list(Task.t()), list(atom())) :: {:ok, list(Task.t())}
  def distribute_load(tasks, available_providers) do
    # Simple round-robin distribution with capability matching
    distributed =
      tasks
      |> Enum.with_index()
      |> Enum.map(fn {task, index} ->
        # Try capability match first
        {:ok, suggested_providers} = auto_allocate(task)

        # Filter to only available providers
        matching_providers =
          Enum.filter(suggested_providers, &(&1 in available_providers))

        # If no match, use round-robin
        provider =
          if Enum.empty?(matching_providers) do
            Enum.at(available_providers, rem(index, length(available_providers)))
          else
            # Use first matching provider
            List.first(matching_providers)
          end

        Task.assign_to(task, provider)
      end)

    {:ok, distributed}
  end

  @doc """
  Manually assigns a task to specific providers.
  """
  @spec assign(Task.t(), atom() | list(atom())) :: {:ok, Task.t()}
  def assign(task, provider_or_providers) do
    {:ok, Task.assign_to(task, provider_or_providers)}
  end

  @doc """
  Gets capabilities for a specific provider.
  """
  @spec get_capabilities(atom()) :: list(atom())
  def get_capabilities(provider) do
    Map.get(@provider_capabilities, provider, [])
  end

  @doc """
  Gets all available providers.
  """
  @spec get_available_providers() :: list(atom())
  def get_available_providers do
    Application.get_env(:multi_agent_coder, :providers, [])
    |> Keyword.keys()
  end

  @doc """
  Suggests the best provider for a specific task type.
  """
  @spec suggest_provider(atom()) :: atom() | nil
  def suggest_provider(task_type) do
    @provider_capabilities
    |> Enum.find(fn {_provider, capabilities} ->
      task_type in capabilities
    end)
    |> case do
      {provider, _} -> provider
      nil -> nil
    end
  end

  # Private functions

  defp detect_required_capabilities(description) do
    description_lower = String.downcase(description)

    @task_keywords
    |> Enum.filter(fn {_category, keywords} ->
      Enum.any?(keywords, &String.contains?(description_lower, &1))
    end)
    |> Enum.map(fn {category, _} -> category end)
  end

  defp match_providers(capabilities) when capabilities == [] do
    # No specific capabilities detected, return empty
    []
  end

  defp match_providers(capabilities) do
    @provider_capabilities
    |> Enum.filter(fn {_provider, provider_caps} ->
      # Check if provider has any of the required capabilities
      Enum.any?(capabilities, &(&1 in provider_caps))
    end)
    |> Enum.map(fn {provider, _} -> provider end)
    |> Enum.uniq()
  end
end
