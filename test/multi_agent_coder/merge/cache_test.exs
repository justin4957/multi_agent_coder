defmodule MultiAgentCoder.Merge.CacheTest do
  # Cannot be async since we're sharing a global Cache GenServer
  use ExUnit.Case, async: false

  alias MultiAgentCoder.Merge.Cache

  setup do
    # Cache is already started by application supervisor
    # Just clear it for each test
    Cache.clear()
    :ok
  end

  describe "AST caching" do
    test "caches and retrieves AST successfully" do
      content = "defmodule Test do\n  def hello, do: :world\nend"
      ast = {:defmodule, [], [:Test]}

      # First access should miss
      assert :miss = Cache.get_ast(content)

      # Cache the AST
      :ok = Cache.put_ast(content, ast)

      # Second access should hit
      assert {:ok, ^ast} = Cache.get_ast(content)
    end

    test "different content produces different cache keys" do
      content1 = "defmodule Test1 do\nend"
      content2 = "defmodule Test2 do\nend"
      ast1 = {:defmodule, [], [:Test1]}
      ast2 = {:defmodule, [], [:Test2]}

      Cache.put_ast(content1, ast1)
      Cache.put_ast(content2, ast2)

      assert {:ok, ^ast1} = Cache.get_ast(content1)
      assert {:ok, ^ast2} = Cache.get_ast(content2)
    end

    test "same content produces cache hits" do
      content = "defmodule Test do\nend"
      ast = {:defmodule, [], [:Test]}

      Cache.put_ast(content, ast)

      # Multiple accesses should all hit
      assert {:ok, ^ast} = Cache.get_ast(content)
      assert {:ok, ^ast} = Cache.get_ast(content)
      assert {:ok, ^ast} = Cache.get_ast(content)
    end
  end

  describe "analysis caching" do
    test "caches and retrieves analysis results" do
      content = "defmodule Test do\n  def hello, do: :world\nend"

      analysis = %{
        functions: [:hello],
        modules: [:Test],
        complexity: 1
      }

      assert :miss = Cache.get_analysis(content)

      Cache.put_analysis(content, analysis)

      assert {:ok, ^analysis} = Cache.get_analysis(content)
    end

    test "stores complex analysis structures" do
      content = "complex code here"

      analysis = %{
        functions: [
          %{name: :foo, arity: 2},
          %{name: :bar, arity: 1}
        ],
        modules: [:TestModule],
        imports: [:Logger, :GenServer],
        dependencies: [:crypto, :jason],
        side_effects: [:io_operation, :file_operation],
        complexity: 15
      }

      Cache.put_analysis(content, analysis)

      assert {:ok, ^analysis} = Cache.get_analysis(content)
    end
  end

  describe "TTL and expiration" do
    test "entries expire after TTL" do
      content = "test content"
      ast = {:test, :ast}

      # Cache with very short TTL (1 second)
      Cache.put_ast(content, ast, 1)

      # Should be available immediately
      assert {:ok, ^ast} = Cache.get_ast(content)

      # Wait for expiration
      Process.sleep(1100)

      # Should be expired now
      assert :miss = Cache.get_ast(content)
    end

    test "entries without TTL never expire" do
      content = "test content"
      ast = {:test, :ast}

      Cache.put_ast(content, ast, nil)

      # Should be available after a delay
      Process.sleep(100)
      assert {:ok, ^ast} = Cache.get_ast(content)
    end
  end

  describe "cache management" do
    test "clear removes all entries" do
      content1 = "content 1"
      content2 = "content 2"
      ast1 = {:ast, 1}
      ast2 = {:ast, 2}

      Cache.put_ast(content1, ast1)
      Cache.put_ast(content2, ast2)

      assert {:ok, ^ast1} = Cache.get_ast(content1)
      assert {:ok, ^ast2} = Cache.get_ast(content2)

      Cache.clear()

      assert :miss = Cache.get_ast(content1)
      assert :miss = Cache.get_ast(content2)
    end

    test "size returns number of entries" do
      assert 0 = Cache.size()

      Cache.put_ast("content1", {:ast, 1})
      assert Cache.size() >= 1

      Cache.put_ast("content2", {:ast, 2})
      assert Cache.size() >= 2

      Cache.clear()
      assert 0 = Cache.size()
    end
  end

  describe "statistics" do
    test "tracks hits and misses" do
      content = "test content"
      ast = {:test, :ast}

      # Initial miss
      Cache.get_ast(content)
      stats = Cache.stats()
      assert stats.misses >= 1

      # Cache it
      Cache.put_ast(content, ast)

      # Now hit
      Cache.get_ast(content)
      Cache.get_ast(content)

      stats = Cache.stats()
      assert stats.hits >= 2
    end

    test "calculates hit rate" do
      Cache.clear()

      content = "test content"
      ast = {:test, :ast}

      # Miss
      Cache.get_ast(content)

      # Cache and hit twice
      Cache.put_ast(content, ast)
      Cache.get_ast(content)
      Cache.get_ast(content)

      stats = Cache.stats()
      hit_rate = Cache.Stats.hit_rate(stats)

      # Should be around 66.67% (2 hits out of 3 total accesses)
      assert hit_rate > 50.0
      assert hit_rate < 100.0
    end
  end

  describe "concurrent access" do
    test "handles concurrent reads and writes" do
      content = "concurrent test"
      ast = {:concurrent, :ast}

      Cache.put_ast(content, ast)

      # Spawn multiple processes reading concurrently
      tasks =
        for _i <- 1..100 do
          Task.async(fn ->
            assert {:ok, ^ast} = Cache.get_ast(content)
          end)
        end

      # All should succeed
      Enum.each(tasks, &Task.await/1)
    end

    test "handles concurrent writes to different keys" do
      tasks =
        for i <- 1..50 do
          Task.async(fn ->
            content = "content_#{i}"
            ast = {:ast, i}
            Cache.put_ast(content, ast)
            assert {:ok, ^ast} = Cache.get_ast(content)
          end)
        end

      Enum.each(tasks, &Task.await/1)
    end
  end

  describe "memory efficiency" do
    test "handles large content without issues" do
      # Create a large content string (1MB)
      large_content = String.duplicate("a", 1024 * 1024)
      ast = {:large, :ast}

      Cache.put_ast(large_content, ast)
      assert {:ok, ^ast} = Cache.get_ast(large_content)
    end

    test "caches multiple large entries" do
      entries =
        for i <- 1..10 do
          content = String.duplicate("content_#{i}", 10_000)
          ast = {:ast, i}
          {content, ast}
        end

      # Cache all entries
      Enum.each(entries, fn {content, ast} ->
        Cache.put_ast(content, ast)
      end)

      # Verify all can be retrieved
      Enum.each(entries, fn {content, ast} ->
        assert {:ok, ^ast} = Cache.get_ast(content)
      end)
    end
  end
end
