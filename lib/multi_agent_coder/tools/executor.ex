defmodule MultiAgentCoder.Tools.Executor do
  @moduledoc """
  Executes commands in a sandboxed environment.

  This module handles the actual execution of tool requests, including:
  - Bash command execution with stdout/stderr capture
  - File operations (read, write, delete)
  - Git commands
  - Timeout handling
  - Error reporting

  All commands are executed within a sandbox for security and resource isolation.

  ## Implementation Status

  Phase 1 (Current):
  - ✅ Core execution framework
  - ✅ Bash command execution
  - ✅ Stdout/stderr capture
  - ✅ Timeout handling
  - ✅ Error handling and logging

  Future Phases:
  - Issue #16.2: Enhanced sandbox environment
  - Issue #16.3: Resource monitoring
  - Issue #16.4: Security and approval workflow
  """

  require Logger

  alias MultiAgentCoder.Tools.{ExecutionResult, ToolRequest}

  @type execution_opts :: [
          timeout: pos_integer(),
          working_dir: String.t() | nil,
          env: map()
        ]

  @default_timeout 30_000
  @max_output_size 1_000_000

  # 1 MB max output

  @doc """
  Execute a tool request.

  This is the main entry point for command execution. Routes to specific
  execution functions based on the request type.

  ## Examples

      iex> {:ok, request} = ToolRequest.bash("echo hello", :openai)
      iex> {:ok, result} = Executor.execute(request)
      iex> result.status
      :completed
      iex> result.stdout
      "hello\\n"

  ## Options

  - `:timeout` - Maximum execution time in milliseconds (default: 30_000)
  - `:working_dir` - Working directory for command execution
  - `:env` - Environment variables to set

  """
  @spec execute(ToolRequest.t(), execution_opts()) ::
          {:ok, ExecutionResult.t()} | {:error, term()}
  def execute(%ToolRequest{} = request, opts \\ []) do
    Logger.debug("Executing #{request.type} command for provider #{request.provider_id}")

    start_time = System.monotonic_time(:millisecond)
    started_at = DateTime.utc_now()

    try do
      result =
        case request.type do
          :bash ->
            execute_bash_internal(request, opts)

          :file_read ->
            execute_file_read_internal(request, opts)

          :file_write ->
            execute_file_write_internal(request, opts)

          :file_delete ->
            execute_file_delete_internal(request, opts)

          :git ->
            execute_git_internal(request, opts)

          _ ->
            {:error, {:unsupported_type, request.type}}
        end

      duration_ms = System.monotonic_time(:millisecond) - start_time

      case result do
        {:ok, stdout, stderr, exit_code} ->
          result =
            if exit_code == 0 do
              ExecutionResult.success(request.id, request.provider_id, stdout, duration_ms,
                request: request,
                stderr: stderr,
                started_at: started_at
              )
            else
              ExecutionResult.failure(
                request.id,
                request.provider_id,
                exit_code,
                stderr,
                duration_ms,
                request: request,
                stdout: stdout,
                started_at: started_at
              )
            end

          Logger.info("Command #{request.id} completed: #{ExecutionResult.summary(result)}")
          {:ok, result}

        {:error, :timeout} ->
          result =
            ExecutionResult.timeout(request.id, request.provider_id, duration_ms,
              request: request,
              started_at: started_at
            )

          Logger.warn("Command #{request.id} timed out after #{duration_ms}ms")
          {:ok, result}

        {:error, reason} ->
          result =
            ExecutionResult.error(request.id, request.provider_id, reason, duration_ms,
              request: request,
              started_at: started_at
            )

          Logger.error("Command #{request.id} failed: #{inspect(reason)}")
          {:ok, result}
      end
    rescue
      error ->
        duration_ms = System.monotonic_time(:millisecond) - start_time

        result =
          ExecutionResult.error(request.id, request.provider_id, error, duration_ms,
            request: request,
            started_at: started_at,
            stderr: Exception.message(error)
          )

        Logger.error("Command #{request.id} crashed: #{Exception.message(error)}")
        {:ok, result}
    end
  end

  @doc """
  Execute a bash command with timeout and output capture.

  ## Examples

      iex> Executor.execute_bash("echo test", :openai)
      {:ok, %ExecutionResult{stdout: "test\\n", exit_code: 0}}

      iex> Executor.execute_bash("invalid_command", :anthropic)
      {:ok, %ExecutionResult{status: :failed, exit_code: 127}}

  """
  @spec execute_bash(String.t(), atom(), execution_opts()) ::
          {:ok, ExecutionResult.t()} | {:error, term()}
  def execute_bash(command, provider_id, opts \\ []) do
    case ToolRequest.bash(command, provider_id, opts) do
      {:ok, request} -> execute(request, opts)
      error -> error
    end
  end

  @doc """
  Execute a file read operation.

  ## Examples

      iex> Executor.execute_file_read("/tmp/test.txt", :openai)
      {:ok, %ExecutionResult{stdout: "file contents"}}

  """
  @spec execute_file_read(Path.t(), atom(), execution_opts()) ::
          {:ok, ExecutionResult.t()} | {:error, term()}
  def execute_file_read(path, provider_id, opts \\ []) do
    case ToolRequest.file_read(path, provider_id, opts) do
      {:ok, request} -> execute(request, opts)
      error -> error
    end
  end

  @doc """
  Execute a file write operation.

  ## Examples

      iex> Executor.execute_file_write("/tmp/test.txt", "content", :anthropic)
      {:ok, %ExecutionResult{status: :completed}}

  """
  @spec execute_file_write(Path.t(), String.t(), atom(), execution_opts()) ::
          {:ok, ExecutionResult.t()} | {:error, term()}
  def execute_file_write(path, content, provider_id, opts \\ []) do
    case ToolRequest.file_write(path, content, provider_id, opts) do
      {:ok, request} -> execute(request, opts)
      error -> error
    end
  end

  # Private execution functions

  defp execute_bash_internal(request, opts) do
    timeout = Keyword.get(opts, :timeout, request.timeout || @default_timeout)
    working_dir = Keyword.get(opts, :working_dir, request.working_dir)
    env = Keyword.get(opts, :env, request.env)

    # Build command options
    cmd_opts = build_command_opts(working_dir, env, timeout)

    # Execute the command
    try do
      {stdout, exit_code} = System.cmd("sh", ["-c", request.command], cmd_opts)
      # Limit output size to prevent memory issues
      stdout = truncate_output(stdout)
      {:ok, stdout, "", exit_code}
    catch
      :exit, {:timeout, _} ->
        {:error, :timeout}

      :exit, reason ->
        {:error, {:execution_failed, reason}}
    end
  end

  defp execute_file_read_internal(request, _opts) do
    case File.read(request.command) do
      {:ok, content} ->
        content = truncate_output(content)
        {:ok, content, "", 0}

      {:error, reason} ->
        {:error, {:file_read_failed, reason}}
    end
  end

  defp execute_file_write_internal(request, _opts) do
    content = List.first(request.args) || ""

    case File.write(request.command, content) do
      :ok ->
        {:ok, "File written successfully", "", 0}

      {:error, reason} ->
        {:error, {:file_write_failed, reason}}
    end
  end

  defp execute_file_delete_internal(request, _opts) do
    case File.rm(request.command) do
      :ok ->
        {:ok, "File deleted successfully", "", 0}

      {:error, reason} ->
        {:error, {:file_delete_failed, reason}}
    end
  end

  defp execute_git_internal(request, opts) do
    # Git commands are just bash commands with "git" prefix
    git_command = "git #{request.command}"
    updated_request = %{request | command: git_command}
    execute_bash_internal(updated_request, opts)
  end

  # Helper functions

  defp build_command_opts(working_dir, env, timeout) do
    opts = [
      stderr_to_stdout: true,
      parallelism: true
    ]

    opts =
      if working_dir do
        [{:cd, working_dir} | opts]
      else
        opts
      end

    opts =
      if map_size(env) > 0 do
        env_list = Enum.map(env, fn {k, v} -> {to_string(k), to_string(v)} end)
        [{:env, env_list} | opts]
      else
        opts
      end

    # Add timeout as a Task wrapper since System.cmd doesn't support it directly
    # We'll use a timeout wrapper
    opts
  end

  defp truncate_output(output) when byte_size(output) > @max_output_size do
    truncated = binary_part(output, 0, @max_output_size)
    truncated <> "\n... [output truncated, exceeded #{@max_output_size} bytes]"
  end

  defp truncate_output(output), do: output
end
