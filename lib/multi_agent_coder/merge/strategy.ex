defmodule MultiAgentCoder.Merge.Strategy do
  @moduledoc """
  Defines and implements various merge strategies for combining code from multiple providers.

  Available strategies:
  - `:auto` - Automatically selects the best strategy based on conflict analysis
  - `:semantic` - Uses semantic understanding to merge code intelligently
  - `:manual` - Requires user intervention for all conflicts
  - `:last_write_wins` - Simple strategy where the last change wins
  - `:first_write_wins` - Simple strategy where the first change wins
  - `:union` - Combines all non-conflicting changes
  - `:intersection` - Only keeps changes that all providers agree on
  """

  alias MultiAgentCoder.FileOps.ConflictDetector
  alias MultiAgentCoder.Merge.{SemanticAnalyzer, MLResolver}

  require Logger

  @type strategy ::
          :auto
          | :semantic
          | :manual
          | :last_write_wins
          | :first_write_wins
          | :union
          | :intersection
          | :voting
          | :hybrid
          | :ml_recommended
          | :context_aware
  @type resolution :: map()

  @doc """
  Resolves conflicts using the specified strategy.
  """
  @spec resolve_conflicts(list(ConflictDetector.conflict()), strategy()) ::
          {:ok, resolution()} | {:error, String.t()}
  def resolve_conflicts(conflicts, strategy) do
    Logger.info("Resolving #{length(conflicts)} conflicts using #{strategy} strategy")

    resolutions =
      conflicts
      |> Enum.map(fn conflict ->
        {conflict.file, resolve_single_conflict(conflict, strategy)}
      end)
      |> Map.new()

    {:ok, resolutions}
  end

  @doc """
  Selects the best strategy based on conflict characteristics.
  """
  @spec select_best_strategy(list(ConflictDetector.conflict())) :: strategy()
  def select_best_strategy(conflicts) do
    cond do
      all_simple_additions?(conflicts) -> :union
      all_different_functions?(conflicts) -> :semantic
      has_complex_overlaps?(conflicts) -> :manual
      true -> :auto
    end
  end

  @doc """
  Applies a specific merge strategy to file contents.
  """
  @spec apply_strategy(map(), strategy()) :: {:ok, String.t()} | {:error, String.t()}
  def apply_strategy(provider_contents, strategy) do
    case strategy do
      :last_write_wins ->
        apply_last_write_wins(provider_contents)

      :first_write_wins ->
        apply_first_write_wins(provider_contents)

      :union ->
        apply_union_strategy(provider_contents)

      :intersection ->
        apply_intersection_strategy(provider_contents)

      :semantic ->
        SemanticAnalyzer.merge_semantically(provider_contents)

      :auto ->
        apply_auto_strategy(provider_contents)

      :manual ->
        {:error, "Manual strategy requires interactive resolution"}

      :voting ->
        apply_voting_strategy(provider_contents)

      :hybrid ->
        apply_hybrid_strategy(provider_contents)

      :ml_recommended ->
        apply_ml_recommended_strategy(provider_contents)

      :context_aware ->
        apply_context_aware_strategy(provider_contents)

      _ ->
        {:error, "Unknown strategy: #{strategy}"}
    end
  end

  @doc """
  Creates a merge plan showing how conflicts will be resolved.
  """
  @spec create_merge_plan(list(ConflictDetector.conflict()), strategy()) ::
          {:ok, list(map())} | {:error, String.t()}
  def create_merge_plan(conflicts, strategy) do
    plan =
      conflicts
      |> Enum.map(fn conflict ->
        %{
          file: conflict.file,
          type: conflict.type,
          providers: conflict.providers,
          resolution: plan_resolution(conflict, strategy),
          strategy: strategy
        }
      end)

    {:ok, plan}
  end

  # Private functions

  defp resolve_single_conflict(conflict, strategy) do
    case strategy do
      :auto ->
        auto_resolve_conflict(conflict)

      :last_write_wins ->
        {:accept, List.last(conflict.providers)}

      :first_write_wins ->
        {:accept, List.first(conflict.providers)}

      :union ->
        {:merge, union_merge_spec(conflict)}

      :intersection ->
        {:merge, intersection_merge_spec(conflict)}

      :semantic ->
        {:merge, :semantic}

      :manual ->
        {:manual, conflict}
    end
  end

  defp auto_resolve_conflict(conflict) do
    cond do
      # If it's a simple addition (no actual conflict), accept all
      conflict.type == :addition ->
        {:merge, :union}

      # If changes are in different parts of the file, merge them
      conflict.type == :line_level and non_overlapping?(conflict) ->
        {:merge, :union}

      # If changes are semantically equivalent, accept any
      semantically_equivalent_changes?(conflict) ->
        {:accept, List.first(conflict.providers)}

      # Otherwise, try semantic merge
      true ->
        {:merge, :semantic}
    end
  end

  defp non_overlapping?(conflict) do
    # Check if line ranges don't overlap
    case conflict do
      %{details: %{line_ranges: ranges}} ->
        # Check if any ranges overlap
        sorted_ranges = Enum.sort_by(ranges, fn {_provider, {start_line, _}} -> start_line end)

        sorted_ranges
        |> Enum.chunk_every(2, 1, :discard)
        |> Enum.all?(fn [{_p1, {_s1, e1}}, {_p2, {s2, _e2}}] ->
          # No overlap if first ends before second starts
          e1 < s2
        end)

      _ ->
        false
    end
  end

  defp semantically_equivalent_changes?(conflict) do
    # Check if all providers made semantically equivalent changes
    case conflict.details do
      %{contents: contents} when is_map(contents) ->
        unique_contents =
          contents
          |> Map.values()
          |> Enum.uniq()

        if length(unique_contents) <= 1 do
          # All providers have the same content
          true
        else
          # Check semantic equivalence
          check_semantic_equivalence(unique_contents)
        end

      _ ->
        false
    end
  end

  defp check_semantic_equivalence(contents) do
    # Use semantic analyzer to check equivalence
    contents
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.all?(fn [c1, c2] ->
      SemanticAnalyzer.semantically_equivalent?(c1, c2)
    end)
  end

  defp apply_last_write_wins(provider_contents) do
    # Get the last provider's content (sorted by provider name for determinism)
    last_content =
      provider_contents
      |> Enum.sort_by(fn {provider, _} -> provider end)
      |> List.last()
      |> elem(1)

    {:ok, last_content}
  end

  defp apply_first_write_wins(provider_contents) do
    # Get the first provider's content (sorted by provider name for determinism)
    first_content =
      provider_contents
      |> Enum.sort_by(fn {provider, _} -> provider end)
      |> List.first()
      |> elem(1)

    {:ok, first_content}
  end

  defp apply_union_strategy(provider_contents) do
    # Combine all unique changes from all providers
    # This is complex and would need line-by-line analysis
    with {:ok, analyzed} <- analyze_all_changes(provider_contents),
         {:ok, unified} <- unify_changes(analyzed) do
      {:ok, unified}
    else
      error -> error
    end
  end

  defp apply_intersection_strategy(provider_contents) do
    # Only keep changes that all providers agree on
    with {:ok, analyzed} <- analyze_all_changes(provider_contents),
         {:ok, common} <- find_common_changes(analyzed) do
      {:ok, common}
    else
      error -> error
    end
  end

  defp apply_auto_strategy(provider_contents) do
    # Try strategies in order of sophistication
    strategies = [:semantic, :union, :last_write_wins]

    Enum.reduce_while(strategies, {:error, "No strategy succeeded"}, fn strategy, _acc ->
      case apply_strategy(provider_contents, strategy) do
        {:ok, _merged} = success ->
          {:halt, success}

        {:error, _reason} ->
          {:cont, {:error, "Auto strategy failed"}}
      end
    end)
  end

  defp analyze_all_changes(provider_contents) do
    # Analyze changes from each provider
    analyzed =
      provider_contents
      |> Enum.map(fn {provider, content} ->
        lines = String.split(content, "\n")
        {provider, lines}
      end)
      |> Map.new()

    {:ok, analyzed}
  end

  defp unify_changes(analyzed_changes) do
    # Get all unique lines from all providers
    all_lines =
      analyzed_changes
      |> Map.values()
      |> List.flatten()
      |> Enum.uniq()
      |> Enum.join("\n")

    {:ok, all_lines}
  end

  defp find_common_changes(analyzed_changes) do
    # Find lines that appear in all providers' versions
    all_line_sets =
      analyzed_changes
      |> Map.values()
      |> Enum.map(&MapSet.new/1)

    common_lines =
      all_line_sets
      |> Enum.reduce(&MapSet.intersection/2)
      |> MapSet.to_list()
      |> Enum.join("\n")

    {:ok, common_lines}
  end

  defp union_merge_spec(_conflict) do
    %{
      type: :union,
      combine: :all_changes
    }
  end

  defp intersection_merge_spec(_conflict) do
    %{
      type: :intersection,
      combine: :common_only
    }
  end

  defp plan_resolution(conflict, strategy) do
    case strategy do
      :auto ->
        # Determine what auto would do
        case auto_resolve_conflict(conflict) do
          {:accept, provider} -> "Accept #{provider}'s version"
          {:merge, :semantic} -> "Merge semantically"
          {:merge, :union} -> "Combine all changes"
          _ -> "Automatic resolution"
        end

      :last_write_wins ->
        "Use #{List.last(conflict.providers)}'s version"

      :first_write_wins ->
        "Use #{List.first(conflict.providers)}'s version"

      :union ->
        "Combine all non-conflicting changes"

      :intersection ->
        "Keep only common changes"

      :semantic ->
        "Merge using semantic analysis"

      :manual ->
        "Requires manual resolution"
    end
  end

  defp all_simple_additions?(conflicts) do
    Enum.all?(conflicts, fn conflict ->
      conflict.type == :addition or
        (conflict.type == :line_level and non_overlapping?(conflict))
    end)
  end

  defp all_different_functions?(conflicts) do
    # Check if all conflicts are in different functions
    Enum.all?(conflicts, fn conflict ->
      case conflict.details do
        %{scope: :function, function_name: _name} -> true
        _ -> false
      end
    end)
  end

  defp has_complex_overlaps?(conflicts) do
    Enum.any?(conflicts, fn conflict ->
      conflict.type == :file_level or
        (conflict.type == :line_level and not non_overlapping?(conflict))
    end)
  end

  # Advanced Strategy Implementations

  defp apply_voting_strategy(provider_contents) do
    Logger.info("Applying voting strategy with #{map_size(provider_contents)} providers")

    # Score each provider's version
    scored_versions =
      provider_contents
      |> Enum.map(fn {provider, content} ->
        score = score_version_quality(content, provider_contents)
        {provider, content, score}
      end)
      |> Enum.sort_by(fn {_p, _c, score} -> score end, :desc)

    case scored_versions do
      [] ->
        {:error, "No provider content available"}

      [{_best_provider, best_content, best_score} | rest] ->
        # Check if there's a clear winner (score significantly higher than others)
        has_clear_winner =
          case rest do
            [{_, _, second_score} | _] -> best_score - second_score > 0.2
            [] -> true
          end

        if has_clear_winner do
          Logger.info("Voting strategy: clear winner found with score #{best_score}")
          {:ok, best_content}
        else
          # No clear winner, try to combine best parts
          Logger.info("Voting strategy: no clear winner, attempting hybrid merge")
          apply_hybrid_strategy(provider_contents)
        end
    end
  end

  defp apply_hybrid_strategy(provider_contents) do
    Logger.info("Applying hybrid 'best of both' strategy")

    # Analyze all versions semantically
    analyzed_versions =
      provider_contents
      |> Enum.map(fn {provider, content} ->
        case analyze_version_features(content) do
          {:ok, features} -> {provider, content, features}
          _ -> {provider, content, %{}}
        end
      end)

    # Extract best parts from each version
    merged_content = merge_best_features(analyzed_versions)

    case merged_content do
      {:ok, _} = success -> success
      _ -> apply_semantic_fallback(provider_contents)
    end
  end

  defp apply_ml_recommended_strategy(provider_contents) do
    Logger.info("Applying ML-recommended strategy")

    # Create a mock conflict for ML analysis
    mock_conflict = %{
      file: "unknown",
      type: :line_level,
      providers: Map.keys(provider_contents),
      details: %{contents: provider_contents}
    }

    case MLResolver.analyze_conflict(mock_conflict) do
      {:ok, analysis} ->
        Logger.info(
          "ML recommendation: #{analysis.recommended_strategy} with confidence #{analysis.confidence}"
        )

        # Apply the recommended strategy
        if analysis.recommended_provider do
          case Map.get(provider_contents, analysis.recommended_provider) do
            nil -> apply_auto_strategy(provider_contents)
            content -> {:ok, content}
          end
        else
          apply_strategy(provider_contents, analysis.recommended_strategy)
        end

      {:error, reason} ->
        Logger.warning("ML strategy failed: #{reason}, falling back to auto")
        apply_auto_strategy(provider_contents)
    end
  end

  defp apply_context_aware_strategy(provider_contents) do
    Logger.info("Applying context-aware strategy")

    # Analyze context for each version
    context_scores =
      provider_contents
      |> Enum.map(fn {provider, content} ->
        score = analyze_code_context(content)
        {provider, score}
      end)
      |> Map.new()

    # Find provider with best context score
    best_provider =
      context_scores
      |> Enum.max_by(fn {_p, score} -> score end, fn -> nil end)

    case best_provider do
      {provider, score} when score > 0.6 ->
        Logger.info("Context-aware strategy: chose #{provider} with score #{score}")
        {:ok, Map.get(provider_contents, provider)}

      _ ->
        Logger.info("Context-aware strategy: no clear winner, using semantic merge")
        apply_semantic_fallback(provider_contents)
    end
  end

  # Helper Functions for Advanced Strategies

  defp score_version_quality(content, all_versions) do
    # Multiple quality factors
    complexity_score = 1.0 - normalize_complexity(calculate_simple_complexity(content))
    similarity_score = calculate_average_similarity(content, all_versions)
    structure_score = score_code_structure(content)
    length_score = score_reasonable_length(content, all_versions)

    # Weighted combination
    complexity_score * 0.3 +
      similarity_score * 0.25 +
      structure_score * 0.25 +
      length_score * 0.2
  end

  defp calculate_simple_complexity(content) do
    # Simple heuristic-based complexity
    lines = String.split(content, "\n")

    control_flow_keywords = ["if", "case", "cond", "for", "while", "do"]

    complexity =
      lines
      |> Enum.count(fn line ->
        Enum.any?(control_flow_keywords, &String.contains?(line, &1))
      end)

    complexity + 1
  end

  defp normalize_complexity(complexity) do
    # Normalize to 0-1 range (simpler code gets higher score)
    min(complexity / 20.0, 1.0)
  end

  defp calculate_average_similarity(content, all_versions) do
    other_contents =
      all_versions
      |> Map.values()
      |> Enum.reject(&(&1 == content))

    if Enum.empty?(other_contents) do
      0.5
    else
      similarities =
        other_contents
        |> Enum.map(&simple_similarity(content, &1))

      Enum.sum(similarities) / length(similarities)
    end
  end

  defp simple_similarity(str1, str2) do
    # Jaccard similarity on words
    words1 = String.split(str1) |> MapSet.new()
    words2 = String.split(str2) |> MapSet.new()

    intersection = MapSet.intersection(words1, words2) |> MapSet.size()
    union = MapSet.union(words1, words2) |> MapSet.size()

    if union > 0 do
      intersection / union
    else
      0.0
    end
  end

  defp score_code_structure(content) do
    # Check for good code structure (functions, modules, documentation)
    has_functions = String.contains?(content, "def ") || String.contains?(content, "defp ")
    has_moduledoc = String.contains?(content, "@moduledoc")
    has_docs = String.contains?(content, "@doc")
    has_specs = String.contains?(content, "@spec")

    score = 0.4

    score = if has_functions, do: score + 0.2, else: score
    score = if has_moduledoc, do: score + 0.2, else: score
    score = if has_docs, do: score + 0.1, else: score
    score = if has_specs, do: score + 0.1, else: score

    score
  end

  defp score_reasonable_length(content, all_versions) do
    lengths = Map.values(all_versions) |> Enum.map(&String.length/1)
    avg_length = Enum.sum(lengths) / length(lengths)
    this_length = String.length(content)

    # Penalize versions that are much longer or much shorter than average
    diff_ratio = abs(this_length - avg_length) / max(avg_length, 1)

    max(0.0, 1.0 - diff_ratio)
  end

  defp analyze_version_features(content) do
    # Extract key features from the code
    features = %{
      functions: extract_function_names(content),
      imports: extract_imports(content),
      has_tests: String.contains?(content, "test "),
      has_error_handling:
        String.contains?(content, "rescue") or String.contains?(content, "catch"),
      has_documentation: String.contains?(content, "@doc")
    }

    {:ok, features}
  end

  defp extract_function_names(content) do
    # Simple regex-based extraction
    ~r/def[p]?\s+(\w+)/
    |> Regex.scan(content)
    |> Enum.map(fn [_, name] -> name end)
  end

  defp extract_imports(content) do
    ~r/(?:alias|import|use)\s+([\w\.]+)/
    |> Regex.scan(content)
    |> Enum.map(fn [_, module] -> module end)
  end

  defp merge_best_features(analyzed_versions) do
    # Combine unique functions and features from all versions
    all_functions =
      analyzed_versions
      |> Enum.flat_map(fn {_, _, features} -> Map.get(features, :functions, []) end)
      |> Enum.uniq()

    # Find version with most comprehensive feature set
    best_version =
      analyzed_versions
      |> Enum.max_by(
        fn {_, _, features} ->
          score_feature_completeness(features)
        end,
        fn -> nil end
      )

    case best_version do
      {_, content, _} -> {:ok, content}
      nil -> {:error, "Could not determine best version"}
    end
  end

  defp score_feature_completeness(features) do
    score = length(Map.get(features, :functions, []))
    score = score + length(Map.get(features, :imports, []))
    score = if Map.get(features, :has_tests), do: score + 5, else: score
    score = if Map.get(features, :has_error_handling), do: score + 3, else: score
    score = if Map.get(features, :has_documentation), do: score + 2, else: score
    score
  end

  defp analyze_code_context(content) do
    # Analyze various context factors
    has_proper_structure = String.contains?(content, "defmodule")
    has_type_specs = String.contains?(content, "@spec")
    has_tests = String.contains?(content, "test ")
    has_docs = String.contains?(content, "@doc")
    reasonable_length = String.length(content) > 50 and String.length(content) < 10000

    score = 0.2
    score = if has_proper_structure, do: score + 0.25, else: score
    score = if has_type_specs, do: score + 0.15, else: score
    score = if has_tests, do: score + 0.2, else: score
    score = if has_docs, do: score + 0.1, else: score
    score = if reasonable_length, do: score + 0.1, else: score

    score
  end

  defp apply_semantic_fallback(provider_contents) do
    Logger.info("Falling back to semantic merge")
    SemanticAnalyzer.merge_semantically(provider_contents)
  end
end
