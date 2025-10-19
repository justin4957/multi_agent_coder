defmodule MultiAgentCoder.Tools.Approver do
  @moduledoc """
  Handles command approval workflows based on danger level.

  Implements approval logic including:
  - Auto-approval for safe commands
  - Interactive prompts for warning/dangerous commands
  - Approval history and "trust for session" functionality
  - Configurable approval modes

  ## Configuration

      config :multi_agent_coder, :tools,
        approval_mode: :auto,           # :auto | :prompt | :deny_all | :allow_all
        auto_approve_safe: true,        # Auto-approve safe commands
        prompt_on_warning: true,        # Prompt for warning commands
        always_prompt_dangerous: true,  # Always prompt for dangerous
        trust_for_session: true         # Remember approvals

  ## Approval Modes

  - `:auto` - Auto-approve safe, prompt for warning/dangerous (default)
  - `:prompt` - Prompt for all commands
  - `:deny_all` - Deny all commands
  - `:allow_all` - Approve all commands (dangerous!)

  ## Usage

      # Classify and check approval
      {:ok, classification} = Classifier.classify("mix deps.get")
      {:ok, result} = Approver.check_approval(classification, "mix deps.get", :openai)

      case result do
        :approved -> # Execute command
        :denied -> # Reject command
        :queued -> # Queue for later approval
      end
  """

  require Logger

  alias MultiAgentCoder.Tools.{Classifier, ApprovalHistory}

  @type approval_result :: :approved | :denied | :queued
  @type approval_mode :: :auto | :prompt | :deny_all | :allow_all

  @doc """
  Check if a command should be approved for execution.

  Takes a classified command and returns the approval decision based on
  the danger level and configuration.

  ## Examples

      iex> classification = %{level: :safe, reason: "Test execution"}
      iex> Approver.check_approval(classification, "mix test", :openai)
      {:ok, :approved}

      iex> classification = %{level: :blocked}
      iex> Approver.check_approval(classification, "sudo rm -rf /", :openai)
      {:ok, :denied}
  """
  @spec check_approval(map(), String.t(), atom()) :: {:ok, approval_result()}
  def check_approval(classification, command, provider) do
    mode = get_approval_mode()

    result =
      case mode do
        :allow_all ->
          Logger.warn("Approval mode :allow_all - auto-approving all commands!")
          record_approval(command, provider, classification.level, :auto)
          :approved

        :deny_all ->
          Logger.info("Approval mode :deny_all - denying command: #{command}")
          :denied

        :prompt ->
          prompt_user_for_approval(command, provider, classification)

        :auto ->
          auto_approve(command, provider, classification)
      end

    {:ok, result}
  end

  @doc """
  Prompt user for command approval interactively.

  Displays command details and waits for user input.

  ## Returns

  - `:approved` - User approved the command
  - `:denied` - User denied the command
  - `:queued` - User requested to queue for later
  """
  @spec prompt_user(map()) :: {:ok, approval_result()}
  def prompt_user(command_info) do
    result =
      prompt_user_for_approval(
        command_info.command,
        command_info.provider,
        %{level: command_info.danger_level, reason: command_info.reason}
      )

    {:ok, result}
  end

  @doc """
  Manually approve a pending command.

  This is used when commands are queued and need manual approval later.
  """
  @spec approve_command(String.t()) :: :ok | {:error, term()}
  def approve_command(command) do
    # This would integrate with a command queue system
    # For now, just log the approval
    Logger.info("Manually approved command: #{command}")
    :ok
  end

  @doc """
  Get the current approval mode from configuration.
  """
  @spec get_approval_mode() :: approval_mode()
  def get_approval_mode do
    Application.get_env(:multi_agent_coder, :tools, [])
    |> Keyword.get(:approval_mode, :auto)
  end

  # Private Functions

  defp auto_approve(command, provider, classification) do
    case classification.level do
      :safe ->
        if get_config(:auto_approve_safe, true) do
          Logger.debug("Auto-approving safe command: #{command}")
          record_approval(command, provider, :safe, :auto)
          :approved
        else
          prompt_user_for_approval(command, provider, classification)
        end

      :warning ->
        # Check if previously approved in this session
        if get_config(:trust_for_session, true) and
             ApprovalHistory.previously_approved?(command) do
          Logger.debug("Previously approved in session: #{command}")
          record_approval(command, provider, :warning, :auto)
          :approved
        else
          if get_config(:prompt_on_warning, true) do
            prompt_user_for_approval(command, provider, classification)
          else
            Logger.debug("Auto-approving warning command: #{command}")
            record_approval(command, provider, :warning, :auto)
            :approved
          end
        end

      :dangerous ->
        if get_config(:always_prompt_dangerous, true) do
          prompt_user_for_approval(command, provider, classification)
        else
          # Still check session history even for dangerous commands
          if get_config(:trust_for_session, true) and
               ApprovalHistory.previously_approved?(command) do
            Logger.debug("Previously approved dangerous command in session: #{command}")
            record_approval(command, provider, :dangerous, :auto)
            :approved
          else
            prompt_user_for_approval(command, provider, classification)
          end
        end

      :blocked ->
        Logger.warn("Blocked command denied: #{command}")
        :denied
    end
  end

  defp prompt_user_for_approval(command, provider, classification) do
    display_approval_prompt(command, provider, classification)

    case get_user_input() do
      :approve ->
        record_approval(command, provider, classification.level, :user)
        Logger.info("User approved command: #{command}")
        :approved

      :deny ->
        Logger.info("User denied command: #{command}")
        :denied

      :modify ->
        IO.puts("\n📝 Command modification not yet implemented.")
        IO.puts("For now, please deny and submit a modified command.\n")
        prompt_user_for_approval(command, provider, classification)

      :view_details ->
        display_detailed_info(command, classification)
        prompt_user_for_approval(command, provider, classification)

      :trust_session ->
        record_approval(command, provider, classification.level, :user)
        Logger.info("User approved and trusted for session: #{command}")
        :approved

      :queue ->
        Logger.info("User queued command for later: #{command}")
        :queued

      :unknown ->
        IO.puts("Invalid input. Please try again.")
        prompt_user_for_approval(command, provider, classification)
    end
  end

  defp display_approval_prompt(command, provider, classification) do
    level_icon = get_level_icon(classification.level)
    level_color = get_level_color(classification.level)

    IO.puts("\n#{level_color}┌─────────────────────────────────────────────────────────────┐")
    IO.puts("│ #{level_icon}  Command Approval Required")
    IO.puts("└─────────────────────────────────────────────────────────────┘\033[0m\n")

    IO.puts("Provider:     #{format_provider(provider)}")
    IO.puts("Command:      #{format_command(command)}")
    IO.puts("Danger Level: #{format_danger_level(classification.level)}")
    IO.puts("Reason:       #{classification.reason}\n")

    IO.puts("#{Classifier.explain_level(classification.level)}\n")

    IO.puts("Options:")
    IO.puts("  [A]pprove       - Execute this command once")
    IO.puts("  [T]rust session - Execute and trust for this session")
    IO.puts("  [D]eny          - Reject this command")
    IO.puts("  [V]iew details  - Show more information")
    IO.puts("  [Q]ueue         - Queue for manual approval later\n")

    IO.write("Your choice: ")
  end

  defp get_user_input do
    case IO.gets("") |> String.trim() |> String.downcase() do
      "a" -> :approve
      "t" -> :trust_session
      "d" -> :deny
      "m" -> :modify
      "v" -> :view_details
      "q" -> :queue
      # Default to deny on empty input
      "" -> :deny
      _ -> :unknown
    end
  end

  defp display_detailed_info(command, classification) do
    IO.puts("\n" <> String.duplicate("=", 60))
    IO.puts("DETAILED COMMAND INFORMATION")
    IO.puts(String.duplicate("=", 60) <> "\n")

    IO.puts("Command: #{command}")
    IO.puts("Danger Level: #{classification.level}")
    IO.puts("Reason: #{classification.reason}\n")

    IO.puts("Explanation:")
    IO.puts(Classifier.explain_level(classification.level) <> "\n")

    case classification.level do
      :warning ->
        IO.puts("⚠️  Warning commands may modify your system state but are")
        IO.puts("   generally safe. Examples include installing dependencies,")
        IO.puts("   making git commits, or formatting code.\n")

      :dangerous ->
        IO.puts("🚨 Dangerous commands can cause data loss or system issues.")
        IO.puts("   Examples include deleting files, dropping databases, or")
        IO.puts("   force-pushing to git repositories.\n")

        IO.puts("⚠️  Please verify:")
        IO.puts("   • You understand what this command will do")
        IO.puts("   • You have recent backups if needed")
        IO.puts("   • This is the intended operation\n")

      _ ->
        :ok
    end

    IO.puts(String.duplicate("=", 60) <> "\n")
    IO.puts("Press Enter to return to approval prompt...")
    IO.gets("")
  end

  defp record_approval(command, provider, danger_level, approved_by) do
    if Process.whereis(ApprovalHistory) do
      ApprovalHistory.add_approval(command, provider, danger_level, approved_by)
    else
      Logger.warn("ApprovalHistory not started, cannot record approval")
    end
  end

  defp get_config(key, default) do
    Application.get_env(:multi_agent_coder, :tools, [])
    |> Keyword.get(key, default)
  end

  # Formatting Helpers

  defp get_level_icon(:safe), do: "✓"
  defp get_level_icon(:warning), do: "⚠️ "
  defp get_level_icon(:dangerous), do: "🚨"
  defp get_level_icon(:blocked), do: "🚫"

  # Green
  defp get_level_color(:safe), do: "\033[32m"
  # Yellow
  defp get_level_color(:warning), do: "\033[33m"
  # Red
  defp get_level_color(:dangerous), do: "\033[31m"
  # Bright Red
  defp get_level_color(:blocked), do: "\033[91m"

  defp format_provider(provider) do
    # Cyan
    "\033[36m#{provider}\033[0m"
  end

  defp format_command(command) do
    # Bold
    "\033[1m#{command}\033[0m"
  end

  defp format_danger_level(:safe), do: "\033[32m●\033[0m SAFE"
  defp format_danger_level(:warning), do: "\033[33m●\033[0m WARNING"
  defp format_danger_level(:dangerous), do: "\033[31m●\033[0m DANGEROUS"
  defp format_danger_level(:blocked), do: "\033[91m●\033[0m BLOCKED"
end
