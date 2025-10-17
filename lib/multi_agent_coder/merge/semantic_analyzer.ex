defmodule MultiAgentCoder.Merge.SemanticAnalyzer do
  @moduledoc """
  Performs semantic analysis of code to enable intelligent merging.

  This module understands code structure and semantics to:
  - Identify functionally equivalent code
  - Detect non-conflicting parallel changes
  - Merge complementary implementations
  - Preserve code intent across different implementations
  """

  require Logger

  @type code_ast :: any()
  @type analysis_result :: {:ok, map()} | {:error, String.t()}

  @doc """
  Analyzes code semantically to understand its structure and intent.
  """
  @spec analyze_code(String.t(), String.t()) :: analysis_result()
  def analyze_code(content, file_type \\ ".ex") do
    case parse_code(content, file_type) do
      {:ok, ast} ->
        analysis = %{
          functions: extract_functions(ast),
          modules: extract_modules(ast),
          imports: extract_imports(ast),
          dependencies: extract_dependencies(ast),
          side_effects: detect_side_effects(ast),
          complexity: calculate_complexity(ast)
        }

        {:ok, analysis}

      error ->
        error
    end
  end

  @doc """
  Merges multiple code versions semantically.

  This attempts to combine code from different providers by understanding
  the semantic meaning and structure rather than just text differences.
  """
  @spec merge_semantically(map()) :: {:ok, String.t()} | {:error, String.t()}
  def merge_semantically(provider_changes) when is_map(provider_changes) do
    Logger.info("Performing semantic merge for #{map_size(provider_changes)} providers")

    with {:ok, analyzed} <- analyze_all_versions(provider_changes),
         {:ok, merged_ast} <- merge_asts(analyzed),
         {:ok, code} <- generate_code(merged_ast) do
      {:ok, code}
    else
      error ->
        Logger.warning("Semantic merge failed, falling back to text merge: #{inspect(error)}")
        fallback_text_merge(provider_changes)
    end
  end

  @doc """
  Determines if two code snippets are semantically equivalent.
  """
  @spec semantically_equivalent?(String.t(), String.t()) :: boolean()
  def semantically_equivalent?(code1, code2) do
    with {:ok, ast1} <- parse_code(code1, ".ex"),
         {:ok, ast2} <- parse_code(code2, ".ex") do
      normalize_ast(ast1) == normalize_ast(ast2)
    else
      _ -> false
    end
  end

  @doc """
  Identifies complementary changes that can be safely merged.
  """
  @spec find_complementary_changes(map()) :: {:ok, list()} | {:error, String.t()}
  def find_complementary_changes(provider_changes) do
    analyzed = analyze_all_versions(provider_changes)

    case analyzed do
      {:ok, versions} ->
        complementary = identify_complementary_parts(versions)
        {:ok, complementary}

      error ->
        error
    end
  end

  # Private functions

  defp parse_code(content, ".ex") do
    case Code.string_to_quoted(content) do
      {:ok, ast} -> {:ok, ast}
      {:error, {line, error, _}} -> {:error, "Parse error at line #{line}: #{error}"}
    end
  end

  defp parse_code(content, file_type) do
    # For non-Elixir files, use appropriate parsers
    # This would integrate with language-specific parsers
    {:ok, {:raw, content, file_type}}
  end

  defp analyze_all_versions(provider_changes) do
    analyzed =
      provider_changes
      |> Enum.map(fn {provider, content} ->
        case analyze_code(content) do
          {:ok, analysis} -> {provider, analysis}
          _ -> {provider, nil}
        end
      end)
      |> Enum.reject(fn {_, analysis} -> is_nil(analysis) end)
      |> Map.new()

    if map_size(analyzed) == 0 do
      {:error, "No valid code to analyze"}
    else
      {:ok, analyzed}
    end
  end

  defp merge_asts(analyzed_versions) do
    # Extract all unique functions, modules, etc from all versions
    merged = %{
      functions: merge_functions(analyzed_versions),
      modules: merge_modules(analyzed_versions),
      imports: merge_imports(analyzed_versions)
    }

    # Convert back to AST
    reconstruct_ast(merged)
  end

  defp merge_functions(versions) do
    versions
    |> Enum.flat_map(fn {_provider, analysis} ->
      Map.get(analysis, :functions, [])
    end)
    |> Enum.uniq_by(&function_signature/1)
    |> resolve_function_conflicts()
  end

  defp merge_modules(versions) do
    versions
    |> Enum.flat_map(fn {_provider, analysis} ->
      Map.get(analysis, :modules, [])
    end)
    |> Enum.uniq_by(&module_name/1)
    |> resolve_module_conflicts()
  end

  defp merge_imports(versions) do
    versions
    |> Enum.flat_map(fn {_provider, analysis} ->
      Map.get(analysis, :imports, [])
    end)
    |> Enum.uniq()
  end

  defp extract_functions(ast) do
    # Walk the AST and extract function definitions
    functions = []

    Macro.prewalk(ast, functions, fn
      {:def, _meta, [{name, _, args} | _body]} = node, acc ->
        function_info = %{
          name: name,
          arity: length(args || []),
          ast: node
        }

        {node, [function_info | acc]}

      {:defp, _meta, [{name, _, args} | _body]} = node, acc ->
        function_info = %{
          name: name,
          arity: length(args || []),
          private: true,
          ast: node
        }

        {node, [function_info | acc]}

      node, acc ->
        {node, acc}
    end)
    |> elem(1)
    |> Enum.reverse()
  end

  defp extract_modules(ast) do
    modules = []

    Macro.prewalk(ast, modules, fn
      {:defmodule, _meta, [{:__aliases__, _, module_parts} | _body]} = node, acc ->
        module_info = %{
          name: Module.concat(module_parts),
          ast: node
        }

        {node, [module_info | acc]}

      node, acc ->
        {node, acc}
    end)
    |> elem(1)
    |> Enum.reverse()
  end

  defp extract_imports(ast) do
    imports = []

    Macro.prewalk(ast, imports, fn
      {:import, _meta, [module | _opts]} = node, acc ->
        {node, [module | acc]}

      {:use, _meta, [module | _opts]} = node, acc ->
        {node, [module | acc]}

      {:alias, _meta, [module | _opts]} = node, acc ->
        {node, [module | acc]}

      node, acc ->
        {node, acc}
    end)
    |> elem(1)
    |> Enum.reverse()
    |> Enum.uniq()
  end

  defp extract_dependencies(ast) do
    # Extract external dependencies and function calls
    deps = []

    Macro.prewalk(ast, deps, fn
      {{:., _, [module, function]}, _, args} = node, acc when is_list(args) ->
        dep = %{module: module, function: function, arity: length(args)}
        {node, [dep | acc]}

      node, acc ->
        {node, acc}
    end)
    |> elem(1)
    |> Enum.reverse()
    |> Enum.uniq()
  end

  defp detect_side_effects(ast) do
    # Identify operations with side effects
    side_effects = []

    Macro.prewalk(ast, side_effects, fn
      {:send, _, _} = node, acc ->
        {node, [:message_passing | acc]}

      {{:., _, [Process, _]}, _, _} = node, acc ->
        {node, [:process_operation | acc]}

      {{:., _, [GenServer, _]}, _, _} = node, acc ->
        {node, [:genserver_call | acc]}

      {{:., _, [File, _]}, _, _} = node, acc ->
        {node, [:file_operation | acc]}

      {{:., _, [IO, _]}, _, _} = node, acc ->
        {node, [:io_operation | acc]}

      node, acc ->
        {node, acc}
    end)
    |> elem(1)
    |> Enum.uniq()
  end

  defp calculate_complexity(ast) do
    # Calculate cyclomatic complexity
    complexity = 1

    Macro.prewalk(ast, complexity, fn
      {:if, _, _} = node, acc ->
        {node, acc + 1}

      {:case, _, _} = node, acc ->
        {node, acc + count_case_clauses(node) - 1}

      {:cond, _, _} = node, acc ->
        {node, acc + count_cond_clauses(node) - 1}

      node, acc ->
        {node, acc}
    end)
    |> elem(1)
  end

  defp count_case_clauses({:case, _, [_, [do: clauses]]}) when is_list(clauses) do
    length(clauses)
  end

  defp count_case_clauses(_), do: 0

  defp count_cond_clauses({:cond, _, [[do: clauses]]}) when is_list(clauses) do
    length(clauses)
  end

  defp count_cond_clauses(_), do: 0

  defp normalize_ast(ast) do
    # Remove metadata and normalize for comparison
    Macro.prewalk(ast, fn
      {op, _meta, args} -> {op, [], args}
      node -> node
    end)
  end

  defp function_signature(%{name: name, arity: arity}) do
    {name, arity}
  end

  defp module_name(%{name: name}) do
    name
  end

  defp resolve_function_conflicts(functions) do
    # Group by signature and resolve conflicts
    functions
    |> Enum.group_by(&function_signature/1)
    |> Enum.map(fn {_sig, implementations} ->
      # If multiple implementations, choose the most complete/complex one
      Enum.max_by(implementations, fn impl ->
        calculate_complexity(Map.get(impl, :ast, nil))
      end)
    end)
  end

  defp resolve_module_conflicts(modules) do
    # Similar to function conflicts
    modules
    |> Enum.group_by(&module_name/1)
    |> Enum.map(fn {_name, implementations} ->
      # Merge module contents
      # TODO: Properly merge module contents
      List.first(implementations)
    end)
  end

  defp reconstruct_ast(merged_components) do
    # Rebuild the AST from merged components
    functions = Map.get(merged_components, :functions, [])
    imports = Map.get(merged_components, :imports, [])

    # Build a simple module structure
    module_body =
      imports
      |> Enum.map(fn import_spec ->
        {:import, [], [import_spec]}
      end)
      |> Enum.concat(Enum.map(functions, &Map.get(&1, :ast)))

    # Return as a quoted expression
    ast = {:__block__, [], module_body}
    {:ok, ast}
  end

  defp generate_code(ast) do
    # Convert AST back to Elixir code
    try do
      code = Macro.to_string(ast)
      {:ok, format_code(code)}
    rescue
      error ->
        {:error, "Failed to generate code: #{inspect(error)}"}
    end
  end

  defp format_code(code) do
    # Format the generated code
    case Code.format_string!(code) do
      formatted when is_list(formatted) ->
        IO.iodata_to_binary(formatted)

      formatted ->
        formatted
    end
  rescue
    _ -> code
  end

  defp fallback_text_merge(provider_changes) do
    # Simple text-based merge as fallback
    # Concatenate all changes with conflict markers
    merged =
      provider_changes
      |> Enum.map(fn {provider, content} ->
        """
        # <<<<<<< #{provider}
        #{content}
        # >>>>>>> #{provider}
        """
      end)
      |> Enum.join("\n")

    {:ok, merged}
  end

  defp identify_complementary_parts(analyzed_versions) do
    # Find parts that don't conflict and can be combined
    all_functions =
      analyzed_versions
      |> Enum.flat_map(fn {provider, analysis} ->
        functions = Map.get(analysis, :functions, [])
        Enum.map(functions, &{&1, provider})
      end)

    # Group by signature to find unique additions
    complementary =
      all_functions
      |> Enum.group_by(fn {func, _provider} -> function_signature(func) end)
      |> Enum.filter(fn {_sig, implementations} -> length(implementations) == 1 end)
      |> Enum.map(fn {_sig, [{func, provider}]} ->
        %{function: func, provider: provider, type: :unique_addition}
      end)

    complementary
  end
end
