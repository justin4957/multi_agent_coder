defmodule MultiAgentCoder.FileOps.HistoryTest do
  use ExUnit.Case, async: false

  alias MultiAgentCoder.FileOps.History

  setup do
    {:ok, _pid} = start_supervised(History)
    History.reset()
    :ok
  end

  describe "record/6" do
    test "records file operation in history" do
      History.record("lib/user.ex", :openai, :create, nil, "defmodule User do\nend")

      history = History.get_file_history("lib/user.ex")
      assert length(history) == 1

      entry = hd(history)
      assert entry.file == "lib/user.ex"
      assert entry.provider == :openai
      assert entry.operation == :create
    end

    test "records multiple operations" do
      History.record("lib/user.ex", :openai, :create, nil, "v1")
      History.record("lib/user.ex", :anthropic, :modify, "v1", "v2")

      history = History.get_file_history("lib/user.ex")
      assert length(history) == 2
    end
  end

  describe "get_file_history/1" do
    test "returns history in reverse chronological order" do
      History.record("lib/user.ex", :openai, :create, nil, "v1")
      :timer.sleep(10)
      History.record("lib/user.ex", :anthropic, :modify, "v1", "v2")

      history = History.get_file_history("lib/user.ex")
      [latest, _oldest] = history

      assert latest.provider == :anthropic
    end

    test "returns empty list for file with no history" do
      history = History.get_file_history("lib/unknown.ex")
      assert history == []
    end
  end

  describe "get_provider_history/1" do
    test "returns all operations by a provider" do
      History.record("lib/user.ex", :openai, :create, nil, "v1")
      History.record("lib/auth.ex", :openai, :create, nil, "v1")
      History.record("lib/schema.ex", :anthropic, :create, nil, "v1")

      openai_history = History.get_provider_history(:openai)
      assert length(openai_history) == 2
    end
  end

  describe "get_current_version/1" do
    test "returns latest version of file" do
      History.record("lib/user.ex", :openai, :create, nil, "v1")
      History.record("lib/user.ex", :anthropic, :modify, "v1", "v2")

      current = History.get_current_version("lib/user.ex")
      assert current == "v2"
    end

    test "returns nil for file with no history" do
      assert History.get_current_version("lib/unknown.ex") == nil
    end
  end

  describe "revert_to_version/2" do
    test "reverts to specified version" do
      History.record("lib/user.ex", :openai, :create, nil, "v1")
      [entry] = History.get_file_history("lib/user.ex")

      {:ok, content} = History.revert_to_version("lib/user.ex", entry.id)
      assert content == "v1"
    end

    test "returns error for non-existent entry" do
      result = History.revert_to_version("lib/user.ex", "invalid_id")
      assert result == {:error, :not_found}
    end
  end

  describe "get_stats/0" do
    test "calculates statistics" do
      History.record("lib/user.ex", :openai, :create, nil, "line 1\nline 2")
      History.record("lib/auth.ex", :anthropic, :create, nil, "line 1")

      stats = History.get_stats()
      assert stats.total_entries == 2
      assert stats.files_tracked == 2
    end
  end
end
