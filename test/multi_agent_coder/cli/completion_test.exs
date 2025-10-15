defmodule MultiAgentCoder.CLI.CompletionTest do
  use ExUnit.Case, async: true

  alias MultiAgentCoder.CLI.Completion

  describe "complete/1" do
    test "returns all commands for empty input" do
      completions = Completion.complete("")

      assert "ask" in completions
      assert "help" in completions
      assert "exit" in completions
    end

    test "completes partial command" do
      completions = Completion.complete("as")

      assert completions == ["ask"]
    end

    test "completes with multiple matches" do
      completions = Completion.complete("h")

      assert "help" in completions
      assert "history" in completions
    end

    test "returns empty list for no matches" do
      completions = Completion.complete("xyz")

      assert completions == []
    end

    test "completes full command" do
      completions = Completion.complete("help")

      assert completions == ["help"]
    end
  end

  describe "commands/0" do
    test "returns list of available commands" do
      commands = Completion.commands()

      assert is_list(commands)
      assert "ask" in commands
      assert "help" in commands
      assert "exit" in commands
      assert "compare" in commands
    end
  end

  describe "strategies/0" do
    test "returns list of available strategies" do
      strategies = Completion.strategies()

      assert is_list(strategies)
      assert "all" in strategies
      assert "fastest" in strategies
      assert "dialectical" in strategies
    end
  end

  describe "providers/0" do
    test "returns list of configured providers" do
      providers = Completion.providers()

      assert is_list(providers)
      # List will be empty or contain configured providers
      # depending on test environment
    end
  end
end
