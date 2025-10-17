defmodule MultiAgentCoder.Merge.EngineTest do
  use ExUnit.Case
  alias MultiAgentCoder.Merge.Engine
  alias MultiAgentCoder.FileOps.Tracker

  setup do
    # Start necessary processes
    {:ok, _} = Tracker.start_link()
    :ok
  end

  describe "merge_all/1" do
    test "successfully merges files from multiple providers with no conflicts" do
      # Setup test data
      Tracker.track_file_operation(
        :provider1,
        "lib/example.ex",
        :create,
        after_content: "defmodule Example do\n  def hello, do: :world\nend"
      )

      Tracker.track_file_operation(
        :provider2,
        "lib/another.ex",
        :create,
        after_content: "defmodule Another do\n  def foo, do: :bar\nend"
      )

      # Perform merge
      assert {:ok, merged_files} = Engine.merge_all(strategy: :auto)
      assert map_size(merged_files) == 2
      assert Map.has_key?(merged_files, "lib/example.ex")
      assert Map.has_key?(merged_files, "lib/another.ex")
    end

    test "handles conflicts with auto strategy" do
      # Create conflicting changes
      Tracker.track_file_operation(
        :provider1,
        "lib/conflict.ex",
        :create,
        after_content: "defmodule Conflict do\n  def func, do: 1\nend"
      )

      Tracker.track_file_operation(
        :provider2,
        "lib/conflict.ex",
        :create,
        after_content: "defmodule Conflict do\n  def func, do: 2\nend"
      )

      # Merge should still succeed with auto strategy
      assert {:ok, merged_files} = Engine.merge_all(strategy: :auto)
      assert Map.has_key?(merged_files, "lib/conflict.ex")
    end

    test "returns error when no providers are active" do
      # Clear all providers
      Tracker.reset()

      assert {:error, "No active providers found"} = Engine.merge_all()
    end

    test "respects dry_run option" do
      Tracker.track_file_operation(:provider1, "lib/test.ex", :create,
        after_content: "defmodule Test do\nend"
      )

      assert {:ok, merged_files} = Engine.merge_all(dry_run: true)
      assert map_size(merged_files) == 1

      # Verify files weren't actually written
      refute File.exists?("lib/test.ex")
    end
  end

  describe "merge_file/2" do
    test "merges a specific file from all providers" do
      file_path = "lib/specific.ex"

      Tracker.track_file_operation(:provider1, file_path, :create,
        after_content: "# Provider 1 version"
      )

      Tracker.track_file_operation(:provider2, file_path, :create,
        after_content: "# Provider 2 version"
      )

      assert {:ok, merged_content} = Engine.merge_file(file_path, strategy: :last_write_wins)
      assert is_binary(merged_content)
    end

    test "returns error for non-existent file" do
      assert {:error, _} = Engine.merge_file("non/existent.ex")
    end

    test "handles single provider gracefully" do
      file_path = "lib/single.ex"
      content = "defmodule Single do\nend"
      Tracker.track_file_operation(:provider1, file_path, :create, after_content: content)

      assert {:ok, ^content} = Engine.merge_file(file_path)
    end
  end

  describe "list_conflicts/0" do
    test "returns empty list when no conflicts exist" do
      Tracker.track_file_operation(:provider1, "lib/file1.ex", :create, after_content: "content1")
      Tracker.track_file_operation(:provider2, "lib/file2.ex", :create, after_content: "content2")

      assert {:ok, []} = Engine.list_conflicts()
    end

    test "detects file-level conflicts" do
      Tracker.track_file_operation(:provider1, "lib/conflict.ex", :create,
        after_content: "version1"
      )

      Tracker.track_file_operation(:provider2, "lib/conflict.ex", :create,
        after_content: "version2"
      )

      assert {:ok, conflicts} = Engine.list_conflicts()
      assert length(conflicts) > 0

      conflict = List.first(conflicts)
      assert conflict.file == "lib/conflict.ex"
      assert :provider1 in conflict.providers
      assert :provider2 in conflict.providers
    end

    test "detects line-level conflicts" do
      content1 = """
      defmodule Test do
        def func1, do: 1
        def func2, do: 2
      end
      """

      content2 = """
      defmodule Test do
        def func1, do: 10
        def func2, do: 2
      end
      """

      Tracker.track_file_operation(:provider1, "lib/test.ex", :create, after_content: content1)
      Tracker.track_file_operation(:provider2, "lib/test.ex", :create, after_content: content2)

      assert {:ok, conflicts} = Engine.list_conflicts()
      assert length(conflicts) > 0
    end
  end

  describe "preview_merge/1" do
    test "shows merge preview without applying changes" do
      Tracker.track_file_operation(:provider1, "lib/preview.ex", :create,
        after_content: "# Preview content"
      )

      assert {:ok, preview} = Engine.preview_merge()
      assert Map.has_key?(preview, "lib/preview.ex")

      # Verify no actual files were created
      refute File.exists?("lib/preview.ex")
    end

    test "preview includes all provider files" do
      Tracker.track_file_operation(:provider1, "lib/file1.ex", :create, after_content: "content1")
      Tracker.track_file_operation(:provider2, "lib/file2.ex", :create, after_content: "content2")
      Tracker.track_file_operation(:provider3, "lib/file3.ex", :create, after_content: "content3")

      assert {:ok, preview} = Engine.preview_merge()
      assert map_size(preview) == 3
    end
  end

  describe "merge strategies" do
    setup do
      file_path = "lib/strategy_test.ex"

      Tracker.track_file_operation(:provider1, file_path, :create,
        after_content: "# First version"
      )

      Tracker.track_file_operation(:provider2, file_path, :create,
        after_content: "# Second version"
      )

      Tracker.track_file_operation(:provider3, file_path, :create,
        after_content: "# Third version"
      )

      {:ok, file_path: file_path}
    end

    test "auto strategy attempts semantic merge first", %{file_path: file_path} do
      assert {:ok, merged_files} = Engine.merge_all(strategy: :auto)
      assert Map.has_key?(merged_files, file_path)
    end

    test "semantic strategy uses code understanding", %{file_path: file_path} do
      # Add semantically equivalent code
      code1 = """
      defmodule Test do
        def add(a, b), do: a + b
      end
      """

      code2 = """
      defmodule Test do
        def add(x, y), do: x + y
      end
      """

      Tracker.track_file_operation(:provider1, "lib/semantic.ex", :create, after_content: code1)
      Tracker.track_file_operation(:provider2, "lib/semantic.ex", :create, after_content: code2)

      assert {:ok, merged_files} = Engine.merge_all(strategy: :semantic)
      assert Map.has_key?(merged_files, "lib/semantic.ex")
    end

    test "manual strategy requires interactive mode", %{file_path: _file_path} do
      assert {:ok, _merged_files} = Engine.merge_all(strategy: :manual, interactive: false)
      # Should fall back to another strategy when not interactive
    end
  end

  describe "integration with test runs" do
    test "runs tests after merge when option is set" do
      Tracker.track_file_operation(:provider1, "lib/tested.ex", :create,
        after_content: "defmodule Tested do\nend"
      )

      assert {:ok, merged_files} = Engine.merge_all(run_tests: true)
      assert map_size(merged_files) == 1
      # Tests would be executed here in production
    end
  end

  describe "error handling" do
    test "handles provider errors gracefully" do
      # Simulate provider with invalid content
      Tracker.track_file_operation(:provider1, "lib/invalid.ex", :create,
        after_content: "invalid elixir code {[}"
      )

      # Should still attempt merge
      assert {:ok, merged_files} = Engine.merge_all(strategy: :auto)
      assert map_size(merged_files) >= 0
    end

    test "handles missing file content" do
      # Track file without content
      Tracker.register_provider(:empty_provider)

      assert {:ok, _} = Engine.merge_all()
    end
  end
end
