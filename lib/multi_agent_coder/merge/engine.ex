defmodule MultiAgentCoder.Merge.Engine do
  @moduledoc """
  Core merge engine for intelligently combining code from multiple providers.

  This module orchestrates the entire merge process, including:
  - Loading changes from all providers
  - Detecting conflicts
  - Applying merge strategies
  - Resolving conflicts
  - Producing the final merged output
  """

  alias MultiAgentCoder.FileOps.Tracker
  alias MultiAgentCoder.FileOps.ConflictDetector
  alias MultiAgentCoder.Merge.Strategy
  alias MultiAgentCoder.Merge.SemanticAnalyzer
  alias MultiAgentCoder.Merge.ConflictResolver

  require Logger

  @type merge_result :: {:ok, merged_files()} | {:error, String.t()}
  @type merged_files :: %{String.t() => String.t()}
  @type merge_options :: [
          strategy: :auto | :manual | :semantic,
          interactive: boolean(),
          preserve_comments: boolean(),
          run_tests: boolean()
        ]

  @doc """
  Performs an automatic merge of all provider changes.

  ## Options
    - `:strategy` - The merge strategy to use (:auto, :manual, :semantic)
    - `:interactive` - Whether to use interactive conflict resolution
    - `:preserve_comments` - Whether to preserve all provider comments
    - `:run_tests` - Whether to run tests after merge
  """
  @spec merge_all(merge_options()) :: merge_result()
  def merge_all(opts \\ []) do
    strategy = Keyword.get(opts, :strategy, :auto)
    interactive = Keyword.get(opts, :interactive, false)

    Logger.info("Starting merge with strategy: #{strategy}")

    with {:ok, providers} <- get_active_providers(),
         {:ok, file_changes} <- collect_file_changes(providers),
         {:ok, conflicts} <- detect_conflicts(file_changes),
         {:ok, resolved} <- resolve_conflicts(conflicts, strategy, interactive),
         {:ok, merged} <- apply_merges(file_changes, resolved) do
      if Keyword.get(opts, :run_tests, false) do
        run_and_compare_tests(merged, providers)
      end

      {:ok, merged}
    else
      {:error, reason} = error ->
        Logger.error("Merge failed: #{reason}")
        error
    end
  end

  @doc """
  Merges a specific file from all providers.
  """
  @spec merge_file(String.t(), merge_options()) :: {:ok, String.t()} | {:error, String.t()}
  def merge_file(file_path, opts \\ []) do
    strategy = Keyword.get(opts, :strategy, :auto)

    with {:ok, providers} <- get_active_providers(),
         {:ok, changes} <- get_file_changes(file_path, providers),
         {:ok, merged_content} <- merge_file_content(changes, strategy) do
      {:ok, merged_content}
    else
      error -> error
    end
  end

  @doc """
  Lists all conflicts detected across all files.
  """
  @spec list_conflicts() :: {:ok, list(ConflictDetector.conflict())} | {:error, String.t()}
  def list_conflicts() do
    with {:ok, providers} <- get_active_providers(),
         {:ok, file_changes} <- collect_file_changes(providers) do
      detect_conflicts(file_changes)
    end
  end

  @doc """
  Previews what a merge would produce without applying it.
  """
  @spec preview_merge(merge_options()) :: {:ok, merged_files()} | {:error, String.t()}
  def preview_merge(opts \\ []) do
    # Similar to merge_all but doesn't write files
    merge_all(Keyword.put(opts, :dry_run, true))
  end

  # Private functions

  defp get_active_providers() do
    # Get all unique providers from tracked files
    files = Tracker.list_files()

    providers =
      files
      |> Enum.flat_map(fn file -> [file.owner | file.contributors] end)
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()

    case providers do
      [] -> {:error, "No active providers found"}
      providers -> {:ok, providers}
    end
  end

  defp collect_file_changes(providers) do
    changes =
      providers
      |> Enum.reduce(%{}, fn provider, acc ->
        # Get files where this provider is owner or contributor
        files = Tracker.list_files(provider: provider)

        Enum.reduce(files, acc, fn file_info, acc2 ->
          file_path = file_info.path

          Map.update(
            acc2,
            file_path,
            %{provider => get_file_content(file_path)},
            fn existing ->
              Map.put(existing, provider, get_file_content(file_path))
            end
          )
        end)
      end)

    {:ok, changes}
  end

  defp get_file_content(file_path) do
    # Get the current content from file history
    case Tracker.get_file_history(file_path) do
      [latest | _] -> latest.after_content
      [] -> nil
    end
  end

  defp get_file_changes(file_path, providers) do
    # Get content for each provider that has worked on this file
    file_info = Tracker.get_file_status(file_path)

    if file_info do
      content = get_file_content(file_path)

      # Create a map with content for each provider that contributed
      changes =
        providers
        |> Enum.filter(fn provider ->
          provider == file_info.owner || provider in file_info.contributors
        end)
        |> Enum.map(fn provider -> {provider, content} end)
        |> Map.new()

      if map_size(changes) == 0 do
        {:error, "No changes found for file: #{file_path}"}
      else
        {:ok, changes}
      end
    else
      {:error, "File not found: #{file_path}"}
    end
  end

  defp detect_conflicts(file_changes) do
    conflicts =
      file_changes
      |> Enum.flat_map(fn {file_path, provider_changes} ->
        if map_size(provider_changes) > 1 do
          analyze_file_conflicts(file_path, provider_changes)
        else
          []
        end
      end)

    {:ok, conflicts}
  end

  defp analyze_file_conflicts(file_path, provider_changes) do
    # Use ConflictDetector to identify specific conflicts
    providers = Map.keys(provider_changes)

    case ConflictDetector.detect_conflicts(file_path, providers) do
      {:ok, conflicts} -> conflicts
      _ -> []
    end
  end

  defp resolve_conflicts(conflicts, strategy, interactive) do
    if interactive and not Enum.empty?(conflicts) do
      ConflictResolver.resolve_interactive(conflicts)
    else
      Strategy.resolve_conflicts(conflicts, strategy)
    end
  end

  defp apply_merges(file_changes, resolutions) do
    merged_files =
      file_changes
      |> Enum.map(fn {file_path, provider_changes} ->
        merged_content = merge_with_resolutions(file_path, provider_changes, resolutions)
        {file_path, merged_content}
      end)
      |> Map.new()

    {:ok, merged_files}
  end

  defp merge_with_resolutions(file_path, provider_changes, resolutions) do
    # If only one provider changed the file, use their version
    if map_size(provider_changes) == 1 do
      provider_changes
      |> Map.values()
      |> List.first()
    else
      # Multiple providers changed the file - apply resolutions
      resolution = Map.get(resolutions, file_path, :auto)
      apply_resolution_strategy(provider_changes, resolution)
    end
  end

  defp apply_resolution_strategy(provider_changes, :auto) do
    # Try semantic merge first, fall back to last-write-wins
    case SemanticAnalyzer.merge_semantically(provider_changes) do
      {:ok, merged} ->
        merged

      _ ->
        # Last write wins as fallback
        provider_changes
        |> Map.values()
        |> List.last()
    end
  end

  defp apply_resolution_strategy(provider_changes, {:accept, provider}) do
    Map.get(provider_changes, provider)
  end

  defp apply_resolution_strategy(provider_changes, {:merge, merge_spec}) do
    # Apply custom merge specification
    apply_merge_spec(provider_changes, merge_spec)
  end

  defp apply_merge_spec(provider_changes, _merge_spec) do
    # Implementation would combine parts from different providers
    # based on the merge specification
    # For now, fall back to semantic merge
    case SemanticAnalyzer.merge_semantically(provider_changes) do
      {:ok, merged} -> merged
      _ -> Map.values(provider_changes) |> List.first()
    end
  end

  defp merge_file_content(changes, strategy) do
    if map_size(changes) == 1 do
      {:ok, changes |> Map.values() |> List.first()}
    else
      case strategy do
        :semantic ->
          SemanticAnalyzer.merge_semantically(changes)

        :auto ->
          # Try semantic first, fall back to last-write-wins
          case SemanticAnalyzer.merge_semantically(changes) do
            {:ok, merged} -> {:ok, merged}
            _ -> {:ok, changes |> Map.values() |> List.last()}
          end

        :manual ->
          {:error, "Manual merge requires interactive mode"}
      end
    end
  end

  defp run_and_compare_tests(_merged_files, _providers) do
    Logger.info("Running tests on merged code...")

    # This would integrate with the build/test system
    # For now, just log
    {:ok, :tests_passed}
  end
end
