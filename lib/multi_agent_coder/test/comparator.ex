defmodule MultiAgentCoder.Test.Comparator do
  @moduledoc """
  Compares test results across multiple providers.

  Analyzes and ranks provider code based on test pass rates,
  code quality, and other metrics.
  """

  require Logger

  alias MultiAgentCoder.Build.Monitor
  alias MultiAgentCoder.Quality.Checker
  alias MultiAgentCoder.Test.Runner

  @type comparison_result :: %{
          rankings: list(provider_ranking()),
          best_provider: atom(),
          summary: map(),
          recommendations: list(String.t())
        }

  @type provider_ranking :: %{
          provider: atom(),
          rank: integer(),
          overall_score: integer(),
          build_score: integer(),
          test_score: integer(),
          quality_score: integer(),
          metrics: map()
        }

  @doc """
  Compares build and test results across providers.

  ## Parameters
    - build_results: Map of provider => build_result
    - test_results: Map of provider => test_result
    - quality_results: Map of provider => quality_result (optional)

  ## Returns
    comparison_result with rankings and recommendations
  """
  def compare_results(build_results, test_results, quality_results \\ %{}) do
    provider_scores =
      build_results
      |> Map.keys()
      |> Enum.map(fn provider ->
        calculate_provider_score(
          provider,
          build_results[provider],
          test_results[provider],
          quality_results[provider]
        )
      end)
      |> Enum.sort_by(& &1.overall_score, :desc)
      |> Enum.with_index(1)
      |> Enum.map(fn {score, rank} -> Map.put(score, :rank, rank) end)

    best_provider = List.first(provider_scores).provider

    %{
      rankings: provider_scores,
      best_provider: best_provider,
      summary: generate_summary(provider_scores),
      recommendations: generate_recommendations(provider_scores, test_results)
    }
  end

  @doc """
  Formats comparison results for display.
  """
  def format_comparison(comparison) do
    lines = [
      "\n" <> IO.ANSI.cyan() <> "═══ Provider Comparison ═══" <> IO.ANSI.reset(),
      ""
    ]

    ranking_lines =
      Enum.flat_map(comparison.rankings, fn ranking ->
        format_provider_ranking(ranking)
      end)

    summary_lines = [
      "",
      IO.ANSI.cyan() <> "Summary:" <> IO.ANSI.reset(),
      "  Best Code: #{format_provider_name(comparison.best_provider)} " <>
        "(#{get_score(comparison.rankings, comparison.best_provider)}/100)",
      ""
    ]

    recommendation_lines =
      if length(comparison.recommendations) > 0 do
        [
          IO.ANSI.cyan() <> "Recommendations:" <> IO.ANSI.reset()
        ] ++ Enum.map(comparison.recommendations, &"  • #{&1}")
      else
        []
      end

    (lines ++ ranking_lines ++ summary_lines ++ recommendation_lines)
    |> Enum.join("\n")
  end

  @doc """
  Generates a side-by-side comparison table.
  """
  def generate_comparison_table(build_results, test_results) do
    providers = Map.keys(build_results)

    headers = ["Metric" | Enum.map(providers, &format_provider_name/1)]

    rows = [
      build_status_row(providers, build_results),
      warnings_row(providers, build_results),
      tests_total_row(providers, test_results),
      tests_passed_row(providers, test_results),
      pass_rate_row(providers, test_results),
      coverage_row(providers, test_results)
    ]

    format_table(headers, rows)
  end

  # Private Functions

  defp calculate_provider_score(provider, build_result, test_result, quality_result) do
    build_summary = if build_result, do: Monitor.summarize_build(build_result), else: %{score: 0}

    test_summary = if test_result, do: Runner.summarize_tests(test_result), else: %{score: 0}

    quality_summary =
      if quality_result, do: Checker.summarize_quality(quality_result), else: %{score: 0}

    # Weight: Build 30%, Tests 40%, Quality 30%
    overall_score =
      round(
        build_summary.score * 0.3 +
          test_summary.score * 0.4 +
          quality_summary.score * 0.3
      )

    %{
      provider: provider,
      overall_score: overall_score,
      build_score: build_summary.score,
      test_score: test_summary.score,
      quality_score: quality_summary.score,
      metrics: %{
        build_success: build_result && build_result.success,
        test_pass_rate:
          test_result && test_result.total > 0 &&
            test_result.passed_count / test_result.total * 100,
        warnings: build_result && length(build_result.warnings || []),
        test_failures: test_result && test_result.failed_count,
        coverage: test_result && test_result.coverage
      }
    }
  end

  defp generate_summary(provider_scores) do
    total_providers = length(provider_scores)
    passing_builds = Enum.count(provider_scores, & &1.metrics.build_success)

    passing_tests =
      Enum.count(provider_scores, fn score ->
        score.metrics.test_pass_rate && score.metrics.test_pass_rate == 100.0
      end)

    avg_score =
      if total_providers > 0 do
        Enum.sum(Enum.map(provider_scores, & &1.overall_score)) / total_providers
      else
        0
      end

    %{
      total_providers: total_providers,
      passing_builds: passing_builds,
      passing_all_tests: passing_tests,
      average_score: Float.round(avg_score, 1)
    }
  end

  defp generate_recommendations(provider_scores, test_results) do
    recommendations = []

    # Best provider recommendation
    best = List.first(provider_scores)

    recommendations =
      if best && best.overall_score >= 90 do
        [
          "Accept #{format_provider_name(best.provider)}'s code - excellent quality (#{best.overall_score}/100)"
          | recommendations
        ]
      else
        recommendations
      end

    # Find providers with failing tests
    failing_providers =
      Enum.filter(provider_scores, fn score ->
        score.metrics.test_failures && score.metrics.test_failures > 0
      end)

    recommendations =
      if length(failing_providers) > 0 do
        Enum.reduce(failing_providers, recommendations, fn score, acc ->
          test_result = test_results[score.provider]

          if test_result && length(test_result.failures) > 0 do
            [
              "Send test failures to #{format_provider_name(score.provider)} for fixes (#{score.metrics.test_failures} failing)"
              | acc
            ]
          else
            acc
          end
        end)
      else
        recommendations
      end

    # Suggest merge if multiple providers have good code
    good_providers =
      Enum.filter(provider_scores, fn score ->
        score.overall_score >= 75 && score.metrics.build_success
      end)

    recommendations =
      if length(good_providers) > 1 do
        names = Enum.map(good_providers, &format_provider_name(&1.provider)) |> Enum.join(" and ")
        ["Consider merging best features from #{names}" | recommendations]
      else
        recommendations
      end

    Enum.reverse(recommendations)
  end

  defp format_provider_ranking(ranking) do
    rank_marker =
      case ranking.rank do
        1 -> IO.ANSI.green() <> "🥇 #1" <> IO.ANSI.reset()
        2 -> IO.ANSI.yellow() <> "🥈 #2" <> IO.ANSI.reset()
        3 -> IO.ANSI.light_black() <> "🥉 #3" <> IO.ANSI.reset()
        n -> "   ##{n}"
      end

    [
      "#{rank_marker} #{format_provider_name(ranking.provider)} - #{ranking.overall_score}/100",
      "    Build: #{ranking.build_score}/100 | Tests: #{ranking.test_score}/100 | Quality: #{ranking.quality_score}/100",
      "    #{format_metrics(ranking.metrics)}",
      ""
    ]
  end

  defp format_metrics(metrics) do
    parts = []

    parts =
      if metrics.build_success do
        [IO.ANSI.green() <> "✓ Build passed" <> IO.ANSI.reset() | parts]
      else
        [IO.ANSI.red() <> "✗ Build failed" <> IO.ANSI.reset() | parts]
      end

    parts =
      if metrics.test_pass_rate do
        color = if metrics.test_pass_rate == 100.0, do: IO.ANSI.green(), else: IO.ANSI.yellow()

        [
          color <>
            "#{Float.round(metrics.test_pass_rate, 1)}% tests passing" <> IO.ANSI.reset()
          | parts
        ]
      else
        parts
      end

    parts =
      if metrics.warnings && metrics.warnings > 0 do
        [IO.ANSI.yellow() <> "#{metrics.warnings} warnings" <> IO.ANSI.reset() | parts]
      else
        parts
      end

    parts =
      if metrics.coverage do
        [IO.ANSI.cyan() <> "#{metrics.coverage}% coverage" <> IO.ANSI.reset() | parts]
      else
        parts
      end

    Enum.reverse(parts) |> Enum.join(" | ")
  end

  defp format_provider_name(provider) do
    provider
    |> to_string()
    |> String.capitalize()
  end

  defp get_score(rankings, provider) do
    ranking = Enum.find(rankings, &(&1.provider == provider))
    if ranking, do: ranking.overall_score, else: 0
  end

  # Table formatting helpers

  defp build_status_row(providers, build_results) do
    [
      "Build Status"
      | Enum.map(providers, fn p ->
          if build_results[p] && build_results[p].success, do: "✓ Pass", else: "✗ Fail"
        end)
    ]
  end

  defp warnings_row(providers, build_results) do
    [
      "Warnings"
      | Enum.map(providers, fn p ->
          count = if build_results[p], do: length(build_results[p].warnings || []), else: 0
          "#{count}"
        end)
    ]
  end

  defp tests_total_row(providers, test_results) do
    ["Tests Total" | Enum.map(providers, fn p -> "#{test_results[p].total}" end)]
  end

  defp tests_passed_row(providers, test_results) do
    ["Tests Passed" | Enum.map(providers, fn p -> "#{test_results[p].passed_count}" end)]
  end

  defp pass_rate_row(providers, test_results) do
    [
      "Pass Rate"
      | Enum.map(providers, fn p ->
          if test_results[p].total > 0 do
            rate = test_results[p].passed_count / test_results[p].total * 100
            "#{Float.round(rate, 1)}%"
          else
            "N/A"
          end
        end)
    ]
  end

  defp coverage_row(providers, test_results) do
    [
      "Coverage"
      | Enum.map(providers, fn p ->
          if test_results[p].coverage, do: "#{test_results[p].coverage}%", else: "N/A"
        end)
    ]
  end

  defp format_table(headers, rows) do
    col_widths = calculate_column_widths([headers | rows])

    header_line = format_row(headers, col_widths)
    separator = format_separator(col_widths)
    data_lines = Enum.map(rows, &format_row(&1, col_widths))

    [header_line, separator | data_lines]
    |> Enum.join("\n")
  end

  defp calculate_column_widths(rows) do
    rows
    |> Enum.zip()
    |> Enum.map(fn column_tuple ->
      column_tuple
      |> Tuple.to_list()
      |> Enum.map(&String.length/1)
      |> Enum.max()
    end)
  end

  defp format_row(cells, widths) do
    cells
    |> Enum.zip(widths)
    |> Enum.map(fn {cell, width} -> String.pad_trailing(cell, width) end)
    |> Enum.join(" | ")
    |> then(&("| " <> &1 <> " |"))
  end

  defp format_separator(widths) do
    widths
    |> Enum.map(&String.duplicate("─", &1))
    |> Enum.join("─┼─")
    |> then(&("├─" <> &1 <> "─┤"))
  end
end
