defmodule MultiAgentCoder.Tools.Classifier do
  @moduledoc """
  Classifies commands by danger level for approval workflows.

  Commands are classified into four categories:
  - :safe - Auto-approve (read operations, tests)
  - :warning - Prompt on first use (installs, commits)
  - :dangerous - Always require approval (destructive operations)
  - :blocked - Never allow (sudo, shell injection patterns)

  ## Implementation Status: STUB

  This module is a stub for architecture planning. Implementation tracked in:
  - Issue #16.3: Command classification and safety system
  """

  @type danger_level :: :safe | :warning | :dangerous | :blocked

  @doc """
  Classify a command by its danger level.

  Returns {:ok, %{level: level, reason: reason}} or {:error, :blocked}
  """
  @spec classify(String.t()) :: {:ok, map()} | {:error, :blocked}
  def classify(_command) do
    {:error, :not_implemented}
  end

  @doc """
  Check if a command matches a blocked pattern.
  """
  @spec blocked?(String.t()) :: boolean()
  def blocked?(_command) do
    false
  end

  @doc """
  Get the list of safe command patterns.
  """
  @spec safe_patterns() :: list(Regex.t())
  def safe_patterns do
    []
  end
end
