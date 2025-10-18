defmodule MultiAgentCoder.Merge.Parsers.ParserRegistry do
  @moduledoc """
  Registry for language-specific parsers.

  Maps file extensions to the appropriate parser module.
  """

  alias MultiAgentCoder.Merge.Parsers.{
    JavaScriptParser,
    PythonParser,
    GoParser,
    RustParser
  }

  @type parser_module :: module()

  @doc """
  Returns the parser module for the given file extension.
  Returns nil if no parser is available for the extension.
  """
  @spec get_parser(String.t()) :: {:ok, parser_module()} | {:error, :unsupported}
  def get_parser(file_extension) when is_binary(file_extension) do
    # Normalize extension to include leading dot
    ext =
      if String.starts_with?(file_extension, ".") do
        file_extension
      else
        "." <> file_extension
      end

    case parser_map()[ext] do
      nil -> {:error, :unsupported}
      parser -> {:ok, parser}
    end
  end

  @doc """
  Returns all supported file extensions.
  """
  @spec supported_extensions() :: list(String.t())
  def supported_extensions do
    Map.keys(parser_map())
  end

  @doc """
  Returns true if the given file extension is supported.
  """
  @spec supported?(String.t()) :: boolean()
  def supported?(file_extension) do
    case get_parser(file_extension) do
      {:ok, _} -> true
      {:error, :unsupported} -> false
    end
  end

  @doc """
  Analyzes code using the appropriate parser for the file type.
  """
  @spec analyze(String.t(), String.t()) :: {:ok, map()} | {:error, String.t()}
  def analyze(content, file_extension) do
    case get_parser(file_extension) do
      {:ok, parser} ->
        MultiAgentCoder.Merge.Parsers.ParserBehaviour.analyze(parser, content)

      {:error, :unsupported} ->
        {:error, "Unsupported file type: #{file_extension}"}
    end
  end

  # Private functions

  defp parser_map do
    %{
      # JavaScript/TypeScript
      ".js" => JavaScriptParser,
      ".jsx" => JavaScriptParser,
      ".ts" => JavaScriptParser,
      ".tsx" => JavaScriptParser,
      ".mjs" => JavaScriptParser,
      ".cjs" => JavaScriptParser,
      # Python
      ".py" => PythonParser,
      ".pyw" => PythonParser,
      # Go
      ".go" => GoParser,
      # Rust
      ".rs" => RustParser
    }
  end
end
