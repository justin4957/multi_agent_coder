defmodule MultiAgentCoder.Agent.OCITest do
  use ExUnit.Case, async: true

  alias MultiAgentCoder.Agent.OCI

  describe "validate_credentials/3" do
    test "returns error for invalid API key" do
      # Test with obviously invalid key
      result =
        OCI.validate_credentials("invalid_key", "https://test.example.com", "test-compartment")

      assert {:error, _reason} = result
    end

    test "returns error for empty API key" do
      result = OCI.validate_credentials("", "https://test.example.com", "test-compartment")
      assert {:error, _reason} = result
    end

    test "returns error for missing endpoint" do
      result = OCI.validate_credentials("test_key", "", "test-compartment")
      assert {:error, _reason} = result
    end

    test "returns error for missing compartment_id" do
      result = OCI.validate_credentials("test_key", "https://test.example.com", "")
      assert {:error, _reason} = result
    end
  end

  # Note: Full integration tests for call/3 would require:
  # 1. Mocking HTTPClient responses
  # 2. Valid test API keys and OCI credentials
  # 3. Network access to OCI endpoints
  #
  # These should be handled in integration tests or with proper mocking framework
end
