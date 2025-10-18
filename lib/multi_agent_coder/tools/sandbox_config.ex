defmodule MultiAgentCoder.Tools.SandboxConfig do
  @moduledoc """
  Configuration for sandboxed command execution.

  Defines the execution environment, resource limits, and security constraints
  for commands executed in the sandbox.
  """

  @type resource_limits :: %{
          max_memory_mb: pos_integer(),
          max_cpu_percent: pos_integer(),
          timeout_ms: pos_integer()
        }

  @type t :: %__MODULE__{
          working_dir: Path.t(),
          allowed_paths: [Path.t()],
          env_vars: map(),
          resource_limits: resource_limits()
        }

  @enforce_keys [:working_dir]
  defstruct [
    :working_dir,
    allowed_paths: [],
    env_vars: %{},
    resource_limits: %{
      max_memory_mb: 512,
      max_cpu_percent: 80,
      timeout_ms: 300_000
    }
  ]

  @doc """
  Creates a new sandbox configuration.

  ## Examples

      iex> SandboxConfig.new("/tmp/sandbox")
      {:ok, %SandboxConfig{working_dir: "/tmp/sandbox"}}

      iex> SandboxConfig.new("/tmp", allowed_paths: ["lib", "test"])
      {:ok, %SandboxConfig{working_dir: "/tmp", allowed_paths: ["lib", "test"]}}

  ## Options

  - `:allowed_paths` - List of allowed directory paths (relative to working_dir)
  - `:env_vars` - Environment variables to set for command execution
  - `:resource_limits` - Resource limit overrides

  """
  @spec new(Path.t(), keyword()) :: {:ok, t()} | {:error, String.t()}
  def new(working_dir, opts \\ []) do
    with :ok <- validate_working_dir(working_dir) do
      config = %__MODULE__{
        working_dir: Path.expand(working_dir),
        allowed_paths: expand_allowed_paths(working_dir, Keyword.get(opts, :allowed_paths, [])),
        env_vars: Keyword.get(opts, :env_vars, %{}),
        resource_limits: merge_resource_limits(Keyword.get(opts, :resource_limits, %{}))
      }

      {:ok, config}
    end
  end

  @doc """
  Creates a new sandbox configuration, raising on error.

  ## Examples

      iex> SandboxConfig.new!("/tmp/sandbox")
      %SandboxConfig{working_dir: "/tmp/sandbox"}

  """
  @spec new!(Path.t(), keyword()) :: t()
  def new!(working_dir, opts \\ []) do
    case new(working_dir, opts) do
      {:ok, config} -> config
      {:error, reason} -> raise ArgumentError, reason
    end
  end

  @doc """
  Creates a default sandbox configuration using the current working directory.

  ## Examples

      iex> SandboxConfig.default()
      {:ok, %SandboxConfig{working_dir: "/path/to/project"}}

  """
  @spec default() :: {:ok, t()}
  def default do
    working_dir = File.cwd!()

    new(working_dir,
      allowed_paths: ["lib", "test", "config", "priv"],
      env_vars: %{}
    )
  end

  @doc """
  Updates resource limits for the configuration.

  ## Examples

      iex> config = SandboxConfig.new!("/tmp")
      iex> SandboxConfig.with_limits(config, timeout_ms: 60_000)
      %SandboxConfig{resource_limits: %{timeout_ms: 60_000, ...}}

  """
  @spec with_limits(t(), keyword()) :: t()
  def with_limits(%__MODULE__{} = config, limits) do
    updated_limits = Map.merge(config.resource_limits, Map.new(limits))
    %{config | resource_limits: updated_limits}
  end

  @doc """
  Adds an allowed path to the configuration.

  ## Examples

      iex> config = SandboxConfig.new!("/tmp")
      iex> SandboxConfig.allow_path(config, "extras")
      %SandboxConfig{allowed_paths: [..., "/tmp/extras"]}

  """
  @spec allow_path(t(), Path.t()) :: t()
  def allow_path(%__MODULE__{} = config, path) do
    expanded = Path.expand(path, config.working_dir)
    %{config | allowed_paths: [expanded | config.allowed_paths]}
  end

  @doc """
  Sets environment variables for the configuration.

  ## Examples

      iex> config = SandboxConfig.new!("/tmp")
      iex> SandboxConfig.with_env(config, %{"MIX_ENV" => "test"})
      %SandboxConfig{env_vars: %{"MIX_ENV" => "test"}}

  """
  @spec with_env(t(), map()) :: t()
  def with_env(%__MODULE__{} = config, env_vars) do
    %{config | env_vars: Map.merge(config.env_vars, env_vars)}
  end

  # Private Functions

  defp validate_working_dir(working_dir) when is_binary(working_dir) do
    expanded = Path.expand(working_dir)

    if File.dir?(expanded) do
      :ok
    else
      {:error, "Working directory does not exist: #{expanded}"}
    end
  end

  defp validate_working_dir(_) do
    {:error, "Working directory must be a string"}
  end

  defp expand_allowed_paths(working_dir, paths) do
    Enum.map(paths, fn path ->
      Path.expand(path, working_dir)
    end)
  end

  defp merge_resource_limits(custom_limits) do
    default_limits = %{
      max_memory_mb: 512,
      max_cpu_percent: 80,
      timeout_ms: 300_000
    }

    Map.merge(default_limits, Map.new(custom_limits))
  end
end
