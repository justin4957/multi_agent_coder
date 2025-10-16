defmodule MultiAgentCoder.Monitor.FileTrackerTest do
  use ExUnit.Case, async: false

  alias MultiAgentCoder.Monitor.FileTracker

  setup do
    # Start FileTracker for each test
    {:ok, _pid} = start_supervised(FileTracker)

    # Reset state before each test
    FileTracker.reset()

    :ok
  end

  describe "track_operation/4" do
    test "tracks a file creation operation" do
      FileTracker.track_operation(:openai, "lib/user.ex", :create)

      operations = FileTracker.get_provider_operations(:openai)

      assert length(operations) == 1
      assert hd(operations).provider == :openai
      assert hd(operations).file == "lib/user.ex"
      assert hd(operations).operation == :create
    end

    test "tracks multiple operations for a provider" do
      FileTracker.track_operation(:openai, "lib/user.ex", :create)
      FileTracker.track_operation(:openai, "lib/auth.ex", :modify)
      FileTracker.track_operation(:openai, "test/user_test.exs", :create)

      operations = FileTracker.get_provider_operations(:openai)

      assert length(operations) == 3
    end

    test "tracks lines changed in operation" do
      FileTracker.track_operation(:anthropic, "lib/schema.ex", :modify, lines_changed: 45)

      operations = FileTracker.get_provider_operations(:anthropic)

      assert hd(operations).lines_changed == 45
    end

    test "tracks operations from multiple providers" do
      FileTracker.track_operation(:openai, "lib/user.ex", :create)
      FileTracker.track_operation(:anthropic, "lib/auth.ex", :create)

      openai_ops = FileTracker.get_provider_operations(:openai)
      anthropic_ops = FileTracker.get_provider_operations(:anthropic)

      assert length(openai_ops) == 1
      assert length(anthropic_ops) == 1
    end
  end

  describe "get_file_providers/1" do
    test "returns providers that accessed a file" do
      FileTracker.track_operation(:openai, "lib/user.ex", :create)

      providers = FileTracker.get_file_providers("lib/user.ex")

      assert :openai in providers
      assert length(providers) == 1
    end

    test "returns multiple providers for same file" do
      FileTracker.track_operation(:openai, "lib/user.ex", :create)
      FileTracker.track_operation(:anthropic, "lib/user.ex", :modify)

      providers = FileTracker.get_file_providers("lib/user.ex")

      assert :openai in providers
      assert :anthropic in providers
      assert length(providers) == 2
    end

    test "returns empty list for non-accessed file" do
      providers = FileTracker.get_file_providers("lib/unknown.ex")

      assert providers == []
    end
  end

  describe "get_conflicts/0" do
    test "detects conflict when multiple providers access same file" do
      FileTracker.track_operation(:openai, "lib/user.ex", :create)
      FileTracker.track_operation(:anthropic, "lib/user.ex", :modify)

      conflicts = FileTracker.get_conflicts()

      assert length(conflicts) == 1
      {file, providers} = hd(conflicts)
      assert file == "lib/user.ex"
      assert :openai in providers
      assert :anthropic in providers
    end

    test "does not report conflict for different files" do
      FileTracker.track_operation(:openai, "lib/user.ex", :create)
      FileTracker.track_operation(:anthropic, "lib/auth.ex", :create)

      conflicts = FileTracker.get_conflicts()

      assert conflicts == []
    end

    test "tracks multiple conflicts" do
      FileTracker.track_operation(:openai, "lib/user.ex", :create)
      FileTracker.track_operation(:anthropic, "lib/user.ex", :modify)
      FileTracker.track_operation(:deepseek, "lib/auth.ex", :create)
      FileTracker.track_operation(:local, "lib/auth.ex", :modify)

      conflicts = FileTracker.get_conflicts()

      assert length(conflicts) == 2
    end

    test "updates existing conflict when third provider accesses file" do
      FileTracker.track_operation(:openai, "lib/user.ex", :create)
      FileTracker.track_operation(:anthropic, "lib/user.ex", :modify)
      FileTracker.track_operation(:deepseek, "lib/user.ex", :modify)

      conflicts = FileTracker.get_conflicts()

      assert length(conflicts) == 1
      {_file, providers} = hd(conflicts)
      assert length(providers) == 3
    end
  end

  describe "get_stats/0" do
    test "calculates statistics correctly" do
      FileTracker.track_operation(:openai, "lib/user.ex", :create, lines_changed: 100)
      FileTracker.track_operation(:openai, "lib/auth.ex", :modify, lines_changed: 50)
      FileTracker.track_operation(:anthropic, "test/user_test.exs", :create, lines_changed: 75)

      stats = FileTracker.get_stats()

      assert stats.total_operations == 3
      assert stats.total_files_touched == 3
      assert stats.total_providers == 2
      assert stats.total_lines_changed == 225
    end

    test "counts operations by type" do
      FileTracker.track_operation(:openai, "lib/user.ex", :create)
      FileTracker.track_operation(:openai, "lib/auth.ex", :create)
      FileTracker.track_operation(:anthropic, "lib/user.ex", :modify)
      FileTracker.track_operation(:deepseek, "lib/old.ex", :delete)

      stats = FileTracker.get_stats()

      assert stats.operations_by_type[:create] == 2
      assert stats.operations_by_type[:modify] == 1
      assert stats.operations_by_type[:delete] == 1
    end

    test "counts operations by provider" do
      FileTracker.track_operation(:openai, "lib/user.ex", :create)
      FileTracker.track_operation(:openai, "lib/auth.ex", :create)
      FileTracker.track_operation(:anthropic, "test/test.exs", :create)

      stats = FileTracker.get_stats()

      assert stats.operations_by_provider[:openai] == 2
      assert stats.operations_by_provider[:anthropic] == 1
    end

    test "tracks conflicts in stats" do
      FileTracker.track_operation(:openai, "lib/user.ex", :create)
      FileTracker.track_operation(:anthropic, "lib/user.ex", :modify)

      stats = FileTracker.get_stats()

      assert stats.conflicts == 1
    end
  end

  describe "reset/0" do
    test "clears all tracked operations" do
      FileTracker.track_operation(:openai, "lib/user.ex", :create)
      FileTracker.track_operation(:anthropic, "lib/auth.ex", :create)

      FileTracker.reset()

      stats = FileTracker.get_stats()

      assert stats.total_operations == 0
      assert stats.total_files_touched == 0
      assert stats.total_providers == 0
    end

    test "clears conflicts" do
      FileTracker.track_operation(:openai, "lib/user.ex", :create)
      FileTracker.track_operation(:anthropic, "lib/user.ex", :modify)

      assert length(FileTracker.get_conflicts()) == 1

      FileTracker.reset()

      assert FileTracker.get_conflicts() == []
    end
  end
end
