defmodule MultiAgentCoder.Test.Runner do
  @moduledoc """
  Runs tests for provider-generated code.

  Executes test suites concurrently for multiple providers,
  monitors progress, and captures detailed results.
  """

  require Logger

  @type test_result :: %{
          provider: atom(),
          passed: boolean(),
          total: integer(),
          passed_count: integer(),
          failed_count: integer(),
          failures: list(test_failure()),
          duration: integer(),
          coverage: float() | nil,
          output: String.t(),
          timestamp: DateTime.t()
        }

  @type test_failure :: %{
          test_name: String.t(),
          error_message: String.t(),
          location: String.t()
        }

  @doc """
  Runs tests for a specific provider's code.

  ## Parameters
    - provider: Provider name
    - project_dir: Directory containing the code
    - opts: Options
      - `:language` - Programming language (default: :elixir)
      - `:broadcast` - Broadcast progress (default: true)
      - `:coverage` - Enable coverage (default: false)

  ## Returns
    `{:ok, test_result}` or `{:error, reason}`
  """
  def run_tests(provider, project_dir, opts \\ []) do
    language = Keyword.get(opts, :language, :elixir)
    broadcast = Keyword.get(opts, :broadcast, true)
    coverage = Keyword.get(opts, :coverage, false)

    Logger.info("#{provider}: Running tests...")

    if broadcast do
      broadcast_event(provider, :test_started, %{project_dir: project_dir})
    end

    start_time = System.monotonic_time(:millisecond)

    result =
      case language do
        :elixir -> run_elixir_tests(provider, project_dir, broadcast, coverage)
        :python -> run_python_tests(provider, project_dir, broadcast)
        :javascript -> run_javascript_tests(provider, project_dir, broadcast)
        _ -> {:error, :unsupported_language}
      end

    duration = System.monotonic_time(:millisecond) - start_time

    case result do
      {:ok, test_data} ->
        test_result = Map.put(test_data, :duration, duration)

        if broadcast do
          broadcast_event(provider, :test_completed, test_result)
        end

        {:ok, test_result}

      {:error, _reason} = error ->
        if broadcast do
          broadcast_event(provider, :test_failed, %{duration: duration})
        end

        error
    end
  end

  @doc """
  Runs tests for multiple providers concurrently.
  """
  def run_concurrent_tests(providers_and_dirs, opts \\ []) do
    tasks =
      Enum.map(providers_and_dirs, fn {provider, project_dir} ->
        Task.async(fn ->
          {provider, run_tests(provider, project_dir, opts)}
        end)
      end)

    results = Task.await_many(tasks, 180_000)
    Map.new(results)
  end

  @doc """
  Gets a summary of test results.
  """
  def summarize_tests(test_result) do
    pass_rate =
      if test_result.total > 0 do
        test_result.passed_count / test_result.total * 100
      else
        0
      end

    %{
      passed: test_result.passed,
      total: test_result.total,
      passed_count: test_result.passed_count,
      failed_count: test_result.failed_count,
      pass_rate: Float.round(pass_rate, 1),
      duration_ms: test_result.duration,
      coverage: test_result.coverage,
      score: calculate_test_score(test_result)
    }
  end

  # Private Functions - Elixir Tests

  defp run_elixir_tests(provider, project_dir, broadcast, coverage) do
    Logger.info("#{provider}: Running ExUnit tests...")

    if broadcast do
      broadcast_event(provider, :test_progress, %{step: "Running ExUnit tests..."})
    end

    cmd = if coverage, do: ["test", "--cover"], else: ["test"]

    result =
      System.cmd("mix", cmd,
        cd: project_dir,
        stderr_to_stdout: true
      )

    case result do
      {output, 0} ->
        test_stats = parse_elixir_test_output(output)
        coverage_pct = if coverage, do: parse_elixir_coverage(output), else: nil

        if broadcast and test_stats.total > 0 do
          broadcast_event(provider, :test_progress, %{
            passed: test_stats.total - test_stats.failures,
            total: test_stats.total
          })
        end

        {:ok,
         %{
           provider: provider,
           passed: true,
           total: test_stats.total,
           passed_count: test_stats.total - test_stats.failures,
           failed_count: test_stats.failures,
           failures: [],
           coverage: coverage_pct,
           output: output,
           timestamp: DateTime.utc_now()
         }}

      {output, _exit_code} ->
        test_stats = parse_elixir_test_output(output)
        failures = extract_elixir_test_failures(output)
        coverage_pct = if coverage, do: parse_elixir_coverage(output), else: nil

        if broadcast do
          broadcast_event(provider, :test_failures, %{
            count: length(failures),
            failures: failures
          })
        end

        {:ok,
         %{
           provider: provider,
           passed: false,
           total: test_stats.total,
           passed_count: test_stats.total - test_stats.failures,
           failed_count: test_stats.failures,
           failures: failures,
           coverage: coverage_pct,
           output: output,
           timestamp: DateTime.utc_now()
         }}
    end
  rescue
    error ->
      Logger.error("#{provider}: Test execution failed - #{Exception.message(error)}")
      {:error, {:test_failed, Exception.message(error)}}
  end

  # Private Functions - Python Tests

  defp run_python_tests(provider, project_dir, broadcast) do
    Logger.info("#{provider}: Running pytest...")

    if broadcast do
      broadcast_event(provider, :test_progress, %{step: "Running pytest..."})
    end

    result =
      System.cmd("pytest", ["-v", "--tb=short"],
        cd: project_dir,
        stderr_to_stdout: true
      )

    case result do
      {output, 0} ->
        {:ok,
         %{
           provider: provider,
           passed: true,
           total: count_pytest_tests(output),
           passed_count: count_pytest_tests(output),
           failed_count: 0,
           failures: [],
           coverage: nil,
           output: output,
           timestamp: DateTime.utc_now()
         }}

      {output, _} ->
        total = count_pytest_tests(output)
        failures = extract_pytest_failures(output)

        {:ok,
         %{
           provider: provider,
           passed: false,
           total: total,
           passed_count: total - length(failures),
           failed_count: length(failures),
           failures: failures,
           coverage: nil,
           output: output,
           timestamp: DateTime.utc_now()
         }}
    end
  rescue
    _ ->
      {:error, :pytest_not_available}
  end

  # Private Functions - JavaScript Tests

  defp run_javascript_tests(provider, project_dir, broadcast) do
    Logger.info("#{provider}: Running npm test...")

    if broadcast do
      broadcast_event(provider, :test_progress, %{step: "Running npm test..."})
    end

    result =
      System.cmd("npm", ["test"],
        cd: project_dir,
        stderr_to_stdout: true
      )

    case result do
      {output, 0} ->
        {:ok,
         %{
           provider: provider,
           passed: true,
           total: 1,
           passed_count: 1,
           failed_count: 0,
           failures: [],
           coverage: nil,
           output: output,
           timestamp: DateTime.utc_now()
         }}

      {output, _} ->
        {:ok,
         %{
           provider: provider,
           passed: false,
           total: 1,
           passed_count: 0,
           failed_count: 1,
           failures: [%{test_name: "npm test", error_message: output, location: ""}],
           coverage: nil,
           output: output,
           timestamp: DateTime.utc_now()
         }}
    end
  rescue
    _ ->
      {:error, :npm_not_available}
  end

  # Helper Functions

  defp parse_elixir_test_output(output) do
    case Regex.run(~r/(\d+) tests?, (\d+) failures?/, output) do
      [_, total, failures] ->
        %{total: String.to_integer(total), failures: String.to_integer(failures)}

      _ ->
        %{total: 0, failures: 0}
    end
  end

  defp extract_elixir_test_failures(output) do
    Regex.scan(~r/\d+\) (.+?)\n\s+(.+?:\d+)/s, output)
    |> Enum.map(fn [_, test_name, location] ->
      error = extract_failure_message(output, test_name)

      %{
        test_name: String.trim(test_name),
        location: String.trim(location),
        error_message: error
      }
    end)
  end

  defp extract_failure_message(output, test_name) do
    # Try to extract the assertion error or exception message
    case Regex.run(~r/#{Regex.escape(test_name)}.*?\n\s+(.+?)(?:\n\n|\z)/s, output) do
      [_, message] -> String.trim(message)
      _ -> "Test failed"
    end
  end

  defp parse_elixir_coverage(output) do
    case Regex.run(~r/(\d+\.\d+)%/, output) do
      [_, percentage] -> String.to_float(percentage)
      _ -> nil
    end
  end

  defp count_pytest_tests(output) do
    Regex.scan(~r/test_.+? PASSED|test_.+? FAILED/, output) |> length()
  end

  defp extract_pytest_failures(output) do
    Regex.scan(~r/(test_.+?) FAILED/, output)
    |> Enum.map(fn [_, test_name] ->
      %{
        test_name: test_name,
        error_message: "Test failed",
        location: ""
      }
    end)
  end

  defp calculate_test_score(test_result) do
    if test_result.total == 0 do
      0
    else
      pass_rate = test_result.passed_count / test_result.total

      base_score = round(pass_rate * 60)

      coverage_bonus =
        if test_result.coverage do
          round(test_result.coverage / 100 * 20)
        else
          0
        end

      base_score + coverage_bonus
    end
  end

  defp broadcast_event(provider, event_type, data) do
    Phoenix.PubSub.broadcast(
      MultiAgentCoder.PubSub,
      "test:#{provider}",
      {:test_event, event_type, data}
    )
  end
end
