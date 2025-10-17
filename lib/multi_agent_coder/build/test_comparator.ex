defmodule MultiAgentCoder.Build.TestComparator do
  @moduledoc """
  Compares test results across multiple provider implementations.

  Analyzes and compares:
  - Test pass/fail rates
  - Performance metrics
  - Coverage statistics
  - Common failure patterns
  """

  require Logger

  @type test_result :: map()
  @type provider :: atom()
  @type comparison :: map()

  @doc """
  Compares test results from multiple providers.
  """
  @spec compare(%{provider() => test_result()}) :: comparison()
  def compare(test_results) when is_map(test_results) do
    %{
      summary: generate_summary(test_results),
      performance: compare_performance(test_results),
      coverage: compare_coverage(test_results),
      failures: analyze_failures(test_results),
      consistency: check_consistency(test_results),
      recommendations: generate_recommendations(test_results)
    }
  end

  @doc """
  Identifies common test failures across providers.
  """
  @spec find_common_failures(%{provider() => test_result()}) :: list(map())
  def find_common_failures(test_results) do
    all_failures =
      test_results
      |> Enum.flat_map(fn {provider, result} ->
        case result do
          {:error, %{failures: failures}} ->
            Enum.map(failures, &Map.put(&1, :provider, provider))

          _ ->
            []
        end
      end)

    # Group by failure message/type
    all_failures
    |> Enum.group_by(&failure_signature/1)
    |> Enum.filter(fn {_, failures} -> length(failures) > 1 end)
    |> Enum.map(fn {signature, failures} ->
      %{
        signature: signature,
        providers: Enum.map(failures, & &1.provider) |> Enum.uniq(),
        count: length(failures),
        type: common_failure_type(failures)
      }
    end)
  end

  @doc """
  Calculates test success metrics for each provider.
  """
  @spec calculate_metrics(%{provider() => test_result()}) :: %{provider() => map()}
  def calculate_metrics(test_results) do
    test_results
    |> Enum.map(fn {provider, result} ->
      metrics =
        case result do
          {:ok, %{stats: stats}} ->
            %{
              success_rate: calculate_success_rate(stats),
              total_tests: Map.get(stats, :total, 0),
              passed: Map.get(stats, :passed, 0),
              failed: Map.get(stats, :failed, 0),
              skipped: Map.get(stats, :skipped, 0),
              status: :passed
            }

          {:error, %{failures: failures}} ->
            %{
              success_rate: 0.0,
              total_tests: length(failures),
              passed: 0,
              failed: length(failures),
              skipped: 0,
              status: :failed
            }

          _ ->
            %{
              success_rate: 0.0,
              total_tests: 0,
              passed: 0,
              failed: 0,
              skipped: 0,
              status: :unknown
            }
        end

      {provider, metrics}
    end)
    |> Map.new()
  end

  @doc """
  Ranks providers by test performance.
  """
  @spec rank_providers(%{provider() => test_result()}) :: list({provider(), float()})
  def rank_providers(test_results) do
    metrics = calculate_metrics(test_results)

    metrics
    |> Enum.map(fn {provider, m} ->
      # Calculate composite score
      score =
        m.success_rate * 0.5 +
          if(m.total_tests > 0, do: 30.0, else: 0.0) +
          if m.status == :passed, do: 20.0, else: 0.0

      {provider, score}
    end)
    |> Enum.sort_by(fn {_, score} -> score end, :desc)
  end

  # Private functions

  defp generate_summary(test_results) do
    total_providers = map_size(test_results)
    passed_providers = Enum.count(test_results, fn {_, r} -> match?({:ok, _}, r) end)
    failed_providers = total_providers - passed_providers

    total_tests =
      test_results
      |> Enum.map(fn {_, result} ->
        case result do
          {:ok, %{stats: %{total: total}}} -> total
          {:error, %{failures: failures}} -> length(failures)
          _ -> 0
        end
      end)
      |> Enum.sum()

    %{
      providers: %{
        total: total_providers,
        passed: passed_providers,
        failed: failed_providers
      },
      tests: %{
        total: total_tests,
        average_per_provider: if(total_providers > 0, do: total_tests / total_providers, else: 0)
      },
      overall_health: calculate_overall_health(passed_providers, total_providers)
    }
  end

  defp calculate_overall_health(passed, total) when total > 0 do
    ratio = passed / total

    cond do
      ratio == 1.0 -> :excellent
      ratio >= 0.8 -> :good
      ratio >= 0.5 -> :fair
      true -> :poor
    end
  end

  defp calculate_overall_health(_, _), do: :unknown

  defp compare_performance(test_results) do
    # Extract performance metrics from test outputs
    performance_data =
      test_results
      |> Enum.map(fn {provider, result} ->
        perf = extract_performance_metrics(result)
        {provider, perf}
      end)
      |> Map.new()

    %{
      execution_times: extract_execution_times(performance_data),
      memory_usage: extract_memory_usage(performance_data),
      fastest_provider: find_fastest_provider(performance_data),
      most_efficient: find_most_efficient_provider(performance_data)
    }
  end

  defp extract_performance_metrics({:ok, %{output: output}}) do
    # Parse performance metrics from test output
    %{
      execution_time: parse_execution_time(output),
      memory: parse_memory_usage(output),
      cpu: parse_cpu_usage(output)
    }
  end

  defp extract_performance_metrics(_), do: %{}

  defp parse_execution_time(output) do
    case Regex.run(~r/Finished in (\d+\.?\d*) seconds/, output) do
      [_, time] -> String.to_float(time)
      _ -> nil
    end
  end

  defp parse_memory_usage(output) do
    case Regex.run(~r/Memory: (\d+\.?\d*) MB/, output) do
      [_, mem] -> String.to_float(mem)
      _ -> nil
    end
  end

  defp parse_cpu_usage(output) do
    case Regex.run(~r/CPU: (\d+)%/, output) do
      [_, cpu] -> String.to_integer(cpu)
      _ -> nil
    end
  end

  defp extract_execution_times(performance_data) do
    performance_data
    |> Enum.map(fn {provider, perf} ->
      {provider, Map.get(perf, :execution_time)}
    end)
    |> Enum.reject(fn {_, time} -> is_nil(time) end)
    |> Map.new()
  end

  defp extract_memory_usage(performance_data) do
    performance_data
    |> Enum.map(fn {provider, perf} ->
      {provider, Map.get(perf, :memory)}
    end)
    |> Enum.reject(fn {_, mem} -> is_nil(mem) end)
    |> Map.new()
  end

  defp find_fastest_provider(performance_data) do
    performance_data
    |> Enum.min_by(
      fn {_, perf} -> Map.get(perf, :execution_time, :infinity) end,
      fn -> {nil, %{}} end
    )
    |> elem(0)
  end

  defp find_most_efficient_provider(performance_data) do
    performance_data
    |> Enum.min_by(
      fn {_, perf} -> Map.get(perf, :memory, :infinity) end,
      fn -> {nil, %{}} end
    )
    |> elem(0)
  end

  defp compare_coverage(test_results) do
    coverage_data =
      test_results
      |> Enum.map(fn {provider, result} ->
        coverage = extract_coverage(result)
        {provider, coverage}
      end)
      |> Map.new()

    %{
      by_provider: coverage_data,
      average: calculate_average_coverage(coverage_data),
      best_coverage: find_best_coverage(coverage_data)
    }
  end

  defp extract_coverage({:ok, %{output: output}}) do
    case Regex.run(~r/Coverage: (\d+\.?\d*)%/, output) do
      [_, cov] -> String.to_float(cov)
      _ -> 0.0
    end
  end

  defp extract_coverage(_), do: 0.0

  defp calculate_average_coverage(coverage_data) do
    values = Map.values(coverage_data)

    if Enum.empty?(values) do
      0.0
    else
      Enum.sum(values) / length(values)
    end
  end

  defp find_best_coverage(coverage_data) do
    if map_size(coverage_data) == 0 do
      nil
    else
      coverage_data
      |> Enum.max_by(fn {_, cov} -> cov end)
      |> elem(0)
    end
  end

  defp analyze_failures(test_results) do
    all_failures = extract_all_failures(test_results)
    common_failures = find_common_failures(test_results)

    %{
      total: length(all_failures),
      by_provider: group_failures_by_provider(all_failures),
      common: common_failures,
      patterns: identify_failure_patterns(all_failures)
    }
  end

  defp extract_all_failures(test_results) do
    test_results
    |> Enum.flat_map(fn {provider, result} ->
      case result do
        {:error, %{failures: failures}} ->
          Enum.map(failures, &Map.put(&1, :provider, provider))

        _ ->
          []
      end
    end)
  end

  defp group_failures_by_provider(failures) do
    failures
    |> Enum.group_by(& &1.provider)
    |> Enum.map(fn {provider, provider_failures} ->
      {provider, length(provider_failures)}
    end)
    |> Map.new()
  end

  defp identify_failure_patterns(failures) do
    failures
    |> Enum.map(& &1.type)
    |> Enum.frequencies()
    |> Enum.sort_by(fn {_, count} -> count end, :desc)
    |> Enum.map(fn {type, count} ->
      %{
        type: type,
        count: count,
        percentage: count / length(failures) * 100
      }
    end)
  end

  defp check_consistency(test_results) do
    metrics = calculate_metrics(test_results)

    # Check if all providers have same number of tests
    test_counts =
      metrics
      |> Map.values()
      |> Enum.map(& &1.total_tests)
      |> Enum.uniq()

    # Check if all providers have similar pass rates
    pass_rates =
      metrics
      |> Map.values()
      |> Enum.map(& &1.success_rate)

    variance = calculate_variance(pass_rates)

    %{
      consistent_test_count: length(test_counts) == 1,
      test_count_variance: test_counts,
      success_rate_variance: variance,
      consistency_score: calculate_consistency_score(test_counts, variance)
    }
  end

  defp calculate_variance(values) when length(values) > 1 do
    mean = Enum.sum(values) / length(values)

    variance =
      values
      |> Enum.map(fn x -> :math.pow(x - mean, 2) end)
      |> Enum.sum()
      |> Kernel./(length(values))

    :math.sqrt(variance)
  end

  defp calculate_variance(_), do: 0.0

  defp calculate_consistency_score(test_counts, variance) do
    count_score = if length(test_counts) == 1, do: 50, else: 0
    variance_score = max(0, 50 - variance * 10)
    count_score + variance_score
  end

  defp generate_recommendations(test_results) do
    metrics = calculate_metrics(test_results)
    failures = analyze_failures(test_results)
    consistency = check_consistency(test_results)

    recommendations = []

    # Check for providers with low success rates
    low_performers =
      metrics
      |> Enum.filter(fn {_, m} -> m.success_rate < 70 end)
      |> Enum.map(fn {p, _} -> p end)

    recommendations =
      if not Enum.empty?(low_performers) do
        [
          "Focus on improving test success for: #{Enum.join(low_performers, ", ")}"
          | recommendations
        ]
      else
        recommendations
      end

    # Check for common failures
    recommendations =
      if length(failures.common) > 0 do
        ["Address common failures affecting multiple providers" | recommendations]
      else
        recommendations
      end

    # Check consistency
    recommendations =
      if consistency.consistency_score < 50 do
        ["Improve consistency across provider implementations" | recommendations]
      else
        recommendations
      end

    if Enum.empty?(recommendations) do
      ["All providers show good test performance"]
    else
      recommendations
    end
  end

  defp failure_signature(failure) do
    # Create a signature for grouping similar failures
    {Map.get(failure, :type), normalize_message(Map.get(failure, :message, ""))}
  end

  defp normalize_message(message) do
    # Remove provider-specific details from failure messages
    message
    |> String.replace(~r/\d+/, "N")
    |> String.replace(~r/0x[0-9a-f]+/i, "0xADDR")
    |> String.trim()
  end

  defp common_failure_type(failures) do
    failures
    |> Enum.map(& &1.type)
    |> Enum.frequencies()
    |> Enum.max_by(fn {_, count} -> count end)
    |> elem(0)
  end

  defp calculate_success_rate(%{total: 0}), do: 0.0

  defp calculate_success_rate(%{total: total, passed: passed}) do
    passed / total * 100
  end

  defp calculate_success_rate(_), do: 0.0
end
