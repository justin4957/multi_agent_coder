defmodule MultiAgentCoder.Merge.Parsers.ParserRegistryTest do
  use ExUnit.Case, async: true

  alias MultiAgentCoder.Merge.Parsers.{
    ParserRegistry,
    JavaScriptParser,
    PythonParser,
    GoParser,
    RustParser
  }

  describe "get_parser/1" do
    test "returns JavaScript parser for .js extension" do
      assert {:ok, JavaScriptParser} = ParserRegistry.get_parser(".js")
    end

    test "returns JavaScript parser for .jsx extension" do
      assert {:ok, JavaScriptParser} = ParserRegistry.get_parser(".jsx")
    end

    test "returns JavaScript parser for .ts extension" do
      assert {:ok, JavaScriptParser} = ParserRegistry.get_parser(".ts")
    end

    test "returns JavaScript parser for .tsx extension" do
      assert {:ok, JavaScriptParser} = ParserRegistry.get_parser(".tsx")
    end

    test "returns Python parser for .py extension" do
      assert {:ok, PythonParser} = ParserRegistry.get_parser(".py")
    end

    test "returns Go parser for .go extension" do
      assert {:ok, GoParser} = ParserRegistry.get_parser(".go")
    end

    test "returns Rust parser for .rs extension" do
      assert {:ok, RustParser} = ParserRegistry.get_parser(".rs")
    end

    test "returns error for unsupported extension" do
      assert {:error, :unsupported} = ParserRegistry.get_parser(".xyz")
    end

    test "normalizes extensions without leading dot" do
      assert {:ok, JavaScriptParser} = ParserRegistry.get_parser("js")
      assert {:ok, PythonParser} = ParserRegistry.get_parser("py")
    end
  end

  describe "supported_extensions/0" do
    test "returns all supported extensions" do
      extensions = ParserRegistry.supported_extensions()

      assert ".js" in extensions
      assert ".jsx" in extensions
      assert ".ts" in extensions
      assert ".tsx" in extensions
      assert ".py" in extensions
      assert ".go" in extensions
      assert ".rs" in extensions
    end
  end

  describe "supported?/1" do
    test "returns true for supported extensions" do
      assert ParserRegistry.supported?(".js")
      assert ParserRegistry.supported?(".py")
      assert ParserRegistry.supported?(".go")
      assert ParserRegistry.supported?(".rs")
    end

    test "returns false for unsupported extensions" do
      refute ParserRegistry.supported?(".xyz")
      refute ParserRegistry.supported?(".abc")
    end
  end
end
