defmodule MultiAgentCoder.Merge.ConflictResolver do
  @moduledoc """
  Interactive and automated conflict resolution for code merges.

  Provides both interactive UI for manual resolution and automated
  resolution based on configurable rules and patterns.
  """

  alias MultiAgentCoder.FileOps.ConflictDetector
  alias MultiAgentCoder.Merge.SemanticAnalyzer
  alias MultiAgentCoder.Merge.Strategy

  require Logger

  @type resolution :: {:accept, atom()} | {:merge, map()} | {:custom, String.t()}
  @type resolution_map :: %{String.t() => resolution()}

  @doc """
  Resolves conflicts interactively with user input.
  """
  @spec resolve_interactive(list(ConflictDetector.conflict())) ::
          {:ok, resolution_map()} | {:error, String.t()}
  def resolve_interactive(conflicts) do
    IO.puts("\n🔀 Interactive Conflict Resolution")
    IO.puts("=" <> String.duplicate("=", 39))
    IO.puts("Found #{length(conflicts)} conflict(s) to resolve\n")

    resolutions =
      conflicts
      |> Enum.with_index(1)
      |> Enum.map(fn {conflict, index} ->
        IO.puts("\n📍 Conflict #{index} of #{length(conflicts)}")
        resolution = resolve_single_interactive(conflict)
        {conflict.file, resolution}
      end)
      |> Map.new()

    IO.puts("\n✅ All conflicts resolved")
    {:ok, resolutions}
  end

  @doc """
  Automatically resolves conflicts based on rules and patterns.
  """
  @spec resolve_automatic(list(ConflictDetector.conflict()), keyword()) :: {:ok, resolution_map()}
  def resolve_automatic(conflicts, opts \\ []) do
    rules = Keyword.get(opts, :rules, default_rules())

    resolutions =
      conflicts
      |> Enum.map(fn conflict ->
        resolution = apply_resolution_rules(conflict, rules)
        {conflict.file, resolution}
      end)
      |> Map.new()

    {:ok, resolutions}
  end

  @doc """
  Displays a conflict and available resolution options.
  """
  @spec show_conflict(ConflictDetector.conflict()) :: :ok
  def show_conflict(conflict) do
    IO.puts("\n📄 File: #{conflict.file}")
    IO.puts("   Type: #{format_conflict_type(conflict.type)}")
    IO.puts("   Providers: #{Enum.join(conflict.providers, ", ")}")

    case conflict.details do
      %{line_ranges: ranges} ->
        IO.puts("   Line ranges:")

        Enum.each(ranges, fn {provider, {start_line, end_line}} ->
          IO.puts("     • #{provider}: lines #{start_line}-#{end_line}")
        end)

      %{description: desc} ->
        IO.puts("   Details: #{desc}")

      _ ->
        :ok
    end

    :ok
  end

  @doc """
  Previews what a resolution would produce.
  """
  @spec preview_resolution(ConflictDetector.conflict(), resolution()) ::
          {:ok, String.t()} | {:error, String.t()}
  def preview_resolution(conflict, resolution) do
    case resolution do
      {:accept, provider} ->
        get_provider_content(conflict, provider)

      {:merge, merge_spec} ->
        apply_merge_spec(conflict, merge_spec)

      {:custom, content} ->
        {:ok, content}

      _ ->
        {:error, "Unknown resolution type"}
    end
  end

  @doc """
  Creates conflict markers in the traditional Git style.
  """
  @spec create_conflict_markers(map(), String.t()) :: String.t()
  def create_conflict_markers(provider_contents, base_file \\ nil) do
    providers = Map.keys(provider_contents)

    sections =
      providers
      |> Enum.map(fn provider ->
        content = Map.get(provider_contents, provider)

        """
        <<<<<<< #{provider}
        #{content}
        =======
        """
      end)

    base_section =
      if base_file do
        """
        ||||||| base
        #{base_file}
        =======
        """
      else
        ""
      end

    sections
    |> Enum.join()
    |> Kernel.<>(base_section)
    |> Kernel.<>(">>>>>>> end\n")
  end

  # Private functions

  defp resolve_single_interactive(conflict) do
    show_conflict(conflict)
    show_conflict_contents(conflict)

    IO.puts("\n🔧 Resolution Options:")
    IO.puts("  1. Accept provider version")
    IO.puts("  2. Merge semantically")
    IO.puts("  3. Merge with custom strategy")
    IO.puts("  4. Edit manually")
    IO.puts("  5. Skip (mark for later)")
    IO.puts("  6. View side-by-side diff")

    case IO.gets("\nChoose option [1-6]: ") |> String.trim() do
      "1" ->
        choose_provider(conflict)

      "2" ->
        {:merge, :semantic}

      "3" ->
        choose_merge_strategy(conflict)

      "4" ->
        edit_manually(conflict)

      "5" ->
        {:skip, conflict}

      "6" ->
        show_side_by_side_diff(conflict)
        resolve_single_interactive(conflict)

      _ ->
        IO.puts("❌ Invalid option, please try again")
        resolve_single_interactive(conflict)
    end
  end

  defp show_conflict_contents(conflict) do
    case conflict.details do
      %{contents: contents} when is_map(contents) ->
        IO.puts("\n📝 Conflicting Content:")

        Enum.each(contents, fn {provider, content} ->
          IO.puts("\n--- #{provider} ---")

          # Show first 10 lines of content
          lines = String.split(content, "\n") |> Enum.take(10)
          Enum.each(lines, &IO.puts("    #{&1}"))

          if length(String.split(content, "\n")) > 10 do
            IO.puts("    ... (#{length(String.split(content, "\n")) - 10} more lines)")
          end
        end)

      _ ->
        :ok
    end
  end

  defp choose_provider(conflict) do
    IO.puts("\n📦 Available Providers:")

    providers = conflict.providers

    providers
    |> Enum.with_index(1)
    |> Enum.each(fn {provider, index} ->
      IO.puts("  #{index}. #{provider}")
    end)

    case IO.gets("\nChoose provider [1-#{length(providers)}]: ") |> String.trim() do
      input ->
        case Integer.parse(input) do
          {index, ""} when index > 0 and index <= length(providers) ->
            provider = Enum.at(providers, index - 1)
            {:accept, provider}

          _ ->
            IO.puts("❌ Invalid selection")
            choose_provider(conflict)
        end
    end
  end

  defp choose_merge_strategy(conflict) do
    IO.puts("\n🔀 Merge Strategies:")
    IO.puts("  1. Union (combine all changes)")
    IO.puts("  2. Intersection (common changes only)")
    IO.puts("  3. Three-way merge")
    IO.puts("  4. Line-by-line selection")

    case IO.gets("\nChoose strategy [1-4]: ") |> String.trim() do
      "1" ->
        {:merge, %{strategy: :union}}

      "2" ->
        {:merge, %{strategy: :intersection}}

      "3" ->
        {:merge, %{strategy: :three_way}}

      "4" ->
        line_by_line_merge(conflict)

      _ ->
        IO.puts("❌ Invalid strategy")
        choose_merge_strategy(conflict)
    end
  end

  defp edit_manually(conflict) do
    # In a real implementation, this would open an editor
    IO.puts("\n✏️  Manual Edit Mode")
    IO.puts("Enter your custom resolution (end with '.' on a new line):")

    lines = read_until_dot()
    content = Enum.join(lines, "\n")

    {:custom, content}
  end

  defp read_until_dot(lines \\ []) do
    case IO.gets("") |> String.trim() do
      "." ->
        Enum.reverse(lines)

      line ->
        read_until_dot([line | lines])
    end
  end

  defp show_side_by_side_diff(conflict) do
    case conflict.details do
      %{contents: contents} when is_map(contents) ->
        providers = Map.keys(contents) |> Enum.take(2)

        if length(providers) >= 2 do
          [p1, p2] = providers
          content1 = Map.get(contents, p1) |> String.split("\n")
          content2 = Map.get(contents, p2) |> String.split("\n")

          IO.puts("\n📊 Side-by-Side Diff")
          IO.puts(String.duplicate("=", 80))
          IO.puts("#{String.pad_trailing(to_string(p1), 38)} | #{p2}")
          IO.puts(String.duplicate("-", 80))

          max_lines = max(length(content1), length(content2))

          0..(max_lines - 1)
          |> Enum.each(fn i ->
            line1 = Enum.at(content1, i, "") |> String.slice(0, 37)
            line2 = Enum.at(content2, i, "")

            marker =
              cond do
                Enum.at(content1, i) != Enum.at(content2, i) -> "≠"
                true -> " "
              end

            IO.puts("#{String.pad_trailing(line1, 37)} #{marker}| #{line2}")
          end)
        else
          IO.puts("Not enough providers for side-by-side diff")
        end

      _ ->
        IO.puts("No content available for diff")
    end
  end

  defp line_by_line_merge(conflict) do
    case conflict.details do
      %{contents: contents} when is_map(contents) ->
        # Implement line-by-line selection
        # This is simplified - real implementation would be more sophisticated
        IO.puts("\n📝 Line-by-Line Merge")
        IO.puts("Feature not fully implemented - using semantic merge instead")
        {:merge, :semantic}

      _ ->
        {:merge, :semantic}
    end
  end

  defp get_provider_content(conflict, provider) do
    case conflict.details do
      %{contents: contents} ->
        case Map.get(contents, provider) do
          nil -> {:error, "Provider content not found"}
          content -> {:ok, content}
        end

      _ ->
        {:error, "No content available"}
    end
  end

  defp apply_merge_spec(conflict, :semantic) do
    case conflict.details do
      %{contents: contents} when is_map(contents) ->
        SemanticAnalyzer.merge_semantically(contents)

      _ ->
        {:error, "No content available for semantic merge"}
    end
  end

  defp apply_merge_spec(conflict, %{strategy: strategy}) do
    case conflict.details do
      %{contents: contents} when is_map(contents) ->
        Strategy.apply_strategy(contents, strategy)

      _ ->
        {:error, "No content available for merge"}
    end
  end

  defp apply_merge_spec(_conflict, _spec) do
    {:error, "Unknown merge specification"}
  end

  defp format_conflict_type(:file_level), do: "File-level conflict"
  defp format_conflict_type(:line_level), do: "Line-level conflict"
  defp format_conflict_type(:addition), do: "New file addition"
  defp format_conflict_type(type), do: to_string(type)

  defp default_rules() do
    [
      # Accept additions from any provider
      %{
        pattern: %{type: :addition},
        resolution: :accept_any
      },

      # Merge non-overlapping changes
      %{
        pattern: %{type: :line_level, overlapping: false},
        resolution: :merge_union
      },

      # Semantic merge for function changes
      %{
        pattern: %{scope: :function},
        resolution: :merge_semantic
      },

      # Last write wins for configuration files
      %{
        pattern: %{file_pattern: ~r/\.(json|yaml|toml|config)$/},
        resolution: :last_write_wins
      }
    ]
  end

  defp apply_resolution_rules(conflict, rules) do
    matching_rule =
      Enum.find(rules, fn rule ->
        matches_pattern?(conflict, rule.pattern)
      end)

    if matching_rule do
      apply_rule_resolution(conflict, matching_rule.resolution)
    else
      # Default to semantic merge
      {:merge, :semantic}
    end
  end

  defp matches_pattern?(conflict, pattern) do
    Enum.all?(pattern, fn {key, expected} ->
      case key do
        :type ->
          conflict.type == expected

        :file_pattern ->
          Regex.match?(expected, conflict.file)

        :overlapping ->
          case conflict.details do
            %{overlapping: actual} -> actual == expected
            _ -> false
          end

        :scope ->
          case conflict.details do
            %{scope: actual} -> actual == expected
            _ -> false
          end

        _ ->
          false
      end
    end)
  end

  defp apply_rule_resolution(conflict, :accept_any) do
    {:accept, List.first(conflict.providers)}
  end

  defp apply_rule_resolution(_conflict, :merge_union) do
    {:merge, %{strategy: :union}}
  end

  defp apply_rule_resolution(_conflict, :merge_semantic) do
    {:merge, :semantic}
  end

  defp apply_rule_resolution(conflict, :last_write_wins) do
    {:accept, List.last(conflict.providers)}
  end

  defp apply_rule_resolution(_conflict, resolution) do
    {:merge, resolution}
  end
end
