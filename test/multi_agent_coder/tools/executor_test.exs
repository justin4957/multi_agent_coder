defmodule MultiAgentCoder.Tools.ExecutorTest do
  use ExUnit.Case, async: true

  alias MultiAgentCoder.Tools.{Executor, ExecutionResult, ToolRequest}

  describe "execute/2 with bash commands" do
    test "executes simple bash command successfully" do
      {:ok, request} = ToolRequest.bash("echo 'hello world'", :openai)
      {:ok, result} = Executor.execute(request)

      assert result.status == :completed
      assert result.exit_code == 0
      assert String.trim(result.stdout) == "hello world"
      assert result.provider == :openai
      assert result.command_id == request.id
      assert result.duration_ms > 0
    end

    test "captures stdout from commands" do
      {:ok, request} = ToolRequest.bash("echo 'test output'", :anthropic)
      {:ok, result} = Executor.execute(request)

      assert result.status == :completed
      assert String.contains?(result.stdout, "test output")
    end

    test "handles command failure with non-zero exit code" do
      {:ok, request} = ToolRequest.bash("exit 42", :deepseek)
      {:ok, result} = Executor.execute(request)

      assert result.status == :failed
      assert result.exit_code == 42
    end

    test "handles invalid commands" do
      {:ok, request} = ToolRequest.bash("nonexistent_command_12345", :openai)
      {:ok, result} = Executor.execute(request)

      assert result.status == :failed
      assert result.exit_code == 127
    end

    test "executes multiline commands" do
      command = """
      echo "line 1"
      echo "line 2"
      echo "line 3"
      """

      {:ok, request} = ToolRequest.bash(command, :anthropic)
      {:ok, result} = Executor.execute(request)

      assert result.status == :completed
      assert String.contains?(result.stdout, "line 1")
      assert String.contains?(result.stdout, "line 2")
      assert String.contains?(result.stdout, "line 3")
    end

    test "preserves command request in result" do
      {:ok, request} = ToolRequest.bash("pwd", :openai)
      {:ok, result} = Executor.execute(request)

      assert result.request == request
      assert result.request.command == "pwd"
    end
  end

  describe "execute_bash/3" do
    test "executes bash command via convenience function" do
      {:ok, result} = Executor.execute_bash("echo test", :openai)

      assert result.status == :completed
      assert String.contains?(result.stdout, "test")
    end

    test "accepts options" do
      {:ok, result} = Executor.execute_bash("echo test", :anthropic, timeout: 5000)

      assert result.status == :completed
    end
  end

  describe "execute/2 with file operations" do
    setup do
      # Create a temporary directory for tests
      temp_dir = System.tmp_dir!()
      test_file = Path.join(temp_dir, "executor_test_#{:rand.uniform(10000)}.txt")

      on_exit(fn ->
        File.rm(test_file)
      end)

      %{test_file: test_file}
    end

    test "reads file content", %{test_file: file} do
      content = "test file content"
      File.write!(file, content)

      {:ok, request} = ToolRequest.file_read(file, :openai)
      {:ok, result} = Executor.execute(request)

      assert result.status == :completed
      assert result.stdout == content
      assert result.exit_code == 0
    end

    test "writes file content", %{test_file: file} do
      content = "new content"

      {:ok, request} = ToolRequest.file_write(file, content, :anthropic)
      {:ok, result} = Executor.execute(request)

      assert result.status == :completed
      assert File.read!(file) == content
    end

    test "handles file read errors for non-existent files" do
      {:ok, request} = ToolRequest.file_read("/nonexistent/file.txt", :deepseek)
      {:ok, result} = Executor.execute(request)

      assert result.status == :failed
      assert result.error != nil
    end

    test "handles file write errors for invalid paths" do
      {:ok, request} = ToolRequest.file_write("/invalid/path/file.txt", "content", :openai)
      {:ok, result} = Executor.execute(request)

      assert result.status == :failed
      assert result.error != nil
    end

    test "deletes files", %{test_file: file} do
      File.write!(file, "temp")

      {:ok, request} = ToolRequest.new(:file_delete, file, :anthropic)
      {:ok, result} = Executor.execute(request)

      assert result.status == :completed
      refute File.exists?(file)
    end
  end

  describe "execute/2 with git commands" do
    test "executes git commands" do
      {:ok, request} = ToolRequest.git("--version", :openai)
      {:ok, result} = Executor.execute(request)

      assert result.status == :completed
      assert String.contains?(result.stdout, "git version")
    end

    test "handles git command failures" do
      {:ok, request} = ToolRequest.git("invalid-git-command", :anthropic)
      {:ok, result} = Executor.execute(request)

      assert result.status == :failed
    end
  end

  describe "execution timing" do
    test "records execution duration" do
      {:ok, request} = ToolRequest.bash("sleep 0.1", :openai)
      {:ok, result} = Executor.execute(request)

      assert result.duration_ms >= 100
      assert result.duration_ms < 500
    end

    test "includes timestamps" do
      {:ok, request} = ToolRequest.bash("echo test", :anthropic)
      {:ok, result} = Executor.execute(request)

      assert %DateTime{} = result.started_at
      assert %DateTime{} = result.completed_at
      assert DateTime.compare(result.completed_at, result.started_at) in [:gt, :eq]
    end
  end

  describe "output truncation" do
    test "truncates very large output" do
      # Generate output larger than 1MB (1 million bytes)
      # Each "y\n" is 2 bytes, so we need 500,000+ lines
      {:ok, request} = ToolRequest.bash("yes | head -n 600000", :openai)
      {:ok, result} = Executor.execute(request)

      assert result.status == :completed
      # Output should be truncated to around 1MB
      if byte_size(result.stdout) > 1_000_000 do
        assert String.contains?(result.stdout, "output truncated")
      end

      # Should not be significantly larger than 1MB + truncation message
      assert byte_size(result.stdout) <= 1_100_000
    end
  end

  describe "error handling" do
    test "handles crashes gracefully" do
      # This will cause an error during execution
      {:ok, request} = ToolRequest.new(:bash, "kill $$", :openai)
      {:ok, result} = Executor.execute(request)

      # Should still return a result, not crash
      assert %ExecutionResult{} = result
      assert result.provider == :openai
    end

    test "returns result even for failed commands" do
      {:ok, request} = ToolRequest.bash("exit 1", :anthropic)
      {:ok, result} = Executor.execute(request)

      assert result.status == :failed
      assert result.exit_code == 1
    end
  end

  describe "working directory" do
    test "executes commands in specified working directory" do
      {:ok, request} = ToolRequest.bash("pwd", :openai, working_dir: "/tmp")
      {:ok, result} = Executor.execute(request, working_dir: "/tmp")

      assert result.status == :completed

      assert String.contains?(result.stdout, "/tmp") or
               String.contains?(result.stdout, "/private/tmp")
    end
  end

  describe "environment variables" do
    test "sets environment variables for command execution" do
      {:ok, request} =
        ToolRequest.bash("echo $MY_TEST_VAR", :anthropic, env: %{"MY_TEST_VAR" => "test_value"})

      {:ok, result} = Executor.execute(request, env: %{"MY_TEST_VAR" => "test_value"})

      assert result.status == :completed
      assert String.contains?(result.stdout, "test_value")
    end
  end
end
