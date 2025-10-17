defmodule MultiAgentCoder.Build.QualityAnalyzer do
  @moduledoc """
  Analyzes code quality metrics across provider implementations.

  Performs analysis on:
  - Code complexity
  - Documentation coverage
  - Code style consistency
  - Security vulnerabilities
  - Best practices adherence
  """

  alias MultiAgentCoder.FileOps.Tracker
  alias MultiAgentCoder.Merge.SemanticAnalyzer

  require Logger

  @type quality_report :: map()
  @type file_path :: String.t()

  @doc """
  Analyzes code quality for a set of files.
  """
  @spec analyze_files(list(file_path()), keyword()) :: quality_report()
  def analyze_files(files, opts \\ []) do
    Logger.info("Analyzing quality for #{length(files)} files")

    analyses =
      files
      |> Enum.map(fn file ->
        {file, analyze_file(file, opts)}
      end)
      |> Map.new()

    %{
      files: analyses,
      summary: generate_summary(analyses),
      score: calculate_overall_score(analyses),
      recommendations: generate_quality_recommendations(analyses)
    }
  end

  @doc """
  Compares quality metrics between providers.
  """
  @spec compare_quality(map(), map()) :: map()
  def compare_quality(provider1_analysis, provider2_analysis) do
    %{
      score_diff: provider1_analysis.score - provider2_analysis.score,
      better_provider: determine_better_quality(provider1_analysis, provider2_analysis),
      comparison_details: detailed_comparison(provider1_analysis, provider2_analysis)
    }
  end

  @doc """
  Runs security analysis on code.
  """
  @spec analyze_security(list(file_path())) :: map()
  def analyze_security(files) do
    vulnerabilities =
      files
      |> Enum.flat_map(&scan_for_vulnerabilities/1)

    %{
      vulnerabilities: vulnerabilities,
      severity_counts: group_by_severity(vulnerabilities),
      risk_level: calculate_risk_level(vulnerabilities)
    }
  end

  # Private functions

  defp analyze_file(file_path, opts) do
    case Tracker.get_file_history(file_path) do
      [latest | _] when latest.after_content != nil ->
        content = latest.after_content

        %{
          complexity: analyze_complexity(content, file_path),
          documentation: analyze_documentation(content),
          style: analyze_style(content, opts),
          metrics: calculate_metrics(content),
          issues: find_issues(content)
        }

      _ ->
        %{error: "Unable to read file"}
    end
  end

  defp analyze_complexity(content, file_path) do
    # Use SemanticAnalyzer to parse and analyze complexity
    case SemanticAnalyzer.analyze_code(content, Path.extname(file_path)) do
      {:ok, analysis} ->
        %{
          cyclomatic: Map.get(analysis, :complexity, 0),
          nesting_depth: calculate_nesting_depth(content),
          function_count: length(Map.get(analysis, :functions, [])),
          module_count: length(Map.get(analysis, :modules, [])),
          rating: rate_complexity(Map.get(analysis, :complexity, 0))
        }

      _ ->
        %{error: "Unable to analyze complexity"}
    end
  end

  defp calculate_nesting_depth(content) do
    # Simple heuristic: count maximum indentation level
    content
    |> String.split("\n")
    |> Enum.map(fn line ->
      case Regex.run(~r/^(\s*)/, line) do
        [_, spaces] -> String.length(spaces) / 2
        _ -> 0
      end
    end)
    |> Enum.max(fn -> 0 end)
    |> round()
  end

  defp rate_complexity(complexity) do
    cond do
      complexity <= 5 -> :excellent
      complexity <= 10 -> :good
      complexity <= 15 -> :fair
      complexity <= 20 -> :poor
      true -> :very_poor
    end
  end

  defp analyze_documentation(content) do
    lines = String.split(content, "\n")
    total_lines = length(lines)

    doc_lines =
      lines
      |> Enum.count(fn line ->
        String.contains?(line, ["@moduledoc", "@doc", "#", "//", "/*", "*/"]) or
          String.trim(line) |> String.starts_with?(["#", "//"])
      end)

    functions = extract_function_definitions(content)
    documented_functions = count_documented_functions(content, functions)

    %{
      coverage: if(total_lines > 0, do: doc_lines / total_lines * 100, else: 0),
      doc_lines: doc_lines,
      total_lines: total_lines,
      function_coverage:
        if(length(functions) > 0, do: documented_functions / length(functions) * 100, else: 100),
      rating: rate_documentation(doc_lines / max(total_lines, 1))
    }
  end

  defp extract_function_definitions(content) do
    # Extract function definitions based on common patterns
    patterns = [
      ~r/def\s+(\w+)/,
      ~r/defp\s+(\w+)/,
      ~r/function\s+(\w+)/,
      ~r/func\s+(\w+)/,
      ~r/fn\s+(\w+)/
    ]

    patterns
    |> Enum.flat_map(fn pattern ->
      Regex.scan(pattern, content)
      |> Enum.map(fn [_, name] -> name end)
    end)
    |> Enum.uniq()
  end

  defp count_documented_functions(content, functions) do
    # Check if functions have documentation
    Enum.count(functions, fn func ->
      # Look for doc comment before function
      pattern = Regex.compile!("(@doc|#|//|/\\*).*?#{Regex.escape(func)}", "s")
      Regex.match?(pattern, content)
    end)
  end

  defp rate_documentation(ratio) do
    cond do
      ratio >= 0.3 -> :excellent
      ratio >= 0.2 -> :good
      ratio >= 0.1 -> :fair
      ratio >= 0.05 -> :poor
      true -> :very_poor
    end
  end

  defp analyze_style(content, opts) do
    max_line_length = Keyword.get(opts, :max_line_length, 120)
    issues = []

    lines = String.split(content, "\n")

    # Check line length
    long_lines =
      lines
      |> Enum.with_index(1)
      |> Enum.filter(fn {line, _} -> String.length(line) > max_line_length end)
      |> Enum.map(fn {_, line_no} -> {:long_line, line_no} end)

    issues = issues ++ long_lines

    # Check trailing whitespace
    trailing_whitespace =
      lines
      |> Enum.with_index(1)
      |> Enum.filter(fn {line, _} -> Regex.match?(~r/\s+$/, line) end)
      |> Enum.map(fn {_, line_no} -> {:trailing_whitespace, line_no} end)

    issues = issues ++ trailing_whitespace

    # Check indentation consistency
    indentation_issues = check_indentation_consistency(lines)
    issues = issues ++ indentation_issues

    %{
      issues: issues,
      issue_count: length(issues),
      rating: rate_style(length(issues))
    }
  end

  defp check_indentation_consistency(lines) do
    # Detect mixed tabs and spaces
    lines
    |> Enum.with_index(1)
    |> Enum.filter(fn {line, _} ->
      String.contains?(line, "\t") and String.starts_with?(line, " ")
    end)
    |> Enum.map(fn {_, line_no} -> {:mixed_indentation, line_no} end)
  end

  defp rate_style(issue_count) do
    cond do
      issue_count == 0 -> :excellent
      issue_count <= 5 -> :good
      issue_count <= 10 -> :fair
      issue_count <= 20 -> :poor
      true -> :very_poor
    end
  end

  defp calculate_metrics(content) do
    lines = String.split(content, "\n")

    %{
      loc: length(lines),
      sloc: Enum.count(lines, fn l -> String.trim(l) != "" end),
      comment_lines: Enum.count(lines, &is_comment?/1),
      blank_lines: Enum.count(lines, fn l -> String.trim(l) == "" end),
      average_line_length: calculate_average_line_length(lines),
      max_line_length: lines |> Enum.map(&String.length/1) |> Enum.max(fn -> 0 end)
    }
  end

  defp is_comment?(line) do
    trimmed = String.trim(line)

    String.starts_with?(trimmed, ["#", "//", "/*", "*/", "*"]) or
      String.contains?(trimmed, ["@doc", "@moduledoc"])
  end

  defp calculate_average_line_length(lines) do
    non_empty = Enum.filter(lines, fn l -> String.trim(l) != "" end)

    if Enum.empty?(non_empty) do
      0
    else
      total_length = non_empty |> Enum.map(&String.length/1) |> Enum.sum()
      round(total_length / length(non_empty))
    end
  end

  defp find_issues(content) do
    issues = []

    # Check for common code smells
    issues = issues ++ find_code_smells(content)

    # Check for potential bugs
    issues = issues ++ find_potential_bugs(content)

    # Check for performance issues
    issues = issues ++ find_performance_issues(content)

    issues
  end

  defp find_code_smells(content) do
    smells = []

    # Check for TODO/FIXME comments
    smells =
      if Regex.match?(~r/TODO|FIXME|HACK|XXX/i, content) do
        [{:code_smell, :unfinished_code, "Contains TODO/FIXME comments"} | smells]
      else
        smells
      end

    # Check for magic numbers
    smells =
      if Regex.match?(~r/\b\d{3,}\b/, content) do
        [{:code_smell, :magic_numbers, "Contains magic numbers"} | smells]
      else
        smells
      end

    # Check for deeply nested code
    smells =
      if calculate_nesting_depth(content) > 4 do
        [{:code_smell, :deep_nesting, "Deeply nested code detected"} | smells]
      else
        smells
      end

    smells
  end

  defp find_potential_bugs(content) do
    bugs = []

    # Check for common bug patterns
    bugs =
      if Regex.match?(~r/==\s*nil|!=\s*nil/, content) do
        [{:potential_bug, :nil_check, "Direct nil comparison found"} | bugs]
      else
        bugs
      end

    bugs =
      if Regex.match?(~r/rescue\s+_/, content) do
        [{:potential_bug, :catch_all, "Catch-all rescue clause found"} | bugs]
      else
        bugs
      end

    bugs
  end

  defp find_performance_issues(content) do
    issues = []

    # Check for N+1 query patterns
    issues =
      if Regex.match?(~r/Enum\.map.*?Repo\.|for.*?do.*?Repo\./, content) do
        [{:performance, :n_plus_one, "Potential N+1 query pattern"} | issues]
      else
        issues
      end

    # Check for inefficient string concatenation in loops
    issues =
      if Regex.match?(~r/Enum\.reduce.*?<>|for.*?do.*?<>/, content) do
        [{:performance, :string_concat, "String concatenation in loop"} | issues]
      else
        issues
      end

    issues
  end

  defp scan_for_vulnerabilities(file_path) do
    case Tracker.get_file_history(file_path) do
      [latest | _] when latest.after_content != nil ->
        content = latest.after_content
        vulnerabilities = []

        # Check for hardcoded secrets
        vulnerabilities =
          if Regex.match?(
               ~r/password\s*=\s*["'][^"']+["']|api_key\s*=\s*["'][^"']+["']/i,
               content
             ) do
            [
              %{
                type: :hardcoded_secret,
                severity: :high,
                file: file_path,
                description: "Potential hardcoded credentials detected"
              }
              | vulnerabilities
            ]
          else
            vulnerabilities
          end

        # Check for SQL injection vulnerabilities
        vulnerabilities =
          if Regex.match?(~r/Repo\.query.*?<>|execute.*?".*?#\{/, content) do
            [
              %{
                type: :sql_injection,
                severity: :critical,
                file: file_path,
                description: "Potential SQL injection vulnerability"
              }
              | vulnerabilities
            ]
          else
            vulnerabilities
          end

        # Check for unsafe deserialization
        vulnerabilities =
          if Regex.match?(~r/:erlang\.binary_to_term|:pickle\.loads/, content) do
            [
              %{
                type: :unsafe_deserialization,
                severity: :high,
                file: file_path,
                description: "Unsafe deserialization detected"
              }
              | vulnerabilities
            ]
          else
            vulnerabilities
          end

        vulnerabilities

      _ ->
        []
    end
  end

  defp group_by_severity(vulnerabilities) do
    vulnerabilities
    |> Enum.group_by(& &1.severity)
    |> Enum.map(fn {severity, vulns} -> {severity, length(vulns)} end)
    |> Map.new()
  end

  defp calculate_risk_level(vulnerabilities) do
    severity_scores = %{critical: 10, high: 5, medium: 2, low: 1}

    total_score =
      vulnerabilities
      |> Enum.map(fn v -> Map.get(severity_scores, v.severity, 0) end)
      |> Enum.sum()

    cond do
      total_score == 0 -> :none
      total_score <= 5 -> :low
      total_score <= 15 -> :medium
      total_score <= 30 -> :high
      true -> :critical
    end
  end

  defp generate_summary(file_analyses) do
    total_files = map_size(file_analyses)

    # Calculate averages
    avg_complexity =
      file_analyses
      |> Map.values()
      |> Enum.map(fn a -> get_in(a, [:complexity, :cyclomatic]) || 0 end)
      |> average()

    avg_doc_coverage =
      file_analyses
      |> Map.values()
      |> Enum.map(fn a -> get_in(a, [:documentation, :coverage]) || 0 end)
      |> average()

    total_issues =
      file_analyses
      |> Map.values()
      |> Enum.map(fn a -> length(Map.get(a, :issues, [])) end)
      |> Enum.sum()

    %{
      files_analyzed: total_files,
      average_complexity: avg_complexity,
      average_doc_coverage: avg_doc_coverage,
      total_issues: total_issues,
      health: determine_health(avg_complexity, avg_doc_coverage, total_issues)
    }
  end

  defp average(list) when length(list) > 0 do
    Enum.sum(list) / length(list)
  end

  defp average(_), do: 0

  defp determine_health(complexity, doc_coverage, issues) do
    score = 100
    score = score - min(complexity * 2, 30)
    score = score - max(0, 20 - doc_coverage / 5)
    score = score - min(issues, 30)

    cond do
      score >= 80 -> :excellent
      score >= 60 -> :good
      score >= 40 -> :fair
      score >= 20 -> :poor
      true -> :critical
    end
  end

  defp calculate_overall_score(file_analyses) do
    scores =
      file_analyses
      |> Map.values()
      |> Enum.map(&calculate_file_score/1)

    if Enum.empty?(scores) do
      0
    else
      round(Enum.sum(scores) / length(scores))
    end
  end

  defp calculate_file_score(analysis) do
    base_score = 100

    # Deduct for complexity
    complexity_penalty = min(get_in(analysis, [:complexity, :cyclomatic]) || 0, 30)

    # Deduct for poor documentation
    doc_score = get_in(analysis, [:documentation, :coverage]) || 0
    doc_penalty = max(0, 30 - doc_score / 3)

    # Deduct for style issues
    style_issues = get_in(analysis, [:style, :issue_count]) || 0
    style_penalty = min(style_issues * 2, 20)

    # Deduct for code issues
    issues = length(Map.get(analysis, :issues, []))
    issue_penalty = min(issues * 5, 20)

    max(0, base_score - complexity_penalty - doc_penalty - style_penalty - issue_penalty)
  end

  defp generate_quality_recommendations(file_analyses) do
    recommendations = []

    # Check for high complexity files
    complex_files =
      file_analyses
      |> Enum.filter(fn {_, a} ->
        get_in(a, [:complexity, :cyclomatic]) || 0 > 10
      end)
      |> Enum.map(fn {f, _} -> Path.basename(f) end)

    recommendations =
      if not Enum.empty?(complex_files) do
        ["Refactor complex files: #{Enum.join(complex_files, ", ")}" | recommendations]
      else
        recommendations
      end

    # Check for poor documentation
    poorly_documented =
      file_analyses
      |> Enum.filter(fn {_, a} ->
        get_in(a, [:documentation, :coverage]) || 0 < 10
      end)
      |> Enum.map(fn {f, _} -> Path.basename(f) end)

    recommendations =
      if not Enum.empty?(poorly_documented) do
        ["Add documentation to: #{Enum.join(poorly_documented, ", ")}" | recommendations]
      else
        recommendations
      end

    # Check for files with many issues
    problematic_files =
      file_analyses
      |> Enum.filter(fn {_, a} ->
        length(Map.get(a, :issues, [])) > 5
      end)
      |> Enum.map(fn {f, _} -> Path.basename(f) end)

    recommendations =
      if not Enum.empty?(problematic_files) do
        ["Fix issues in: #{Enum.join(problematic_files, ", ")}" | recommendations]
      else
        recommendations
      end

    if Enum.empty?(recommendations) do
      ["Code quality is good overall"]
    else
      recommendations
    end
  end

  defp determine_better_quality(analysis1, analysis2) do
    if analysis1.score > analysis2.score do
      :provider1
    else
      :provider2
    end
  end

  defp detailed_comparison(analysis1, analysis2) do
    %{
      complexity: %{
        provider1: get_in(analysis1, [:summary, :average_complexity]) || 0,
        provider2: get_in(analysis2, [:summary, :average_complexity]) || 0
      },
      documentation: %{
        provider1: get_in(analysis1, [:summary, :average_doc_coverage]) || 0,
        provider2: get_in(analysis2, [:summary, :average_doc_coverage]) || 0
      },
      issues: %{
        provider1: get_in(analysis1, [:summary, :total_issues]) || 0,
        provider2: get_in(analysis2, [:summary, :total_issues]) || 0
      }
    }
  end
end
