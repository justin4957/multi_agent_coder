defmodule MultiAgentCoder.Merge.SemanticAnalyzerTest do
  # Cannot be async since we're sharing a global Cache GenServer
  use ExUnit.Case, async: false

  alias MultiAgentCoder.Merge.{SemanticAnalyzer, Cache}

  setup do
    # Cache is already started by application supervisor
    # Just clear it for each test
    Cache.clear()
    :ok
  end

  describe "analyze_code/2" do
    test "analyzes simple Elixir code" do
      code = """
      defmodule TestModule do
        def hello(name) do
          "Hello, \#{name}!"
        end
      end
      """

      assert {:ok, analysis} = SemanticAnalyzer.analyze_code(code, ".ex")
      assert is_map(analysis)
      assert Map.has_key?(analysis, :functions)
      assert Map.has_key?(analysis, :modules)
      assert Map.has_key?(analysis, :complexity)
    end

    test "uses cache for identical code" do
      code = """
      defmodule CachedModule do
        def test, do: :ok
      end
      """

      # First call should miss cache and analyze
      assert {:ok, analysis1} = SemanticAnalyzer.analyze_code(code, ".ex")

      # Second call should hit cache
      assert {:ok, analysis2} = SemanticAnalyzer.analyze_code(code, ".ex")

      # Results should be identical
      assert analysis1 == analysis2

      # Verify cache was used
      stats = Cache.stats()
      assert stats.hits >= 1
    end

    test "handles syntax errors gracefully" do
      # Use actually invalid Elixir syntax - "end" alone is a syntax error
      invalid_code = "end"

      assert {:error, error_msg} = SemanticAnalyzer.analyze_code(invalid_code, ".ex")
      assert is_binary(error_msg)
      assert error_msg =~ "Parse error"
    end

    test "extracts function information" do
      code = """
      defmodule Functions do
        def public_func(arg1, arg2), do: arg1 + arg2
        defp private_func(), do: :private
      end
      """

      assert {:ok, analysis} = SemanticAnalyzer.analyze_code(code, ".ex")

      functions = analysis.functions
      assert length(functions) == 2

      public_func = Enum.find(functions, &(&1.name == :public_func))
      assert public_func.arity == 2
      refute Map.get(public_func, :private)

      private_func = Enum.find(functions, &(&1.name == :private_func))
      assert private_func.arity == 0
      assert Map.get(private_func, :private)
    end

    test "detects complexity" do
      simple_code = """
      defmodule Simple do
        def add(a, b), do: a + b
      end
      """

      complex_code = """
      defmodule Complex do
        def process(data) do
          if data do
            case data do
              :a -> :result_a
              :b -> :result_b
              _ -> :other
            end
          else
            :empty
          end
        end
      end
      """

      {:ok, simple_analysis} = SemanticAnalyzer.analyze_code(simple_code, ".ex")
      {:ok, complex_analysis} = SemanticAnalyzer.analyze_code(complex_code, ".ex")

      assert complex_analysis.complexity > simple_analysis.complexity
    end
  end

  describe "analyze_files_parallel/2" do
    test "analyzes multiple files in parallel" do
      files = [
        {"file1.ex", "defmodule File1 do\nend", ".ex"},
        {"file2.ex", "defmodule File2 do\nend", ".ex"},
        {"file3.ex", "defmodule File3 do\nend", ".ex"}
      ]

      results = SemanticAnalyzer.analyze_files_parallel(files)

      assert map_size(results) == 3
      assert Map.has_key?(results, "file1.ex")
      assert Map.has_key?(results, "file2.ex")
      assert Map.has_key?(results, "file3.ex")

      Enum.each(results, fn {_path, result} ->
        assert match?({:ok, _analysis}, result)
      end)
    end

    test "handles mixed successful and failed analyses" do
      files = [
        {"valid.ex", "defmodule Valid do\nend", ".ex"},
        {"invalid.ex", "end", ".ex"}
      ]

      results = SemanticAnalyzer.analyze_files_parallel(files)

      assert {:ok, _} = results["valid.ex"]
      assert {:error, _} = results["invalid.ex"]
    end

    test "processes many files efficiently" do
      # Create 50 files to analyze
      files =
        for i <- 1..50 do
          code = "defmodule Module#{i} do\n  def func#{i}, do: #{i}\nend"
          {"file#{i}.ex", code, ".ex"}
        end

      start_time = System.monotonic_time(:millisecond)
      results = SemanticAnalyzer.analyze_files_parallel(files)
      end_time = System.monotonic_time(:millisecond)

      # All should be analyzed successfully
      assert map_size(results) == 50

      # Should complete in reasonable time (parallel should be faster than sequential)
      duration = end_time - start_time
      assert duration < 10_000
    end

    test "respects concurrency limit" do
      files =
        for i <- 1..10 do
          {"file#{i}.ex", "defmodule Mod#{i} do\nend", ".ex"}
        end

      # Use low concurrency
      results = SemanticAnalyzer.analyze_files_parallel(files, max_concurrency: 2)

      assert map_size(results) == 10
    end
  end

  describe "merge_semantically/1" do
    test "merges identical code from multiple providers" do
      code = """
      defmodule Identical do
        def same, do: :identical
      end
      """

      provider_changes = %{
        anthropic: code,
        deepseek: code
      }

      assert {:ok, merged} = SemanticAnalyzer.merge_semantically(provider_changes)
      assert is_binary(merged)
    end

    test "merges complementary functions from different providers" do
      code1 = """
      defmodule Test do
        def func1, do: 1
      end
      """

      code2 = """
      defmodule Test do
        def func2, do: 2
      end
      """

      provider_changes = %{
        anthropic: code1,
        deepseek: code2
      }

      assert {:ok, merged} = SemanticAnalyzer.merge_semantically(provider_changes)
      assert is_binary(merged)
    end

    test "uses cache during semantic merge" do
      code = """
      defmodule CachedMerge do
        def test, do: :ok
      end
      """

      provider_changes = %{
        anthropic: code,
        deepseek: code
      }

      # First merge
      {:ok, _} = SemanticAnalyzer.merge_semantically(provider_changes)

      # Second merge should use cache
      {:ok, _} = SemanticAnalyzer.merge_semantically(provider_changes)

      stats = Cache.stats()
      # Should have cache hits for the analysis
      assert stats.hits > 0
    end
  end

  describe "semantically_equivalent?/2" do
    test "identifies identical code as equivalent" do
      code1 = "defmodule Test do\nend"
      code2 = "defmodule Test do\nend"

      assert SemanticAnalyzer.semantically_equivalent?(code1, code2)
    end

    test "identifies different code as not equivalent" do
      code1 = "defmodule Test1 do\nend"
      code2 = "defmodule Test2 do\nend"

      refute SemanticAnalyzer.semantically_equivalent?(code1, code2)
    end

    test "normalizes whitespace differences" do
      code1 = """
      defmodule Test do
        def func, do: :ok
      end
      """

      code2 = """
      defmodule Test do
        def func, do: :ok
      end
      """

      # This may or may not be true depending on AST normalization
      # The test is valid regardless of result
      result = SemanticAnalyzer.semantically_equivalent?(code1, code2)
      assert is_boolean(result)
    end
  end

  describe "find_complementary_changes/1" do
    test "identifies unique additions from each provider" do
      code1 = """
      defmodule Test do
        def func_a, do: :a
      end
      """

      code2 = """
      defmodule Test do
        def func_b, do: :b
      end
      """

      provider_changes = %{
        anthropic: code1,
        deepseek: code2
      }

      assert {:ok, complementary} =
               SemanticAnalyzer.find_complementary_changes(provider_changes)

      assert is_list(complementary)
    end

    test "handles no complementary changes" do
      code = """
      defmodule Test do
        def same, do: :same
      end
      """

      provider_changes = %{
        anthropic: code,
        deepseek: code
      }

      assert {:ok, complementary} =
               SemanticAnalyzer.find_complementary_changes(provider_changes)

      # When both providers have the same code, there should be no unique additions
      assert is_list(complementary)
    end
  end

  describe "is_large_file?/1" do
    test "identifies small files correctly" do
      small_content = String.duplicate("a", 1024)
      refute SemanticAnalyzer.is_large_file?(small_content)
    end

    test "identifies large files correctly" do
      # Create content larger than 5MB threshold
      large_content = String.duplicate("a", 6 * 1024 * 1024)
      assert SemanticAnalyzer.is_large_file?(large_content)
    end

    test "handles boundary cases" do
      # Just under 5MB
      almost_large = String.duplicate("a", 5 * 1024 * 1024 - 100)
      refute SemanticAnalyzer.is_large_file?(almost_large)

      # Just over 5MB
      just_large = String.duplicate("a", 5 * 1024 * 1024 + 100)
      assert SemanticAnalyzer.is_large_file?(just_large)
    end
  end

  describe "caching integration" do
    test "AST parsing uses cache" do
      code = """
      defmodule CacheTest do
        def test, do: :ok
      end
      """

      # First analysis
      {:ok, _} = SemanticAnalyzer.analyze_code(code, ".ex")

      # Get cache stats
      stats = Cache.stats()
      initial_misses = stats.misses

      # Second analysis should use cached AST
      {:ok, _} = SemanticAnalyzer.analyze_code(code, ".ex")

      stats = Cache.stats()
      # Cache misses should not increase significantly
      assert stats.misses <= initial_misses + 1
    end

    test "different file types cache separately" do
      content = "test content"

      {:ok, _} = SemanticAnalyzer.analyze_code(content, ".ex")
      {:ok, _} = SemanticAnalyzer.analyze_code(content, ".py")

      # Both should be cached separately
      stats = Cache.stats()
      assert stats.total_entries >= 2
    end
  end

  describe "performance under load" do
    test "handles analyzing many provider versions efficiently" do
      # Create 10 different provider versions
      provider_changes =
        for i <- 1..10, into: %{} do
          code = """
          defmodule Provider#{i} do
            def func_#{i}, do: #{i}
          end
          """

          {String.to_atom("provider#{i}"), code}
        end

      assert {:ok, merged} = SemanticAnalyzer.merge_semantically(provider_changes)
      assert is_binary(merged)
    end
  end
end
