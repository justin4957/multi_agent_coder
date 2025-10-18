defmodule MultiAgentCoder.Tools.ExecutionResultTest do
  use ExUnit.Case, async: true

  alias MultiAgentCoder.Tools.{ExecutionResult, ToolRequest}

  describe "success/5" do
    test "creates successful result" do
      result = ExecutionResult.success("cmd_123", :openai, "output", 150)

      assert result.command_id == "cmd_123"
      assert result.provider == :openai
      assert result.status == :completed
      assert result.exit_code == 0
      assert result.stdout == "output"
      assert result.stderr == ""
      assert result.duration_ms == 150
      assert %DateTime{} = result.started_at
      assert %DateTime{} = result.completed_at
      assert result.error == nil
    end

    test "includes request when provided" do
      {:ok, request} = ToolRequest.bash("echo test", :anthropic)
      result = ExecutionResult.success("cmd_1", :anthropic, "out", 100, request: request)

      assert result.request == request
    end

    test "includes stderr when provided" do
      result = ExecutionResult.success("cmd_1", :openai, "out", 100, stderr: "warning")

      assert result.stderr == "warning"
    end
  end

  describe "failure/6" do
    test "creates failed result" do
      result = ExecutionResult.failure("cmd_456", :anthropic, 1, "error output", 200)

      assert result.command_id == "cmd_456"
      assert result.provider == :anthropic
      assert result.status == :failed
      assert result.exit_code == 1
      assert result.stderr == "error output"
      assert result.duration_ms == 200
    end

    test "includes stdout for failed commands" do
      result =
        ExecutionResult.failure("cmd_1", :deepseek, 2, "err", 100, stdout: "partial output")

      assert result.stdout == "partial output"
    end

    test "includes error details" do
      result =
        ExecutionResult.failure("cmd_1", :openai, 127, "not found", 50, error: :command_not_found)

      assert result.error == :command_not_found
    end
  end

  describe "timeout/4" do
    test "creates timeout result" do
      result = ExecutionResult.timeout("cmd_789", :deepseek, 5000)

      assert result.command_id == "cmd_789"
      assert result.provider == :deepseek
      assert result.status == :timeout
      assert result.exit_code == nil
      assert result.duration_ms == 5000
      assert result.error == :timeout
    end

    test "includes partial output" do
      result = ExecutionResult.timeout("cmd_1", :openai, 1000, stdout: "partial")

      assert result.stdout == "partial"
    end
  end

  describe "error/5" do
    test "creates error result" do
      result = ExecutionResult.error("cmd_111", :anthropic, "Command failed", 75)

      assert result.command_id == "cmd_111"
      assert result.provider == :anthropic
      assert result.status == :failed
      assert result.error == "Command failed"
      assert result.duration_ms == 75
    end

    test "accepts any error term" do
      error_struct = %RuntimeError{message: "boom"}
      result = ExecutionResult.error("cmd_1", :openai, error_struct, 100)

      assert result.error == error_struct
    end
  end

  describe "success?/1" do
    test "returns true for successful execution" do
      result = ExecutionResult.success("cmd_1", :openai, "ok", 100)

      assert ExecutionResult.success?(result)
    end

    test "returns false for failed execution" do
      result = ExecutionResult.failure("cmd_1", :openai, 1, "err", 100)

      refute ExecutionResult.success?(result)
    end

    test "returns false for timeout" do
      result = ExecutionResult.timeout("cmd_1", :openai, 1000)

      refute ExecutionResult.success?(result)
    end

    test "returns false for error" do
      result = ExecutionResult.error("cmd_1", :openai, "error", 100)

      refute ExecutionResult.success?(result)
    end
  end

  describe "failed?/1" do
    test "returns true for failed execution" do
      result = ExecutionResult.failure("cmd_1", :openai, 1, "err", 100)

      assert ExecutionResult.failed?(result)
    end

    test "returns true for timeout" do
      result = ExecutionResult.timeout("cmd_1", :openai, 1000)

      assert ExecutionResult.failed?(result)
    end

    test "returns false for successful execution" do
      result = ExecutionResult.success("cmd_1", :openai, "ok", 100)

      refute ExecutionResult.failed?(result)
    end
  end

  describe "summary/1" do
    test "summarizes successful execution" do
      result = ExecutionResult.success("cmd_1", :openai, "ok", 150)
      summary = ExecutionResult.summary(result)

      assert summary == "Completed successfully in 150ms"
    end

    test "summarizes failed execution with exit code" do
      result = ExecutionResult.failure("cmd_1", :openai, 42, "err", 200)
      summary = ExecutionResult.summary(result)

      assert summary == "Failed with exit code 42 in 200ms"
    end

    test "summarizes timeout" do
      result = ExecutionResult.timeout("cmd_1", :openai, 5000)
      summary = ExecutionResult.summary(result)

      assert summary == "Timed out after 5000ms"
    end

    test "summarizes error" do
      result = ExecutionResult.error("cmd_1", :openai, "Something broke", 100)
      summary = ExecutionResult.summary(result)

      assert String.contains?(summary, "Failed with error")
      assert String.contains?(summary, "100ms")
    end
  end

  describe "format/1" do
    test "formats successful result with output" do
      result = ExecutionResult.success("cmd_123", :openai, "hello\n", 100)
      formatted = ExecutionResult.format(result)

      assert String.contains?(formatted, "cmd_123")
      assert String.contains?(formatted, "openai")
      assert String.contains?(formatted, "Completed successfully")
      assert String.contains?(formatted, "Output: hello")
    end

    test "formats failed result with error" do
      result = ExecutionResult.failure("cmd_456", :anthropic, 1, "error message", 200)
      formatted = ExecutionResult.format(result)

      assert String.contains?(formatted, "cmd_456")
      assert String.contains?(formatted, "Failed with exit code 1")
      assert String.contains?(formatted, "Error: error message")
    end

    test "formats timeout without output" do
      result = ExecutionResult.timeout("cmd_789", :deepseek, 5000)
      formatted = ExecutionResult.format(result)

      assert String.contains?(formatted, "cmd_789")
      assert String.contains?(formatted, "Timed out")
      refute String.contains?(formatted, "Output:")
    end

    test "handles empty output" do
      result = ExecutionResult.success("cmd_1", :openai, "", 100)
      formatted = ExecutionResult.format(result)

      refute String.contains?(formatted, "Output:")
    end
  end

  describe "metadata" do
    test "stores custom metadata" do
      result =
        ExecutionResult.success("cmd_1", :openai, "out", 100, metadata: %{custom_field: "value"})

      assert result.metadata == %{custom_field: "value"}
    end
  end

  describe "timing information" do
    test "includes started_at timestamp" do
      now = DateTime.utc_now()
      result = ExecutionResult.success("cmd_1", :openai, "out", 100, started_at: now)

      assert result.started_at == now
    end

    test "sets default timestamps when not provided" do
      result = ExecutionResult.success("cmd_1", :openai, "out", 100)

      assert %DateTime{} = result.started_at
      assert %DateTime{} = result.completed_at
    end
  end
end
