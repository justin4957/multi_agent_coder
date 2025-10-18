defmodule MultiAgentCoder.CLI.Help do
  @moduledoc """
  Comprehensive help system for interactive commands.

  Provides general help, command-specific help, and command discovery.
  """

  alias MultiAgentCoder.CLI.Formatter

  @doc """
  Shows general help information.
  """
  def show_general_help do
    IO.puts(Formatter.format_header("Multi-Agent Coder - Interactive Commands"))

    IO.puts("""
    #{IO.ANSI.cyan()}COMMAND CATEGORIES#{IO.ANSI.reset()}

    #{IO.ANSI.green()}Task Control:#{IO.ANSI.reset()}
      pause, resume, cancel, restart, priority

    #{IO.ANSI.green()}Inspection:#{IO.ANSI.reset()}
      status, tasks, providers, logs, stats, inspect

    #{IO.ANSI.green()}Workflow Management:#{IO.ANSI.reset()}
      strategy, allocate, redistribute, focus, compare

    #{IO.ANSI.green()}File Management:#{IO.ANSI.reset()}
      files, diff, history, lock, conflicts, merge, revert

    #{IO.ANSI.green()}Provider Management:#{IO.ANSI.reset()}
      enable, disable, switch, config

    #{IO.ANSI.green()}Session Management:#{IO.ANSI.reset()}
      save, load, sessions, export

    #{IO.ANSI.green()}Utility:#{IO.ANSI.reset()}
      clear, set, watch, follow, interactive

    #{IO.ANSI.cyan()}QUICK START#{IO.ANSI.reset()}
      <question>         Ask all providers a question
      status             Show overall system status
      tasks              List all tasks
      help <command>     Get detailed help for a command
      commands           List all available commands
      exit               Exit interactive mode

    #{IO.ANSI.cyan()}ALIASES (shortcuts)#{IO.ANSI.reset()}
      p   → pause        r   → resume       c   → cancel
      s   → status       t   → tasks        f   → files
      m   → merge        h   → help         q   → quit

    #{IO.ANSI.cyan()}EXAMPLES#{IO.ANSI.reset()}
      > Write a function to reverse a linked list
      > status
      > pause anthropic
      > allocate "Build auth system" to openai,anthropic
      > help merge

    Type 'help <command>' for detailed information about a specific command.
    Type 'commands' to see all available commands.
    """)
  end

  @doc """
  Shows help for a specific command.
  """
  def show_command_help(command) do
    case String.downcase(command) do
      # Task Control
      "pause" -> show_pause_help()
      "resume" -> show_resume_help()
      "cancel" -> show_cancel_help()
      "restart" -> show_restart_help()
      "priority" -> show_priority_help()
      # Inspection
      "status" -> show_status_help()
      "tasks" -> show_tasks_help()
      "providers" -> show_providers_help()
      "logs" -> show_logs_help()
      "stats" -> show_stats_help()
      "inspect" -> show_inspect_help()
      # Workflow
      "strategy" -> show_strategy_help()
      "allocate" -> show_allocate_help()
      "redistribute" -> show_redistribute_help()
      "focus" -> show_focus_help()
      "compare" -> show_compare_help()
      # File Management
      "files" -> show_files_help()
      "diff" -> show_diff_help()
      "history" -> show_history_help()
      "lock" -> show_lock_help()
      "merge" -> show_merge_help()
      "revert" -> show_revert_help()
      "conflicts" -> show_conflicts_help()
      # Provider Management
      "enable" -> show_enable_help()
      "disable" -> show_disable_help()
      "switch" -> show_switch_help()
      "config" -> show_config_help()
      # Session Management
      "save" -> show_save_help()
      "load" -> show_load_help()
      "sessions" -> show_sessions_help()
      "export" -> show_export_help()
      # Utility
      "clear" -> show_clear_help()
      "set" -> show_set_help()
      "watch" -> show_watch_help()
      "follow" -> show_follow_help()
      # Build/Test
      "build" -> show_build_help()
      "test" -> show_test_help()
      "quality" -> show_quality_help()
      "failures" -> show_failures_help()
      _ -> show_unknown_command(command)
    end
  end

  @doc """
  Lists all available commands.
  """
  def show_all_commands do
    IO.puts(Formatter.format_header("All Available Commands"))

    commands = [
      {"Task Control", ["pause", "resume", "cancel", "restart", "priority"]},
      {"Inspection", ["status", "tasks", "providers", "logs", "stats", "inspect"]},
      {"Workflow", ["strategy", "allocate", "redistribute", "focus", "compare"]},
      {"File Management", ["files", "diff", "history", "lock", "merge", "revert", "conflicts"]},
      {"Provider Management", ["enable", "disable", "switch", "config"]},
      {"Session Management", ["save", "load", "sessions", "export"]},
      {"Build/Test", ["build", "test", "quality", "failures"]},
      {"Utility", ["clear", "set", "watch", "follow", "help", "exit"]}
    ]

    Enum.each(commands, fn {category, cmds} ->
      IO.puts(["\n", IO.ANSI.cyan(), category, ":", IO.ANSI.reset()])
      IO.puts("  " <> Enum.join(cmds, ", "))
    end)

    IO.puts(
      "\n#{IO.ANSI.faint()}Type 'help <command>' for details on any command#{IO.ANSI.reset()}"
    )
  end

  # Individual command help functions

  defp show_pause_help do
    IO.puts("""
    #{IO.ANSI.cyan()}#{IO.ANSI.bright()}PAUSE#{IO.ANSI.reset()} - Pause provider execution

    #{IO.ANSI.yellow()}Usage:#{IO.ANSI.reset()}
      pause <provider>   Pause a specific provider
      pause all          Pause all providers
      p <provider>       Shortcut alias

    #{IO.ANSI.yellow()}Description:#{IO.ANSI.reset()}
      Temporarily pauses task execution for one or all providers.
      Running tasks will complete, but new tasks won't start.

    #{IO.ANSI.yellow()}Examples:#{IO.ANSI.reset()}
      > pause anthropic      # Pause only Claude
      > pause all            # Pause all providers
      > p openai             # Shortcut to pause OpenAI

    #{IO.ANSI.yellow()}Related:#{IO.ANSI.reset()}
      resume - Resume paused providers
      status - Check which providers are paused
    """)
  end

  defp show_resume_help do
    IO.puts("""
    #{IO.ANSI.cyan()}#{IO.ANSI.bright()}RESUME#{IO.ANSI.reset()} - Resume paused providers

    #{IO.ANSI.yellow()}Usage:#{IO.ANSI.reset()}
      resume <provider>  Resume a specific provider
      resume all         Resume all providers
      r <provider>       Shortcut alias

    #{IO.ANSI.yellow()}Description:#{IO.ANSI.reset()}
      Resumes execution for previously paused providers.
      Pending tasks will start processing.

    #{IO.ANSI.yellow()}Examples:#{IO.ANSI.reset()}
      > resume anthropic     # Resume Claude
      > resume all           # Resume all paused providers
      > r openai             # Shortcut to resume OpenAI

    #{IO.ANSI.yellow()}Related:#{IO.ANSI.reset()}
      pause - Pause providers
      status - Check provider status
    """)
  end

  defp show_cancel_help do
    IO.puts("""
    #{IO.ANSI.cyan()}#{IO.ANSI.bright()}CANCEL#{IO.ANSI.reset()} - Cancel a task

    #{IO.ANSI.yellow()}Usage:#{IO.ANSI.reset()}
      cancel <task-id>   Cancel a specific task
      c <task-id>        Shortcut alias

    #{IO.ANSI.yellow()}Description:#{IO.ANSI.reset()}
      Cancels a pending or running task by its ID.
      The task will be marked as cancelled and removed from the queue.

    #{IO.ANSI.yellow()}Examples:#{IO.ANSI.reset()}
      > cancel task-123      # Cancel specific task
      > c task-456           # Shortcut

    #{IO.ANSI.yellow()}Related:#{IO.ANSI.reset()}
      tasks - List all tasks to find IDs
      restart - Restart a failed or cancelled task
      inspect - View detailed task information
    """)
  end

  defp show_restart_help do
    IO.puts("""
    #{IO.ANSI.cyan()}#{IO.ANSI.bright()}RESTART#{IO.ANSI.reset()} - Restart a task

    #{IO.ANSI.yellow()}Usage:#{IO.ANSI.reset()}
      restart <task-id>  Restart a failed or completed task

    #{IO.ANSI.yellow()}Description:#{IO.ANSI.reset()}
      Creates a new task with the same description and settings,
      assigning it to the same providers. Useful for retrying failed tasks.

    #{IO.ANSI.yellow()}Examples:#{IO.ANSI.reset()}
      > restart task-123     # Restart task with new ID

    #{IO.ANSI.yellow()}Related:#{IO.ANSI.reset()}
      cancel - Cancel a running task
      tasks - View all tasks
      failures - See failed tasks
    """)
  end

  defp show_priority_help do
    IO.puts("""
    #{IO.ANSI.cyan()}#{IO.ANSI.bright()}PRIORITY#{IO.ANSI.reset()} - Adjust task priority

    #{IO.ANSI.yellow()}Usage:#{IO.ANSI.reset()}
      priority <task-id> <high|normal|low>

    #{IO.ANSI.yellow()}Description:#{IO.ANSI.reset()}
      Changes the priority of a pending task.
      High priority tasks are executed before normal and low priority tasks.

    #{IO.ANSI.yellow()}Priority Levels:#{IO.ANSI.reset()}
      high   - Execute first
      normal - Default priority
      low    - Execute after higher priority tasks

    #{IO.ANSI.yellow()}Examples:#{IO.ANSI.reset()}
      > priority task-123 high       # Set to high priority
      > priority task-456 low        # Set to low priority

    #{IO.ANSI.yellow()}Related:#{IO.ANSI.reset()}
      tasks - View task queue with priorities
      inspect - View task details
    """)
  end

  defp show_status_help do
    IO.puts("""
    #{IO.ANSI.cyan()}#{IO.ANSI.bright()}STATUS#{IO.ANSI.reset()} - Show system status

    #{IO.ANSI.yellow()}Usage:#{IO.ANSI.reset()}
      status     Show overall status
      s          Shortcut alias

    #{IO.ANSI.yellow()}Description:#{IO.ANSI.reset()}
      Displays a comprehensive overview of the system including:
      - Provider status (active/paused)
      - Task queue statistics
      - Current routing strategy
      - Focused provider (if any)

    #{IO.ANSI.yellow()}Examples:#{IO.ANSI.reset()}
      > status               # Show full status
      > s                    # Shortcut

    #{IO.ANSI.yellow()}Related:#{IO.ANSI.reset()}
      providers - Detailed provider information
      tasks - Task queue details
      stats - Usage statistics
    """)
  end

  defp show_tasks_help do
    IO.puts("""
    #{IO.ANSI.cyan()}#{IO.ANSI.bright()}TASKS#{IO.ANSI.reset()} - List all tasks

    #{IO.ANSI.yellow()}Usage:#{IO.ANSI.reset()}
      tasks      List all tasks
      t          Shortcut alias

    #{IO.ANSI.yellow()}Description:#{IO.ANSI.reset()}
      Shows all tasks organized by status:
      - Pending: Waiting to be executed
      - Running: Currently being processed
      - Completed: Successfully finished
      - Failed: Ended with errors

    #{IO.ANSI.yellow()}Examples:#{IO.ANSI.reset()}
      > tasks                # List all tasks
      > t                    # Shortcut

    #{IO.ANSI.yellow()}Related:#{IO.ANSI.reset()}
      inspect - View detailed task information
      cancel - Cancel a task
      priority - Change task priority
    """)
  end

  defp show_providers_help do
    IO.puts("""
    #{IO.ANSI.cyan()}#{IO.ANSI.bright()}PROVIDERS#{IO.ANSI.reset()} - Show provider status

    #{IO.ANSI.yellow()}Usage:#{IO.ANSI.reset()}
      providers  Show detailed provider status

    #{IO.ANSI.yellow()}Description:#{IO.ANSI.reset()}
      Displays detailed information about each provider:
      - Current status (active/paused)
      - Active task count
      - Completed/failed task counts
      - Token usage
      - Average completion time

    #{IO.ANSI.yellow()}Examples:#{IO.ANSI.reset()}
      > providers            # Show all provider details

    #{IO.ANSI.yellow()}Related:#{IO.ANSI.reset()}
      status - Overall system status
      logs - View provider logs
      config - View provider configuration
    """)
  end

  defp show_logs_help do
    IO.puts("""
    #{IO.ANSI.cyan()}#{IO.ANSI.bright()}LOGS#{IO.ANSI.reset()} - View provider logs

    #{IO.ANSI.yellow()}Usage:#{IO.ANSI.reset()}
      logs <provider>    Show recent logs for a provider

    #{IO.ANSI.yellow()}Description:#{IO.ANSI.reset()}
      Displays recent activity logs for a specific provider,
      including task starts, completions, and errors.

    #{IO.ANSI.yellow()}Examples:#{IO.ANSI.reset()}
      > logs anthropic       # Show Claude's logs
      > logs openai          # Show OpenAI's logs

    #{IO.ANSI.yellow()}Related:#{IO.ANSI.reset()}
      follow - Stream real-time provider activity
      providers - View provider status
    """)
  end

  defp show_stats_help do
    IO.puts("""
    #{IO.ANSI.cyan()}#{IO.ANSI.bright()}STATS#{IO.ANSI.reset()} - Show session statistics

    #{IO.ANSI.yellow()}Usage:#{IO.ANSI.reset()}
      stats      Show comprehensive statistics

    #{IO.ANSI.yellow()}Description:#{IO.ANSI.reset()}
      Displays session-wide statistics including:
      - Total tasks and success rate
      - Token usage across all providers
      - Provider distribution
      - Time and cost estimates

    #{IO.ANSI.yellow()}Examples:#{IO.ANSI.reset()}
      > stats                # Show all statistics

    #{IO.ANSI.yellow()}Related:#{IO.ANSI.reset()}
      status - Current system status
      providers - Provider-specific stats
    """)
  end

  defp show_inspect_help do
    IO.puts("""
    #{IO.ANSI.cyan()}#{IO.ANSI.bright()}INSPECT#{IO.ANSI.reset()} - Inspect task details

    #{IO.ANSI.yellow()}Usage:#{IO.ANSI.reset()}
      inspect <task-id>  Show detailed task information

    #{IO.ANSI.yellow()}Description:#{IO.ANSI.reset()}
      Shows comprehensive information about a specific task:
      - Task ID and description
      - Current status
      - Priority level
      - Assigned providers
      - Elapsed time
      - Progress (if available)

    #{IO.ANSI.yellow()}Examples:#{IO.ANSI.reset()}
      > inspect task-123     # View task details

    #{IO.ANSI.yellow()}Related:#{IO.ANSI.reset()}
      tasks - List all tasks
      watch - Watch task in real-time
    """)
  end

  defp show_strategy_help do
    IO.puts("""
    #{IO.ANSI.cyan()}#{IO.ANSI.bright()}STRATEGY#{IO.ANSI.reset()} - Change routing strategy

    #{IO.ANSI.yellow()}Usage:#{IO.ANSI.reset()}
      strategy <all|sequential|dialectical>

    #{IO.ANSI.yellow()}Strategies:#{IO.ANSI.reset()}
      all          - Send tasks to all providers concurrently
      sequential   - Process one provider at a time
      dialectical  - Use dialectical reasoning approach

    #{IO.ANSI.yellow()}Description:#{IO.ANSI.reset()}
      Changes how tasks are distributed across providers.
      Affects all future task allocations.

    #{IO.ANSI.yellow()}Examples:#{IO.ANSI.reset()}
      > strategy all         # Use all providers
      > strategy sequential  # One at a time

    #{IO.ANSI.yellow()}Related:#{IO.ANSI.reset()}
      allocate - Manually allocate tasks
      redistribute - Rebalance tasks
    """)
  end

  defp show_allocate_help do
    IO.puts("""
    #{IO.ANSI.cyan()}#{IO.ANSI.bright()}ALLOCATE#{IO.ANSI.reset()} - Manually allocate task

    #{IO.ANSI.yellow()}Usage:#{IO.ANSI.reset()}
      allocate "<task>" to <providers>

    #{IO.ANSI.yellow()}Description:#{IO.ANSI.reset()}
      Manually assigns a task to specific providers,
      overriding the automatic allocation strategy.

    #{IO.ANSI.yellow()}Examples:#{IO.ANSI.reset()}
      > allocate "Build auth system" to anthropic,openai
      > allocate "Fix bug" to deepseek

    #{IO.ANSI.yellow()}Related:#{IO.ANSI.reset()}
      strategy - Change allocation strategy
      redistribute - Rebalance tasks
      tasks - View allocated tasks
    """)
  end

  defp show_redistribute_help do
    IO.puts("""
    #{IO.ANSI.cyan()}#{IO.ANSI.bright()}REDISTRIBUTE#{IO.ANSI.reset()} - Rebalance tasks

    #{IO.ANSI.yellow()}Usage:#{IO.ANSI.reset()}
      redistribute   Rebalance tasks across providers

    #{IO.ANSI.yellow()}Description:#{IO.ANSI.reset()}
      Analyzes current provider load and redistributes
      pending tasks for optimal performance.

    #{IO.ANSI.yellow()}Examples:#{IO.ANSI.reset()}
      > redistribute         # Rebalance all tasks

    #{IO.ANSI.yellow()}Related:#{IO.ANSI.reset()}
      allocate - Manual task allocation
      providers - View provider load
    """)
  end

  defp show_focus_help do
    IO.puts("""
    #{IO.ANSI.cyan()}#{IO.ANSI.bright()}FOCUS#{IO.ANSI.reset()} - Focus on provider output

    #{IO.ANSI.yellow()}Usage:#{IO.ANSI.reset()}
      focus <provider>   Focus on specific provider

    #{IO.ANSI.yellow()}Description:#{IO.ANSI.reset()}
      Displays output from a single provider prominently
      while others continue working in the background.

    #{IO.ANSI.yellow()}Examples:#{IO.ANSI.reset()}
      > focus anthropic      # Focus on Claude
      > focus openai         # Focus on OpenAI

    #{IO.ANSI.yellow()}Related:#{IO.ANSI.reset()}
      compare - Compare all provider outputs
      follow - Stream provider activity
    """)
  end

  defp show_compare_help do
    IO.puts("""
    #{IO.ANSI.cyan()}#{IO.ANSI.bright()}COMPARE#{IO.ANSI.reset()} - Compare responses

    #{IO.ANSI.yellow()}Usage:#{IO.ANSI.reset()}
      compare    Show side-by-side comparison

    #{IO.ANSI.yellow()}Description:#{IO.ANSI.reset()}
      Displays all provider responses from the last query
      in a side-by-side comparison view.

    #{IO.ANSI.yellow()}Examples:#{IO.ANSI.reset()}
      > compare              # Compare last responses

    #{IO.ANSI.yellow()}Related:#{IO.ANSI.reset()}
      accept - Accept a specific response
      focus - Focus on one provider
    """)
  end

  defp show_merge_help do
    IO.puts("""
    #{IO.ANSI.cyan()}#{IO.ANSI.bright()}MERGE#{IO.ANSI.reset()} - Merge provider code

    #{IO.ANSI.yellow()}Usage:#{IO.ANSI.reset()}
      merge auto         Automatic merge
      merge interactive  Interactive merge
      m auto             Shortcut alias

    #{IO.ANSI.yellow()}Strategies:#{IO.ANSI.reset()}
      auto         - AI-powered automatic merging
      interactive  - Step-by-step conflict resolution

    #{IO.ANSI.yellow()}Description:#{IO.ANSI.reset()}
      Intelligently combines code from multiple providers,
      resolving conflicts using semantic understanding.

    #{IO.ANSI.yellow()}Examples:#{IO.ANSI.reset()}
      > merge auto           # Auto-merge all code
      > merge interactive    # Resolve conflicts manually
      > m auto               # Shortcut

    #{IO.ANSI.yellow()}Related:#{IO.ANSI.reset()}
      conflicts - List conflicts
      diff - View file differences
      revert - Revert changes
    """)
  end

  defp show_files_help do
    IO.puts("""
    #{IO.ANSI.cyan()}#{IO.ANSI.bright()}FILES#{IO.ANSI.reset()} - List tracked files

    #{IO.ANSI.yellow()}Usage:#{IO.ANSI.reset()}
      files      List all tracked files
      f          Shortcut alias

    #{IO.ANSI.yellow()}Description:#{IO.ANSI.reset()}
      Shows all files being tracked by the system with:
      - File status (new, modified, locked, conflict)
      - Owner provider
      - Line count
      - Last modification time

    #{IO.ANSI.yellow()}Examples:#{IO.ANSI.reset()}
      > files                # List all files
      > f                    # Shortcut

    #{IO.ANSI.yellow()}Related:#{IO.ANSI.reset()}
      diff - View file changes
      history - View file history
      lock - Lock a file
    """)
  end

  defp show_diff_help do
    IO.puts("""
    #{IO.ANSI.cyan()}#{IO.ANSI.bright()}DIFF#{IO.ANSI.reset()} - Show file differences

    #{IO.ANSI.yellow()}Usage:#{IO.ANSI.reset()}
      diff <file-path>   Show changes to file

    #{IO.ANSI.yellow()}Description:#{IO.ANSI.reset()}
      Displays a unified diff showing all changes made to
      a file by different providers.

    #{IO.ANSI.yellow()}Examples:#{IO.ANSI.reset()}
      > diff lib/auth.ex     # Show changes to auth.ex

    #{IO.ANSI.yellow()}Related:#{IO.ANSI.reset()}
      files - List all files
      history - View complete file history
      revert - Revert changes
    """)
  end

  defp show_history_help do
    IO.puts("""
    #{IO.ANSI.cyan()}#{IO.ANSI.bright()}HISTORY#{IO.ANSI.reset()} - View file or command history

    #{IO.ANSI.yellow()}Usage:#{IO.ANSI.reset()}
      history                Show command history
      history <file-path>    Show file modification history
      history search <term>  Search command history

    #{IO.ANSI.yellow()}Description:#{IO.ANSI.reset()}
      Without arguments: Shows recent commands.
      With file path: Shows complete modification history for a file.
      With search: Finds commands matching a pattern.

    #{IO.ANSI.yellow()}Examples:#{IO.ANSI.reset()}
      > history                    # Show recent commands
      > history lib/auth.ex        # Show file history
      > history search "merge"     # Search for merge commands

    #{IO.ANSI.yellow()}Related:#{IO.ANSI.reset()}
      diff - View current file changes
      files - List all tracked files
    """)
  end

  defp show_lock_help do
    IO.puts("""
    #{IO.ANSI.cyan()}#{IO.ANSI.bright()}LOCK#{IO.ANSI.reset()} - Lock a file

    #{IO.ANSI.yellow()}Usage:#{IO.ANSI.reset()}
      lock <file-path>   Lock file for exclusive access

    #{IO.ANSI.yellow()}Description:#{IO.ANSI.reset()}
      Locks a file to prevent other providers from modifying it.
      Useful when you want exclusive control over a file.

    #{IO.ANSI.yellow()}Examples:#{IO.ANSI.reset()}
      > lock lib/auth.ex     # Lock auth.ex

    #{IO.ANSI.yellow()}Related:#{IO.ANSI.reset()}
      files - View file status
      revert - Revert file changes
    """)
  end

  defp show_revert_help do
    IO.puts("""
    #{IO.ANSI.cyan()}#{IO.ANSI.bright()}REVERT#{IO.ANSI.reset()} - Revert provider changes

    #{IO.ANSI.yellow()}Usage:#{IO.ANSI.reset()}
      revert <file> <provider>   Revert changes from provider

    #{IO.ANSI.yellow()}Description:#{IO.ANSI.reset()}
      Reverts all changes made by a specific provider to a file,
      restoring the previous state.

    #{IO.ANSI.yellow()}Examples:#{IO.ANSI.reset()}
      > revert lib/auth.ex anthropic    # Revert Claude's changes

    #{IO.ANSI.yellow()}Related:#{IO.ANSI.reset()}
      diff - View file changes
      history - View file history
      merge - Merge provider changes
    """)
  end

  defp show_conflicts_help do
    IO.puts("""
    #{IO.ANSI.cyan()}#{IO.ANSI.bright()}CONFLICTS#{IO.ANSI.reset()} - List conflicts

    #{IO.ANSI.yellow()}Usage:#{IO.ANSI.reset()}
      conflicts  Show all detected conflicts

    #{IO.ANSI.yellow()}Description:#{IO.ANSI.reset()}
      Lists all conflicts between provider changes including:
      - Conflicting files
      - Conflict type (file-level, line-level)
      - Providers involved
      - Line ranges affected

    #{IO.ANSI.yellow()}Examples:#{IO.ANSI.reset()}
      > conflicts            # List all conflicts

    #{IO.ANSI.yellow()}Related:#{IO.ANSI.reset()}
      merge interactive - Resolve conflicts
      diff - View file changes
    """)
  end

  defp show_enable_help do
    IO.puts("""
    #{IO.ANSI.cyan()}#{IO.ANSI.bright()}ENABLE#{IO.ANSI.reset()} - Enable a provider

    #{IO.ANSI.yellow()}Usage:#{IO.ANSI.reset()}
      enable <provider>  Enable a provider

    #{IO.ANSI.yellow()}Description:#{IO.ANSI.reset()}
      Enables a previously disabled provider, adding it to
      the active provider pool for new tasks.

    #{IO.ANSI.yellow()}Examples:#{IO.ANSI.reset()}
      > enable deepseek      # Enable DeepSeek

    #{IO.ANSI.yellow()}Related:#{IO.ANSI.reset()}
      disable - Disable a provider
      providers - View provider status
    """)
  end

  defp show_disable_help do
    IO.puts("""
    #{IO.ANSI.cyan()}#{IO.ANSI.bright()}DISABLE#{IO.ANSI.reset()} - Disable a provider

    #{IO.ANSI.yellow()}Usage:#{IO.ANSI.reset()}
      disable <provider>  Disable a provider

    #{IO.ANSI.yellow()}Description:#{IO.ANSI.reset()}
      Removes a provider from the active pool.
      Running tasks will complete, but no new tasks will be assigned.

    #{IO.ANSI.yellow()}Examples:#{IO.ANSI.reset()}
      > disable local        # Disable local provider

    #{IO.ANSI.yellow()}Related:#{IO.ANSI.reset()}
      enable - Enable a provider
      pause - Temporarily pause a provider
    """)
  end

  defp show_switch_help do
    IO.puts("""
    #{IO.ANSI.cyan()}#{IO.ANSI.bright()}SWITCH#{IO.ANSI.reset()} - Switch provider model

    #{IO.ANSI.yellow()}Usage:#{IO.ANSI.reset()}
      switch <provider> <model>  Switch to different model

    #{IO.ANSI.yellow()}Description:#{IO.ANSI.reset()}
      Changes the model used by a provider.
      Takes effect for new tasks only.

    #{IO.ANSI.yellow()}Examples:#{IO.ANSI.reset()}
      > switch anthropic claude-3-opus
      > switch openai gpt-4-turbo

    #{IO.ANSI.yellow()}Related:#{IO.ANSI.reset()}
      config - View current configuration
      providers - View provider status
    """)
  end

  defp show_config_help do
    IO.puts("""
    #{IO.ANSI.cyan()}#{IO.ANSI.bright()}CONFIG#{IO.ANSI.reset()} - View configuration

    #{IO.ANSI.yellow()}Usage:#{IO.ANSI.reset()}
      config             Show all configuration
      config <provider>  Show provider configuration

    #{IO.ANSI.yellow()}Description:#{IO.ANSI.reset()}
      Displays current system or provider-specific configuration
      including models, settings, and status.

    #{IO.ANSI.yellow()}Examples:#{IO.ANSI.reset()}
      > config               # Show all config
      > config anthropic     # Show Claude config

    #{IO.ANSI.yellow()}Related:#{IO.ANSI.reset()}
      providers - View provider status
      switch - Change provider model
      set - Set runtime options
    """)
  end

  defp show_save_help do
    IO.puts("""
    #{IO.ANSI.cyan()}#{IO.ANSI.bright()}SAVE#{IO.ANSI.reset()} - Save session

    #{IO.ANSI.yellow()}Usage:#{IO.ANSI.reset()}
      save <name>    Save current session

    #{IO.ANSI.yellow()}Description:#{IO.ANSI.reset()}
      Saves the current session including:
      - Last prompt and responses
      - Provider configuration
      - Timestamp

    #{IO.ANSI.yellow()}Examples:#{IO.ANSI.reset()}
      > save auth-implementation
      > save bug-fix-session

    #{IO.ANSI.yellow()}Related:#{IO.ANSI.reset()}
      load - Load a saved session
      sessions - List saved sessions
      export - Export session data
    """)
  end

  defp show_load_help do
    IO.puts("""
    #{IO.ANSI.cyan()}#{IO.ANSI.bright()}LOAD#{IO.ANSI.reset()} - Load session

    #{IO.ANSI.yellow()}Usage:#{IO.ANSI.reset()}
      load <name>    Load a saved session

    #{IO.ANSI.yellow()}Description:#{IO.ANSI.reset()}
      Loads a previously saved session,
      restoring the context and responses.

    #{IO.ANSI.yellow()}Examples:#{IO.ANSI.reset()}
      > load auth-implementation

    #{IO.ANSI.yellow()}Related:#{IO.ANSI.reset()}
      save - Save current session
      sessions - List available sessions
    """)
  end

  defp show_sessions_help do
    IO.puts("""
    #{IO.ANSI.cyan()}#{IO.ANSI.bright()}SESSIONS#{IO.ANSI.reset()} - List saved sessions

    #{IO.ANSI.yellow()}Usage:#{IO.ANSI.reset()}
      sessions   List all saved sessions

    #{IO.ANSI.yellow()}Description:#{IO.ANSI.reset()}
      Shows all previously saved sessions available for loading.

    #{IO.ANSI.yellow()}Examples:#{IO.ANSI.reset()}
      > sessions             # List all sessions

    #{IO.ANSI.yellow()}Related:#{IO.ANSI.reset()}
      save - Save current session
      load - Load a session
    """)
  end

  defp show_export_help do
    IO.puts("""
    #{IO.ANSI.cyan()}#{IO.ANSI.bright()}EXPORT#{IO.ANSI.reset()} - Export session data

    #{IO.ANSI.yellow()}Usage:#{IO.ANSI.reset()}
      export <format>    Export session to format

    #{IO.ANSI.yellow()}Formats:#{IO.ANSI.reset()}
      json - JSON format
      csv  - CSV format
      md   - Markdown format

    #{IO.ANSI.yellow()}Description:#{IO.ANSI.reset()}
      Exports session data to various formats for
      external analysis or documentation.

    #{IO.ANSI.yellow()}Examples:#{IO.ANSI.reset()}
      > export json          # Export as JSON
      > export md            # Export as Markdown

    #{IO.ANSI.yellow()}Related:#{IO.ANSI.reset()}
      save - Save session
      sessions - List sessions
    """)
  end

  defp show_clear_help do
    IO.puts("""
    #{IO.ANSI.cyan()}#{IO.ANSI.bright()}CLEAR#{IO.ANSI.reset()} - Clear screen

    #{IO.ANSI.yellow()}Usage:#{IO.ANSI.reset()}
      clear      Clear the terminal screen

    #{IO.ANSI.yellow()}Description:#{IO.ANSI.reset()}
      Clears the terminal display for a clean view.

    #{IO.ANSI.yellow()}Examples:#{IO.ANSI.reset()}
      > clear                # Clear screen
    """)
  end

  defp show_set_help do
    IO.puts("""
    #{IO.ANSI.cyan()}#{IO.ANSI.bright()}SET#{IO.ANSI.reset()} - Set runtime option

    #{IO.ANSI.yellow()}Usage:#{IO.ANSI.reset()}
      set <option> <value>   Set a runtime option

    #{IO.ANSI.yellow()}Description:#{IO.ANSI.reset()}
      Configures runtime options for the current session.
      Settings persist until session end.

    #{IO.ANSI.yellow()}Examples:#{IO.ANSI.reset()}
      > set display_mode split
      > set timeout 120

    #{IO.ANSI.yellow()}Related:#{IO.ANSI.reset()}
      config - View current configuration
    """)
  end

  defp show_watch_help do
    IO.puts("""
    #{IO.ANSI.cyan()}#{IO.ANSI.bright()}WATCH#{IO.ANSI.reset()} - Watch task in real-time

    #{IO.ANSI.yellow()}Usage:#{IO.ANSI.reset()}
      watch <task-id>    Watch task execution

    #{IO.ANSI.yellow()}Description:#{IO.ANSI.reset()}
      Enters a real-time monitoring mode for a specific task,
      showing progress updates as they happen.

    #{IO.ANSI.yellow()}Examples:#{IO.ANSI.reset()}
      > watch task-123       # Watch task execution

    #{IO.ANSI.yellow()}Related:#{IO.ANSI.reset()}
      follow - Follow provider activity
      inspect - View task details
      tasks - List all tasks
    """)
  end

  defp show_follow_help do
    IO.puts("""
    #{IO.ANSI.cyan()}#{IO.ANSI.bright()}FOLLOW#{IO.ANSI.reset()} - Follow provider activity

    #{IO.ANSI.yellow()}Usage:#{IO.ANSI.reset()}
      follow <provider>  Stream provider activity

    #{IO.ANSI.yellow()}Description:#{IO.ANSI.reset()}
      Streams real-time activity from a provider,
      showing all tasks and operations as they happen.

    #{IO.ANSI.yellow()}Examples:#{IO.ANSI.reset()}
      > follow anthropic     # Follow Claude's activity

    #{IO.ANSI.yellow()}Related:#{IO.ANSI.reset()}
      watch - Watch specific task
      logs - View provider logs
      focus - Focus on provider output
    """)
  end

  defp show_build_help do
    IO.puts("""
    #{IO.ANSI.cyan()}#{IO.ANSI.bright()}BUILD#{IO.ANSI.reset()} - Build all provider code

    #{IO.ANSI.yellow()}Usage:#{IO.ANSI.reset()}
      build      Build code from all providers

    #{IO.ANSI.yellow()}Description:#{IO.ANSI.reset()}
      Runs build process for code from each provider,
      comparing results and identifying build issues.

    #{IO.ANSI.yellow()}Examples:#{IO.ANSI.reset()}
      > build                # Build all provider code

    #{IO.ANSI.yellow()}Related:#{IO.ANSI.reset()}
      test - Run tests
      quality - Run quality checks
      failures - View build failures
    """)
  end

  defp show_test_help do
    IO.puts("""
    #{IO.ANSI.cyan()}#{IO.ANSI.bright()}TEST#{IO.ANSI.reset()} - Run tests

    #{IO.ANSI.yellow()}Usage:#{IO.ANSI.reset()}
      test       Run tests for all providers

    #{IO.ANSI.yellow()}Description:#{IO.ANSI.reset()}
      Executes test suites for each provider's implementation,
      comparing results and identifying failures.

    #{IO.ANSI.yellow()}Examples:#{IO.ANSI.reset()}
      > test                 # Run all tests

    #{IO.ANSI.yellow()}Related:#{IO.ANSI.reset()}
      build - Build code
      quality - Quality checks
      failures - View test failures
    """)
  end

  defp show_quality_help do
    IO.puts("""
    #{IO.ANSI.cyan()}#{IO.ANSI.bright()}QUALITY#{IO.ANSI.reset()} - Run quality checks

    #{IO.ANSI.yellow()}Usage:#{IO.ANSI.reset()}
      quality    Run code quality analysis

    #{IO.ANSI.yellow()}Description:#{IO.ANSI.reset()}
      Analyzes code quality across multiple dimensions:
      - Code style and linting
      - Cyclomatic complexity
      - Test coverage
      - Documentation completeness
      - Security vulnerabilities

    #{IO.ANSI.yellow()}Examples:#{IO.ANSI.reset()}
      > quality              # Run all quality checks

    #{IO.ANSI.yellow()}Related:#{IO.ANSI.reset()}
      test - Run tests
      build - Build code
    """)
  end

  defp show_failures_help do
    IO.puts("""
    #{IO.ANSI.cyan()}#{IO.ANSI.bright()}FAILURES#{IO.ANSI.reset()} - Show failures

    #{IO.ANSI.yellow()}Usage:#{IO.ANSI.reset()}
      failures   Show build and test failures

    #{IO.ANSI.yellow()}Description:#{IO.ANSI.reset()}
      Displays detailed failure reports from recent
      build and test runs, including error messages
      and suggestions for fixes.

    #{IO.ANSI.yellow()}Examples:#{IO.ANSI.reset()}
      > failures             # Show all failures

    #{IO.ANSI.yellow()}Related:#{IO.ANSI.reset()}
      build - Run builds
      test - Run tests
      quality - Quality analysis
    """)
  end

  defp show_unknown_command(command) do
    IO.puts([
      IO.ANSI.red(),
      "Unknown command: '#{command}'",
      IO.ANSI.reset()
    ])

    IO.puts("\nType 'help' for general help or 'commands' to see all available commands.")
  end
end
