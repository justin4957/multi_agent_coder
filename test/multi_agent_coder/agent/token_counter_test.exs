defmodule MultiAgentCoder.Agent.TokenCounterTest do
  use ExUnit.Case, async: true

  alias MultiAgentCoder.Agent.TokenCounter

  describe "estimate_tokens/1" do
    test "estimates tokens for text" do
      text = "This is a test with approximately twenty characters"
      tokens = TokenCounter.estimate_tokens(text)
      assert tokens > 0
      # Rough estimate: ~4 chars per token
      assert tokens >= div(String.length(text), 5)
    end

    test "returns 0 for empty string" do
      assert TokenCounter.estimate_tokens("") == 0
    end

    test "handles non-binary input" do
      assert TokenCounter.estimate_tokens(nil) == 0
      assert TokenCounter.estimate_tokens(123) == 0
    end
  end

  describe "calculate_cost/4" do
    test "calculates OpenAI GPT-4 cost" do
      cost = TokenCounter.calculate_cost(:openai, "gpt-4", 1000, 2000)
      assert cost > 0
      # GPT-4: $0.03/1K input, $0.06/1K output
      expected = (1000 * 0.03 / 1000) + (2000 * 0.06 / 1000)
      assert_in_delta cost, expected, 0.0001
    end

    test "calculates Anthropic Claude cost" do
      cost = TokenCounter.calculate_cost(:anthropic, "claude-sonnet-4", 1000, 2000)
      assert cost > 0
    end

    test "returns 0 for local models" do
      cost = TokenCounter.calculate_cost(:local, "llama2", 1000, 2000)
      assert cost == 0.0
    end
  end

  describe "format_cost/1" do
    test "formats small costs" do
      assert TokenCounter.format_cost(0.001) == "< $0.01"
      assert TokenCounter.format_cost(0.005) == "< $0.01"
    end

    test "formats larger costs with decimals" do
      formatted = TokenCounter.format_cost(1.5678)
      assert String.starts_with?(formatted, "$")
      assert String.contains?(formatted, "1.5")
    end
  end

  describe "create_usage_summary/4" do
    test "creates summary with all fields" do
      summary =
        TokenCounter.create_usage_summary(
          :openai,
          "gpt-4",
          "Hello world",
          "Hello! How can I help you?"
        )

      assert summary.provider == :openai
      assert summary.model == "gpt-4"
      assert summary.input_tokens > 0
      assert summary.output_tokens > 0
      assert summary.total_tokens == summary.input_tokens + summary.output_tokens
      assert summary.estimated_cost >= 0
      assert is_binary(summary.formatted_cost)
    end
  end
end
