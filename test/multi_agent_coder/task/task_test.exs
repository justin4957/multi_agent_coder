defmodule MultiAgentCoder.Task.TaskTest do
  use ExUnit.Case, async: true

  alias MultiAgentCoder.Task.Task

  describe "new/2" do
    test "creates a task with default values" do
      task = Task.new("Implement feature")

      assert task.description == "Implement feature"
      assert task.status == :pending
      assert task.priority == 5
      assert task.dependencies == []
      assert task.metadata == %{}
      assert task.assigned_to == nil
      assert task.result == nil
      assert task.error == nil
      assert is_binary(task.id)
      assert %DateTime{} = task.created_at
    end

    test "creates a task with custom options" do
      task =
        Task.new("Implement feature",
          priority: 8,
          dependencies: ["task_1", "task_2"],
          metadata: %{type: :feature}
        )

      assert task.priority == 8
      assert task.dependencies == ["task_1", "task_2"]
      assert task.metadata == %{type: :feature}
    end

    test "generates unique task IDs" do
      task1 = Task.new("Task 1")
      task2 = Task.new("Task 2")

      assert task1.id != task2.id
    end
  end

  describe "assign_to/2" do
    test "assigns task to a single provider" do
      task = Task.new("Implement feature")
      assigned = Task.assign_to(task, :openai)

      assert assigned.assigned_to == [:openai]
      assert assigned.status == :queued
    end

    test "assigns task to multiple providers" do
      task = Task.new("Implement feature")
      assigned = Task.assign_to(task, [:openai, :anthropic])

      assert assigned.assigned_to == [:openai, :anthropic]
      assert assigned.status == :queued
    end

    test "converts single atom to list" do
      task = Task.new("Implement feature")
      assigned = Task.assign_to(task, :deepseek)

      assert is_list(assigned.assigned_to)
      assert assigned.assigned_to == [:deepseek]
    end
  end

  describe "start/1" do
    test "marks task as running and sets started_at" do
      task = Task.new("Implement feature")
      started = Task.start(task)

      assert started.status == :running
      assert %DateTime{} = started.started_at
    end

    test "updates previously queued task" do
      task =
        Task.new("Implement feature")
        |> Task.assign_to(:openai)

      assert task.status == :queued

      started = Task.start(task)
      assert started.status == :running
    end
  end

  describe "complete/2" do
    test "marks task as completed with result" do
      task =
        Task.new("Implement feature")
        |> Task.start()

      result = %{code: "def hello, do: :world"}
      completed = Task.complete(task, result)

      assert completed.status == :completed
      assert completed.result == result
      assert %DateTime{} = completed.completed_at
    end
  end

  describe "fail/2" do
    test "marks task as failed with error" do
      task =
        Task.new("Implement feature")
        |> Task.start()

      error = %{reason: "timeout"}
      failed = Task.fail(task, error)

      assert failed.status == :failed
      assert failed.error == error
      assert %DateTime{} = failed.completed_at
    end
  end

  describe "cancel/1" do
    test "marks task as cancelled" do
      task = Task.new("Implement feature")
      cancelled = Task.cancel(task)

      assert cancelled.status == :cancelled
      assert %DateTime{} = cancelled.completed_at
    end

    test "can cancel running task" do
      task =
        Task.new("Implement feature")
        |> Task.start()

      cancelled = Task.cancel(task)
      assert cancelled.status == :cancelled
    end
  end

  describe "update_metadata/2" do
    test "updates task metadata" do
      task = Task.new("Implement feature", metadata: %{type: :feature})
      updated = Task.update_metadata(task, %{priority_reason: "urgent"})

      assert updated.metadata == %{type: :feature, priority_reason: "urgent"}
    end

    test "overwrites existing metadata keys" do
      task = Task.new("Implement feature", metadata: %{type: :feature})
      updated = Task.update_metadata(task, %{type: :bugfix})

      assert updated.metadata == %{type: :bugfix}
    end
  end

  describe "can_execute?/2" do
    test "returns true when no dependencies" do
      task = Task.new("Implement feature")
      completed_ids = MapSet.new()

      assert Task.can_execute?(task, completed_ids)
    end

    test "returns true when all dependencies are met" do
      task = Task.new("Implement feature", dependencies: ["task_1", "task_2"])
      completed_ids = MapSet.new(["task_1", "task_2", "task_3"])

      assert Task.can_execute?(task, completed_ids)
    end

    test "returns false when some dependencies are not met" do
      task = Task.new("Implement feature", dependencies: ["task_1", "task_2"])
      completed_ids = MapSet.new(["task_1"])

      refute Task.can_execute?(task, completed_ids)
    end

    test "returns false when no dependencies are met" do
      task = Task.new("Implement feature", dependencies: ["task_1", "task_2"])
      completed_ids = MapSet.new()

      refute Task.can_execute?(task, completed_ids)
    end
  end

  describe "elapsed_time/1" do
    test "returns nil when task not started" do
      task = Task.new("Implement feature")

      assert Task.elapsed_time(task) == nil
    end

    test "returns elapsed time for running task" do
      task = Task.new("Implement feature") |> Task.start()
      Process.sleep(10)

      elapsed = Task.elapsed_time(task)
      assert is_integer(elapsed)
      assert elapsed >= 10
    end

    test "returns total elapsed time for completed task" do
      task = Task.new("Implement feature") |> Task.start()
      Process.sleep(10)

      completed = Task.complete(task, "result")
      elapsed = Task.elapsed_time(completed)

      assert is_integer(elapsed)
      assert elapsed >= 10
    end
  end
end
