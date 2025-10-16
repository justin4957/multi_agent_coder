defmodule MultiAgentCoder.Task.TaskPropertyTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias MultiAgentCoder.Task.Task

  describe "Task.new/1 properties" do
    property "always generates unique IDs" do
      check all(
              description <- string(:ascii, min_length: 1, max_length: 100),
              max_runs: 50
            ) do
        task1 = Task.new(description)
        task2 = Task.new(description)

        assert task1.id != task2.id
        assert is_binary(task1.id)
        assert is_binary(task2.id)
      end
    end

    property "preserves description" do
      check all(description <- string(:ascii, min_length: 1, max_length: 100)) do
        task = Task.new(description)
        assert task.description == description
      end
    end

    property "creates tasks in pending state" do
      check all(description <- string(:ascii, min_length: 1, max_length: 100)) do
        task = Task.new(description)
        assert task.status == :pending
      end
    end

    property "sets default priority to 5" do
      check all(description <- string(:ascii, min_length: 1, max_length: 100)) do
        task = Task.new(description)
        assert task.priority == 5
      end
    end
  end

  describe "Task.new/2 with priority" do
    property "accepts valid integer priorities" do
      check all(
              description <- string(:ascii, min_length: 1, max_length: 100),
              priority <- integer(1..10)
            ) do
        task = Task.new(description, priority: priority)
        assert task.priority == priority
      end
    end
  end

  describe "Task.assign_to/2 properties" do
    property "assigns providers correctly" do
      check all(
              description <- string(:ascii, min_length: 1, max_length: 100),
              providers <-
                list_of(member_of([:openai, :anthropic, :deepseek, :perplexity, :local]),
                  min_length: 1,
                  max_length: 5
                )
            ) do
        task = Task.new(description)
        assigned_task = Task.assign_to(task, providers)

        assert assigned_task.assigned_to == providers
        # Original task should be unchanged (immutability)
        assert task.assigned_to == nil or task.assigned_to == []
      end
    end
  end

  describe "Task state transitions" do
    property "can transition from pending to running" do
      check all(description <- string(:ascii, min_length: 1, max_length: 100)) do
        task = Task.new(description)
        running_task = Task.start(task)

        assert running_task.status == :running
        assert running_task.started_at != nil
      end
    end

    property "can transition from running to completed" do
      check all(
              description <- string(:ascii, min_length: 1, max_length: 100),
              result <- string(:ascii, min_length: 1, max_length: 500)
            ) do
        task =
          Task.new(description)
          |> Task.start()
          |> Task.complete(result)

        assert task.status == :completed
        assert task.result == result
        assert task.completed_at != nil
      end
    end

    property "can transition from running to failed" do
      check all(
              description <- string(:ascii, min_length: 1, max_length: 100),
              reason <- string(:ascii, min_length: 1, max_length: 200)
            ) do
        task =
          Task.new(description)
          |> Task.start()
          |> Task.fail(reason)

        assert task.status == :failed
        assert task.error == reason
        assert task.completed_at != nil
      end
    end

    property "elapsed time is always non-negative" do
      check all(description <- string(:ascii, min_length: 1, max_length: 100)) do
        task = Task.new(description) |> Task.start()
        elapsed = Task.elapsed_time(task)

        assert is_integer(elapsed)
        assert elapsed >= 0
      end
    end
  end

  describe "Task cancellation properties" do
    property "can cancel pending tasks" do
      check all(description <- string(:ascii, min_length: 1, max_length: 100)) do
        task = Task.new(description)
        cancelled_task = Task.cancel(task)

        assert cancelled_task.status == :cancelled
        assert cancelled_task.completed_at != nil
      end
    end

    property "can cancel running tasks" do
      check all(description <- string(:ascii, min_length: 1, max_length: 100)) do
        task =
          Task.new(description)
          |> Task.start()
          |> Task.cancel()

        assert task.status == :cancelled
      end
    end
  end

  describe "Task immutability properties" do
    property "task operations return new structs" do
      check all(description <- string(:ascii, min_length: 1, max_length: 100)) do
        original = Task.new(description)
        modified = Task.start(original)

        # Original should be unchanged
        assert original.status == :pending
        assert original.started_at == nil

        # Modified should have changes
        assert modified.status == :running
        assert modified.started_at != nil
      end
    end
  end
end
