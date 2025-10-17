defmodule MultiAgentCoder.Merge.StrategyTest do
  use ExUnit.Case
  alias MultiAgentCoder.Merge.Strategy

  describe "resolve_conflicts/2" do
    test "resolves conflicts with last_write_wins strategy" do
      conflicts = [
        %{
          file: "lib/test.ex",
          type: :file_level,
          providers: [:provider1, :provider2, :provider3],
          details: %{}
        }
      ]

      assert {:ok, resolutions} = Strategy.resolve_conflicts(conflicts, :last_write_wins)
      assert resolutions["lib/test.ex"] == {:accept, :provider3}
    end

    test "resolves conflicts with first_write_wins strategy" do
      conflicts = [
        %{
          file: "lib/test.ex",
          type: :file_level,
          providers: [:provider1, :provider2],
          details: %{}
        }
      ]

      assert {:ok, resolutions} = Strategy.resolve_conflicts(conflicts, :first_write_wins)
      assert resolutions["lib/test.ex"] == {:accept, :provider1}
    end

    test "resolves non-overlapping line conflicts with union strategy" do
      conflicts = [
        %{
          file: "lib/test.ex",
          type: :line_level,
          providers: [:provider1, :provider2],
          details: %{
            line_ranges: [
              {:provider1, {1, 5}},
              {:provider2, {10, 15}}
            ]
          }
        }
      ]

      assert {:ok, resolutions} = Strategy.resolve_conflicts(conflicts, :union)
      assert match?({:merge, _}, resolutions["lib/test.ex"])
    end

    test "handles auto strategy for simple additions" do
      conflicts = [
        %{
          file: "lib/new_file.ex",
          type: :addition,
          providers: [:provider1],
          details: %{}
        }
      ]

      assert {:ok, resolutions} = Strategy.resolve_conflicts(conflicts, :auto)
      assert resolutions["lib/new_file.ex"] == {:merge, :union}
    end

    test "handles empty conflict list" do
      assert {:ok, resolutions} = Strategy.resolve_conflicts([], :auto)
      assert map_size(resolutions) == 0
    end
  end

  describe "select_best_strategy/1" do
    test "selects union for all simple additions" do
      conflicts = [
        %{type: :addition, details: %{}},
        %{type: :addition, details: %{}}
      ]

      assert Strategy.select_best_strategy(conflicts) == :union
    end

    test "selects semantic for different function conflicts" do
      conflicts = [
        %{
          type: :line_level,
          details: %{scope: :function, function_name: "func1"}
        },
        %{
          type: :line_level,
          details: %{scope: :function, function_name: "func2"}
        }
      ]

      assert Strategy.select_best_strategy(conflicts) == :semantic
    end

    test "selects manual for complex overlapping conflicts" do
      conflicts = [
        %{
          type: :line_level,
          details: %{
            line_ranges: [
              {:provider1, {1, 10}},
              {:provider2, {5, 15}}
            ]
          }
        }
      ]

      assert Strategy.select_best_strategy(conflicts) == :manual
    end

    test "defaults to manual for mixed conflicts with file_level" do
      conflicts = [
        %{type: :addition, details: %{}},
        %{type: :file_level, details: %{}}
      ]

      # has_complex_overlaps? returns true for :file_level conflicts
      assert Strategy.select_best_strategy(conflicts) == :manual
    end
  end

  describe "apply_strategy/2" do
    setup do
      provider_contents = %{
        provider1: "# Version 1\ndef func, do: 1",
        provider2: "# Version 2\ndef func, do: 2",
        provider3: "# Version 3\ndef func, do: 3"
      }

      {:ok, contents: provider_contents}
    end

    test "applies last_write_wins strategy", %{contents: contents} do
      assert {:ok, result} = Strategy.apply_strategy(contents, :last_write_wins)
      assert result == "# Version 3\ndef func, do: 3"
    end

    test "applies first_write_wins strategy", %{contents: contents} do
      assert {:ok, result} = Strategy.apply_strategy(contents, :first_write_wins)
      assert result == "# Version 1\ndef func, do: 1"
    end

    test "applies union strategy", %{contents: contents} do
      assert {:ok, result} = Strategy.apply_strategy(contents, :union)
      assert is_binary(result)
      # Union should combine all unique lines
    end

    test "applies intersection strategy", %{contents: contents} do
      assert {:ok, result} = Strategy.apply_strategy(contents, :intersection)
      assert is_binary(result)
      # Intersection should only keep common lines
    end

    test "returns error for unknown strategy", %{contents: contents} do
      assert {:error, "Unknown strategy: " <> _} = Strategy.apply_strategy(contents, :unknown)
    end

    test "handles manual strategy requirement", %{contents: contents} do
      assert {:error, "Manual strategy requires interactive resolution"} =
               Strategy.apply_strategy(contents, :manual)
    end

    test "auto strategy tries multiple approaches", %{contents: contents} do
      assert {:ok, result} = Strategy.apply_strategy(contents, :auto)
      assert is_binary(result)
    end
  end

  describe "create_merge_plan/2" do
    test "creates detailed merge plan for conflicts" do
      conflicts = [
        %{
          file: "lib/file1.ex",
          type: :file_level,
          providers: [:p1, :p2],
          details: %{}
        },
        %{
          file: "lib/file2.ex",
          type: :line_level,
          providers: [:p1, :p3],
          details: %{}
        }
      ]

      assert {:ok, plan} = Strategy.create_merge_plan(conflicts, :auto)
      assert length(plan) == 2

      [plan1, plan2] = plan
      assert plan1.file == "lib/file1.ex"
      assert plan1.strategy == :auto
      assert is_binary(plan1.resolution)

      assert plan2.file == "lib/file2.ex"
      assert plan2.strategy == :auto
    end

    test "includes strategy-specific resolution descriptions" do
      conflicts = [
        %{
          file: "test.ex",
          type: :file_level,
          providers: [:p1, :p2],
          details: %{}
        }
      ]

      assert {:ok, plan} = Strategy.create_merge_plan(conflicts, :last_write_wins)
      assert [%{resolution: resolution}] = plan
      assert String.contains?(resolution, "p2")
    end
  end

  describe "semantic equivalence detection" do
    test "attempts semantic merge for syntactically different code" do
      conflict = %{
        file: "lib/test.ex",
        type: :line_level,
        providers: [:p1, :p2],
        details: %{
          contents: %{
            p1: "def add(a, b), do: a + b",
            p2: "def add(x, y), do: x + y"
          }
        }
      }

      assert {:ok, resolutions} = Strategy.resolve_conflicts([conflict], :auto)
      resolution = resolutions["lib/test.ex"]
      # Different variable names trigger semantic merge attempt
      assert resolution == {:merge, :semantic}
    end

    test "handles non-equivalent semantic changes" do
      conflict = %{
        file: "lib/test.ex",
        type: :line_level,
        providers: [:p1, :p2],
        details: %{
          contents: %{
            p1: "def add(a, b), do: a + b",
            p2: "def add(a, b), do: a * b"
          }
        }
      }

      assert {:ok, resolutions} = Strategy.resolve_conflicts([conflict], :auto)
      resolution = resolutions["lib/test.ex"]
      # Should try semantic merge for non-equivalent changes
      assert resolution == {:merge, :semantic}
    end
  end

  describe "edge cases" do
    test "handles conflicts with missing details gracefully" do
      conflict = %{
        file: "test.ex",
        type: :file_level,
        providers: [:p1, :p2],
        details: nil
      }

      assert {:ok, resolutions} = Strategy.resolve_conflicts([conflict], :auto)
      assert Map.has_key?(resolutions, "test.ex")
    end

    test "handles single provider in conflict" do
      conflict = %{
        file: "test.ex",
        type: :addition,
        providers: [:p1],
        details: %{}
      }

      assert {:ok, resolutions} = Strategy.resolve_conflicts([conflict], :auto)
      assert resolutions["test.ex"] == {:merge, :union}
    end

    test "handles empty provider list" do
      conflict = %{
        file: "test.ex",
        type: :file_level,
        providers: [],
        details: %{}
      }

      assert {:ok, resolutions} = Strategy.resolve_conflicts([conflict], :auto)
      # Should handle gracefully even with no providers
      assert is_map(resolutions)
    end
  end
end
