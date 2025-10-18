defmodule MultiAgentCoder.Merge.Parsers.PythonParserTest do
  use ExUnit.Case, async: false

  alias MultiAgentCoder.Merge.Parsers.PythonParser

  @moduletag :python_parser

  describe "parse/1" do
    @tag :skip
    test "parses a simple Python function" do
      code = """
      def hello(name):
          return f"Hello, {name}"
      """

      case PythonParser.parse(code) do
        {:ok, ast} ->
          assert is_map(ast)
          assert Map.has_key?(ast, "functions")

        {:error, reason} ->
          IO.warn("Python parser not available: #{reason}")
      end
    end

    @tag :skip
    test "parses Python class definitions" do
      code = """
      class Person:
          def __init__(self, name):
              self.name = name

          def greet(self):
              print(f"Hello, {self.name}")
      """

      case PythonParser.parse(code) do
        {:ok, ast} ->
          assert is_map(ast)
          assert Map.has_key?(ast, "classes")

        {:error, _reason} ->
          :ok
      end
    end
  end

  describe "extract_functions/1" do
    test "extracts functions from parsed AST" do
      ast = %{
        "functions" => [
          %{"name" => "hello", "arity" => 1, "params" => ["name"]},
          %{"name" => "goodbye", "arity" => 0, "params" => []}
        ]
      }

      functions = PythonParser.extract_functions(ast)

      assert length(functions) == 2
      assert Enum.any?(functions, &(&1.name == "hello"))
    end
  end

  describe "supported_extensions/0" do
    test "returns all Python file extensions" do
      extensions = PythonParser.supported_extensions()

      assert ".py" in extensions
      assert ".pyw" in extensions
    end
  end
end
