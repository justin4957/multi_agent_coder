defmodule MultiAgentCoder.CLI.HistoryTest do
  use ExUnit.Case, async: false

  alias MultiAgentCoder.CLI.History

  setup do
    # Override history file path for testing
    # Note: This would require modifying History module to accept config
    # For now, we'll use the real directory but clean up after

    # Clear history before each test
    History.clear()

    on_exit(fn ->
      History.clear()
    end)

    :ok
  end

  describe "load/0" do
    test "returns empty list when no history file exists" do
      History.clear()
      assert History.load() == []
    end

    test "loads existing history from file" do
      History.append("command 1")
      History.append("command 2")

      loaded = History.load()
      assert "command 1" in loaded
      assert "command 2" in loaded
    end
  end

  describe "append/1" do
    test "appends command to history" do
      History.append("test command")
      history = History.load()

      assert "test command" in history
    end

    test "does not append empty commands" do
      History.append("")
      History.append("   ")

      assert History.load() == []
    end

    test "does not duplicate last command" do
      History.append("same command")
      History.append("same command")

      history = History.load()
      assert Enum.count(history, &(&1 == "same command")) == 1
    end

    test "allows same command if not consecutive" do
      History.append("command a")
      History.append("command b")
      History.append("command a")

      history = History.load()
      assert Enum.count(history, &(&1 == "command a")) == 2
    end
  end

  describe "clear/0" do
    test "removes all history" do
      History.append("command 1")
      History.append("command 2")

      History.clear()

      assert History.load() == []
    end
  end

  describe "search/1" do
    setup do
      History.append("list all files")
      History.append("grep for pattern")
      History.append("list directories")
      History.append("find files")

      :ok
    end

    test "finds commands containing search term" do
      results = History.search("list")

      assert length(results) == 2
      assert "list all files" in results
      assert "list directories" in results
    end

    test "returns empty list for no matches" do
      results = History.search("nonexistent")

      assert results == []
    end

    test "returns results in reverse order (most recent first)" do
      results = History.search("list")

      assert List.first(results) == "list directories"
    end
  end

  describe "last/1" do
    setup do
      History.append("command 1")
      History.append("command 2")
      History.append("command 3")
      History.append("command 4")

      :ok
    end

    test "returns last N commands" do
      results = History.last(2)

      assert length(results) == 2
      assert List.first(results) == "command 4"
      assert List.last(results) == "command 3"
    end

    test "returns all commands if N is larger than history size" do
      results = History.last(10)

      assert length(results) == 4
    end

    test "returns commands in reverse order (most recent first)" do
      results = History.last(4)

      assert Enum.at(results, 0) == "command 4"
      assert Enum.at(results, 1) == "command 3"
      assert Enum.at(results, 2) == "command 2"
      assert Enum.at(results, 3) == "command 1"
    end
  end

  describe "count/0" do
    test "returns zero for empty history" do
      assert History.count() == 0
    end

    test "returns correct count" do
      History.append("command 1")
      History.append("command 2")
      History.append("command 3")

      assert History.count() == 3
    end
  end
end
