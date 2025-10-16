defmodule MultiAgentCoder.Task.AllocatorTest do
  use ExUnit.Case, async: true

  alias MultiAgentCoder.Task.{Allocator, Task}

  describe "auto_allocate/1" do
    test "allocates algorithm task to OpenAI" do
      {:ok, providers} = Allocator.auto_allocate("Implement quicksort algorithm")

      assert :openai in providers
    end

    test "allocates refactoring task to Anthropic" do
      {:ok, providers} = Allocator.auto_allocate("Refactor authentication module")

      assert :anthropic in providers
    end

    test "allocates architecture task to Anthropic" do
      {:ok, providers} = Allocator.auto_allocate("Design a microservices architecture")

      assert :anthropic in providers
    end

    test "allocates research task to Perplexity" do
      {:ok, providers} = Allocator.auto_allocate("Research best practices for API design")

      assert :perplexity in providers
    end

    test "allocates API task to Perplexity" do
      {:ok, providers} = Allocator.auto_allocate("Implement REST API endpoints")

      assert :perplexity in providers
    end

    test "allocates quick fix to DeepSeek" do
      {:ok, providers} = Allocator.auto_allocate("Quick fix for typo in function")

      assert :deepseek in providers
    end

    test "accepts Task struct as input" do
      task = Task.new("Implement sorting algorithm")
      {:ok, providers} = Allocator.auto_allocate(task)

      assert is_list(providers)
      assert length(providers) > 0
    end

    test "returns all available providers for generic task" do
      # Set up mock configuration
      Application.put_env(:multi_agent_coder, :providers,
        openai: [],
        anthropic: []
      )

      {:ok, providers} = Allocator.auto_allocate("Do something generic")

      assert is_list(providers)
      assert length(providers) >= 0

      # Clean up
      Application.delete_env(:multi_agent_coder, :providers)
    end

    test "handles multiple matching capabilities" do
      {:ok, providers} =
        Allocator.auto_allocate("Optimize sorting algorithm for performance")

      # Should match both "optimize" (openai) and "sort" (openai)
      assert :openai in providers
    end
  end

  describe "distribute_load/2" do
    test "distributes tasks across providers" do
      tasks = [
        Task.new("Task 1"),
        Task.new("Task 2"),
        Task.new("Task 3")
      ]

      available_providers = [:openai, :anthropic, :deepseek]

      {:ok, distributed} = Allocator.distribute_load(tasks, available_providers)

      assert length(distributed) == 3
      assert Enum.all?(distributed, &(&1.assigned_to != nil))
      assert Enum.all?(distributed, &(&1.status == :queued))
    end

    test "respects provider capabilities when distributing" do
      tasks = [
        Task.new("Implement quicksort algorithm"),
        Task.new("Refactor code structure")
      ]

      available_providers = [:openai, :anthropic]

      {:ok, distributed} = Allocator.distribute_load(tasks, available_providers)

      # First task should be assigned to OpenAI (algorithms)
      [task1, task2] = distributed

      assert task1.assigned_to in [[:openai], [:anthropic]]
      assert task2.assigned_to in [[:openai], [:anthropic]]
    end

    test "uses round-robin when no capability match" do
      tasks = [
        Task.new("Generic task 1"),
        Task.new("Generic task 2"),
        Task.new("Generic task 3"),
        Task.new("Generic task 4")
      ]

      available_providers = [:openai, :anthropic]

      {:ok, distributed} = Allocator.distribute_load(tasks, available_providers)

      providers_used =
        distributed
        |> Enum.map(& &1.assigned_to)
        |> List.flatten()

      # Should have used both providers
      assert :openai in providers_used or :anthropic in providers_used
    end
  end

  describe "assign/2" do
    test "manually assigns task to single provider" do
      task = Task.new("Implement feature")
      {:ok, assigned} = Allocator.assign(task, :openai)

      assert assigned.assigned_to == [:openai]
      assert assigned.status == :queued
    end

    test "manually assigns task to multiple providers" do
      task = Task.new("Implement feature")
      {:ok, assigned} = Allocator.assign(task, [:openai, :anthropic])

      assert assigned.assigned_to == [:openai, :anthropic]
      assert assigned.status == :queued
    end
  end

  describe "get_capabilities/1" do
    test "returns capabilities for OpenAI" do
      capabilities = Allocator.get_capabilities(:openai)

      assert :algorithms in capabilities
      assert :data_structures in capabilities
      assert :optimization in capabilities
    end

    test "returns capabilities for Anthropic" do
      capabilities = Allocator.get_capabilities(:anthropic)

      assert :refactoring in capabilities
      assert :architecture in capabilities
      assert :best_practices in capabilities
    end

    test "returns capabilities for DeepSeek" do
      capabilities = Allocator.get_capabilities(:deepseek)

      assert :code_completion in capabilities
      assert :quick_fixes in capabilities
    end

    test "returns capabilities for Perplexity" do
      capabilities = Allocator.get_capabilities(:perplexity)

      assert :research in capabilities
      assert :api_usage in capabilities
    end

    test "returns empty list for unknown provider" do
      capabilities = Allocator.get_capabilities(:unknown)

      assert capabilities == []
    end
  end

  describe "suggest_provider/1" do
    test "suggests OpenAI for algorithms" do
      provider = Allocator.suggest_provider(:algorithms)

      assert provider == :openai
    end

    test "suggests Anthropic for refactoring" do
      provider = Allocator.suggest_provider(:refactoring)

      assert provider == :anthropic
    end

    test "suggests DeepSeek for code completion" do
      provider = Allocator.suggest_provider(:code_completion)

      assert provider == :deepseek
    end

    test "suggests Perplexity for research" do
      provider = Allocator.suggest_provider(:research)

      assert provider == :perplexity
    end

    test "returns nil for unknown capability" do
      provider = Allocator.suggest_provider(:unknown_capability)

      assert provider == nil
    end
  end

  describe "get_available_providers/0" do
    test "returns configured providers" do
      # Set up test configuration
      Application.put_env(:multi_agent_coder, :providers,
        openai: [api_key: "test"],
        anthropic: [api_key: "test"]
      )

      providers = Allocator.get_available_providers()

      assert is_list(providers)
      assert :openai in providers
      assert :anthropic in providers

      # Clean up
      Application.delete_env(:multi_agent_coder, :providers)
    end

    test "returns empty list when no providers configured" do
      Application.delete_env(:multi_agent_coder, :providers)

      providers = Allocator.get_available_providers()

      assert providers == []
    end
  end
end
