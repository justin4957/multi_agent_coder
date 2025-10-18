defmodule MultiAgentCoder.Merge.Parsers.JavaScriptParser do
  @moduledoc """
  Parser for JavaScript and TypeScript code.

  Uses Node.js with @babel/parser to parse JavaScript/TypeScript code
  and extract semantic information for intelligent merging.
  """

  @behaviour MultiAgentCoder.Merge.Parsers.ParserBehaviour

  require Logger

  @parser_script_path Path.join([__DIR__, "scripts", "js_parser.mjs"])

  @impl true
  def parse(content) do
    case call_node_parser(content) do
      {:ok, parsed_data} ->
        {:ok, parsed_data}

      {:error, reason} ->
        Logger.warning("JavaScript parsing failed: #{reason}")
        {:error, reason}
    end
  end

  @impl true
  def extract_functions(ast) do
    Map.get(ast, "functions", [])
    |> Enum.map(&normalize_function/1)
  end

  @impl true
  def extract_modules(ast) do
    Map.get(ast, "modules", [])
    |> Enum.map(&normalize_module/1)
  end

  @impl true
  def extract_imports(ast) do
    Map.get(ast, "imports", [])
  end

  @impl true
  def extract_dependencies(ast) do
    Map.get(ast, "dependencies", [])
    |> Enum.map(&normalize_dependency/1)
  end

  @impl true
  def detect_side_effects(ast) do
    Map.get(ast, "sideEffects", [])
    |> Enum.map(&String.to_atom/1)
  end

  @impl true
  def calculate_complexity(ast) do
    Map.get(ast, "complexity", 1)
  end

  @impl true
  def supported_extensions do
    [".js", ".jsx", ".ts", ".tsx", ".mjs", ".cjs"]
  end

  # Private functions

  defp call_node_parser(content) do
    # Create a temporary file for the content
    temp_file = Path.join(System.tmp_dir!(), "js_parse_#{:erlang.unique_integer([:positive])}.js")

    try do
      File.write!(temp_file, content)

      case System.cmd("node", [@parser_script_path, temp_file],
             stderr_to_stdout: true,
             env: [{"NODE_NO_WARNINGS", "1"}]
           ) do
        {output, 0} ->
          case Jason.decode(output) do
            {:ok, parsed} -> {:ok, parsed}
            {:error, _} -> {:error, "Failed to decode parser output"}
          end

        {error_output, _} ->
          {:error, "Parser execution failed: #{error_output}"}
      end
    rescue
      error ->
        {:error, "Parser error: #{inspect(error)}"}
    after
      File.rm(temp_file)
    end
  end

  defp normalize_function(func_data) when is_map(func_data) do
    %{
      name: Map.get(func_data, "name", "anonymous"),
      arity: Map.get(func_data, "arity", 0),
      params: Map.get(func_data, "params", []),
      ast: func_data,
      async: Map.get(func_data, "async", false),
      exported: Map.get(func_data, "exported", false)
    }
  end

  defp normalize_module(module_data) when is_map(module_data) do
    %{
      name: Map.get(module_data, "name", "unknown"),
      ast: module_data,
      exported: Map.get(module_data, "exported", false)
    }
  end

  defp normalize_dependency(dep_data) when is_map(dep_data) do
    %{
      module: Map.get(dep_data, "module"),
      function: Map.get(dep_data, "function"),
      source: Map.get(dep_data, "source")
    }
  end
end
