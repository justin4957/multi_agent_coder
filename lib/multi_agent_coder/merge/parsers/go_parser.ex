defmodule MultiAgentCoder.Merge.Parsers.GoParser do
  @moduledoc """
  Parser for Go code.

  Uses Go's built-in go/parser and go/ast packages to parse Go code
  and extract semantic information for intelligent merging.
  """

  @behaviour MultiAgentCoder.Merge.Parsers.ParserBehaviour

  require Logger

  @parser_script_path Path.join([__DIR__, "scripts", "go_parser.go"])

  @impl true
  def parse(content) do
    case call_go_parser(content) do
      {:ok, parsed_data} ->
        {:ok, parsed_data}

      {:error, reason} ->
        Logger.warning("Go parsing failed: #{reason}")
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
    structs = Map.get(ast, "structs", [])
    interfaces = Map.get(ast, "interfaces", [])

    (structs ++ interfaces)
    |> Enum.map(&normalize_type/1)
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
    [".go"]
  end

  # Private functions

  defp call_go_parser(content) do
    # Create a temporary file for the content
    temp_file =
      Path.join(System.tmp_dir!(), "go_parse_#{:erlang.unique_integer([:positive])}.go")

    try do
      File.write!(temp_file, content)

      # First, try to compile the parser if it doesn't exist
      compiled_parser = @parser_script_path <> ".bin"

      unless File.exists?(compiled_parser) do
        case System.cmd("go", ["build", "-o", compiled_parser, @parser_script_path],
               stderr_to_stdout: true
             ) do
          {_, 0} -> :ok
          {error, _} -> Logger.warning("Failed to compile Go parser: #{error}")
        end
      end

      # Run the parser
      parser_cmd =
        if File.exists?(compiled_parser),
          do: compiled_parser,
          else: "go run " <> @parser_script_path

      {cmd, args} =
        if File.exists?(compiled_parser) do
          {compiled_parser, [temp_file]}
        else
          {"go", ["run", @parser_script_path, temp_file]}
        end

      case System.cmd(cmd, args, stderr_to_stdout: true) do
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
      exported: Map.get(func_data, "exported", false),
      receiver: Map.get(func_data, "receiver")
    }
  end

  defp normalize_type(type_data) when is_map(type_data) do
    %{
      name: Map.get(type_data, "name", "unknown"),
      ast: type_data,
      exported: Map.get(type_data, "exported", false),
      kind: Map.get(type_data, "kind", "unknown")
    }
  end

  defp normalize_dependency(dep_data) when is_map(dep_data) do
    %{
      function: Map.get(dep_data, "function"),
      package: Map.get(dep_data, "package")
    }
  end
end
