defmodule MultiAgentCoder.Monitor.ProgressCalculator do
  @moduledoc """
  Calculates task progress and completion percentages.

  Provides utilities for estimating progress based on various metrics:
  - Time elapsed vs estimated time
  - Subtasks completed
  - Lines of code generated
  - File operations completed

  ## Examples

      iex> alias MultiAgentCoder.Monitor.ProgressCalculator
      iex> ProgressCalculator.calculate_progress(
      ...>   total_subtasks: 10,
      ...>   completed_subtasks: 7
      ...> )
      %{percentage: 70.0, status: :in_progress, estimated_remaining_ms: nil}
  """

  @type progress_result :: %{
          percentage: float(),
          status: :not_started | :in_progress | :completed | :error,
          estimated_remaining_ms: integer() | nil
        }

  @doc """
  Calculates progress percentage based on completed vs total subtasks.
  """
  @spec calculate_progress(keyword()) :: progress_result()
  def calculate_progress(opts) do
    completed = Keyword.get(opts, :completed_subtasks, 0)
    total = Keyword.get(opts, :total_subtasks, 1)

    percentage = if total > 0, do: completed / total * 100.0, else: 0.0

    status = determine_status(percentage, opts)

    estimated_remaining =
      if Keyword.has_key?(opts, :elapsed_ms) and percentage > 0 do
        calculate_estimated_remaining(
          Keyword.get(opts, :elapsed_ms),
          percentage
        )
      end

    %{
      percentage: percentage,
      status: status,
      estimated_remaining_ms: estimated_remaining
    }
  end

  @doc """
  Calculates progress based on time elapsed vs estimated total time.
  """
  @spec calculate_time_based_progress(integer(), integer()) :: progress_result()
  def calculate_time_based_progress(elapsed_ms, estimated_total_ms)
      when estimated_total_ms > 0 do
    percentage = min(elapsed_ms / estimated_total_ms * 100.0, 100.0)
    remaining = max(estimated_total_ms - elapsed_ms, 0)

    %{
      percentage: percentage,
      status: determine_status(percentage, []),
      estimated_remaining_ms: remaining
    }
  end

  def calculate_time_based_progress(_elapsed_ms, _estimated_total_ms) do
    %{
      percentage: 0.0,
      status: :not_started,
      estimated_remaining_ms: nil
    }
  end

  @doc """
  Calculates overall progress across multiple providers.
  """
  @spec calculate_overall_progress(list(progress_result())) :: progress_result()
  def calculate_overall_progress([]),
    do: %{percentage: 0.0, status: :not_started, estimated_remaining_ms: nil}

  def calculate_overall_progress(progress_results) when is_list(progress_results) do
    total_percentage =
      progress_results
      |> Enum.map(& &1.percentage)
      |> Enum.sum()

    average_percentage = total_percentage / length(progress_results)

    # Determine overall status
    statuses = Enum.map(progress_results, & &1.status)

    overall_status =
      cond do
        Enum.any?(statuses, &(&1 == :error)) -> :error
        Enum.all?(statuses, &(&1 == :completed)) -> :completed
        Enum.any?(statuses, &(&1 == :in_progress)) -> :in_progress
        true -> :not_started
      end

    # Calculate estimated remaining (max of all providers)
    estimated_remaining =
      progress_results
      |> Enum.map(& &1.estimated_remaining_ms)
      |> Enum.reject(&is_nil/1)
      |> case do
        [] -> nil
        times -> Enum.max(times)
      end

    %{
      percentage: average_percentage,
      status: overall_status,
      estimated_remaining_ms: estimated_remaining
    }
  end

  @doc """
  Formats progress as a visual progress bar.
  """
  @spec format_progress_bar(float(), integer()) :: String.t()
  def format_progress_bar(percentage, width \\ 20) do
    filled = round(percentage / 100 * width)
    empty = width - filled

    "[" <>
      String.duplicate("█", filled) <>
      String.duplicate("░", empty) <>
      "] #{:erlang.float_to_binary(percentage, decimals: 1)}%"
  end

  @doc """
  Formats estimated remaining time in human-readable format.
  """
  @spec format_estimated_remaining(integer() | nil) :: String.t()
  def format_estimated_remaining(nil), do: "unknown"
  def format_estimated_remaining(ms) when ms < 1000, do: "< 1s"

  def format_estimated_remaining(ms) when ms < 60_000 do
    "~#{div(ms, 1000)}s"
  end

  def format_estimated_remaining(ms) when ms < 3_600_000 do
    minutes = div(ms, 60_000)
    seconds = div(rem(ms, 60_000), 1000)
    "~#{minutes}m #{seconds}s"
  end

  def format_estimated_remaining(ms) do
    hours = div(ms, 3_600_000)
    minutes = div(rem(ms, 3_600_000), 60_000)
    "~#{hours}h #{minutes}m"
  end

  @doc """
  Calculates progress based on lines of code generated vs target.
  """
  @spec calculate_lines_progress(integer(), integer()) :: progress_result()
  def calculate_lines_progress(current_lines, target_lines) when target_lines > 0 do
    percentage = min(current_lines / target_lines * 100.0, 100.0)

    %{
      percentage: percentage,
      status: determine_status(percentage, []),
      estimated_remaining_ms: nil
    }
  end

  def calculate_lines_progress(_current_lines, _target_lines) do
    %{
      percentage: 0.0,
      status: :not_started,
      estimated_remaining_ms: nil
    }
  end

  # Private Functions

  defp determine_status(percentage, opts) do
    has_error = Keyword.get(opts, :has_error, false)

    cond do
      has_error -> :error
      percentage >= 100.0 -> :completed
      percentage > 0.0 -> :in_progress
      true -> :not_started
    end
  end

  defp calculate_estimated_remaining(elapsed_ms, percentage) when percentage > 0 do
    total_estimated = elapsed_ms / (percentage / 100.0)
    remaining = total_estimated - elapsed_ms
    round(remaining)
  end
end
