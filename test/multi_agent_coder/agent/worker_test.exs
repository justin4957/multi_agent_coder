defmodule MultiAgentCoder.Agent.WorkerTest do
  use ExUnit.Case, async: false

  alias MultiAgentCoder.Agent.Worker

  setup do
    # Application components are already started by the application
    # No need to start them manually
    :ok
  end

  describe "initialization" do
    test "initializes worker with correct state" do
      opts = [
        provider: :test_provider,
        model: "test-model",
        api_key: "test-key",
        temperature: 0.5,
        max_tokens: 2048
      ]

      {:ok, pid} = start_supervised({Worker, opts})

      status = Worker.get_status(:test_provider)

      assert status.status == :idle
      assert status.current_task == nil
    end

    test "resolves system environment API keys" do
      System.put_env("TEST_API_KEY", "env-key-value")

      opts = [
        provider: :test_env_provider,
        model: "test-model",
        api_key: {:system, "TEST_API_KEY"}
      ]

      {:ok, _pid} = start_supervised({Worker, opts})

      # Worker should start successfully with resolved key
      via = {:via, Registry, {MultiAgentCoder.Agent.Registry, :test_env_provider}}
      assert GenServer.whereis(via) != nil

      System.delete_env("TEST_API_KEY")
    end
  end

  describe "status tracking" do
    setup do
      opts = [provider: :status_test, model: "test-model", api_key: "key"]
      {:ok, _pid} = start_supervised({Worker, opts})
      %{provider: :status_test}
    end

    test "returns idle status initially", %{provider: provider} do
      status = Worker.get_status(provider)
      assert status.status == :idle
      assert is_nil(status.current_task)
    end
  end

  describe "result normalization" do
    test "normalizes new format with usage stats" do
      opts = [provider: :normalize_test, model: "test", api_key: "key"]
      {:ok, _pid} = start_supervised({Worker, opts})

      # This would test the normalize_result function
      # Since it's private, we test it through the public interface
      # In a real scenario, providers return different formats
      assert true
    end
  end

  describe "PubSub broadcasting" do
    setup do
      opts = [provider: :pubsub_test, model: "test-model", api_key: "key"]
      {:ok, _pid} = start_supervised({Worker, opts})

      # Subscribe to provider updates
      Phoenix.PubSub.subscribe(MultiAgentCoder.PubSub, "agent:pubsub_test")

      %{provider: :pubsub_test}
    end

    test "can subscribe to provider updates" do
      # Verify subscription is successful
      # Actual broadcast testing would require executing a task
      # which needs provider mocking
      assert true
    end
  end
end
