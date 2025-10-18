defmodule MultiAgentCoder.Merge.Parsers.ParserBehaviour do
  @moduledoc """
  Behaviour for language-specific code parsers.

  All language parsers must implement this behaviour to ensure consistent
  analysis output across different programming languages.
  """

  @type ast :: any()
  @type function_info :: %{
          required(:name) => String.t(),
          required(:arity) => non_neg_integer(),
          required(:params) => list(String.t()),
          required(:ast) => ast(),
          optional(:private) => boolean(),
          optional(:async) => boolean(),
          optional(:exported) => boolean()
        }

  @type module_info :: %{
          required(:name) => String.t(),
          required(:ast) => ast(),
          optional(:exported) => boolean()
        }

  @type analysis_result :: %{
          functions: list(function_info()),
          modules: list(module_info()),
          imports: list(String.t()),
          dependencies: list(map()),
          side_effects: list(atom()),
          complexity: non_neg_integer()
        }

  @doc """
  Parses the given code content and returns an AST representation.
  """
  @callback parse(content :: String.t()) :: {:ok, ast()} | {:error, String.t()}

  @doc """
  Extracts functions from the parsed AST.
  """
  @callback extract_functions(ast()) :: list(function_info())

  @doc """
  Extracts modules/classes/namespaces from the parsed AST.
  """
  @callback extract_modules(ast()) :: list(module_info())

  @doc """
  Extracts imports/requires/includes from the parsed AST.
  """
  @callback extract_imports(ast()) :: list(String.t())

  @doc """
  Extracts external dependencies and function calls.
  """
  @callback extract_dependencies(ast()) :: list(map())

  @doc """
  Detects operations with side effects (I/O, process operations, etc).
  """
  @callback detect_side_effects(ast()) :: list(atom())

  @doc """
  Calculates cyclomatic complexity for the code.
  """
  @callback calculate_complexity(ast()) :: non_neg_integer()

  @doc """
  Returns the file extensions this parser handles.
  """
  @callback supported_extensions() :: list(String.t())

  @doc """
  Performs full analysis of the code, combining all extraction methods.
  """
  def analyze(parser_module, content) when is_binary(content) do
    case parser_module.parse(content) do
      {:ok, ast} ->
        analysis = %{
          functions: parser_module.extract_functions(ast),
          modules: parser_module.extract_modules(ast),
          imports: parser_module.extract_imports(ast),
          dependencies: parser_module.extract_dependencies(ast),
          side_effects: parser_module.detect_side_effects(ast),
          complexity: parser_module.calculate_complexity(ast)
        }

        {:ok, analysis}

      error ->
        error
    end
  end
end
