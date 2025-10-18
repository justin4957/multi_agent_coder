defmodule MultiAgentCoder.Merge.Parsers.PythonParser do
  @moduledoc """
  Parser for Python code.

  Uses Python's built-in ast module to parse Python code
  and extract semantic information for intelligent merging.
  """

  @behaviour MultiAgentCoder.Merge.Parsers.ParserBehaviour

  require Logger

  @parser_script_path Path.join([__DIR__, "scripts", "python_parser.py"])

  @impl true
  def parse(content) do
    case call_python_parser(content) do
      {:ok, parsed_data} ->
        {:ok, parsed_data}

      {:error, reason} ->
        Logger.warning("Python parsing failed: #{reason}")
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
    Map.get(ast, "classes", [])
    |> Enum.map(&normalize_class/1)
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
    Map.get(ast, "side_effects", [])
    |> Enum.map(&String.to_atom/1)
  end

  @impl true
  def calculate_complexity(ast) do
    Map.get(ast, "complexity", 1)
  end

  @impl true
  def supported_extensions do
    [".py", ".pyw"]
  end

  # Private functions

  defp call_python_parser(content) do
    # Create a temporary file for the content
    temp_file =
      Path.join(System.tmp_dir!(), "py_parse_#{:erlang.unique_integer([:positive])}.py")

    try do
      File.write!(temp_file, content)

      case System.cmd("python3", [@parser_script_path, temp_file], stderr_to_stdout: true) do
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
      name: Map.get(func_data, "name", "unknown"),
      arity: Map.get(func_data, "arity", 0),
      params: Map.get(func_data, "params", []),
      ast: func_data,
      async: Map.get(func_data, "is_async", false),
      private: String.starts_with?(Map.get(func_data, "name", ""), "_")
    }
  end

  defp normalize_class(class_data) when is_map(class_data) do
    %{
      name: Map.get(class_data, "name", "unknown"),
      ast: class_data,
      methods: Map.get(class_data, "methods", [])
    }
  end

  defp normalize_dependency(dep_data) when is_map(dep_data) do
    %{
      function: Map.get(dep_data, "function"),
      arity: Map.get(dep_data, "arity", 0)
    }
  end
end
