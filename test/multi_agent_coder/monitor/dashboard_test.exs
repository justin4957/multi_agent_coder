defmodule MultiAgentCoder.Monitor.DashboardTest do
  use ExUnit.Case, async: false

  alias MultiAgentCoder.Monitor.{Dashboard, FileTracker}

  setup do
    # Start Dashboard for each test
    {:ok, _pid} = start_supervised(Dashboard)

    # Start FileTracker if not already started
    case GenServer.whereis(FileTracker) do
      nil -> {:ok, _} = start_supervised(FileTracker)
      _pid -> :ok
    end

    :ok
  end

  describe "start_monitoring/2" do
    test "initializes monitoring with providers" do
      :ok = Dashboard.start_monitoring([:openai, :anthropic], task: "Test Task")

      state = Dashboard.get_state()

      assert state.task_name == "Test Task"
      assert :openai in state.providers
      assert :anthropic in state.providers
      assert Map.has_key?(state.provider_states, :openai)
      assert Map.has_key?(state.provider_states, :anthropic)
    end

    test "sets initial provider states to idle" do
      Dashboard.start_monitoring([:openai], task: "Test")

      state = Dashboard.get_state()

      assert state.provider_states[:openai].status == :idle
      assert state.provider_states[:openai].progress_percentage == 0.0
    end

    test "tracks elapsed time from start" do
      Dashboard.start_monitoring([:openai], task: "Test")

      Process.sleep(50)

      state = Dashboard.get_state()

      assert state.elapsed_ms > 0
    end
  end

  describe "update_provider_status/3" do
    setup do
      Dashboard.start_monitoring([:openai], task: "Test")
      :ok
    end

    test "updates provider status" do
      Dashboard.update_provider_status(:openai, :active)

      # Give the cast time to process
      Process.sleep(10)

      state = Dashboard.get_state()

      assert state.provider_states[:openai].status == :active
    end

    test "updates current task" do
      Dashboard.update_provider_status(:openai, :active, task: "Writing schema")

      Process.sleep(10)

      state = Dashboard.get_state()

      assert state.provider_states[:openai].current_task == "Writing schema"
    end

    test "updates current file" do
      Dashboard.update_provider_status(:openai, :active, file: "lib/user.ex")

      Process.sleep(10)

      state = Dashboard.get_state()

      assert state.provider_states[:openai].current_file == "lib/user.ex"
    end

    test "updates progress percentage" do
      Dashboard.update_provider_status(:openai, :active, progress: 45.5)

      Process.sleep(10)

      state = Dashboard.get_state()

      assert state.provider_states[:openai].progress_percentage == 45.5
    end

    test "updates lines generated" do
      Dashboard.update_provider_status(:openai, :active, lines_generated: 120)

      Process.sleep(10)

      state = Dashboard.get_state()

      assert state.provider_states[:openai].lines_generated == 120
    end

    test "tracks elapsed time when provider becomes active" do
      Dashboard.update_provider_status(:openai, :active)

      Process.sleep(50)

      Dashboard.update_provider_status(:openai, :active, progress: 50)

      Process.sleep(10)

      state = Dashboard.get_state()

      assert state.provider_states[:openai].elapsed_ms > 0
    end

    test "sets error message" do
      Dashboard.update_provider_status(:openai, :error, error: "API timeout")

      Process.sleep(10)

      state = Dashboard.get_state()

      assert state.provider_states[:openai].status == :error
      assert state.provider_states[:openai].error == "API timeout"
    end
  end

  describe "record_file_operation/4" do
    setup do
      Dashboard.start_monitoring([:openai], task: "Test")
      FileTracker.reset()
      :ok
    end

    test "tracks file operation" do
      Dashboard.record_file_operation(:openai, "lib/user.ex", :create)

      Process.sleep(10)

      operations = FileTracker.get_provider_operations(:openai)

      assert length(operations) == 1
      assert hd(operations).file == "lib/user.ex"
      assert hd(operations).operation == :create
    end

    test "updates current file in provider state" do
      Dashboard.record_file_operation(:openai, "lib/auth.ex", :modify)

      Process.sleep(10)

      state = Dashboard.get_state()

      assert state.provider_states[:openai].current_file == "lib/auth.ex"
    end

    test "tracks lines changed" do
      Dashboard.record_file_operation(:openai, "lib/user.ex", :modify, lines_changed: 75)

      Process.sleep(10)

      operations = FileTracker.get_provider_operations(:openai)

      assert hd(operations).lines_changed == 75
    end
  end

  describe "update_token_usage/3" do
    setup do
      Dashboard.start_monitoring([:openai], task: "Test")
      :ok
    end

    test "accumulates token usage" do
      Dashboard.update_token_usage(:openai, 100, 0.05)
      Dashboard.update_token_usage(:openai, 50, 0.02)

      Process.sleep(10)

      state = Dashboard.get_state()

      assert state.provider_states[:openai].tokens_used == 150
      assert_in_delta state.provider_states[:openai].estimated_cost, 0.07, 0.001
    end
  end

  describe "set_display_mode/1" do
    test "changes display mode" do
      Dashboard.set_display_mode(:compact)

      Process.sleep(10)

      state = Dashboard.get_state()

      assert state.display_mode == :compact
    end
  end

  describe "stop_monitoring/0" do
    test "returns final statistics" do
      Dashboard.start_monitoring([:openai, :anthropic], task: "Test Task")

      Dashboard.update_provider_status(:openai, :completed, lines_generated: 100)
      Dashboard.update_token_usage(:openai, 500, 0.10)

      Dashboard.update_provider_status(:anthropic, :completed, lines_generated: 75)
      Dashboard.update_token_usage(:anthropic, 300, 0.05)

      Process.sleep(10)

      stats = Dashboard.stop_monitoring()

      assert stats.total_providers == 2
      assert stats.completed_providers == 2
      assert stats.total_lines == 175
      assert stats.total_tokens == 800
      assert_in_delta stats.total_cost, 0.15, 0.001
      assert stats.total_elapsed_ms > 0
    end

    test "tracks failed providers" do
      Dashboard.start_monitoring([:openai, :anthropic], task: "Test")

      Dashboard.update_provider_status(:openai, :error, error: "Timeout")
      Dashboard.update_provider_status(:anthropic, :completed)

      Process.sleep(10)

      stats = Dashboard.stop_monitoring()

      assert stats.failed_providers == 1
      assert stats.completed_providers == 1
    end
  end

  describe "get_state/0" do
    test "returns current dashboard state" do
      Dashboard.start_monitoring([:openai], task: "Build API")

      state = Dashboard.get_state()

      assert state.task_name == "Build API"
      assert state.providers == [:openai]
      assert is_map(state.provider_states)
      assert state.display_mode in [:full, :compact, :minimal]
    end
  end

  describe "integration with FileTracker" do
    setup do
      Dashboard.start_monitoring([:openai, :anthropic], task: "Test")
      FileTracker.reset()
      :ok
    end

    test "tracks file operations across multiple providers" do
      Dashboard.record_file_operation(:openai, "lib/user.ex", :create)
      Dashboard.record_file_operation(:anthropic, "lib/auth.ex", :create)
      Dashboard.record_file_operation(:openai, "lib/user.ex", :modify)

      Process.sleep(10)

      file_stats = FileTracker.get_stats()

      assert file_stats.total_operations == 3
      assert file_stats.total_providers == 2
      assert file_stats.total_files_touched == 2
    end

    test "detects file conflicts through Dashboard" do
      Dashboard.record_file_operation(:openai, "lib/user.ex", :create)
      Dashboard.record_file_operation(:anthropic, "lib/user.ex", :modify)

      Process.sleep(10)

      conflicts = FileTracker.get_conflicts()

      assert length(conflicts) == 1
      {file, providers} = hd(conflicts)
      assert file == "lib/user.ex"
      assert :openai in providers
      assert :anthropic in providers
    end
  end
end
