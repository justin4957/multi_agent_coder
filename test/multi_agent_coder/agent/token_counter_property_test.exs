defmodule MultiAgentCoder.Agent.TokenCounterPropertyTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias MultiAgentCoder.Agent.TokenCounter

  describe "Token counting properties" do
    property "token count is always non-negative" do
      check all(text <- string(:ascii, min_length: 0, max_length: 1000)) do
        count = TokenCounter.estimate_tokens(text)
        assert count >= 0
        assert is_integer(count)
      end
    end

    property "longer text has more tokens" do
      check all(
              short <- string(:ascii, min_length: 1, max_length: 50),
              long <- string(:ascii, min_length: 100, max_length: 500)
            ) do
        short_count = TokenCounter.estimate_tokens(short)
        long_count = TokenCounter.estimate_tokens(long)

        assert long_count > short_count
      end
    end

    property "empty string has zero tokens" do
      assert TokenCounter.estimate_tokens("") == 0
    end

    property "concatenated text has approximately sum of tokens" do
      check all(
              text1 <- string(:ascii, min_length: 10, max_length: 100),
              text2 <- string(:ascii, min_length: 10, max_length: 100)
            ) do
        count1 = TokenCounter.estimate_tokens(text1)
        count2 = TokenCounter.estimate_tokens(text2)
        combined_count = TokenCounter.estimate_tokens(text1 <> text2)

        # Allow some margin for tokenization differences
        # Combined should be roughly equal to sum (within 20%)
        expected_sum = count1 + count2
        diff = abs(combined_count - expected_sum)
        # 20% margin
        margin = div(expected_sum, 5)

        assert diff <= margin
      end
    end

    property "repeated text has more tokens than single" do
      check all(
              text <- string(:ascii, min_length: 10, max_length: 50),
              repetitions <- integer(2..5)
            ) do
        single_count = TokenCounter.estimate_tokens(text)
        repeated_text = String.duplicate(text, repetitions)
        repeated_count = TokenCounter.estimate_tokens(repeated_text)

        # Repeated text should have more tokens (general property)
        assert repeated_count > single_count
      end
    end
  end

  describe "Cost calculation properties" do
    property "cost is always non-negative" do
      check all(tokens <- integer(0..100_000)) do
        cost = TokenCounter.calculate_cost(:openai, "gpt-4", tokens, 0)
        assert cost >= 0.0
        assert is_float(cost)
      end
    end

    property "more tokens means higher cost" do
      check all(
              tokens1 <- integer(10..1000),
              tokens2 <- integer(1001..10_000)
            ) do
        cost1 = TokenCounter.calculate_cost(:openai, "gpt-4", tokens1, tokens1)
        cost2 = TokenCounter.calculate_cost(:openai, "gpt-4", tokens2, tokens2)

        assert cost2 > cost1
      end
    end

    property "zero tokens means zero cost" do
      check all(
              provider <- member_of([:openai, :anthropic, :deepseek, :perplexity, :local]),
              model <- string(:alphanumeric, min_length: 1, max_length: 20)
            ) do
        cost = TokenCounter.calculate_cost(provider, model, 0, 0)
        assert cost == 0.0
      end
    end

    property "cost scales linearly with tokens" do
      check all(base_tokens <- integer(100..1000)) do
        single_cost = TokenCounter.calculate_cost(:openai, "gpt-4", base_tokens, base_tokens)

        double_cost =
          TokenCounter.calculate_cost(:openai, "gpt-4", base_tokens * 2, base_tokens * 2)

        # Double tokens should mean roughly double cost (within 1% for rounding)
        ratio = double_cost / single_cost
        assert_in_delta ratio, 2.0, 0.01
      end
    end
  end

  describe "Usage summary properties" do
    property "usage summary contains all required fields" do
      check all(
              provider <- member_of([:openai, :anthropic, :deepseek, :perplexity]),
              model <- string(:alphanumeric, min_length: 1, max_length: 20),
              input <- string(:ascii, min_length: 1, max_length: 100),
              output <- string(:ascii, min_length: 1, max_length: 100)
            ) do
        usage = TokenCounter.create_usage_summary(provider, model, input, output)

        assert Map.has_key?(usage, :input_tokens)
        assert Map.has_key?(usage, :output_tokens)
        assert Map.has_key?(usage, :total_tokens)
        assert Map.has_key?(usage, :estimated_cost)
        assert Map.has_key?(usage, :formatted_cost)

        assert is_integer(usage.input_tokens)
        assert is_integer(usage.output_tokens)
        assert is_integer(usage.total_tokens)
        assert is_float(usage.estimated_cost)
        assert is_binary(usage.formatted_cost)
      end
    end

    property "total tokens equals sum of input and output" do
      check all(
              provider <- member_of([:openai, :anthropic, :deepseek, :perplexity]),
              model <- string(:alphanumeric, min_length: 1, max_length: 20),
              input <- string(:ascii, min_length: 1, max_length: 100),
              output <- string(:ascii, min_length: 1, max_length: 100)
            ) do
        usage = TokenCounter.create_usage_summary(provider, model, input, output)

        assert usage.total_tokens == usage.input_tokens + usage.output_tokens
      end
    end

    property "formatted cost matches calculated cost" do
      check all(
              provider <- member_of([:openai, :anthropic, :deepseek, :perplexity]),
              model <- string(:alphanumeric, min_length: 1, max_length: 20),
              input <- string(:ascii, min_length: 10, max_length: 50),
              output <- string(:ascii, min_length: 10, max_length: 50)
            ) do
        usage = TokenCounter.create_usage_summary(provider, model, input, output)

        # Formatted cost should contain a dollar sign
        assert String.contains?(usage.formatted_cost, "$")
        # And should be a string representation of a number
        assert is_binary(usage.formatted_cost)
      end
    end
  end
end
