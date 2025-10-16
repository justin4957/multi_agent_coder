defmodule MultiAgentCoder.Monitor.ProgressCalculatorTest do
  use ExUnit.Case, async: true
  doctest MultiAgentCoder.Monitor.ProgressCalculator

  alias MultiAgentCoder.Monitor.ProgressCalculator

  describe "calculate_progress/1" do
    test "calculates progress from subtasks" do
      result =
        ProgressCalculator.calculate_progress(
          total_subtasks: 10,
          completed_subtasks: 7
        )

      assert result.percentage == 70.0
      assert result.status == :in_progress
    end

    test "returns 0% for no completed subtasks" do
      result =
        ProgressCalculator.calculate_progress(
          total_subtasks: 10,
          completed_subtasks: 0
        )

      assert result.percentage == 0.0
      assert result.status == :not_started
    end

    test "returns 100% when all subtasks completed" do
      result =
        ProgressCalculator.calculate_progress(
          total_subtasks: 5,
          completed_subtasks: 5
        )

      assert result.percentage == 100.0
      assert result.status == :completed
    end

    test "calculates estimated remaining time" do
      result =
        ProgressCalculator.calculate_progress(
          total_subtasks: 10,
          completed_subtasks: 5,
          elapsed_ms: 5000
        )

      assert result.percentage == 50.0
      # If 50% took 5000ms, remaining 50% should take ~5000ms
      assert result.estimated_remaining_ms == 5000
    end

    test "sets error status when has_error flag is true" do
      result =
        ProgressCalculator.calculate_progress(
          total_subtasks: 10,
          completed_subtasks: 7,
          has_error: true
        )

      assert result.status == :error
    end
  end

  describe "calculate_time_based_progress/2" do
    test "calculates progress from elapsed time" do
      result = ProgressCalculator.calculate_time_based_progress(3000, 10000)

      assert result.percentage == 30.0
      assert result.estimated_remaining_ms == 7000
    end

    test "caps percentage at 100%" do
      result = ProgressCalculator.calculate_time_based_progress(12000, 10000)

      assert result.percentage == 100.0
    end

    test "returns 0% for invalid total time" do
      result = ProgressCalculator.calculate_time_based_progress(5000, 0)

      assert result.percentage == 0.0
      assert result.status == :not_started
    end

    test "calculates remaining time correctly" do
      result = ProgressCalculator.calculate_time_based_progress(7500, 10000)

      assert result.estimated_remaining_ms == 2500
    end

    test "returns 0 remaining when elapsed exceeds estimated" do
      result = ProgressCalculator.calculate_time_based_progress(12000, 10000)

      assert result.estimated_remaining_ms == 0
    end
  end

  describe "calculate_overall_progress/1" do
    test "calculates average progress from multiple providers" do
      results = [
        %{percentage: 50.0, status: :in_progress, estimated_remaining_ms: 1000},
        %{percentage: 75.0, status: :in_progress, estimated_remaining_ms: 500},
        %{percentage: 25.0, status: :in_progress, estimated_remaining_ms: 2000}
      ]

      overall = ProgressCalculator.calculate_overall_progress(results)

      assert overall.percentage == 50.0
      assert overall.status == :in_progress
      # max of all providers
      assert overall.estimated_remaining_ms == 2000
    end

    test "returns completed status when all providers complete" do
      results = [
        %{percentage: 100.0, status: :completed, estimated_remaining_ms: nil},
        %{percentage: 100.0, status: :completed, estimated_remaining_ms: nil}
      ]

      overall = ProgressCalculator.calculate_overall_progress(results)

      assert overall.status == :completed
    end

    test "returns error status if any provider has error" do
      results = [
        %{percentage: 50.0, status: :in_progress, estimated_remaining_ms: 1000},
        %{percentage: 30.0, status: :error, estimated_remaining_ms: nil}
      ]

      overall = ProgressCalculator.calculate_overall_progress(results)

      assert overall.status == :error
    end

    test "returns not_started for empty list" do
      overall = ProgressCalculator.calculate_overall_progress([])

      assert overall.percentage == 0.0
      assert overall.status == :not_started
    end
  end

  describe "format_progress_bar/2" do
    test "formats progress bar with default width" do
      bar = ProgressCalculator.format_progress_bar(50.0)

      assert String.contains?(bar, "█")
      assert String.contains?(bar, "░")
      assert String.contains?(bar, "50.0%")
    end

    test "formats progress bar with custom width" do
      bar = ProgressCalculator.format_progress_bar(50.0, 10)

      # 50% of 10 = 5 filled, 5 empty
      assert bar == "[█████░░░░░] 50.0%"
    end

    test "formats 0% progress" do
      bar = ProgressCalculator.format_progress_bar(0.0, 10)

      assert bar == "[░░░░░░░░░░] 0.0%"
    end

    test "formats 100% progress" do
      bar = ProgressCalculator.format_progress_bar(100.0, 10)

      assert bar == "[██████████] 100.0%"
    end
  end

  describe "format_estimated_remaining/1" do
    test "formats nil as unknown" do
      assert ProgressCalculator.format_estimated_remaining(nil) == "unknown"
    end

    test "formats milliseconds less than 1 second" do
      assert ProgressCalculator.format_estimated_remaining(500) == "< 1s"
    end

    test "formats seconds" do
      assert ProgressCalculator.format_estimated_remaining(5000) == "~5s"
    end

    test "formats minutes and seconds" do
      assert ProgressCalculator.format_estimated_remaining(125_000) == "~2m 5s"
    end

    test "formats hours and minutes" do
      assert ProgressCalculator.format_estimated_remaining(7_325_000) == "~2h 2m"
    end
  end

  describe "calculate_lines_progress/2" do
    test "calculates progress from lines generated" do
      result = ProgressCalculator.calculate_lines_progress(150, 300)

      assert result.percentage == 50.0
      assert result.status == :in_progress
    end

    test "caps progress at 100%" do
      result = ProgressCalculator.calculate_lines_progress(350, 300)

      assert result.percentage == 100.0
    end

    test "returns 0% for invalid target" do
      result = ProgressCalculator.calculate_lines_progress(100, 0)

      assert result.percentage == 0.0
      assert result.status == :not_started
    end

    test "returns completed status at 100%" do
      result = ProgressCalculator.calculate_lines_progress(300, 300)

      assert result.percentage == 100.0
      assert result.status == :completed
    end
  end
end
