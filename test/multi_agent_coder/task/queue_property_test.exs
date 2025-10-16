defmodule MultiAgentCoder.Task.QueuePropertyTest do
  use ExUnit.Case, async: false
  use ExUnitProperties

  alias MultiAgentCoder.Task.{Queue, Task}

  setup do
    # Start Queue for each test
    {:ok, _pid} = start_supervised(Queue)
    :ok
  end

  describe "Queue enqueue/dequeue properties" do
    property "enqueued tasks can be dequeued" do
      check all description <- string(:ascii, min_length: 1, max_length: 100),
                priority <- member_of([:low, :medium, :high, :urgent]),
                max_runs: 20 do
        task = Task.new(description, priority: priority)
        :ok = Queue.enqueue(task)

        # Should be able to dequeue it
        assert {:ok, dequeued_task} = Queue.dequeue()
        assert dequeued_task.id == task.id
        assert dequeued_task.description == task.description
        assert dequeued_task.priority == priority
      end
    end

    property "queue size increases with enqueue" do
      check all descriptions <- list_of(string(:ascii, min_length: 1, max_length: 50),
                  min_length: 1,
                  max_length: 5
                ),
                max_runs: 20 do
        # Clear queue
        Queue.clear()

        initial_status = Queue.status()
        assert initial_status.pending == 0

        # Enqueue tasks
        Enum.each(descriptions, fn desc ->
          task = Task.new(desc)
          Queue.enqueue(task)
        end)

        final_status = Queue.status()
        assert final_status.pending == length(descriptions)
      end
    end

    property "dequeue reduces queue size" do
      check all descriptions <- list_of(string(:ascii, min_length: 1, max_length: 50),
                  min_length: 2,
                  max_length: 5
                ),
                max_runs: 20 do
        Queue.clear()

        # Enqueue all tasks
        Enum.each(descriptions, fn desc ->
          Queue.enqueue(Task.new(desc))
        end)

        before_status = Queue.status()
        Queue.dequeue()
        after_status = Queue.status()

        assert after_status.pending == before_status.pending - 1
      end
    end
  end

  describe "Priority ordering properties" do
    property "urgent tasks are dequeued before high priority" do
      check all urgent_desc <- string(:ascii, min_length: 1, max_length: 50),
                high_desc <- string(:ascii, min_length: 1, max_length: 50),
                max_runs: 20 do
        Queue.clear()

        # Enqueue high priority first
        high_task = Task.new(high_desc, priority: :high)
        Queue.enqueue(high_task)

        # Then enqueue urgent
        urgent_task = Task.new(urgent_desc, priority: :urgent)
        Queue.enqueue(urgent_task)

        # Urgent should come out first
        {:ok, first} = Queue.dequeue()
        assert first.id == urgent_task.id
        assert first.priority == :urgent
      end
    end

    property "higher priority tasks available sooner" do
      check all high_desc <- string(:ascii, min_length: 1, max_length: 50),
                low_desc <- string(:ascii, min_length: 1, max_length: 50),
                max_runs: 20 do
        Queue.clear()

        # Enqueue low priority first, then high
        low_task = Task.new(low_desc, priority: :low)
        high_task = Task.new(high_desc, priority: :high)

        Queue.enqueue(low_task)
        Queue.enqueue(high_task)

        # Dequeue all tasks and collect them
        {:ok, first} = Queue.dequeue()
        {:ok, second} = Queue.dequeue()

        priorities = [first.priority, second.priority]

        # High priority should come before low (though exact order may vary)
        high_index = Enum.find_index(priorities, &(&1 == :high))
        low_index = Enum.find_index(priorities, &(&1 == :low))

        assert high_index < low_index
      end
    end
  end

  describe "Task completion properties" do
    property "completing task updates queue status" do
      check all description <- string(:ascii, min_length: 1, max_length: 100),
                result <- string(:ascii, min_length: 1, max_length: 200),
                max_runs: 20 do
        Queue.clear()

        task = Task.new(description)
        Queue.enqueue(task)
        {:ok, dequeued} = Queue.dequeue()

        # Start task
        running_task = Task.start(dequeued)
        Queue.update_task(running_task.id, running_task)
        before_complete = Queue.status()

        # Complete task
        Queue.complete_task(dequeued.id, result)
        after_complete = Queue.status()

        assert after_complete.completed == before_complete.completed + 1
        assert after_complete.running == before_complete.running - 1
      end
    end

    property "failed tasks are tracked separately" do
      check all description <- string(:ascii, min_length: 1, max_length: 100),
                reason <- string(:ascii, min_length: 1, max_length: 100),
                max_runs: 20 do
        Queue.clear()

        task = Task.new(description)
        Queue.enqueue(task)
        {:ok, dequeued} = Queue.dequeue()

        running_task = Task.start(dequeued)
        Queue.update_task(running_task.id, running_task)
        before_fail = Queue.status()

        Queue.fail_task(dequeued.id, reason)
        after_fail = Queue.status()

        assert after_fail.failed == before_fail.failed + 1
        assert after_fail.running == before_fail.running - 1
      end
    end
  end

  describe "Queue invariants" do
    property "total equals sum of all states" do
      check all descriptions <- list_of(string(:ascii, min_length: 1, max_length: 50),
                  min_length: 1,
                  max_length: 10
                ),
                max_runs: 20 do
        Queue.clear()

        # Enqueue tasks
        Enum.each(descriptions, fn desc ->
          Queue.enqueue(Task.new(desc))
        end)

        status = Queue.status()
        sum = status.pending + status.running + status.completed + status.failed + status.cancelled

        assert status.total == sum
      end
    end

    property "cannot dequeue from empty queue" do
      Queue.clear()
      assert {:error, :empty} = Queue.dequeue()
    end

    property "enqueue and dequeue preserve task identity" do
      check all descriptions <- list_of(string(:ascii, min_length: 1, max_length: 50),
                  min_length: 2,
                  max_length: 5
                ),
                max_runs: 20 do
        Queue.clear()

        # Enqueue all with same priority
        task_ids =
          Enum.map(descriptions, fn desc ->
            task = Task.new(desc, priority: :medium)
            Queue.enqueue(task)
            task.id
          end)
          |> MapSet.new()

        # Dequeue all
        dequeued_ids =
          Enum.map(1..MapSet.size(task_ids), fn _ ->
            {:ok, task} = Queue.dequeue()
            task.id
          end)
          |> MapSet.new()

        # All enqueued tasks should be dequeued (order may vary due to dependencies)
        assert MapSet.equal?(task_ids, dequeued_ids)
      end
    end
  end

  describe "Clear operation properties" do
    property "clear removes all tasks" do
      check all descriptions <- list_of(string(:ascii, min_length: 1, max_length: 50),
                  min_length: 1,
                  max_length: 10
                ),
                max_runs: 20 do
        Queue.clear()

        # Add tasks
        Enum.each(descriptions, fn desc ->
          Queue.enqueue(Task.new(desc))
        end)

        # Clear
        Queue.clear()

        # Should be empty
        status = Queue.status()
        assert status.pending == 0
        assert status.total == 0
      end
    end
  end
end
