defmodule MultiAgentCoder.Merge.PatternLearnerTest do
  use ExUnit.Case, async: false

  alias MultiAgentCoder.Merge.PatternLearner

  setup do
    # Start the PatternLearner if not already started
    case GenServer.whereis(PatternLearner) do
      nil -> {:ok, _pid} = PatternLearner.start_link([])
      _pid -> :ok
    end

    # Clear history before each test
    PatternLearner.clear_history()

    :ok
  end

  describe "pattern learning" do
    test "records resolution choices" do
      conflict = create_test_conflict("test.ex", [:openai, :anthropic])

      PatternLearner.record_resolution(conflict, {:accept, :openai})

      history = PatternLearner.get_history()
      assert length(history) == 1

      [record] = history
      assert record.file_path == "test.ex"
      assert record.chosen_provider == :openai
    end

    test "predicts resolutions after learning" do
      conflict = create_test_conflict("lib/module.ex", [:openai, :anthropic])

      # Record multiple similar choices
      for _ <- 1..10 do
        PatternLearner.record_resolution(conflict, {:accept, :openai})
      end

      # Should predict openai with high confidence
      assert {:ok, resolution, confidence} = PatternLearner.predict_resolution(conflict)
      assert confidence > 0.5
      assert resolution == {:accept, :openai}
    end

    test "returns error when insufficient data" do
      conflict = create_test_conflict("test.ex", [:openai, :anthropic])

      # No data recorded yet
      assert {:error, :insufficient_data} = PatternLearner.predict_resolution(conflict)
    end

    test "builds preference model by file type" do
      conflict_ex = create_test_conflict("test.ex", [:openai, :anthropic])
      conflict_js = create_test_conflict("test.js", [:openai, :deepseek])

      PatternLearner.record_resolution(conflict_ex, {:accept, :openai})
      PatternLearner.record_resolution(conflict_js, {:accept, :deepseek})

      preferences = PatternLearner.get_preferences()

      assert preferences.total_resolutions == 2
      assert Map.has_key?(preferences.by_file_type, ".ex")
      assert Map.has_key?(preferences.by_file_type, ".js")
    end
  end

  describe "history filtering" do
    test "filters history by file type" do
      conflict_ex = create_test_conflict("test.ex", [:openai])
      conflict_js = create_test_conflict("test.js", [:deepseek])

      PatternLearner.record_resolution(conflict_ex, {:accept, :openai})
      PatternLearner.record_resolution(conflict_js, {:accept, :deepseek})

      ex_history = PatternLearner.get_history(file_type: ".ex")
      js_history = PatternLearner.get_history(file_type: ".js")

      assert length(ex_history) == 1
      assert length(js_history) == 1
    end

    test "filters history by conflict type" do
      conflict_file = create_test_conflict("test.ex", [:openai], :file_level)
      conflict_line = create_test_conflict("test2.ex", [:anthropic], :line_level)

      PatternLearner.record_resolution(conflict_file, {:merge, :semantic})
      PatternLearner.record_resolution(conflict_line, {:accept, :anthropic})

      file_history = PatternLearner.get_history(conflict_type: :file_level)
      line_history = PatternLearner.get_history(conflict_type: :line_level)

      assert length(file_history) == 1
      assert length(line_history) == 1
    end
  end

  describe "pattern export/import" do
    test "exports patterns to file" do
      conflict = create_test_conflict("test.ex", [:openai])
      PatternLearner.record_resolution(conflict, {:accept, :openai})

      temp_file = Path.join(System.tmp_dir!(), "patterns_#{:erlang.unique_integer()}.json")

      assert :ok = PatternLearner.export_patterns(temp_file)
      assert File.exists?(temp_file)

      File.rm!(temp_file)
    end

    test "imports patterns from file" do
      # Export first
      conflict = create_test_conflict("test.ex", [:openai])
      PatternLearner.record_resolution(conflict, {:accept, :openai})

      temp_file = Path.join(System.tmp_dir!(), "patterns_#{:erlang.unique_integer()}.json")
      PatternLearner.export_patterns(temp_file)

      # Clear and import
      PatternLearner.clear_history()
      assert length(PatternLearner.get_history()) == 0

      assert :ok = PatternLearner.import_patterns(temp_file)
      assert length(PatternLearner.get_history()) == 1

      File.rm!(temp_file)
    end
  end

  # Helper functions

  defp create_test_conflict(file_path, providers, type \\ :line_level) do
    %{
      file: file_path,
      type: type,
      providers: providers,
      details: %{
        contents: Map.new(providers, fn p -> {p, "test content"} end)
      }
    }
  end
end
