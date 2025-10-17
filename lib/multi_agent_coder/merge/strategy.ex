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
  alias MultiAgentCoder.Merge.SemanticAnalyzer

  require Logger

  @type strategy ::
          :auto
          | :semantic
          | :manual
          | :last_write_wins
          | :first_write_wins
          | :union
          | :intersection
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
end
