defmodule MultiAgentCoder.Task.TrackerTest do
  use ExUnit.Case, async: false

  alias MultiAgentCoder.Task.Tracker

  setup do
    # Start the Tracker GenServer for each test
    {:ok, _pid} = start_supervised(Tracker)

    # Clear the tracker before each test
    Tracker.clear()

    :ok
  end

  describe "start_tracking/2" do
    test "starts tracking a task successfully" do
      assert Tracker.start_tracking("task_1", :openai) == :ok
    end

    test "tracked task appears in get_all_tasks" do
      Tracker.start_tracking("task_1", :openai)

      tasks = Tracker.get_all_tasks()
      assert length(tasks) == 1

      [task] = tasks
      assert task.task_id == "task_1"
      assert task.provider == :openai
      assert task.tokens_used == 0
      assert task.progress == 0.0
    end

    test "increments provider active_tasks stat" do
      Tracker.start_tracking("task_1", :openai)

      {:ok, stats} = Tracker.get_provider_stats(:openai)
      assert stats.active_tasks == 1
    end
  end

  describe "update_progress/2" do
    test "updates task progress successfully" do
      Tracker.start_tracking("task_1", :openai)

      assert Tracker.update_progress("task_1", progress: 0.5, tokens: 100) == :ok

      {:ok, status} = Tracker.get_status("task_1")
      assert status.progress == 0.5
      assert status.tokens_used == 100
    end

    test "returns error for non-existent task" do
      result = Tracker.update_progress("nonexistent", progress: 0.5)
      assert result == {:error, :not_found}
    end

    test "updates last_update timestamp" do
      Tracker.start_tracking("task_1", :openai)

      {:ok, status_before} = Tracker.get_status("task_1")
      Process.sleep(10)

      Tracker.update_progress("task_1", progress: 0.5)

      {:ok, status_after} = Tracker.get_status("task_1")
      assert DateTime.compare(status_after.last_update, status_before.last_update) == :gt
    end

    test "updates provider token statistics" do
      Tracker.start_tracking("task_1", :openai)
      Tracker.update_progress("task_1", tokens: 500)

      {:ok, stats} = Tracker.get_provider_stats(:openai)
      assert stats.total_tokens == 500
    end

    test "calculates estimated completion time" do
      Tracker.start_tracking("task_1", :openai)
      Process.sleep(100)

      Tracker.update_progress("task_1", progress: 0.5)

      {:ok, status} = Tracker.get_status("task_1")
      assert status.estimated_completion != nil
      assert %DateTime{} = status.estimated_completion
    end
  end

  describe "complete_tracking/1" do
    test "completes tracking successfully" do
      Tracker.start_tracking("task_1", :openai)
      assert Tracker.complete_tracking("task_1") == :ok
    end

    test "returns error for non-existent task" do
      result = Tracker.complete_tracking("nonexistent")
      assert result == {:error, :not_found}
    end

    test "removes task from active tracking" do
      Tracker.start_tracking("task_1", :openai)
      Tracker.complete_tracking("task_1")

      result = Tracker.get_status("task_1")
      assert result == {:error, :not_found}
    end

    test "updates provider statistics" do
      Tracker.start_tracking("task_1", :openai)
      Process.sleep(10)
      Tracker.complete_tracking("task_1")

      {:ok, stats} = Tracker.get_provider_stats(:openai)
      assert stats.active_tasks == 0
      assert stats.completed_tasks == 1
      assert stats.average_completion_time > 0
    end

    test "updates global statistics" do
      Tracker.start_tracking("task_1", :openai)
      Tracker.complete_tracking("task_1")

      global_stats = Tracker.get_global_stats()
      assert global_stats.total_completed == 1
    end

    test "calculates average completion time across multiple tasks" do
      Tracker.start_tracking("task_1", :openai)
      Process.sleep(50)
      Tracker.complete_tracking("task_1")

      Tracker.start_tracking("task_2", :openai)
      Process.sleep(50)
      Tracker.complete_tracking("task_2")

      {:ok, stats} = Tracker.get_provider_stats(:openai)
      assert stats.completed_tasks == 2
      assert stats.average_completion_time > 0
    end
  end

  describe "fail_tracking/1" do
    test "fails tracking successfully" do
      Tracker.start_tracking("task_1", :openai)
      assert Tracker.fail_tracking("task_1") == :ok
    end

    test "returns error for non-existent task" do
      result = Tracker.fail_tracking("nonexistent")
      assert result == {:error, :not_found}
    end

    test "removes task from active tracking" do
      Tracker.start_tracking("task_1", :openai)
      Tracker.fail_tracking("task_1")

      result = Tracker.get_status("task_1")
      assert result == {:error, :not_found}
    end

    test "updates provider failed tasks count" do
      Tracker.start_tracking("task_1", :openai)
      Tracker.fail_tracking("task_1")

      {:ok, stats} = Tracker.get_provider_stats(:openai)
      assert stats.active_tasks == 0
      assert stats.failed_tasks == 1
    end

    test "updates global failed count" do
      Tracker.start_tracking("task_1", :openai)
      Tracker.fail_tracking("task_1")

      global_stats = Tracker.get_global_stats()
      assert global_stats.total_failed == 1
    end
  end

  describe "get_status/1" do
    test "returns status for tracked task" do
      Tracker.start_tracking("task_1", :openai)

      {:ok, status} = Tracker.get_status("task_1")
      assert status.task_id == "task_1"
      assert status.provider == :openai
      assert status.progress == 0.0
      assert status.tokens_used == 0
    end

    test "returns error for non-tracked task" do
      result = Tracker.get_status("nonexistent")
      assert result == {:error, :not_found}
    end
  end

  describe "get_all_tasks/0" do
    test "returns empty list when no tasks tracked" do
      tasks = Tracker.get_all_tasks()
      assert tasks == []
    end

    test "returns all tracked tasks" do
      Tracker.start_tracking("task_1", :openai)
      Tracker.start_tracking("task_2", :anthropic)
      Tracker.start_tracking("task_3", :deepseek)

      tasks = Tracker.get_all_tasks()
      assert length(tasks) == 3

      task_ids = Enum.map(tasks, & &1.task_id)
      assert "task_1" in task_ids
      assert "task_2" in task_ids
      assert "task_3" in task_ids
    end
  end

  describe "get_provider_stats/1" do
    test "returns stats for provider" do
      Tracker.start_tracking("task_1", :openai)

      {:ok, stats} = Tracker.get_provider_stats(:openai)
      assert stats.active_tasks == 1
      assert stats.completed_tasks == 0
      assert stats.failed_tasks == 0
      assert stats.total_tokens == 0
      assert stats.average_completion_time == 0.0
    end

    test "returns error for provider with no stats" do
      result = Tracker.get_provider_stats(:nonexistent)
      assert result == {:error, :not_found}
    end

    test "tracks multiple metrics correctly" do
      Tracker.start_tracking("task_1", :openai)
      Tracker.update_progress("task_1", tokens: 100)
      Tracker.complete_tracking("task_1")

      Tracker.start_tracking("task_2", :openai)
      Tracker.fail_tracking("task_2")

      {:ok, stats} = Tracker.get_provider_stats(:openai)
      assert stats.active_tasks == 0
      assert stats.completed_tasks == 1
      assert stats.failed_tasks == 1
      assert stats.total_tokens == 100
    end
  end

  describe "get_all_provider_stats/0" do
    test "returns empty map when no providers tracked" do
      stats = Tracker.get_all_provider_stats()
      assert stats == %{}
    end

    test "returns stats for all providers" do
      Tracker.start_tracking("task_1", :openai)
      Tracker.start_tracking("task_2", :anthropic)

      stats = Tracker.get_all_provider_stats()
      assert Map.has_key?(stats, :openai)
      assert Map.has_key?(stats, :anthropic)
    end
  end

  describe "get_global_stats/0" do
    test "returns global statistics" do
      stats = Tracker.get_global_stats()

      assert Map.has_key?(stats, :active_tasks)
      assert Map.has_key?(stats, :total_providers)
      assert stats.active_tasks == 0
      assert stats.total_providers == 0
    end

    test "tracks global counts correctly" do
      Tracker.start_tracking("task_1", :openai)
      Tracker.start_tracking("task_2", :anthropic)

      stats = Tracker.get_global_stats()
      assert stats.active_tasks == 2
      assert stats.total_providers == 2
    end

    test "includes completed and failed counts" do
      Tracker.start_tracking("task_1", :openai)
      Tracker.complete_tracking("task_1")

      Tracker.start_tracking("task_2", :openai)
      Tracker.fail_tracking("task_2")

      stats = Tracker.get_global_stats()
      assert stats.total_completed == 1
      assert stats.total_failed == 1
    end
  end

  describe "clear/0" do
    test "clears all tracking data" do
      Tracker.start_tracking("task_1", :openai)
      Tracker.start_tracking("task_2", :anthropic)

      Tracker.clear()

      tasks = Tracker.get_all_tasks()
      assert tasks == []

      stats = Tracker.get_all_provider_stats()
      assert stats == %{}
    end
  end

  describe "progress estimation" do
    test "estimated completion time increases with slow progress" do
      Tracker.start_tracking("task_1", :openai)
      Process.sleep(100)

      Tracker.update_progress("task_1", progress: 0.1)

      {:ok, status} = Tracker.get_status("task_1")
      assert status.estimated_completion != nil

      # With only 10% progress after 100ms, estimated total time should be ~1000ms
      eta_seconds = DateTime.diff(status.estimated_completion, DateTime.utc_now(), :millisecond)
      assert eta_seconds > 500
    end

    test "estimated completion time is nil when progress is 0" do
      Tracker.start_tracking("task_1", :openai)

      {:ok, status} = Tracker.get_status("task_1")
      assert status.estimated_completion == nil
    end
  end

  describe "concurrent tracking" do
    test "handles multiple providers simultaneously" do
      Tracker.start_tracking("task_1", :openai)
      Tracker.start_tracking("task_2", :anthropic)
      Tracker.start_tracking("task_3", :deepseek)

      Tracker.update_progress("task_1", progress: 0.3, tokens: 100)
      Tracker.update_progress("task_2", progress: 0.5, tokens: 200)
      Tracker.update_progress("task_3", progress: 0.7, tokens: 300)

      tasks = Tracker.get_all_tasks()
      assert length(tasks) == 3

      {:ok, stats1} = Tracker.get_provider_stats(:openai)
      {:ok, stats2} = Tracker.get_provider_stats(:anthropic)
      {:ok, stats3} = Tracker.get_provider_stats(:deepseek)

      assert stats1.total_tokens == 100
      assert stats2.total_tokens == 200
      assert stats3.total_tokens == 300
    end
  end
end
