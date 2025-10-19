defmodule MultiAgentCoder.Merge.PerformanceMonitorTest do
  # Cannot be async since we're sharing a global PerformanceMonitor GenServer
  use ExUnit.Case, async: false

  alias MultiAgentCoder.Merge.PerformanceMonitor
  alias MultiAgentCoder.Merge.PerformanceMonitor.{Report, Metrics}

  setup do
    # PerformanceMonitor is already started by application supervisor
    # No setup needed
    :ok
  end

  describe "operation tracking" do
    test "tracks a complete operation lifecycle" do
      operation_id = "test_op_1"

      # Start operation
      assert :ok = PerformanceMonitor.start_operation(operation_id)

      # Start a phase
      assert :ok = PerformanceMonitor.start_phase(operation_id, :phase1)

      # Do some work
      Process.sleep(10)

      # End the phase
      assert :ok = PerformanceMonitor.end_phase(operation_id, :phase1)

      # Complete operation
      report = PerformanceMonitor.complete_operation(operation_id)

      assert %Report{} = report
      assert report.total_duration_ms > 0
      assert length(report.phases) == 1
      assert hd(report.phases).phase == :phase1
    end

    test "tracks multiple phases in sequence" do
      operation_id = "test_op_2"

      PerformanceMonitor.start_operation(operation_id)

      # Phase 1
      PerformanceMonitor.start_phase(operation_id, :parse)
      Process.sleep(5)
      PerformanceMonitor.end_phase(operation_id, :parse)

      # Phase 2
      PerformanceMonitor.start_phase(operation_id, :analyze)
      Process.sleep(5)
      PerformanceMonitor.end_phase(operation_id, :analyze)

      # Phase 3
      PerformanceMonitor.start_phase(operation_id, :merge)
      Process.sleep(5)
      PerformanceMonitor.end_phase(operation_id, :merge)

      report = PerformanceMonitor.complete_operation(operation_id)

      assert length(report.phases) == 3
      assert Enum.map(report.phases, & &1.phase) == [:parse, :analyze, :merge]
      assert Enum.all?(report.phases, fn phase -> phase.duration_ms > 0 end)
    end

    test "tracks phase metadata" do
      operation_id = "test_op_3"

      PerformanceMonitor.start_operation(operation_id)

      metadata = %{files: 5, providers: 3}
      PerformanceMonitor.start_phase(operation_id, :merge, metadata)
      Process.sleep(5)
      PerformanceMonitor.end_phase(operation_id, :merge)

      {:ok, metrics} = PerformanceMonitor.get_metrics(operation_id)

      assert [%Metrics{metadata: ^metadata}] = metrics
    end
  end

  describe "phase tracking helper" do
    test "track_phase executes function and measures time" do
      operation_id = "test_op_4"
      PerformanceMonitor.start_operation(operation_id)

      result =
        PerformanceMonitor.track_phase(operation_id, :computation, %{}, fn ->
          Process.sleep(10)
          {:ok, :computed}
        end)

      assert result == {:ok, :computed}

      {:ok, metrics} = PerformanceMonitor.get_metrics(operation_id)
      assert length(metrics) == 1
      assert hd(metrics).phase == :computation
      assert hd(metrics).duration_ms >= 10
    end

    test "track_phase handles function errors" do
      operation_id = "test_op_5"
      PerformanceMonitor.start_operation(operation_id)

      assert_raise RuntimeError, "test error", fn ->
        PerformanceMonitor.track_phase(operation_id, :failing_phase, %{}, fn ->
          raise "test error"
        end)
      end

      # Phase should still be recorded even though it failed
      {:ok, metrics} = PerformanceMonitor.get_metrics(operation_id)
      assert length(metrics) == 1
      assert hd(metrics).phase == :failing_phase
    end
  end

  describe "performance metrics" do
    test "calculates duration correctly" do
      operation_id = "test_op_6"
      PerformanceMonitor.start_operation(operation_id)

      PerformanceMonitor.start_phase(operation_id, :timed_phase)
      Process.sleep(50)
      PerformanceMonitor.end_phase(operation_id, :timed_phase)

      {:ok, metrics} = PerformanceMonitor.get_metrics(operation_id)

      metric = hd(metrics)
      assert metric.duration_ms >= 50
      assert metric.duration_ms < 100
    end

    test "tracks memory delta" do
      operation_id = "test_op_7"
      PerformanceMonitor.start_operation(operation_id)

      PerformanceMonitor.start_phase(operation_id, :memory_test)

      # Allocate some memory
      _data = :binary.copy(<<1>>, 1024 * 1024)

      PerformanceMonitor.end_phase(operation_id, :memory_test)

      {:ok, metrics} = PerformanceMonitor.get_metrics(operation_id)

      metric = hd(metrics)
      assert is_integer(metric.memory_before)
      assert is_integer(metric.memory_after)
      assert is_integer(metric.memory_delta)
    end

    test "identifies slowest phase" do
      operation_id = "test_op_8"
      PerformanceMonitor.start_operation(operation_id)

      # Fast phase
      PerformanceMonitor.track_phase(operation_id, :fast, %{}, fn ->
        Process.sleep(5)
      end)

      # Slow phase
      PerformanceMonitor.track_phase(operation_id, :slow, %{}, fn ->
        Process.sleep(50)
      end)

      # Medium phase
      PerformanceMonitor.track_phase(operation_id, :medium, %{}, fn ->
        Process.sleep(20)
      end)

      report = PerformanceMonitor.complete_operation(operation_id)

      assert report.slowest_phase == :slow
    end
  end

  describe "report generation" do
    test "generates complete report" do
      operation_id = "test_op_9"
      PerformanceMonitor.start_operation(operation_id)

      PerformanceMonitor.track_phase(operation_id, :phase1, %{}, fn ->
        Process.sleep(10)
      end)

      PerformanceMonitor.track_phase(operation_id, :phase2, %{}, fn ->
        Process.sleep(10)
      end)

      report = PerformanceMonitor.complete_operation(operation_id, %{files_processed: 42})

      assert report.files_processed == 42
      assert report.total_duration_ms > 0
      assert report.throughput_files_per_sec > 0
      assert length(report.phases) == 2
    end

    test "calculates throughput correctly" do
      operation_id = "test_op_10"
      PerformanceMonitor.start_operation(operation_id)

      PerformanceMonitor.track_phase(operation_id, :process_files, %{}, fn ->
        Process.sleep(100)
      end)

      report = PerformanceMonitor.complete_operation(operation_id, %{files_processed: 10})

      # 10 files in ~100ms = ~100 files/sec
      assert report.throughput_files_per_sec > 50
      assert report.throughput_files_per_sec < 200
    end

    test "formats report as string" do
      operation_id = "test_op_11"
      PerformanceMonitor.start_operation(operation_id)

      PerformanceMonitor.track_phase(operation_id, :merge, %{}, fn ->
        Process.sleep(10)
      end)

      report = PerformanceMonitor.complete_operation(operation_id, %{files_processed: 5})

      formatted = Report.format(report)

      assert is_binary(formatted)
      assert formatted =~ "Performance Report"
      assert formatted =~ "Total Duration:"
      assert formatted =~ "Files Processed: 5"
      assert formatted =~ "merge:"
    end
  end

  describe "concurrent operations" do
    test "tracks multiple operations independently" do
      op1 = "concurrent_op_1"
      op2 = "concurrent_op_2"

      PerformanceMonitor.start_operation(op1)
      PerformanceMonitor.start_operation(op2)

      PerformanceMonitor.track_phase(op1, :op1_phase, %{}, fn ->
        Process.sleep(10)
      end)

      PerformanceMonitor.track_phase(op2, :op2_phase, %{}, fn ->
        Process.sleep(20)
      end)

      report1 = PerformanceMonitor.complete_operation(op1)
      report2 = PerformanceMonitor.complete_operation(op2)

      assert hd(report1.phases).phase == :op1_phase
      assert hd(report2.phases).phase == :op2_phase
      # Check that the operations tracked different phases with different durations
      assert hd(report2.phases).duration_ms >= hd(report1.phases).duration_ms
    end

    test "handles operations from different processes" do
      tasks =
        for i <- 1..5 do
          Task.async(fn ->
            op_id = "parallel_op_#{i}"
            PerformanceMonitor.start_operation(op_id)

            PerformanceMonitor.track_phase(op_id, :work, %{task: i}, fn ->
              Process.sleep(10)
            end)

            PerformanceMonitor.complete_operation(op_id)
          end)
        end

      reports = Enum.map(tasks, &Task.await/1)

      assert length(reports) == 5
      assert Enum.all?(reports, fn report -> report.total_duration_ms > 0 end)
    end
  end

  describe "error handling" do
    test "handles ending a phase that wasn't started" do
      operation_id = "test_op_12"
      PerformanceMonitor.start_operation(operation_id)

      assert {:error, :not_found} =
               PerformanceMonitor.end_phase(operation_id, :nonexistent_phase)
    end

    test "handles getting metrics for non-existent operation" do
      assert {:error, :not_found} = PerformanceMonitor.get_metrics("nonexistent_op")
    end

    test "handles completing non-existent operation" do
      assert {:error, :not_found} = PerformanceMonitor.complete_operation("nonexistent_op")
    end
  end
end
