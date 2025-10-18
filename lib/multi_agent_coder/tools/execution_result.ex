defmodule MultiAgentCoder.Tools.ExecutionResult do
  @moduledoc """
  Represents the result of a tool execution.

  This struct contains all output and metadata from executing a tool command,
  including status, output streams, timing information, and any errors.
  """

  alias MultiAgentCoder.Tools.ToolRequest

  @type status :: :completed | :failed | :timeout | :cancelled

  @type t :: %__MODULE__{
          command_id: String.t(),
          request: ToolRequest.t() | nil,
          provider: atom(),
          status: status(),
          exit_code: integer() | nil,
          stdout: String.t(),
          stderr: String.t(),
          duration_ms: non_neg_integer(),
          started_at: DateTime.t(),
          completed_at: DateTime.t() | nil,
          error: term() | nil,
          metadata: map()
        }

  @enforce_keys [:command_id, :provider, :status]
  defstruct [
    :command_id,
    :request,
    :provider,
    :status,
    :started_at,
    exit_code: nil,
    stdout: "",
    stderr: "",
    duration_ms: 0,
    completed_at: nil,
    error: nil,
    metadata: %{}
  ]

  @doc """
  Creates a new execution result for a successful execution.

  ## Examples

      iex> ExecutionResult.success("cmd_123", :openai, "output", 150)
      %ExecutionResult{status: :completed, exit_code: 0, stdout: "output"}
  """
  @spec success(String.t(), atom(), String.t(), non_neg_integer(), keyword()) :: t()
  def success(command_id, provider, stdout, duration_ms, opts \\ []) do
    now = DateTime.utc_now()

    %__MODULE__{
      command_id: command_id,
      request: Keyword.get(opts, :request),
      provider: provider,
      status: :completed,
      exit_code: 0,
      stdout: stdout,
      stderr: Keyword.get(opts, :stderr, ""),
      duration_ms: duration_ms,
      started_at: Keyword.get(opts, :started_at, now),
      completed_at: now,
      metadata: Keyword.get(opts, :metadata, %{})
    }
  end

  @doc """
  Creates a new execution result for a failed execution.

  ## Examples

      iex> ExecutionResult.failure("cmd_123", :anthropic, 1, "error output", 100)
      %ExecutionResult{status: :failed, exit_code: 1, stderr: "error output"}
  """
  @spec failure(String.t(), atom(), integer(), String.t(), non_neg_integer(), keyword()) :: t()
  def failure(command_id, provider, exit_code, stderr, duration_ms, opts \\ []) do
    now = DateTime.utc_now()

    %__MODULE__{
      command_id: command_id,
      request: Keyword.get(opts, :request),
      provider: provider,
      status: :failed,
      exit_code: exit_code,
      stdout: Keyword.get(opts, :stdout, ""),
      stderr: stderr,
      duration_ms: duration_ms,
      started_at: Keyword.get(opts, :started_at, now),
      completed_at: now,
      error: Keyword.get(opts, :error),
      metadata: Keyword.get(opts, :metadata, %{})
    }
  end

  @doc """
  Creates a new execution result for a timeout.

  ## Examples

      iex> ExecutionResult.timeout("cmd_123", :deepseek, 5000)
      %ExecutionResult{status: :timeout, duration_ms: 5000}
  """
  @spec timeout(String.t(), atom(), non_neg_integer(), keyword()) :: t()
  def timeout(command_id, provider, duration_ms, opts \\ []) do
    now = DateTime.utc_now()

    %__MODULE__{
      command_id: command_id,
      request: Keyword.get(opts, :request),
      provider: provider,
      status: :timeout,
      exit_code: nil,
      stdout: Keyword.get(opts, :stdout, ""),
      stderr: Keyword.get(opts, :stderr, ""),
      duration_ms: duration_ms,
      started_at: Keyword.get(opts, :started_at, now),
      completed_at: now,
      error: :timeout,
      metadata: Keyword.get(opts, :metadata, %{})
    }
  end

  @doc """
  Creates a new execution result for an error.

  ## Examples

      iex> ExecutionResult.error("cmd_123", :openai, "Command not found", 50)
      %ExecutionResult{status: :failed, error: "Command not found"}
  """
  @spec error(String.t(), atom(), term(), non_neg_integer(), keyword()) :: t()
  def error(command_id, provider, error, duration_ms, opts \\ []) do
    now = DateTime.utc_now()

    %__MODULE__{
      command_id: command_id,
      request: Keyword.get(opts, :request),
      provider: provider,
      status: :failed,
      exit_code: nil,
      stdout: Keyword.get(opts, :stdout, ""),
      stderr: Keyword.get(opts, :stderr, ""),
      duration_ms: duration_ms,
      started_at: Keyword.get(opts, :started_at, now),
      completed_at: now,
      error: error,
      metadata: Keyword.get(opts, :metadata, %{})
    }
  end

  @doc """
  Checks if the execution was successful.

  ## Examples

      iex> result = ExecutionResult.success("cmd_1", :openai, "ok", 100)
      iex> ExecutionResult.success?(result)
      true

      iex> result = ExecutionResult.failure("cmd_1", :openai, 1, "error", 100)
      iex> ExecutionResult.success?(result)
      false
  """
  @spec success?(t()) :: boolean()
  def success?(%__MODULE__{status: :completed, exit_code: 0}), do: true
  def success?(%__MODULE__{}), do: false

  @doc """
  Checks if the execution failed.

  ## Examples

      iex> result = ExecutionResult.failure("cmd_1", :openai, 1, "error", 100)
      iex> ExecutionResult.failed?(result)
      true
  """
  @spec failed?(t()) :: boolean()
  def failed?(%__MODULE__{status: :failed}), do: true
  def failed?(%__MODULE__{status: :timeout}), do: true
  def failed?(%__MODULE__{}), do: false

  @doc """
  Gets a human-readable summary of the result.

  ## Examples

      iex> result = ExecutionResult.success("cmd_1", :openai, "ok", 150)
      iex> ExecutionResult.summary(result)
      "Completed successfully in 150ms"
  """
  @spec summary(t()) :: String.t()
  def summary(%__MODULE__{status: :completed, duration_ms: duration}) do
    "Completed successfully in #{duration}ms"
  end

  def summary(%__MODULE__{status: :failed, exit_code: code, duration_ms: duration})
      when is_integer(code) do
    "Failed with exit code #{code} in #{duration}ms"
  end

  def summary(%__MODULE__{status: :failed, error: error, duration_ms: duration}) do
    "Failed with error: #{inspect(error)} in #{duration}ms"
  end

  def summary(%__MODULE__{status: :timeout, duration_ms: duration}) do
    "Timed out after #{duration}ms"
  end

  def summary(%__MODULE__{status: :cancelled}) do
    "Cancelled"
  end

  @doc """
  Formats the result for logging or display.

  ## Examples

      iex> result = ExecutionResult.success("cmd_1", :openai, "hello\\n", 100)
      iex> ExecutionResult.format(result)
      "[cmd_1] openai: Completed successfully in 100ms\\nOutput: hello\\n"
  """
  @spec format(t()) :: String.t()
  def format(%__MODULE__{} = result) do
    base = "[#{result.command_id}] #{result.provider}: #{summary(result)}"

    output_parts = []

    output_parts =
      if result.stdout != "" and result.status == :completed do
        ["Output: #{String.trim(result.stdout)}" | output_parts]
      else
        output_parts
      end

    output_parts =
      if result.stderr != "" do
        ["Error: #{String.trim(result.stderr)}" | output_parts]
      else
        output_parts
      end

    if Enum.empty?(output_parts) do
      base
    else
      base <> "\n" <> Enum.join(Enum.reverse(output_parts), "\n")
    end
  end
end
