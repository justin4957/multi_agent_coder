defmodule MultiAgentCoder.Merge.MLResolverTest do
  use ExUnit.Case, async: true

  alias MultiAgentCoder.Merge.MLResolver

  describe "conflict analysis" do
    test "analyzes conflict severity and difficulty" do
      conflict = create_test_conflict("lib/core/app.ex", [:openai, :anthropic])

      {:ok, analysis} = MLResolver.analyze_conflict(conflict)

      assert analysis.severity in [:low, :medium, :high, :critical]
      assert analysis.difficulty in [:easy, :moderate, :hard, :very_hard]
      assert is_atom(analysis.recommended_strategy)
      assert is_float(analysis.confidence)
      assert is_list(analysis.reasoning)
    end

    test "detects critical files" do
      conflict = create_test_conflict("mix.exs", [:openai, :anthropic])

      {:ok, analysis} = MLResolver.analyze_conflict(conflict)

      assert analysis.severity == :critical
    end

    test "handles test files as low severity" do
      conflict = create_test_conflict("test/my_test.exs", [:openai, :anthropic])

      {:ok, analysis} = MLResolver.analyze_conflict(conflict)

      assert analysis.severity == :low
    end

    test "provides reasoning for recommendations" do
      conflict = create_test_conflict("lib/util.ex", [:openai, :anthropic])

      {:ok, analysis} = MLResolver.analyze_conflict(conflict)

      assert length(analysis.reasoning) > 0
      assert Enum.all?(analysis.reasoning, &is_binary/1)
    end
  end

  describe "provider scoring" do
    test "scores providers based on multiple factors" do
      conflict = create_test_conflict("lib/test.ex", [:openai, :anthropic, :deepseek])

      scores = MLResolver.score_providers(conflict)

      assert length(scores) == 3

      assert Enum.all?(scores, fn score ->
               is_float(score.overall_score) and
                 score.overall_score >= 0.0 and
                 score.overall_score <= 1.0
             end)
    end

    test "returns scores in descending order" do
      conflict = create_test_conflict("lib/test.ex", [:openai, :anthropic])

      [first, second] = MLResolver.score_providers(conflict)

      assert first.overall_score >= second.overall_score
    end
  end

  describe "context analysis" do
    test "analyzes code context" do
      conflict = create_test_conflict("lib/test.ex", [:openai, :anthropic])

      context = MLResolver.analyze_context(conflict)

      assert is_map(context)
    end

    test "detects framework patterns" do
      phoenix_conflict =
        create_test_conflict("lib/my_app_web/controllers/phoenix_controller.ex", [:openai])

      ecto_conflict = create_test_conflict("lib/my_app/ecto/schema.ex", [:anthropic])

      phoenix_context = MLResolver.analyze_context(phoenix_conflict)
      ecto_context = MLResolver.analyze_context(ecto_conflict)

      assert phoenix_context.framework == :phoenix
      assert ecto_context.framework == :ecto
    end
  end

  describe "semantic similarity" do
    test "calculates similarity between similar code" do
      code1 = """
      defmodule Test do
        def hello(name), do: "Hello, \#{name}"
      end
      """

      code2 = """
      defmodule Test do
        def hello(name), do: "Hello, \#{name}"
      end
      """

      {:ok, similarity} = MLResolver.calculate_semantic_similarity(code1, code2, ".ex")

      assert similarity > 0.9
    end

    test "returns low similarity for different code" do
      code1 = """
      defmodule Test do
        def hello(name), do: "Hello"
      end
      """

      code2 = """
      defmodule Different do
        def goodbye(x, y, z), do: x + y + z
        def another_function, do: :ok
      end
      """

      {:ok, similarity} = MLResolver.calculate_semantic_similarity(code1, code2, ".ex")

      assert similarity < 0.5
    end
  end

  describe "strategy metrics" do
    test "returns metrics for strategies" do
      metrics = MLResolver.get_strategy_metrics(:semantic)

      assert is_map(metrics)
      assert Map.has_key?(metrics, :strategy)
      assert Map.has_key?(metrics, :success_rate)
    end
  end

  # Helper functions

  defp create_test_conflict(file_path, providers) do
    %{
      file: file_path,
      type: :line_level,
      providers: providers,
      details: %{
        contents: Map.new(providers, fn p -> {p, "test content from #{p}"} end)
      }
    }
  end
end
