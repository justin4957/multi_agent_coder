defmodule MultiAgentCoder.Tools.ToolRequest do
  @moduledoc """
  Represents a tool execution request from a provider.

  This struct encapsulates all information needed to execute a tool command,
  including the command type, arguments, provider context, and execution constraints.
  """

  @type tool_type :: :bash | :file_read | :file_write | :file_delete | :git

  @type t :: %__MODULE__{
          id: String.t(),
          type: tool_type(),
          command: String.t(),
          args: list(String.t()),
          provider_id: atom(),
          timeout: pos_integer(),
          working_dir: String.t() | nil,
          env: map(),
          metadata: map()
        }

  @enforce_keys [:type, :command, :provider_id]
  defstruct [
    :id,
    :type,
    :command,
    :provider_id,
    args: [],
    timeout: 30_000,
    working_dir: nil,
    env: %{},
    metadata: %{}
  ]

  @doc """
  Creates a new tool request with validation.

  ## Examples

      iex> ToolRequest.new(:bash, "ls -la", :openai)
      {:ok, %ToolRequest{type: :bash, command: "ls -la", provider_id: :openai}}

      iex> ToolRequest.new(:invalid, "cmd", :openai)
      {:error, "Invalid tool type: :invalid"}
  """
  @spec new(tool_type(), String.t(), atom(), keyword()) :: {:ok, t()} | {:error, String.t()}
  def new(type, command, provider_id, opts \\ []) do
    with :ok <- validate_type(type),
         :ok <- validate_command(command),
         :ok <- validate_provider_id(provider_id) do
      request = %__MODULE__{
        id: generate_id(),
        type: type,
        command: command,
        provider_id: provider_id,
        args: Keyword.get(opts, :args, []),
        timeout: Keyword.get(opts, :timeout, 30_000),
        working_dir: Keyword.get(opts, :working_dir),
        env: Keyword.get(opts, :env, %{}),
        metadata: Keyword.get(opts, :metadata, %{})
      }

      {:ok, request}
    end
  end

  @doc """
  Creates a new tool request, raising on error.

  ## Examples

      iex> ToolRequest.new!(:bash, "echo hello", :anthropic)
      %ToolRequest{type: :bash, command: "echo hello", provider_id: :anthropic}
  """
  @spec new!(tool_type(), String.t(), atom(), keyword()) :: t()
  def new!(type, command, provider_id, opts \\ []) do
    case new(type, command, provider_id, opts) do
      {:ok, request} -> request
      {:error, reason} -> raise ArgumentError, reason
    end
  end

  @doc """
  Creates a bash command request.

  ## Examples

      iex> ToolRequest.bash("pwd", :openai)
      {:ok, %ToolRequest{type: :bash, command: "pwd"}}
  """
  @spec bash(String.t(), atom(), keyword()) :: {:ok, t()} | {:error, String.t()}
  def bash(command, provider_id, opts \\ []) do
    new(:bash, command, provider_id, opts)
  end

  @doc """
  Creates a file read request.

  ## Examples

      iex> ToolRequest.file_read("/path/to/file", :anthropic)
      {:ok, %ToolRequest{type: :file_read, command: "/path/to/file"}}
  """
  @spec file_read(String.t(), atom(), keyword()) :: {:ok, t()} | {:error, String.t()}
  def file_read(path, provider_id, opts \\ []) do
    new(:file_read, path, provider_id, opts)
  end

  @doc """
  Creates a file write request.

  ## Examples

      iex> ToolRequest.file_write("/path/to/file", "content", :openai)
      {:ok, %ToolRequest{type: :file_write, command: "/path/to/file", args: ["content"]}}
  """
  @spec file_write(String.t(), String.t(), atom(), keyword()) ::
          {:ok, t()} | {:error, String.t()}
  def file_write(path, content, provider_id, opts \\ []) do
    opts = Keyword.put(opts, :args, [content])
    new(:file_write, path, provider_id, opts)
  end

  @doc """
  Creates a git command request.

  ## Examples

      iex> ToolRequest.git("status", :deepseek)
      {:ok, %ToolRequest{type: :git, command: "status"}}
  """
  @spec git(String.t(), atom(), keyword()) :: {:ok, t()} | {:error, String.t()}
  def git(command, provider_id, opts \\ []) do
    new(:git, command, provider_id, opts)
  end

  # Private Functions

  defp validate_type(type) when type in [:bash, :file_read, :file_write, :file_delete, :git] do
    :ok
  end

  defp validate_type(type) do
    {:error, "Invalid tool type: #{inspect(type)}"}
  end

  defp validate_command(command) when is_binary(command) and byte_size(command) > 0 do
    :ok
  end

  defp validate_command(_) do
    {:error, "Command must be a non-empty string"}
  end

  defp validate_provider_id(provider_id) when is_atom(provider_id) do
    :ok
  end

  defp validate_provider_id(_) do
    {:error, "Provider ID must be an atom"}
  end

  defp generate_id do
    "tool_#{System.system_time(:nanosecond)}_#{:rand.uniform(10000)}"
  end
end
