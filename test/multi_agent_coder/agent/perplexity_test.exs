defmodule MultiAgentCoder.Agent.PerplexityTest do
  use ExUnit.Case, async: true

  alias MultiAgentCoder.Agent.Perplexity

  describe "validate_credentials/1" do
    test "returns error for invalid API key" do
      # Test with obviously invalid key
      result = Perplexity.validate_credentials("invalid_key")
      assert {:error, _reason} = result
    end

    test "returns error for empty API key" do
      result = Perplexity.validate_credentials("")
      assert {:error, _reason} = result
    end
  end

  # Note: Full integration tests for call/3 would require:
  # 1. Mocking HTTPClient responses
  # 2. Valid test API keys
  # 3. Network access
  #
  # These should be handled in integration tests or with proper mocking framework
end
