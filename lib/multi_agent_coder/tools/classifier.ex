defmodule MultiAgentCoder.Tools.Classifier do
  @moduledoc """
  Classifies commands by danger level for approval workflows.

  Commands are classified into four categories:
  - `:safe` - Auto-approve (read operations, tests)
  - `:warning` - Prompt on first use (installs, commits)
  - `:dangerous` - Always require approval (destructive operations)
  - `:blocked` - Never allow (sudo, shell injection patterns)

  ## Usage

      iex> Classifier.classify("mix test")
      {:ok, %{level: :safe, reason: "Read-only or test operation"}}

      iex> Classifier.classify("mix deps.get")
      {:ok, %{level: :warning, reason: "Dependency installation"}}

      iex> Classifier.classify("rm -rf /")
      {:ok, %{level: :dangerous, reason: "Destructive file operation"}}

      iex> Classifier.classify("sudo rm -rf /")
      {:error, :blocked}

  ## Configuration

  Danger patterns can be customized via application config:

      config :multi_agent_coder, :tools,
        custom_safe_patterns: [~r/^my_safe_command/],
        custom_blocked_patterns: [~r/^forbidden/]
  """

  require Logger

  @type danger_level :: :safe | :warning | :dangerous | :blocked
  @type classification :: %{level: danger_level(), reason: String.t()}

  # Pattern lists are built at runtime to avoid compilation issues with Regex structs

  # Safe commands - Auto-approve
  defp safe_patterns_base do
    [
      # Testing
      {~r/^mix test($|\s)/, "Test execution"},
      {~r/^mix format --check-formatted($|\s)/, "Format check"},
      {~r/^mix compile($|\s)/, "Compilation"},
      {~r/^mix dialyzer($|\s)/, "Type checking"},
      {~r/^mix credo($|\s)/, "Code analysis"},
      {~r/^npm test($|\s)/, "Test execution"},
      {~r/^pytest($|\s)/, "Test execution"},
      {~r/^cargo test($|\s)/, "Test execution"},
      {~r/^go test($|\s)/, "Test execution"},

      # Git read operations
      {~r/^git status($|\s)/, "Git status check"},
      {~r/^git diff($|\s)/, "Git diff view"},
      {~r/^git log($|\s)/, "Git log view"},
      {~r/^git show($|\s)/, "Git show"},
      {~r/^git branch($|\s)/, "Git branch list"},
      {~r/^git remote($|\s)/, "Git remote list"},

      # File read operations
      {~r/^cat\s+/, "File read"},
      {~r/^head\s+/, "File read"},
      {~r/^tail\s+/, "File read"},
      {~r/^less\s+/, "File view"},
      {~r/^more\s+/, "File view"},
      {~r/^grep\s+/, "Text search"},
      {~r/^find\s+/, "File search"},
      {~r/^ls($|\s)/, "Directory listing"},
      {~r/^pwd($|\s)/, "Working directory"},
      {~r/^echo\s+/, "Echo output"},
      {~r/^env($|\s)/, "Environment variables"},
      {~r/^printenv($|\s)/, "Environment variables"},

      # Build operations (safe)
      {~r/^mix deps\.tree($|\s)/, "Dependency tree"},
      {~r/^npm list($|\s)/, "Package list"},
      {~r/^cargo build($|\s)/, "Build"},
      {~r/^go build($|\s)/, "Build"}
    ]
  end

  # Warning commands - Prompt on first use
  defp warning_patterns_base do
    [
      # Dependency management
      {~r/^mix deps\.get($|\s)/, "Dependency installation"},
      {~r/^mix deps\.update($|\s)/, "Dependency update"},
      {~r/^npm install($|\s)/, "Package installation"},
      {~r/^npm update($|\s)/, "Package update"},
      {~r/^yarn install($|\s)/, "Package installation"},
      {~r/^pip install($|\s)/, "Package installation"},
      {~r/^cargo add($|\s)/, "Dependency addition"},
      {~r/^go get($|\s)/, "Package installation"},

      # Git write operations
      {~r/^git add($|\s)/, "Stage changes"},
      {~r/^git commit($|\s)/, "Create commit"},
      {~r/^git push(?!\s+(--force|-f))($|\s)/, "Push to remote"},
      {~r/^git pull($|\s)/, "Pull from remote"},
      {~r/^git merge($|\s)/, "Merge branches"},
      {~r/^git rebase(?!\s+-i)($|\s)/, "Rebase branch"},
      {~r/^git checkout($|\s)/, "Checkout branch"},
      {~r/^git stash($|\s)/, "Stash changes"},

      # File modifications
      {~r/^mix format(?!\s+--check)($|\s)/, "Format code"},
      {~r/^touch\s+/, "Create file"},
      {~r/^mkdir\s+/, "Create directory"},
      {~r/^cp\s+/, "Copy files"},
      {~r/^mv\s+/, "Move files"}
    ]
  end

  # Dangerous commands - Always require approval
  defp dangerous_patterns_base do
    [
      # Destructive file operations
      {~r/^rm\s+-rf\s+/, "Destructive file operation"},
      {~r/^rm\s+-fr\s+/, "Destructive file operation"},
      {~r/^rm\s+.*-r.*-f/, "Destructive file operation"},
      {~r/^rm\s+.*-f.*-r/, "Destructive file operation"},

      # Database operations
      {~r/^mix ecto\.drop($|\s)/, "Database deletion"},
      {~r/^mix ecto\.reset($|\s)/, "Database reset"},
      {~r/^mix ecto\.rollback($|\s)/, "Database rollback"},
      {~r/^psql.*DROP\s+DATABASE/, "Database deletion"},
      {~r/^mysql.*DROP\s+DATABASE/, "Database deletion"},

      # Git force operations
      {~r/^git push\s+(--force|-f)($|\s)/, "Force push"},
      {~r/^git reset\s+--hard($|\s)/, "Hard reset"},
      {~r/^git clean\s+-fd($|\s)/, "Clean untracked files"},
      {~r/^git rebase\s+-i($|\s)/, "Interactive rebase"},

      # Build/release operations
      {~r/^mix release($|\s)/, "Release build"},
      {~r/^mix deploy($|\s)/, "Deployment"},
      {~r/^npm publish($|\s)/, "Package publish"},
      {~r/^cargo publish($|\s)/, "Package publish"},

      # System modifications
      {~r/^chmod\s+777\s+/, "Permissive file permissions"},
      {~r/^chown\s+/, "Change file ownership"}
    ]
  end

  # Blocked commands - Never allow
  defp blocked_patterns_base do
    [
      # Privilege escalation
      {~r/^sudo\s+/, "Privilege escalation not allowed"},
      {~r/^su\s+/, "User switching not allowed"},
      {~r/^doas\s+/, "Privilege escalation not allowed"},

      # Shell injection patterns
      {~r/curl\s+.*\|\s*(sh|bash|zsh)/, "Piped shell execution not allowed"},
      {~r/wget\s+.*\|\s*(sh|bash|zsh)/, "Piped shell execution not allowed"},
      {~r/;\s*rm\s+-rf/, "Command chaining with rm -rf not allowed"},
      {~r/&&\s*rm\s+-rf/, "Command chaining with rm -rf not allowed"},

      # System critical operations
      {~r/^dd\s+if=.*of=\/dev\//, "Direct disk write not allowed"},
      {~r/^mkfs/, "Filesystem creation not allowed"},
      {~r/^fdisk/, "Disk partitioning not allowed"},

      # Network/security risks
      {~r/nc\s+.*-e\s+\/bin\//, "Reverse shell not allowed"},
      {~r/\/bin\/sh\s+-i/, "Interactive shell spawn not allowed"}
    ]
  end

  @doc """
  Classify a command by its danger level.

  Returns `{:ok, %{level: level, reason: reason}}` for allowed commands,
  or `{:error, :blocked}` for blocked commands.

  ## Examples

      iex> Classifier.classify("mix test")
      {:ok, %{level: :safe, reason: "Test execution"}}

      iex> Classifier.classify("sudo rm -rf /")
      {:error, :blocked}
  """
  @spec classify(String.t()) :: {:ok, classification()} | {:error, :blocked}
  def classify(command) when is_binary(command) do
    command = String.trim(command)

    cond do
      matches_pattern?(command, blocked_patterns()) ->
        Logger.warn("Blocked command attempted: #{command}")
        {:error, :blocked}

      match = find_matching_pattern(command, dangerous_patterns()) ->
        {:ok, %{level: :dangerous, reason: match}}

      match = find_matching_pattern(command, warning_patterns()) ->
        {:ok, %{level: :warning, reason: match}}

      match = find_matching_pattern(command, safe_patterns()) ->
        {:ok, %{level: :safe, reason: match}}

      true ->
        Logger.debug("Unknown command classification: #{command}")
        {:ok, %{level: :warning, reason: "Unknown command - requires review"}}
    end
  end

  def classify(_), do: {:error, :invalid_command}

  @doc """
  Check if a command matches a blocked pattern.

  ## Examples

      iex> Classifier.blocked?("sudo rm -rf /")
      true

      iex> Classifier.blocked?("mix test")
      false
  """
  @spec blocked?(String.t()) :: boolean()
  def blocked?(command) when is_binary(command) do
    matches_pattern?(command, blocked_patterns())
  end

  def blocked?(_), do: false

  @doc """
  Get the list of safe command patterns.

  Returns a list of `{regex, reason}` tuples.
  """
  @spec safe_patterns() :: list({Regex.t(), String.t()})
  def safe_patterns do
    custom_patterns = get_custom_patterns(:custom_safe_patterns)
    safe_patterns_list() ++ custom_patterns
  end

  @doc """
  Get the list of warning command patterns.
  """
  @spec warning_patterns() :: list({Regex.t(), String.t()})
  def warning_patterns do
    custom_patterns = get_custom_patterns(:custom_warning_patterns)
    warning_patterns_list() ++ custom_patterns
  end

  @doc """
  Get the list of dangerous command patterns.
  """
  @spec dangerous_patterns() :: list({Regex.t(), String.t()})
  def dangerous_patterns do
    custom_patterns = get_custom_patterns(:custom_dangerous_patterns)
    dangerous_patterns_list() ++ custom_patterns
  end

  @doc """
  Get the list of blocked command patterns.
  """
  @spec blocked_patterns() :: list({Regex.t(), String.t()})
  def blocked_patterns do
    custom_patterns = get_custom_patterns(:custom_blocked_patterns)
    blocked_patterns_list() ++ custom_patterns
  end

  # Private pattern accessors

  defp safe_patterns_list, do: safe_patterns_base()
  defp warning_patterns_list, do: warning_patterns_base()
  defp dangerous_patterns_list, do: dangerous_patterns_base()
  defp blocked_patterns_list, do: blocked_patterns_base()

  @doc """
  Get a human-readable explanation of a danger level.

  ## Examples

      iex> Classifier.explain_level(:safe)
      "Safe - Auto-approved for execution"
  """
  @spec explain_level(danger_level()) :: String.t()
  def explain_level(:safe) do
    "Safe - Auto-approved for execution"
  end

  def explain_level(:warning) do
    "Warning - May modify system state, requires approval on first use"
  end

  def explain_level(:dangerous) do
    "Dangerous - Potentially destructive operation, always requires explicit approval"
  end

  def explain_level(:blocked) do
    "Blocked - Operation not allowed under any circumstances"
  end

  # Private Functions

  defp matches_pattern?(command, patterns) do
    Enum.any?(patterns, fn
      {pattern, _reason} -> Regex.match?(pattern, command)
      pattern when is_struct(pattern, Regex) -> Regex.match?(pattern, command)
    end)
  end

  defp find_matching_pattern(command, patterns) do
    case Enum.find(patterns, fn {pattern, _reason} -> Regex.match?(pattern, command) end) do
      {_pattern, reason} -> reason
      nil -> nil
    end
  end

  defp get_custom_patterns(key) do
    Application.get_env(:multi_agent_coder, :tools, [])
    |> Keyword.get(key, [])
    |> Enum.map(fn
      {pattern, reason} -> {pattern, reason}
      pattern -> {pattern, "Custom pattern"}
    end)
  end
end
