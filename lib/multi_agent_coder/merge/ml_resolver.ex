defmodule MultiAgentCoder.Merge.MLResolver do
  @moduledoc """
  ML-based conflict resolution using learned patterns, provider scoring,
  and contextual analysis.

  Provides intelligent predictions for conflict resolution by:
  - Analyzing provider historical accuracy
  - Scoring conflict severity and resolution difficulty
  - Using semantic similarity for context-aware suggestions
  - Combining multiple signals for confident predictions
  """

  require Logger

  alias MultiAgentCoder.FileOps.ConflictDetector
  alias MultiAgentCoder.Merge.{PatternLearner, SemanticAnalyzer}

  @type provider_score :: %{
          provider: atom(),
          accuracy: float(),
          consistency: float(),
          test_success_rate: float(),
          complexity_score: float(),
          overall_score: float()
        }

  @type conflict_analysis :: %{
          severity: :low | :medium | :high | :critical,
          difficulty: :easy | :moderate | :hard | :very_hard,
          recommended_strategy: atom(),
          recommended_provider: atom() | nil,
          confidence: float(),
          reasoning: list(String.t())
        }

  @doc """
  Analyzes a conflict and provides intelligent resolution suggestions.
  """
  @spec analyze_conflict(ConflictDetector.conflict(), keyword()) ::
          {:ok, conflict_analysis()} | {:error, String.t()}
  def analyze_conflict(conflict, opts \\ []) do
    # Gather multiple sources of intelligence
    severity = assess_conflict_severity(conflict)
    difficulty = assess_resolution_difficulty(conflict)

    # Try to get learned prediction
    learned_prediction =
      case PatternLearner.predict_resolution(conflict) do
        {:ok, resolution, confidence} -> {resolution, confidence}
        {:error, _} -> {nil, 0.0}
      end

    # Score providers based on historical performance
    provider_scores = score_providers(conflict, opts)

    # Analyze code context for semantic hints
    context_analysis = analyze_context(conflict)

    # Combine all signals to make final recommendation
    recommendation =
      make_recommendation(
        conflict,
        severity,
        difficulty,
        learned_prediction,
        provider_scores,
        context_analysis
      )

    {:ok, recommendation}
  end

  @doc """
  Scores each provider based on historical accuracy and other metrics.
  """
  @spec score_providers(ConflictDetector.conflict(), keyword()) :: list(provider_score())
  def score_providers(conflict, _opts \\ []) do
    file_type = Path.extname(conflict.file)

    conflict.providers
    |> Enum.map(fn provider ->
      %{
        provider: provider,
        accuracy: calculate_provider_accuracy(provider, file_type),
        consistency: calculate_provider_consistency(provider),
        test_success_rate: get_provider_test_success_rate(provider),
        complexity_score: calculate_complexity_preference(provider),
        overall_score: 0.0
      }
    end)
    |> Enum.map(&calculate_overall_score/1)
    |> Enum.sort_by(& &1.overall_score, :desc)
  end

  @doc """
  Predicts which provider's code is likely better for a given conflict.
  """
  @spec predict_best_provider(ConflictDetector.conflict(), keyword()) ::
          {:ok, atom(), float()} | {:error, :insufficient_data}
  def predict_best_provider(conflict, opts \\ []) do
    provider_scores = score_providers(conflict, opts)

    if Enum.empty?(provider_scores) do
      {:error, :insufficient_data}
    else
      best = List.first(provider_scores)

      if best.overall_score > 0.5 do
        {:ok, best.provider, best.overall_score}
      else
        {:error, :insufficient_data}
      end
    end
  end

  @doc """
  Analyzes surrounding code for context-aware suggestions.
  """
  @spec analyze_context(ConflictDetector.conflict()) :: map()
  def analyze_context(conflict) do
    file_type = Path.extname(conflict.file)

    # Get semantic analysis if available
    semantic_info =
      case conflict.details do
        %{contents: contents} when is_map(contents) ->
          analyze_semantic_context(contents, file_type)

        _ ->
          %{}
      end

    # Extract framework and pattern information
    framework_hints = detect_framework_patterns(conflict.file)

    Map.merge(semantic_info, %{framework: framework_hints})
  end

  @doc """
  Calculates semantic similarity between code versions.
  """
  @spec calculate_semantic_similarity(String.t(), String.t(), String.t()) ::
          {:ok, float()} | {:error, String.t()}
  def calculate_semantic_similarity(code1, code2, file_type) do
    case SemanticAnalyzer.analyze_code(code1, file_type) do
      {:ok, analysis1} ->
        case SemanticAnalyzer.analyze_code(code2, file_type) do
          {:ok, analysis2} ->
            similarity = compute_similarity(analysis1, analysis2)
            {:ok, similarity}

          error ->
            error
        end

      error ->
        error
    end
  end

  @doc """
  Gets metrics for a specific merge strategy's historical performance.
  """
  @spec get_strategy_metrics(atom()) :: map()
  def get_strategy_metrics(strategy) do
    # In a real implementation, this would query a metrics database
    %{
      strategy: strategy,
      success_rate: 0.85,
      average_resolution_time: 2.5,
      conflicts_resolved: 150,
      user_satisfaction: 0.78
    }
  end

  # Private Functions

  defp assess_conflict_severity(conflict) do
    file_crit = file_criticality(conflict.file)
    change_mag = change_magnitude(conflict)
    provider_disagreement = provider_disagreement_level(conflict)

    # If file is critical, ensure severity is at least high
    if file_crit == :critical do
      :critical
    else
      factors = [file_crit, change_mag, provider_disagreement]

      avg_severity =
        factors
        |> Enum.map(&severity_to_number/1)
        |> Enum.sum()
        |> Kernel./(length(factors))

      number_to_severity(avg_severity)
    end
  end

  defp file_criticality(file_path) do
    cond do
      # Critical configuration files
      Regex.match?(~r/mix\.exs|package\.json|Cargo\.toml/, file_path) -> :critical
      # Important core modules
      String.contains?(file_path, ["core", "main", "app"]) -> :high
      # Test files
      String.contains?(file_path, ["test", "spec"]) -> :low
      # Regular source files
      true -> :medium
    end
  end

  defp change_magnitude(conflict) do
    case conflict.details do
      %{contents: contents} when is_map(contents) ->
        sizes =
          contents
          |> Map.values()
          |> Enum.map(&String.length/1)

        avg_size = Enum.sum(sizes) / length(sizes)
        max_size = Enum.max(sizes)
        diff = max_size - avg_size

        cond do
          diff > 1000 -> :high
          diff > 500 -> :medium
          true -> :low
        end

      _ ->
        :medium
    end
  end

  defp provider_disagreement_level(conflict) do
    if length(conflict.providers) > 2 do
      :high
    else
      :medium
    end
  end

  defp assess_resolution_difficulty(conflict) do
    factors = [
      semantic_complexity(conflict),
      conflict_scope(conflict),
      has_clear_winner?(conflict)
    ]

    score =
      factors
      |> Enum.map(&difficulty_to_number/1)
      |> Enum.sum()
      |> Kernel./(length(factors))

    number_to_difficulty(score)
  end

  defp semantic_complexity(conflict) do
    case conflict.details do
      %{contents: contents} when is_map(contents) ->
        # Try to analyze complexity
        complexities =
          contents
          |> Enum.map(fn {_provider, code} ->
            analyze_code_complexity(code, Path.extname(conflict.file))
          end)

        avg_complexity = Enum.sum(complexities) / length(complexities)

        cond do
          avg_complexity > 15 -> :very_hard
          avg_complexity > 10 -> :hard
          avg_complexity > 5 -> :moderate
          true -> :easy
        end

      _ ->
        :moderate
    end
  end

  defp conflict_scope(conflict) do
    case conflict.type do
      :file_level -> :very_hard
      :line_level -> :moderate
      :addition -> :easy
      _ -> :moderate
    end
  end

  defp has_clear_winner?(conflict) do
    # Check if one provider clearly has better code
    case conflict.details do
      %{contents: contents} when map_size(contents) == 2 ->
        :moderate

      _ ->
        :hard
    end
  end

  defp analyze_code_complexity(code, file_type) do
    case SemanticAnalyzer.analyze_code(code, file_type) do
      {:ok, analysis} -> Map.get(analysis, :complexity, 5)
      _ -> 5
    end
  end

  defp severity_to_number(:low), do: 1.0
  defp severity_to_number(:medium), do: 2.0
  defp severity_to_number(:high), do: 3.0
  defp severity_to_number(:critical), do: 4.0

  defp number_to_severity(n) when n < 1.5, do: :low
  defp number_to_severity(n) when n < 2.5, do: :medium
  defp number_to_severity(n) when n < 3.5, do: :high
  defp number_to_severity(_), do: :critical

  defp difficulty_to_number(:easy), do: 1.0
  defp difficulty_to_number(:moderate), do: 2.0
  defp difficulty_to_number(:hard), do: 3.0
  defp difficulty_to_number(:very_hard), do: 4.0

  defp number_to_difficulty(n) when n < 1.5, do: :easy
  defp number_to_difficulty(n) when n < 2.5, do: :moderate
  defp number_to_difficulty(n) when n < 3.5, do: :hard
  defp number_to_difficulty(_), do: :very_hard

  defp calculate_provider_accuracy(provider, file_type) do
    # Get historical data from pattern learner
    preferences = PatternLearner.get_preferences()

    case get_in(preferences, [:by_provider, provider]) do
      nil ->
        0.5

      data ->
        # Calculate accuracy based on how often this provider was chosen
        data.chosen_count / max(data.total_conflicts, 1)
    end
  end

  defp calculate_provider_consistency(_provider) do
    # Measure how consistent the provider's output is
    # For now, return a baseline
    0.75
  end

  defp get_provider_test_success_rate(_provider) do
    # Would integrate with test runner to get actual success rates
    # For now, return baseline
    0.80
  end

  defp calculate_complexity_preference(_provider) do
    # Measure if provider tends to produce simpler or more complex code
    # Simpler is generally better
    0.70
  end

  defp calculate_overall_score(provider_score) do
    # Weighted combination of all factors
    overall =
      provider_score.accuracy * 0.4 +
        provider_score.consistency * 0.2 +
        provider_score.test_success_rate * 0.3 +
        provider_score.complexity_score * 0.1

    %{provider_score | overall_score: overall}
  end

  defp make_recommendation(
         conflict,
         severity,
         difficulty,
         {learned_resolution, learned_confidence},
         provider_scores,
         _context_analysis
       ) do
    reasoning = []

    # If we have high-confidence learned prediction, use it
    {strategy, provider, confidence, reasoning} =
      if learned_confidence > 0.7 do
        {strategy, provider} =
          case learned_resolution do
            {:accept, p} -> {:accept, p}
            {:merge, s} -> {s, nil}
            _ -> {:auto, nil}
          end

        {strategy, provider, learned_confidence,
         [
           "High confidence from learned patterns (#{Float.round(learned_confidence * 100, 1)}%)"
           | reasoning
         ]}
      else
        # Use provider scoring
        if not Enum.empty?(provider_scores) do
          best = List.first(provider_scores)

          if best.overall_score > 0.6 do
            {:accept, best.provider, best.overall_score,
             ["Provider #{best.provider} has strong historical performance" | reasoning]}
          else
            # Fall back to heuristics based on severity and difficulty
            recommend_by_heuristics(severity, difficulty, reasoning)
          end
        else
          recommend_by_heuristics(severity, difficulty, reasoning)
        end
      end

    %{
      severity: severity,
      difficulty: difficulty,
      recommended_strategy: strategy,
      recommended_provider: provider,
      confidence: confidence,
      reasoning: Enum.reverse(reasoning)
    }
  end

  defp recommend_by_heuristics(severity, difficulty, reasoning) do
    {strategy, confidence, new_reasoning} =
      case {severity, difficulty} do
        {:low, :easy} ->
          {:auto, 0.8, ["Low severity and easy difficulty - auto merge recommended"]}

        {:low, _} ->
          {:semantic, 0.7, ["Low severity - semantic merge should handle this"]}

        {:medium, :easy} ->
          {:union, 0.75, ["Medium severity but easy - union merge recommended"]}

        {:high, _} ->
          {:manual, 0.9, ["High severity - manual review recommended"]}

        {:critical, _} ->
          {:manual, 1.0, ["Critical file - requires manual review"]}

        _ ->
          {:semantic, 0.6, ["Using semantic merge as fallback"]}
      end

    {strategy, nil, confidence, new_reasoning ++ reasoning}
  end

  defp analyze_semantic_context(contents, file_type) do
    # Analyze all versions semantically
    analyses =
      contents
      |> Enum.map(fn {provider, code} ->
        case SemanticAnalyzer.analyze_code(code, file_type) do
          {:ok, analysis} -> {provider, analysis}
          _ -> {provider, nil}
        end
      end)
      |> Enum.reject(fn {_, analysis} -> is_nil(analysis) end)
      |> Map.new()

    if map_size(analyses) >= 2 do
      # Compare function counts, complexity, etc.
      %{
        function_counts: Map.new(analyses, fn {p, a} -> {p, length(a.functions)} end),
        avg_complexity: Map.new(analyses, fn {p, a} -> {p, a.complexity} end),
        has_semantic_diff: map_size(analyses) > 1
      }
    else
      %{}
    end
  end

  defp detect_framework_patterns(file_path) do
    cond do
      String.contains?(file_path, "phoenix") -> :phoenix
      String.contains?(file_path, "ecto") -> :ecto
      String.contains?(file_path, "plug") -> :plug
      String.ends_with?(file_path, "_test.exs") -> :exunit
      true -> :unknown
    end
  end

  defp compute_similarity(analysis1, analysis2) do
    # Compare various aspects
    function_similarity = compare_functions(analysis1.functions, analysis2.functions)
    import_similarity = compare_imports(analysis1.imports, analysis2.imports)
    complexity_similarity = compare_complexity(analysis1.complexity, analysis2.complexity)

    # Weighted average
    function_similarity * 0.5 +
      import_similarity * 0.3 +
      complexity_similarity * 0.2
  end

  defp compare_functions(funcs1, funcs2) do
    if Enum.empty?(funcs1) and Enum.empty?(funcs2) do
      # When both have no functions, return neutral score
      0.5
    else
      # Compare function signatures
      sigs1 =
        MapSet.new(funcs1, fn f ->
          {Map.get(f, "name") || Map.get(f, :name), Map.get(f, "arity") || Map.get(f, :arity)}
        end)

      sigs2 =
        MapSet.new(funcs2, fn f ->
          {Map.get(f, "name") || Map.get(f, :name), Map.get(f, "arity") || Map.get(f, :arity)}
        end)

      intersection_size = MapSet.intersection(sigs1, sigs2) |> MapSet.size()
      union_size = MapSet.union(sigs1, sigs2) |> MapSet.size()

      if union_size > 0 do
        intersection_size / union_size
      else
        0.5
      end
    end
  end

  defp compare_imports(imports1, imports2) do
    set1 = MapSet.new(imports1 || [])
    set2 = MapSet.new(imports2 || [])

    intersection_size = MapSet.intersection(set1, set2) |> MapSet.size()
    union_size = MapSet.union(set1, set2) |> MapSet.size()

    if union_size > 0 do
      intersection_size / union_size
    else
      # When both have no imports, return neutral score (don't assume similarity)
      0.5
    end
  end

  defp compare_complexity(c1, c2) do
    if c1 == 0 and c2 == 0 do
      1.0
    else
      max_c = max(c1, c2)
      min_c = min(c1, c2)
      min_c / max_c
    end
  end
end
