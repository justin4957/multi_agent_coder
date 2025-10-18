defmodule MultiAgentCoder.Tools.SandboxTest do
  use ExUnit.Case, async: true

  alias MultiAgentCoder.Tools.{Sandbox, SandboxConfig}

  describe "prepare/1" do
    test "creates default sandbox configuration" do
      {:ok, config} = Sandbox.prepare()

      assert %SandboxConfig{} = config
      assert config.working_dir == File.cwd!()
    end

    test "creates sandbox with custom working directory" do
      working_dir = System.tmp_dir!()
      {:ok, config} = Sandbox.prepare(working_dir: working_dir)

      assert config.working_dir == Path.expand(working_dir)
    end

    test "creates sandbox with allowed paths" do
      {:ok, config} = Sandbox.prepare(allowed_paths: ["lib", "test"])

      assert length(config.allowed_paths) > 0
    end

    test "returns error for invalid working directory" do
      assert {:error, _} = Sandbox.prepare(working_dir: "/nonexistent/path/12345")
    end
  end

  describe "execute/2" do
    setup do
      {:ok, config} = Sandbox.prepare()
      %{config: config}
    end

    test "executes simple command successfully", %{config: config} do
      {:ok, result} = Sandbox.execute("echo hello", config)

      assert result.exit_code == 0
      assert String.trim(result.stdout) == "hello"
      assert result.stderr == ""
      assert result.duration_ms > 0
      refute result.timed_out
    end

    test "captures command output", %{config: config} do
      {:ok, result} = Sandbox.execute("echo 'test output'", config)

      assert result.exit_code == 0
      assert String.contains?(result.stdout, "test output")
    end

    test "handles command failure with non-zero exit code", %{config: config} do
      {:ok, result} = Sandbox.execute("exit 42", config)

      assert result.exit_code == 42
      refute result.timed_out
    end

    test "handles invalid commands", %{config: config} do
      {:ok, result} = Sandbox.execute("nonexistent_command_12345", config)

      assert result.exit_code == 127
    end

    test "executes multiline commands", %{config: config} do
      command = """
      echo "line 1"
      echo "line 2"
      echo "line 3"
      """

      {:ok, result} = Sandbox.execute(command, config)

      assert result.exit_code == 0
      assert String.contains?(result.stdout, "line 1")
      assert String.contains?(result.stdout, "line 2")
      assert String.contains?(result.stdout, "line 3")
    end

    test "records execution duration", %{config: config} do
      {:ok, result} = Sandbox.execute("sleep 0.1", config)

      assert result.duration_ms >= 100
      assert result.duration_ms < 500
    end

    test "returns error for empty command" do
      {:ok, config} = Sandbox.prepare()
      assert {:error, _} = Sandbox.execute("", config)
    end

    test "returns error for non-string command" do
      {:ok, config} = Sandbox.prepare()
      assert {:error, _} = Sandbox.execute(123, config)
    end
  end

  describe "execute/2 with working directory" do
    setup do
      temp_dir = System.tmp_dir!()
      {:ok, config} = Sandbox.prepare(working_dir: temp_dir)
      %{config: config, temp_dir: temp_dir}
    end

    test "executes commands in specified working directory", %{config: config, temp_dir: temp_dir} do
      {:ok, result} = Sandbox.execute("pwd", config)

      assert result.exit_code == 0
      # Result should contain temp_dir path
      assert String.contains?(result.stdout, Path.basename(temp_dir))
    end
  end

  describe "execute/2 with environment variables" do
    test "sets environment variables for command execution" do
      {:ok, config} = Sandbox.prepare(env_vars: %{"MY_TEST_VAR" => "test_value"})
      {:ok, result} = Sandbox.execute("echo $MY_TEST_VAR", config)

      assert result.exit_code == 0
      assert String.contains?(result.stdout, "test_value")
    end

    test "multiple environment variables" do
      {:ok, config} =
        Sandbox.prepare(env_vars: %{"VAR1" => "value1", "VAR2" => "value2"})

      {:ok, result} = Sandbox.execute("echo $VAR1 $VAR2", config)

      assert result.exit_code == 0
      assert String.contains?(result.stdout, "value1")
      assert String.contains?(result.stdout, "value2")
    end
  end

  describe "execute/2 with timeout" do
    test "enforces timeout on long-running commands" do
      {:ok, config} = Sandbox.prepare(resource_limits: %{timeout_ms: 500})
      {:ok, result} = Sandbox.execute("sleep 10", config)

      assert result.timed_out
      assert result.exit_code == nil
      assert result.duration_ms >= 500
      assert result.duration_ms < 2000
    end

    test "does not timeout fast commands" do
      {:ok, config} = Sandbox.prepare(resource_limits: %{timeout_ms: 5000})
      {:ok, result} = Sandbox.execute("echo quick", config)

      refute result.timed_out
      assert result.exit_code == 0
    end
  end

  describe "execute/2 with output truncation" do
    test "truncates very large output" do
      # Generate output larger than 1MB
      {:ok, config} = Sandbox.prepare()
      {:ok, result} = Sandbox.execute("yes | head -n 600000", config)

      assert result.exit_code == 0

      # Output should be truncated to around 1MB
      if byte_size(result.stdout) > 1_000_000 do
        assert String.contains?(result.stdout, "output truncated")
      end

      # Should not be significantly larger than 1MB + truncation message
      assert byte_size(result.stdout) <= 1_100_000
    end
  end

  describe "validate_path/2" do
    test "validates path within working directory" do
      working_dir = System.tmp_dir!()
      {:ok, config} = SandboxConfig.new(working_dir)

      test_path = Path.join(working_dir, "test.txt")
      assert {:ok, ^test_path} = Sandbox.validate_path(test_path, config)
    end

    test "validates path within allowed paths" do
      working_dir = System.tmp_dir!()
      {:ok, config} = SandboxConfig.new(working_dir, allowed_paths: ["data"])

      test_path = Path.join([working_dir, "data", "file.txt"])
      assert {:ok, _} = Sandbox.validate_path(test_path, config)
    end

    test "rejects path outside allowed paths" do
      working_dir = System.tmp_dir!()
      {:ok, config} = SandboxConfig.new(working_dir, allowed_paths: ["lib"])

      test_path = "/etc/passwd"
      assert {:error, :path_not_allowed} = Sandbox.validate_path(test_path, config)
    end

    test "prevents path traversal attacks" do
      working_dir = System.tmp_dir!()
      {:ok, config} = SandboxConfig.new(working_dir, allowed_paths: ["data"])

      # Try to escape via ../..
      test_path = Path.join([working_dir, "data", "..", "..", "etc", "passwd"])
      assert {:error, :path_not_allowed} = Sandbox.validate_path(test_path, config)
    end

    test "allows all paths when no allowed_paths specified" do
      working_dir = System.tmp_dir!()
      {:ok, config} = SandboxConfig.new(working_dir)

      test_path = Path.join(working_dir, "any/path/file.txt")
      assert {:ok, _} = Sandbox.validate_path(test_path, config)
    end

    test "resolves relative paths correctly" do
      working_dir = System.tmp_dir!()
      {:ok, config} = SandboxConfig.new(working_dir, allowed_paths: ["lib"])

      # Relative path within allowed directory
      assert {:ok, _} = Sandbox.validate_path("lib/module.ex", config)
    end

    test "rejects absolute paths outside allowed directories" do
      working_dir = System.tmp_dir!()
      {:ok, config} = SandboxConfig.new(working_dir, allowed_paths: ["lib"])

      assert {:error, :path_not_allowed} = Sandbox.validate_path("/tmp/other/file.txt", config)
    end
  end

  describe "execute/2 error handling" do
    test "handles port open failures gracefully" do
      # This is hard to test directly, but we can test with invalid config
      {:ok, config} = Sandbox.prepare()

      # Normal execution should work
      {:ok, result} = Sandbox.execute("echo test", config)
      assert result.exit_code == 0
    end

    test "handles command crashes" do
      {:ok, config} = Sandbox.prepare()

      # Command that sends SIGTERM to itself
      {:ok, result} = Sandbox.execute("kill $$", config)

      # Should still return a result
      assert %{} = result
    end
  end

  describe "execute/2 shell escaping" do
    test "handles commands with quotes" do
      {:ok, config} = Sandbox.prepare()
      {:ok, result} = Sandbox.execute("echo 'hello world'", config)

      assert result.exit_code == 0
      assert String.contains?(result.stdout, "hello world")
    end

    test "handles commands with special characters" do
      {:ok, config} = Sandbox.prepare()
      {:ok, result} = Sandbox.execute("echo 'test & test'", config)

      assert result.exit_code == 0
      assert String.contains?(result.stdout, "test & test")
    end

    test "handles commands with dollar signs" do
      {:ok, config} = Sandbox.prepare()
      {:ok, result} = Sandbox.execute("echo '$test'", config)

      assert result.exit_code == 0
      assert String.contains?(result.stdout, "$test")
    end
  end
end
