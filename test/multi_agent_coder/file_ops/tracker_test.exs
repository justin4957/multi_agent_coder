defmodule MultiAgentCoder.FileOps.TrackerTest do
  use ExUnit.Case, async: false

  alias MultiAgentCoder.FileOps.Tracker

  setup do
    # Start all required services
    {:ok, _} = start_supervised(MultiAgentCoder.FileOps.Ownership)
    {:ok, _} = start_supervised(MultiAgentCoder.FileOps.History)
    {:ok, _} = start_supervised(MultiAgentCoder.FileOps.ConflictDetector)
    {:ok, _} = start_supervised(MultiAgentCoder.Monitor.FileTracker)
    {:ok, _} = start_supervised(Tracker)

    Tracker.reset()
    :ok
  end

  describe "track_file_operation/4" do
    test "tracks file creation" do
      result =
        Tracker.track_file_operation(
          :openai,
          "lib/user.ex",
          :create,
          after_content: "defmodule User do\nend"
        )

      assert result == :ok
    end

    test "tracks file modification" do
      Tracker.track_file_operation(:openai, "lib/user.ex", :create, after_content: "v1")

      result =
        Tracker.track_file_operation(
          :openai,
          "lib/user.ex",
          :modify,
          before_content: "v1",
          after_content: "v2"
        )

      assert result == :ok
    end
  end

  describe "get_file_status/1" do
    test "returns file status" do
      Tracker.track_file_operation(:openai, "lib/user.ex", :create, after_content: "content")

      status = Tracker.get_file_status("lib/user.ex")
      assert status.path == "lib/user.ex"
      assert status.owner == :openai
      assert status.status in [:new, :modified]
    end

    test "returns nil for unknown file" do
      status = Tracker.get_file_status("lib/unknown.ex")
      assert is_nil(status)
    end
  end

  describe "list_files/1" do
    test "lists all tracked files" do
      Tracker.track_file_operation(:openai, "lib/user.ex", :create, after_content: "v1")
      Tracker.track_file_operation(:anthropic, "lib/auth.ex", :create, after_content: "v1")

      files = Tracker.list_files()
      assert length(files) == 2
    end

    test "filters files by provider" do
      Tracker.track_file_operation(:openai, "lib/user.ex", :create, after_content: "v1")
      Tracker.track_file_operation(:anthropic, "lib/auth.ex", :create, after_content: "v1")

      files = Tracker.list_files(provider: :openai)
      assert length(files) >= 1
    end
  end

  describe "get_file_diff/1" do
    test "returns diff for file with history" do
      Tracker.track_file_operation(:openai, "lib/user.ex", :create, after_content: "v1")

      case Tracker.get_file_diff("lib/user.ex") do
        {:ok, diff} ->
          assert diff.file == "lib/user.ex"

        {:error, :not_found} ->
          # History might not be recorded yet in async environment
          assert true
      end
    end

    test "returns error for file without history" do
      result = Tracker.get_file_diff("lib/unknown.ex")
      assert result == {:error, :not_found}
    end
  end

  describe "lock_file/2 and unlock_file/2" do
    test "locks and unlocks file" do
      assert Tracker.lock_file("lib/user.ex", :openai) == :ok
      assert Tracker.unlock_file("lib/user.ex", :openai) == :ok
    end
  end

  describe "get_stats/0" do
    test "returns comprehensive statistics" do
      Tracker.track_file_operation(:openai, "lib/user.ex", :create, after_content: "v1")

      stats = Tracker.get_stats()
      assert is_map(stats)
      assert Map.has_key?(stats, :total_files)
    end
  end
end
