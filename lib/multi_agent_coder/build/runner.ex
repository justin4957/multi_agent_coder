defmodule MultiAgentCoder.Build.Runner do
  @moduledoc """
  Orchestrates build and test execution for multiple provider implementations.

  This module handles:
  - Parallel build execution for all providers
  - Test suite execution and result collection
  - Build/test result comparison across providers
  - Feedback loop to providers for improvements
  """

  alias MultiAgentCoder.FileOps.Tracker
  alias MultiAgentCoder.Agent.Worker
  alias MultiAgentCoder.Build.{TestComparator, QualityAnalyzer}

  require Logger

  @type build_result :: {:ok, map()} | {:error, String.t()}
  @type test_result :: {:ok, map()} | {:error, String.t()}
  @type provider :: atom()

  @doc """
  Builds code from all active providers concurrently.
  """
  @spec build_all(keyword()) :: {:ok, %{provider() => build_result()}}
  def build_all(opts \\ []) do
    providers = Keyword.get(opts, :providers, get_active_providers())
    build_cmd = Keyword.get(opts, :build_cmd, default_build_command())

    Logger.info("Starting parallel builds for #{length(providers)} providers")

    build_results =
      providers
      |> Task.async_stream(
        fn provider ->
          {provider, build_provider(provider, build_cmd)}
        end,
        max_concurrency: length(providers),
        timeout: 60_000
      )
      |> Enum.map(fn {:ok, result} -> result end)
      |> Map.new()

    {:ok, build_results}
  end

  @doc """
  Runs tests for all provider implementations concurrently.
  """
  @spec test_all(keyword()) :: {:ok, %{provider() => test_result()}}
  def test_all(opts \\ []) do
    providers = Keyword.get(opts, :providers, get_active_providers())
    test_cmd = Keyword.get(opts, :test_cmd, default_test_command())

    Logger.info("Starting parallel tests for #{length(providers)} providers")

    test_results =
      providers
      |> Task.async_stream(
        fn provider ->
          {provider, test_provider(provider, test_cmd)}
        end,
        max_concurrency: length(providers),
        timeout: 120_000
      )
      |> Enum.map(fn {:ok, result} -> result end)
      |> Map.new()

    {:ok, test_results}
  end

  @doc """
  Compares build and test results across providers.
  """
  @spec compare_results(%{provider() => any()}, %{provider() => any()}) :: {:ok, map()}
  def compare_results(build_results, test_results) do
    comparison = %{
      builds: analyze_build_results(build_results),
      tests: TestComparator.compare(test_results),
      summary: generate_summary(build_results, test_results)
    }

    {:ok, comparison}
  end

  @doc """
  Sends feedback to providers about test failures and suggestions.
  """
  @spec send_feedback_to_providers(map(), keyword()) :: :ok
  def send_feedback_to_providers(test_results, opts \\ []) do
    Enum.each(test_results, fn {provider, result} ->
      case result do
        {:error, failures} ->
          feedback = generate_feedback(provider, failures, opts)
          send_to_provider(provider, feedback)

        _ ->
          :ok
      end
    end)
  end

  @doc """
  Runs quality checks on all provider code.
  """
  @spec run_quality_checks(keyword()) :: {:ok, map()}
  def run_quality_checks(opts \\ []) do
    providers = Keyword.get(opts, :providers, get_active_providers())

    quality_results =
      providers
      |> Enum.map(fn provider ->
        files = Tracker.get_provider_files(provider)
        analysis = QualityAnalyzer.analyze_files(files, opts)
        {provider, analysis}
      end)
      |> Map.new()

    {:ok, quality_results}
  end

  @doc """
  Generates a comprehensive report of all build/test results.
  """
  @spec generate_report(map(), map(), map()) :: String.t()
  def generate_report(build_results, test_results, quality_results) do
    """
    # Multi-Provider Build & Test Report

    ## Build Results
    #{format_build_results(build_results)}

    ## Test Results
    #{format_test_results(test_results)}

    ## Code Quality
    #{format_quality_results(quality_results)}

    ## Recommendations
    #{generate_recommendations(build_results, test_results, quality_results)}
    """
  end

  # Private functions

  defp build_provider(provider, build_cmd) do
    Logger.info("Building #{provider}...")

    # Get provider-specific files
    files = Tracker.get_provider_files(provider)

    if Enum.empty?(files) do
      {:error, "No files to build"}
    else
      # Create a temporary directory for the provider
      tmp_dir = create_temp_dir(provider)

      try do
        # Copy provider files to temp directory
        copy_provider_files(files, tmp_dir)

        # Run build command
        case System.cmd(build_cmd, [], cd: tmp_dir, stderr_to_stdout: true) do
          {output, 0} ->
            {:ok,
             %{
               status: :success,
               output: output,
               files_built: length(files),
               timestamp: DateTime.utc_now()
             }}

          {output, exit_code} ->
            {:error,
             %{
               status: :failed,
               output: output,
               exit_code: exit_code,
               timestamp: DateTime.utc_now()
             }}
        end
      after
        # Cleanup temp directory
        File.rm_rf!(tmp_dir)
      end
    end
  rescue
    error ->
      {:error, "Build failed: #{inspect(error)}"}
  end

  defp test_provider(provider, test_cmd) do
    Logger.info("Testing #{provider}...")

    # Get provider-specific files
    files = Tracker.get_provider_files(provider)

    if Enum.empty?(files) do
      {:error, "No files to test"}
    else
      tmp_dir = create_temp_dir(provider)

      try do
        copy_provider_files(files, tmp_dir)

        # Run test command
        case System.cmd(test_cmd, [], cd: tmp_dir, stderr_to_stdout: true) do
          {output, 0} ->
            # Parse test output
            test_stats = parse_test_output(output)

            {:ok,
             %{
               status: :passed,
               output: output,
               stats: test_stats,
               timestamp: DateTime.utc_now()
             }}

          {output, exit_code} ->
            # Parse failure details
            failures = parse_test_failures(output)

            {:error,
             %{
               status: :failed,
               output: output,
               exit_code: exit_code,
               failures: failures,
               timestamp: DateTime.utc_now()
             }}
        end
      after
        File.rm_rf!(tmp_dir)
      end
    end
  rescue
    error ->
      {:error, "Test execution failed: #{inspect(error)}"}
  end

  defp create_temp_dir(provider) do
    tmp_base = System.tmp_dir!()
    tmp_dir = Path.join(tmp_base, "multi_agent_#{provider}_#{System.unique_integer([:positive])}")
    File.mkdir_p!(tmp_dir)
    tmp_dir
  end

  defp copy_provider_files(files, tmp_dir) do
    Enum.each(files, fn file_path ->
      case Tracker.get_file_content(file_path) do
        {:ok, content} ->
          dest_path = Path.join(tmp_dir, Path.basename(file_path))
          File.write!(dest_path, content)

        _ ->
          :ok
      end
    end)
  end

  defp parse_test_output(output) do
    # Parse test statistics from output
    # This would be customized based on the test framework
    lines = String.split(output, "\n")

    passed = find_stat(lines, ~r/(\d+) (tests?|specs?) passed/)
    failed = find_stat(lines, ~r/(\d+) (tests?|specs?) failed/)
    skipped = find_stat(lines, ~r/(\d+) (tests?|specs?) skipped/)

    %{
      passed: passed,
      failed: failed,
      skipped: skipped,
      total: passed + failed + skipped
    }
  end

  defp find_stat(lines, pattern) do
    Enum.find_value(lines, 0, fn line ->
      case Regex.run(pattern, line) do
        [_, count | _] -> String.to_integer(count)
        _ -> nil
      end
    end)
  end

  defp parse_test_failures(output) do
    # Extract failure details from test output
    lines = String.split(output, "\n")

    lines
    |> Enum.filter(&String.contains?(&1, ["FAIL", "ERROR", "✗"]))
    |> Enum.map(fn line ->
      %{
        message: String.trim(line),
        type: categorize_failure(line)
      }
    end)
  end

  defp categorize_failure(line) do
    cond do
      String.contains?(line, "assertion") -> :assertion
      String.contains?(line, "timeout") -> :timeout
      String.contains?(line, "error") -> :error
      true -> :unknown
    end
  end

  defp analyze_build_results(build_results) do
    successful = Enum.count(build_results, fn {_, r} -> match?({:ok, _}, r) end)
    failed = Enum.count(build_results, fn {_, r} -> match?({:error, _}, r) end)

    %{
      total: map_size(build_results),
      successful: successful,
      failed: failed,
      success_rate:
        if(map_size(build_results) > 0, do: successful / map_size(build_results) * 100, else: 0),
      details: build_results
    }
  end

  defp generate_summary(build_results, test_results) do
    build_success = Enum.count(build_results, fn {_, r} -> match?({:ok, _}, r) end)
    test_success = Enum.count(test_results, fn {_, r} -> match?({:ok, _}, r) end)

    %{
      overall_status:
        determine_overall_status(build_success, test_success, map_size(build_results)),
      builds: %{
        total: map_size(build_results),
        successful: build_success
      },
      tests: %{
        total: map_size(test_results),
        successful: test_success
      },
      timestamp: DateTime.utc_now()
    }
  end

  defp determine_overall_status(build_success, test_success, total) do
    cond do
      build_success == total and test_success == total -> :all_passed
      build_success == 0 or test_success == 0 -> :all_failed
      true -> :partial_success
    end
  end

  defp generate_feedback(provider, failures, opts) do
    include_suggestions = Keyword.get(opts, :include_suggestions, true)

    feedback = %{
      provider: provider,
      timestamp: DateTime.utc_now(),
      failures: failures,
      message: "Your implementation has #{map_size(failures)} test failure(s)."
    }

    if include_suggestions do
      Map.put(feedback, :suggestions, generate_suggestions(failures))
    else
      feedback
    end
  end

  defp generate_suggestions(failures) do
    failures
    |> Map.get(:failures, [])
    |> Enum.map(fn failure ->
      case failure.type do
        :assertion ->
          "Review assertion at: #{failure.message}. Check expected vs actual values."

        :timeout ->
          "Timeout occurred. Consider optimizing performance or increasing timeout."

        :error ->
          "Runtime error: #{failure.message}. Check for nil values or missing dependencies."

        _ ->
          "Test failure: #{failure.message}"
      end
    end)
  end

  defp send_to_provider(provider, feedback) do
    # Send feedback to the provider
    # This could trigger a re-generation or improvement cycle
    Logger.info("Sending feedback to #{provider}: #{inspect(feedback)}")

    # In a real implementation, this would communicate with the agent
    Worker.send_feedback(provider, feedback)
  end

  defp get_active_providers do
    Tracker.list_providers()
  end

  defp default_build_command do
    case File.exists?("mix.exs") do
      true -> "mix"
      false -> "make"
    end
  end

  defp default_test_command do
    case File.exists?("mix.exs") do
      true -> "mix test"
      false -> "make test"
    end
  end

  defp format_build_results(results) do
    results
    |> Enum.map(fn {provider, result} ->
      status = if match?({:ok, _}, result), do: "✓", else: "✗"
      "- #{provider}: #{status}"
    end)
    |> Enum.join("\n")
  end

  defp format_test_results(results) do
    results
    |> Enum.map(fn {provider, result} ->
      case result do
        {:ok, data} ->
          "- #{provider}: ✓ (#{data.stats.passed}/#{data.stats.total} passed)"

        {:error, data} ->
          "- #{provider}: ✗ (#{length(data.failures)} failures)"
      end
    end)
    |> Enum.join("\n")
  end

  defp format_quality_results(results) do
    results
    |> Enum.map(fn {provider, analysis} ->
      score = Map.get(analysis, :score, 0)
      "- #{provider}: Score #{score}/100"
    end)
    |> Enum.join("\n")
  end

  defp generate_recommendations(build_results, test_results, quality_results) do
    recommendations = []

    # Check for consistent failures
    failed_builds =
      build_results
      |> Enum.filter(fn {_, r} -> match?({:error, _}, r) end)
      |> Enum.map(fn {p, _} -> p end)

    failed_tests =
      test_results
      |> Enum.filter(fn {_, r} -> match?({:error, _}, r) end)
      |> Enum.map(fn {p, _} -> p end)

    recommendations =
      if not Enum.empty?(failed_builds) do
        ["- Fix build issues for: #{Enum.join(failed_builds, ", ")}" | recommendations]
      else
        recommendations
      end

    recommendations =
      if not Enum.empty?(failed_tests) do
        ["- Address test failures for: #{Enum.join(failed_tests, ", ")}" | recommendations]
      else
        recommendations
      end

    # Check quality scores
    low_quality =
      quality_results
      |> Enum.filter(fn {_, a} -> Map.get(a, :score, 100) < 70 end)
      |> Enum.map(fn {p, _} -> p end)

    recommendations =
      if not Enum.empty?(low_quality) do
        ["- Improve code quality for: #{Enum.join(low_quality, ", ")}" | recommendations]
      else
        recommendations
      end

    if Enum.empty?(recommendations) do
      "All providers are performing well!"
    else
      Enum.join(recommendations, "\n")
    end
  end
end
