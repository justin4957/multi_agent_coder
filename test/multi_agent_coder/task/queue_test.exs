defmodule MultiAgentCoder.Task.QueueTest do
  use ExUnit.Case, async: false

  alias MultiAgentCoder.Task.{Task, Queue}

  setup do
    # Start the Queue GenServer for each test
    {:ok, _pid} = start_supervised(Queue)

    # Clear the queue before each test
    Queue.clear()

    :ok
  end

  describe "enqueue/1" do
    test "enqueues a task successfully" do
      task = Task.new("Implement feature")
      assert Queue.enqueue(task) == :ok
    end

    test "enqueued task appears in status" do
      task = Task.new("Implement feature")
      Queue.enqueue(task)

      status = Queue.status()
      assert status.pending == 1
      assert status.total == 1
    end

    test "maintains priority order with multiple tasks" do
      task1 = Task.new("Low priority", priority: 3)
      task2 = Task.new("High priority", priority: 8)
      task3 = Task.new("Medium priority", priority: 5)

      Queue.enqueue(task1)
      Queue.enqueue(task2)
      Queue.enqueue(task3)

      all_tasks = Queue.list_all()
      priorities = Enum.map(all_tasks.pending, & &1.priority)

      # Should be sorted by priority descending (8, 5, 3)
      assert priorities == [8, 5, 3]
    end
  end

  describe "dequeue/0" do
    test "dequeues the highest priority task" do
      task1 = Task.new("Low priority", priority: 3)
      task2 = Task.new("High priority", priority: 8)

      Queue.enqueue(task1)
      Queue.enqueue(task2)

      {:ok, dequeued} = Queue.dequeue()
      assert dequeued.priority == 8
      assert dequeued.status == :running
    end

    test "returns error when queue is empty" do
      assert Queue.dequeue() == {:error, :empty}
    end

    test "respects task dependencies" do
      task1 = Task.new("Independent task")
      task2 = Task.new("Dependent task", dependencies: [task1.id])

      Queue.enqueue(task1)
      Queue.enqueue(task2)

      # Should dequeue task1 first even if task2 has higher priority
      {:ok, dequeued} = Queue.dequeue()
      assert dequeued.id == task1.id
    end

    test "dequeues dependent task after dependency completes" do
      task1 = Task.new("Independent task")
      task2 = Task.new("Dependent task", dependencies: [task1.id])

      Queue.enqueue(task1)
      Queue.enqueue(task2)

      {:ok, dequeued1} = Queue.dequeue()
      assert dequeued1.id == task1.id

      # Complete task1
      Queue.complete_task(task1.id, "result")

      # Now task2 should be available
      {:ok, dequeued2} = Queue.dequeue()
      assert dequeued2.id == task2.id
    end

    test "moves task to running state" do
      task = Task.new("Implement feature")
      Queue.enqueue(task)

      status_before = Queue.status()
      assert status_before.pending == 1
      assert status_before.running == 0

      {:ok, _dequeued} = Queue.dequeue()

      status_after = Queue.status()
      assert status_after.pending == 0
      assert status_after.running == 1
    end
  end

  describe "get_task/1" do
    test "retrieves pending task by ID" do
      task = Task.new("Implement feature")
      Queue.enqueue(task)

      {:ok, retrieved} = Queue.get_task(task.id)
      assert retrieved.id == task.id
      assert retrieved.description == task.description
    end

    test "retrieves running task by ID" do
      task = Task.new("Implement feature")
      Queue.enqueue(task)
      {:ok, dequeued} = Queue.dequeue()

      {:ok, retrieved} = Queue.get_task(dequeued.id)
      assert retrieved.status == :running
    end

    test "returns error for non-existent task" do
      assert Queue.get_task("nonexistent_id") == {:error, :not_found}
    end
  end

  describe "update_task/2" do
    test "updates pending task" do
      task = Task.new("Implement feature")
      Queue.enqueue(task)

      updated_task = Task.update_metadata(task, %{custom: "value"})
      assert Queue.update_task(task.id, updated_task) == :ok

      {:ok, retrieved} = Queue.get_task(task.id)
      assert retrieved.metadata.custom == "value"
    end

    test "updates running task" do
      task = Task.new("Implement feature")
      Queue.enqueue(task)
      {:ok, running_task} = Queue.dequeue()

      updated = Task.update_metadata(running_task, %{progress: 0.5})
      assert Queue.update_task(running_task.id, updated) == :ok

      {:ok, retrieved} = Queue.get_task(running_task.id)
      assert retrieved.metadata.progress == 0.5
    end

    test "returns error for non-existent task" do
      task = Task.new("Implement feature")
      result = Queue.update_task("nonexistent_id", task)

      assert result == {:error, :not_found}
    end
  end

  describe "complete_task/2" do
    test "completes running task successfully" do
      task = Task.new("Implement feature")
      Queue.enqueue(task)
      {:ok, running_task} = Queue.dequeue()

      result = %{code: "def hello, do: :world"}
      assert Queue.complete_task(running_task.id, result) == :ok

      status = Queue.status()
      assert status.running == 0
      assert status.completed == 1
    end

    test "completed task has result" do
      task = Task.new("Implement feature")
      Queue.enqueue(task)
      {:ok, running_task} = Queue.dequeue()

      result = "implementation"
      Queue.complete_task(running_task.id, result)

      {:ok, completed} = Queue.get_task(running_task.id)
      assert completed.status == :completed
      assert completed.result == result
    end

    test "returns error for non-running task" do
      task = Task.new("Implement feature")
      Queue.enqueue(task)

      result = Queue.complete_task(task.id, "result")
      assert result == {:error, :not_found}
    end
  end

  describe "fail_task/2" do
    test "fails running task successfully" do
      task = Task.new("Implement feature")
      Queue.enqueue(task)
      {:ok, running_task} = Queue.dequeue()

      error = %{reason: "timeout"}
      assert Queue.fail_task(running_task.id, error) == :ok

      status = Queue.status()
      assert status.running == 0
      assert status.failed == 1
    end

    test "failed task has error information" do
      task = Task.new("Implement feature")
      Queue.enqueue(task)
      {:ok, running_task} = Queue.dequeue()

      error = "connection timeout"
      Queue.fail_task(running_task.id, error)

      {:ok, failed} = Queue.get_task(running_task.id)
      assert failed.status == :failed
      assert failed.error == error
    end

    test "returns error for non-running task" do
      task = Task.new("Implement feature")
      Queue.enqueue(task)

      result = Queue.fail_task(task.id, "error")
      assert result == {:error, :not_found}
    end
  end

  describe "cancel_task/1" do
    test "cancels pending task" do
      task = Task.new("Implement feature")
      Queue.enqueue(task)

      assert Queue.cancel_task(task.id) == :ok

      status = Queue.status()
      assert status.pending == 0
      assert status.cancelled == 1
    end

    test "cancels running task" do
      task = Task.new("Implement feature")
      Queue.enqueue(task)
      {:ok, running_task} = Queue.dequeue()

      assert Queue.cancel_task(running_task.id) == :ok

      status = Queue.status()
      assert status.running == 0
      assert status.cancelled == 1
    end

    test "returns error for non-existent task" do
      result = Queue.cancel_task("nonexistent_id")
      assert result == {:error, :not_found}
    end

    test "cannot cancel completed task" do
      task = Task.new("Implement feature")
      Queue.enqueue(task)
      {:ok, running_task} = Queue.dequeue()
      Queue.complete_task(running_task.id, "result")

      result = Queue.cancel_task(running_task.id)
      assert result == {:error, :not_found}
    end
  end

  describe "status/0" do
    test "returns correct counts for empty queue" do
      status = Queue.status()

      assert status.pending == 0
      assert status.running == 0
      assert status.completed == 0
      assert status.failed == 0
      assert status.cancelled == 0
      assert status.total == 0
    end

    test "returns correct counts with mixed tasks" do
      task1 = Task.new("Task 1", priority: 10)
      task2 = Task.new("Task 2", priority: 9)
      task3 = Task.new("Task 3", priority: 8)
      task4 = Task.new("Task 4", priority: 7)

      Queue.enqueue(task1)
      Queue.enqueue(task2)
      Queue.enqueue(task3)
      Queue.enqueue(task4)

      {:ok, running1} = Queue.dequeue()
      {:ok, running2} = Queue.dequeue()

      # running1 and running2 are task1 and task2 due to priority ordering
      Queue.complete_task(running1.id, "result")
      Queue.fail_task(running2.id, "error")
      # task3 is still in pending, cancel it
      Queue.cancel_task(task3.id)

      status = Queue.status()
      assert status.pending == 1
      assert status.running == 0
      assert status.completed == 1
      assert status.failed == 1
      assert status.cancelled == 1
      assert status.total == 4
    end
  end

  describe "list_all/0" do
    test "lists all tasks by status" do
      task1 = Task.new("Task 1")
      task2 = Task.new("Task 2")

      Queue.enqueue(task1)
      Queue.enqueue(task2)

      {:ok, running} = Queue.dequeue()
      Queue.complete_task(running.id, "result")

      all_tasks = Queue.list_all()

      assert length(all_tasks.pending) == 1
      assert length(all_tasks.running) == 0
      assert length(all_tasks.completed) == 1
      assert length(all_tasks.failed) == 0
      assert length(all_tasks.cancelled) == 0
    end
  end

  describe "clear/0" do
    test "clears all tasks from queue" do
      task1 = Task.new("Task 1")
      task2 = Task.new("Task 2")

      Queue.enqueue(task1)
      Queue.enqueue(task2)

      {:ok, _} = Queue.dequeue()

      status_before = Queue.status()
      assert status_before.total > 0

      Queue.clear()

      status_after = Queue.status()
      assert status_after.total == 0
      assert status_after.pending == 0
      assert status_after.running == 0
    end
  end
end
