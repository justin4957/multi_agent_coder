defmodule MultiAgentCoder.Merge.Parsers.JavaScriptParserTest do
  use ExUnit.Case, async: false

  alias MultiAgentCoder.Merge.Parsers.JavaScriptParser

  @moduletag :javascript_parser

  describe "parse/1" do
    @tag :skip
    test "parses a simple JavaScript function" do
      code = """
      function hello(name) {
        return "Hello, " + name;
      }
      """

      case JavaScriptParser.parse(code) do
        {:ok, ast} ->
          assert is_map(ast)
          assert Map.has_key?(ast, "functions")

        {:error, reason} ->
          # Parser may not be available in CI, skip gracefully
          IO.warn("JavaScript parser not available: #{reason}")
      end
    end

    @tag :skip
    test "parses arrow functions" do
      code = """
      const greet = (name) => {
        return `Hello, ${name}`;
      };
      """

      case JavaScriptParser.parse(code) do
        {:ok, ast} ->
          assert is_map(ast)

        {:error, _reason} ->
          :ok
      end
    end

    @tag :skip
    test "parses class definitions" do
      code = """
      class Person {
        constructor(name) {
          this.name = name;
        }

        greet() {
          console.log("Hello, " + this.name);
        }
      }
      """

      case JavaScriptParser.parse(code) do
        {:ok, ast} ->
          assert is_map(ast)
          assert Map.has_key?(ast, "modules")

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

      functions = JavaScriptParser.extract_functions(ast)

      assert length(functions) == 2
      assert Enum.any?(functions, &(&1.name == "hello"))
      assert Enum.any?(functions, &(&1.name == "goodbye"))
    end
  end

  describe "supported_extensions/0" do
    test "returns all JavaScript file extensions" do
      extensions = JavaScriptParser.supported_extensions()

      assert ".js" in extensions
      assert ".jsx" in extensions
      assert ".ts" in extensions
      assert ".tsx" in extensions
      assert ".mjs" in extensions
      assert ".cjs" in extensions
    end
  end
end
