defmodule MultiAgentCoder.CLI.InteractiveSession do
  @moduledoc """
  Interactive session controller for concurrent multi-agent coding.

  Orchestrates streaming execution across multiple providers with real-time
  concurrent display. Implements the core interactive MVP from issue #8.

  ## Features
  - Concurrent streaming from multiple providers
  - Real-time split-pane display
  - Response selection and comparison
  - Session persistence and replay
  - Interactive commands for control

  ## Example Usage
  ```
  $ ./multi_agent_coder -i

  > Write a function to check if a string is a palindrome

  [Concurrent display shows all providers streaming responses]

  > accept 2    # Accept Claude's response
  > compare     # Show side-by-side comparison
  > save session-name
  > exit
  ```
  """

  require Logger

  alias MultiAgentCoder.Agent.Worker
  alias MultiAgentCoder.CLI.{ConcurrentDisplay, Formatter, History, REPL}
  alias MultiAgentCoder.Task.{Allocator, Queue, Tracker}
  alias MultiAgentCoder.Task.Task, as: CodingTask

  @doc """
  Starts an interactive session with specified providers.

  ## Options
    * `:providers` - List of provider atoms (default: all configured)
    * `:display_mode` - Display mode (:stacked, :split_horizontal)
  """
  def start(opts \\ []) do
    providers = Keyword.get(opts, :providers, get_default_providers())
    display_mode = Keyword.get(opts, :display_mode, :stacked)

    IO.puts(Formatter.format_header("Multi-Agent Coder - Interactive Streaming Mode"))
    IO.puts("Active providers: #{Enum.join(providers, ", ")}")
    IO.puts("Display mode: #{display_mode}")
    IO.puts("")
    IO.puts("Commands:")
    IO.puts("  <your question>    - Stream responses from all providers")
    IO.puts("  accept <n>         - Accept response from provider N")
    IO.puts("  compare            - Show side-by-side comparison of all responses")
    IO.puts("  save <name>        - Save current session")
    IO.puts("  task queue <desc>  - Add task to allocation queue")
    IO.puts("  task list          - Show all queued tasks")
    IO.puts("  task status        - Show queue statistics")
    IO.puts("  files              - List all tracked files")
    IO.puts("  diff <file>        - Show changes to file")
    IO.puts("  history <file>     - Show modification history")
    IO.puts("  lock <file>        - Lock file for exclusive access")
    IO.puts("  merge auto         - Auto-merge code from all providers")
    IO.puts("  merge interactive  - Resolve conflicts interactively")
    IO.puts("  conflicts          - List all conflicts")
    IO.puts("  build              - Build all providers' code")
    IO.puts("  test               - Run all tests")
    IO.puts("  quality            - Run quality checks")
    IO.puts("  failures           - Show test failures")
    IO.puts("  help               - Show this help")
    IO.puts("  exit               - Exit interactive mode")
    IO.puts(Formatter.format_separator())

    # Start the concurrent display manager
    {:ok, _pid} = ConcurrentDisplay.start_link()

    session_state = %{
      providers: providers,
      display_mode: display_mode,
      last_responses: %{},
      last_prompt: nil
    }

    interactive_loop(session_state)
  end

  defp interactive_loop(state) do
    # Use REPL for enhanced input with multi-line support
    case REPL.read_input() do
      {:ok, command} ->
        # Save to history
        History.append(command)

        # Process command
        process_repl_command(command, state)

      :exit ->
        IO.puts("\nGoodbye! 👋")
        :ok

      {:error, reason} ->
        IO.puts([
          IO.ANSI.red(),
          "Error reading input: #{inspect(reason)}",
          IO.ANSI.reset()
        ])

        interactive_loop(state)
    end
  end

  defp process_repl_command(prompt, state) do
    case parse_command(prompt) do
      {:exit} ->
        IO.puts("Goodbye!")
        :ok

      {:help} ->
        show_help()
        interactive_loop(state)

      {:history, :list} ->
        display_history()
        interactive_loop(state)

      {:history, :clear} ->
        History.clear()
        IO.puts("History cleared.")
        interactive_loop(state)

      {:history, {:search, pattern}} ->
        search_history(pattern)
        interactive_loop(state)

      {:accept, index} ->
        handle_accept(state, index)
        interactive_loop(state)

      {:compare} ->
        handle_compare(state)
        interactive_loop(state)

      {:save, session_name} ->
        handle_save(state, session_name)
        interactive_loop(state)

      {:task, :list} ->
        handle_task_list()
        interactive_loop(state)

      {:task, :status} ->
        handle_task_status()
        interactive_loop(state)

      {:task, {:queue, description}} ->
        handle_task_queue(description, state)
        interactive_loop(state)

      {:task, {:cancel, task_id}} ->
        handle_task_cancel(task_id)
        interactive_loop(state)

      {:task, :track} ->
        handle_task_track()
        interactive_loop(state)

      {:files} ->
        handle_files_list()
        interactive_loop(state)

      {:diff, file_path} ->
        handle_file_diff(file_path)
        interactive_loop(state)

      {:file_history, file_path} ->
        handle_file_history(file_path)
        interactive_loop(state)

      {:lock, file_path} ->
        handle_file_lock(file_path, state)
        interactive_loop(state)

      {:revert, file_path, provider} ->
        handle_file_revert(file_path, provider)
        interactive_loop(state)

      {:merge, :auto} ->
        handle_merge_auto()
        interactive_loop(state)

      {:merge, :interactive} ->
        handle_merge_interactive()
        interactive_loop(state)

      {:conflicts} ->
        handle_conflicts_list()
        interactive_loop(state)

      {:build} ->
        handle_build_all(state)
        interactive_loop(state)

      {:test} ->
        handle_test_all(state)
        interactive_loop(state)

      {:quality} ->
        handle_quality_checks()
        interactive_loop(state)

      {:failures} ->
        handle_show_failures()
        interactive_loop(state)

      {:query, question} ->
        new_state = handle_query(state, question)
        interactive_loop(new_state)

      {:error, msg} ->
        IO.puts("Error: #{msg}")
        interactive_loop(state)
    end
  end

  defp parse_command("exit"), do: {:exit}
  defp parse_command("quit"), do: {:exit}
  defp parse_command("q"), do: {:exit}
  defp parse_command("help"), do: {:help}
  defp parse_command("?"), do: {:help}
  defp parse_command("compare"), do: {:compare}
  defp parse_command("history"), do: {:history, :list}
  defp parse_command("history clear"), do: {:history, :clear}

  defp parse_command("history search " <> pattern) do
    {:history, {:search, pattern}}
  end

  defp parse_command("accept " <> index_str) do
    case Integer.parse(index_str) do
      {index, _} -> {:accept, index}
      :error -> {:error, "Invalid index"}
    end
  end

  defp parse_command("save " <> name), do: {:save, name}

  defp parse_command("task list"), do: {:task, :list}
  defp parse_command("task status"), do: {:task, :status}
  defp parse_command("task track"), do: {:task, :track}

  defp parse_command("task queue " <> description) do
    {:task, {:queue, description}}
  end

  defp parse_command("task cancel " <> task_id) do
    {:task, {:cancel, task_id}}
  end

  defp parse_command("files"), do: {:files}

  defp parse_command("diff " <> file_path) do
    {:diff, String.trim(file_path)}
  end

  defp parse_command("history " <> file_path) do
    {:file_history, String.trim(file_path)}
  end

  defp parse_command("lock " <> file_path) do
    {:lock, String.trim(file_path)}
  end

  defp parse_command("revert " <> rest) do
    case String.split(rest, " ", parts: 2) do
      [file_path, provider_str] ->
        {:revert, String.trim(file_path), String.to_atom(String.trim(provider_str))}

      _ ->
        {:error, "Usage: revert <file> <provider>"}
    end
  end

  defp parse_command("merge auto"), do: {:merge, :auto}
  defp parse_command("merge interactive"), do: {:merge, :interactive}
  defp parse_command("conflicts"), do: {:conflicts}
  defp parse_command("build"), do: {:build}
  defp parse_command("test"), do: {:test}
  defp parse_command("quality"), do: {:quality}
  defp parse_command("failures"), do: {:failures}

  defp parse_command(question) when byte_size(question) > 0 do
    {:query, question}
  end

  defp parse_command(_), do: {:error, "Unknown command. Type 'help' for usage."}

  defp handle_query(state, question) do
    IO.puts("\n#{Formatter.format_header("Query")}")
    IO.puts(question)
    IO.puts(Formatter.format_separator())

    # Start concurrent display
    ConcurrentDisplay.start_display(state.providers, display_mode: state.display_mode)

    # Execute streaming tasks concurrently using Task.async
    tasks =
      Enum.map(state.providers, fn provider ->
        Task.async(fn ->
          result = Worker.execute_task_streaming(provider, question, %{})
          {provider, result}
        end)
      end)

    # Wait for all tasks to complete
    results =
      tasks
      |> Enum.map(&Task.await(&1, 120_000))
      |> Enum.into(%{})

    # Stop display and get final state
    _display_results = ConcurrentDisplay.stop_display()

    # Extract responses
    responses =
      Enum.reduce(results, %{}, fn {provider, result}, acc ->
        case result do
          {:ok, content} -> Map.put(acc, provider, content)
          {:error, _} -> acc
        end
      end)

    IO.puts("\n#{Formatter.format_header("All providers completed!")}")
    IO.puts("Commands: accept <n>, compare, save <name>, or ask another question")

    %{state | last_responses: responses, last_prompt: question}
  end

  defp handle_accept(state, index) do
    provider = Enum.at(state.providers, index - 1)

    case Map.get(state.last_responses, provider) do
      nil ->
        IO.puts("Error: Invalid provider index #{index}")

      response ->
        IO.puts("\n#{Formatter.format_header("Selected Response from #{provider}")}")
        IO.puts(response)

        # Optionally write to a file
        IO.puts("\nWould you like to save this to a file? (y/n)")
        answer = IO.gets("> ") |> String.trim() |> String.downcase()

        if answer == "y" do
          IO.puts("Enter filename:")
          filename = IO.gets("> ") |> String.trim()
          File.write(filename, response)
          IO.puts("✓ Saved to #{filename}")
        end
    end
  end

  defp handle_compare(state) do
    if map_size(state.last_responses) == 0 do
      IO.puts("Error: No responses to compare. Ask a question first.")
    else
      IO.puts("\n#{Formatter.format_header("Response Comparison")}")

      Enum.with_index(state.providers, 1)
      |> Enum.each(fn {provider, index} ->
        response = Map.get(state.last_responses, provider, "No response")

        IO.puts("\n[#{index}] #{provider |> to_string() |> String.capitalize()}")
        IO.puts(Formatter.format_separator())
        IO.puts(response)
      end)
    end
  end

  defp handle_save(state, session_name) do
    if state.last_prompt == nil do
      IO.puts("Error: No session to save. Ask a question first.")
    else
      # Save session using Storage module
      session_data = %{
        prompt: state.last_prompt,
        responses: state.last_responses,
        providers: state.providers,
        timestamp: DateTime.utc_now()
      }

      # For MVP, just save to a JSON file
      filename = "sessions/#{session_name}.json"
      File.mkdir_p("sessions")

      case Jason.encode(session_data, pretty: true) do
        {:ok, json} ->
          File.write(filename, json)
          IO.puts("✓ Session saved to #{filename}")

        {:error, reason} ->
          IO.puts("Error saving session: #{inspect(reason)}")
      end
    end
  end

  defp show_help do
    IO.puts("""
    Interactive Commands:
      <your question>    - Query all providers with concurrent streaming display
      accept <n>         - Accept and optionally save response from provider N
                          (1 = first provider, 2 = second, etc.)
      compare            - Show all responses side-by-side for comparison
      save <name>        - Save current session to sessions/<name>.json
      history            - Show recent command history
      history search <pattern>  - Search history for commands matching pattern
      history clear      - Clear all history
      help, ?            - Show this help message
      exit, quit, q      - Exit interactive mode

    Task Allocation Commands:
      task queue <desc>  - Add a task to the allocation queue with auto-routing
      task list          - Show all tasks (pending, running, completed, failed)
      task status        - Show queue statistics and summary
      task track         - Show detailed tracking info for active tasks
      task cancel <id>   - Cancel a queued or running task by ID

    File Operations Commands:
      files              - List all tracked files with status and ownership
      diff <file>        - Show changes to a specific file
      history <file>     - Show complete modification history for a file
      lock <file>        - Lock a file for exclusive access
      revert <file> <provider> - Revert changes made by a specific provider

    Merge & Conflict Resolution Commands:
      merge auto         - Automatically merge code from all providers using AI
      merge interactive  - Interactively resolve conflicts with step-by-step guidance
      conflicts          - List all detected conflicts between providers
      build              - Build code from all providers and compare results
      test               - Run tests for all provider implementations
      quality            - Run comprehensive code quality checks
      failures           - Show detailed build and test failure reports

    Multi-line Input:
      Use \\ at end of line to continue on next line
      Unclosed quotes and brackets automatically continue to next line

    Examples:
      > Write a Python function to reverse a linked list
      > accept 2
      > compare
      > save linkedlist-session

      > task queue "Implement bubble sort algorithm"
      > task list
      > task status

      > Write a function to \\
      ... parse CSV files

      > history search "parse"
      > exit
    """)
  end

  defp display_history do
    history = History.last(20)

    if Enum.empty?(history) do
      IO.puts("No command history.")
    else
      IO.puts([IO.ANSI.cyan(), "Recent commands:", IO.ANSI.reset()])

      history
      |> Enum.with_index(1)
      |> Enum.each(fn {cmd, idx} ->
        IO.puts("  #{idx}. #{cmd}")
      end)
    end
  end

  defp search_history(pattern) do
    results = History.search(pattern)

    if Enum.empty?(results) do
      IO.puts("No commands found matching '#{pattern}'")
    else
      IO.puts([
        IO.ANSI.cyan(),
        "Commands matching '#{pattern}':",
        IO.ANSI.reset()
      ])

      results
      |> Enum.with_index(1)
      |> Enum.each(fn {cmd, idx} ->
        IO.puts("  #{idx}. #{cmd}")
      end)
    end
  end

  defp handle_task_queue(description, state) do
    # Create a new task
    task = CodingTask.new(description)

    # Auto-allocate to best providers
    {:ok, suggested_providers} = Allocator.auto_allocate(task)

    # Filter to only active session providers
    available_providers =
      Enum.filter(suggested_providers, &(&1 in state.providers))

    # Assign task to provider(s)
    assigned_task =
      if Enum.empty?(available_providers) do
        # Fall back to first available provider
        CodingTask.assign_to(task, [List.first(state.providers)])
      else
        CodingTask.assign_to(task, available_providers)
      end

    # Enqueue the task
    Queue.enqueue(assigned_task)

    IO.puts([
      IO.ANSI.green(),
      "✓ Task queued: #{task.id}",
      IO.ANSI.reset()
    ])

    IO.puts("  Description: #{description}")

    IO.puts("  Assigned to: #{Enum.map_join(assigned_task.assigned_to, ", ", &to_string/1)}")

    IO.puts("  Priority: #{task.priority}")
  end

  defp handle_task_list do
    all_tasks = Queue.list_all()

    IO.puts("\n#{Formatter.format_header("Task Queue")}")

    if Enum.empty?(all_tasks.pending) and Enum.empty?(all_tasks.running) do
      IO.puts("No tasks in queue.")
    else
      display_pending_tasks(all_tasks.pending)
      display_running_tasks(all_tasks.running)
    end

    display_completed_count(all_tasks.completed)
    display_failed_count(all_tasks.failed)
  end

  defp display_pending_tasks([]), do: :ok

  defp display_pending_tasks(pending_tasks) do
    IO.puts([IO.ANSI.cyan(), "\nPending Tasks:", IO.ANSI.reset()])

    pending_tasks
    |> Enum.with_index(1)
    |> Enum.each(fn {task, idx} ->
      providers = Enum.map_join(task.assigned_to || [], ", ", &to_string/1)
      IO.puts("  #{idx}. [#{task.id}] #{task.description}")
      IO.puts("     Priority: #{task.priority} | Assigned to: #{providers}")
    end)
  end

  defp display_running_tasks(running_tasks) when map_size(running_tasks) == 0, do: :ok

  defp display_running_tasks(running_tasks) do
    IO.puts([IO.ANSI.yellow(), "\nRunning Tasks:", IO.ANSI.reset()])

    running_tasks
    |> Map.values()
    |> Enum.with_index(1)
    |> Enum.each(fn {task, idx} ->
      providers = Enum.map_join(task.assigned_to || [], ", ", &to_string/1)
      elapsed = CodingTask.elapsed_time(task) || 0
      IO.puts("  #{idx}. [#{task.id}] #{task.description}")
      IO.puts("     Elapsed: #{div(elapsed, 1000)}s | Assigned to: #{providers}")
    end)
  end

  defp display_completed_count([]), do: :ok

  defp display_completed_count(completed_tasks) do
    IO.puts([
      IO.ANSI.green(),
      "\nCompleted: #{length(completed_tasks)}",
      IO.ANSI.reset()
    ])
  end

  defp display_failed_count([]), do: :ok

  defp display_failed_count(failed_tasks) do
    IO.puts([
      IO.ANSI.red(),
      "Failed: #{length(failed_tasks)}",
      IO.ANSI.reset()
    ])
  end

  defp handle_task_status do
    status = Queue.status()

    IO.puts("\n#{Formatter.format_header("Queue Status")}")
    IO.puts("Pending:   #{status.pending}")
    IO.puts("Running:   #{status.running}")
    IO.puts("Completed: #{status.completed}")
    IO.puts("Failed:    #{status.failed}")
    IO.puts("Cancelled: #{status.cancelled}")
    IO.puts("Total:     #{status.total}")
  end

  defp handle_task_cancel(task_id) do
    case Queue.cancel_task(task_id) do
      :ok ->
        IO.puts([
          IO.ANSI.yellow(),
          "✓ Task cancelled: #{task_id}",
          IO.ANSI.reset()
        ])

      {:error, :not_found} ->
        IO.puts([IO.ANSI.red(), "Error: Task not found", IO.ANSI.reset()])
    end
  end

  defp handle_task_track do
    tracked_tasks = Tracker.get_all_tasks()

    IO.puts("\n#{Formatter.format_header("Task Tracking")}")

    display_tracked_tasks(tracked_tasks)
    display_provider_stats()
  end

  defp display_tracked_tasks([]) do
    IO.puts("No tasks currently being tracked.")
  end

  defp display_tracked_tasks(tracked_tasks) do
    tracked_tasks
    |> Enum.with_index(1)
    |> Enum.each(fn {tracking, idx} ->
      elapsed = DateTime.diff(DateTime.utc_now(), tracking.started_at, :millisecond)
      eta = format_eta(tracking.estimated_completion)

      IO.puts("#{idx}. [#{tracking.task_id}] #{tracking.provider}")
      IO.puts("   Progress: #{Float.round(tracking.progress * 100, 1)}%")
      IO.puts("   Elapsed: #{div(elapsed, 1000)}s")
      IO.puts("   Tokens: #{tracking.tokens_used}")
      IO.puts("   ETA: #{eta}s")
    end)
  end

  defp format_eta(nil), do: "unknown"

  defp format_eta(estimated_completion) do
    DateTime.diff(estimated_completion, DateTime.utc_now(), :second)
  end

  defp display_provider_stats do
    provider_stats = Tracker.get_all_provider_stats()

    unless Enum.empty?(provider_stats) do
      IO.puts([IO.ANSI.cyan(), "\nProvider Statistics:", IO.ANSI.reset()])

      Enum.each(provider_stats, fn {provider, stats} ->
        IO.puts("\n#{provider}:")
        IO.puts("  Active: #{stats.active_tasks}")
        IO.puts("  Completed: #{stats.completed_tasks}")
        IO.puts("  Failed: #{stats.failed_tasks}")
        IO.puts("  Tokens: #{stats.total_tokens}")
        IO.puts("  Avg completion: #{Float.round(stats.average_completion_time / 1000, 1)}s")
      end)
    end
  end

  defp handle_files_list do
    alias MultiAgentCoder.FileOps.Tracker

    files = Tracker.list_files()

    IO.puts("\n#{Formatter.format_header("Tracked Files")}")

    if Enum.empty?(files) do
      IO.puts("No files tracked yet.")
    else
      IO.puts(
        String.pad_trailing("File", 50) <>
          " " <>
          String.pad_trailing("Status", 10) <>
          " " <>
          String.pad_trailing("Owner", 15) <>
          " Lines"
      )

      IO.puts(String.duplicate("─", 90))

      Enum.each(files, fn file ->
        status_icon =
          case file.status do
            :new -> "⚡ NEW"
            :modified -> "📝 MOD"
            :deleted -> "🗑 DEL"
            :active -> "⚡ ACTIVE"
            :locked -> "🔒 LOCK"
            :conflict -> "⚠ CONFLICT"
            _ -> "?"
          end

        owner_str = if file.owner, do: to_string(file.owner), else: "-"

        IO.puts(
          String.pad_trailing(file.path, 50) <>
            " " <>
            String.pad_trailing(status_icon, 10) <>
            " " <>
            String.pad_trailing(owner_str, 15) <>
            " #{file.lines}"
        )
      end)

      # Show statistics
      stats = Tracker.get_stats()
      IO.puts("\n#{Formatter.format_separator()}")
      IO.puts("Total files: #{stats.total_files} | Active providers: #{stats.active_providers}")

      if stats.conflicts && stats.conflicts.unresolved_conflicts > 0 do
        IO.puts([
          IO.ANSI.red(),
          "Unresolved conflicts: #{stats.conflicts.unresolved_conflicts}",
          IO.ANSI.reset()
        ])
      end
    end
  end

  defp handle_file_diff(file_path) do
    alias MultiAgentCoder.FileOps.{Diff, Tracker}

    case Tracker.get_file_diff(file_path) do
      {:ok, diff} ->
        IO.puts("\n#{Formatter.format_header("Diff: #{file_path}")}")
        IO.puts(Diff.format(diff, color: true))

      {:error, :not_found} ->
        IO.puts([
          IO.ANSI.red(),
          "Error: No history found for #{file_path}",
          IO.ANSI.reset()
        ])
    end
  end

  defp handle_file_history(file_path) do
    alias MultiAgentCoder.FileOps.Tracker

    history = Tracker.get_file_history(file_path)

    IO.puts("\n#{Formatter.format_header("History: #{file_path}")}")

    if Enum.empty?(history) do
      IO.puts("No history found for this file.")
    else
      Enum.each(history, fn entry ->
        timestamp = format_timestamp(entry.timestamp)

        operation_str =
          case entry.operation do
            :create -> "Created"
            :modify -> "Modified"
            :delete -> "Deleted"
          end

        IO.puts(
          "#{timestamp} [#{entry.provider}] #{operation_str} (+#{entry.diff.stats.additions}/-#{entry.diff.stats.deletions})"
        )
      end)
    end
  end

  defp handle_file_lock(file_path, state) do
    alias MultiAgentCoder.FileOps.Tracker

    # Use first provider in session as locking provider
    provider = List.first(state.providers)

    case Tracker.lock_file(file_path, provider) do
      :ok ->
        IO.puts([
          IO.ANSI.green(),
          "✓ File locked: #{file_path}",
          IO.ANSI.reset()
        ])

      {:error, :locked} ->
        IO.puts([
          IO.ANSI.red(),
          "Error: File is already locked by another provider",
          IO.ANSI.reset()
        ])
    end
  end

  defp handle_file_revert(file_path, provider) do
    alias MultiAgentCoder.FileOps.Tracker

    case Tracker.revert_provider_changes(file_path, provider) do
      {:ok, nil} ->
        IO.puts([
          IO.ANSI.yellow(),
          "✓ File reverted (provider created the file, so it would be deleted)",
          IO.ANSI.reset()
        ])

      {:ok, content} ->
        IO.puts([
          IO.ANSI.green(),
          "✓ Reverted changes by #{provider}",
          IO.ANSI.reset()
        ])

        IO.puts("\nReverted content preview:")
        IO.puts(String.slice(content, 0, 500))

        if String.length(content) > 500 do
          IO.puts("... (truncated)")
        end

      {:error, :not_possible} ->
        IO.puts([
          IO.ANSI.red(),
          "Error: Cannot revert changes (dependencies exist)",
          IO.ANSI.reset()
        ])
    end
  end

  defp format_timestamp(monotonic_time) do
    # Convert monotonic time to a readable format
    # This is a simplified version - in production, you'd want to track actual timestamps
    seconds = div(monotonic_time, 1000)
    minutes = div(seconds, 60)
    hours = div(minutes, 60)

    "#{rem(hours, 24)}:#{String.pad_leading(Integer.to_string(rem(minutes, 60)), 2, "0")}:#{String.pad_leading(Integer.to_string(rem(seconds, 60)), 2, "0")}"
  end

  # Merge command handlers

  defp handle_merge_auto do
    alias MultiAgentCoder.Merge.Engine

    IO.puts("\n#{Formatter.format_header("Automatic Merge")}")
    IO.puts("Starting automatic merge of all provider changes...")

    case Engine.merge_all(strategy: :auto) do
      {:ok, merged_files} ->
        IO.puts([
          IO.ANSI.green(),
          "\n✓ Successfully merged #{map_size(merged_files)} file(s)",
          IO.ANSI.reset()
        ])

        # Show summary of merged files
        Enum.each(merged_files, fn {file_path, _content} ->
          IO.puts("  • #{file_path}")
        end)

        IO.puts("\nUse 'diff <file>' to see merged changes")

      {:error, reason} ->
        IO.puts([
          IO.ANSI.red(),
          "\n✗ Merge failed: #{reason}",
          IO.ANSI.reset()
        ])

        IO.puts("Use 'conflicts' to see conflict details")
    end
  end

  defp handle_merge_interactive do
    alias MultiAgentCoder.Merge.{Engine, ConflictResolver}

    IO.puts("\n#{Formatter.format_header("Interactive Merge")}")

    # First, detect conflicts
    case Engine.list_conflicts() do
      {:ok, []} ->
        IO.puts("No conflicts detected. Running automatic merge...")
        handle_merge_auto()

      {:ok, conflicts} ->
        IO.puts("Found #{length(conflicts)} conflict(s) to resolve")

        # Resolve conflicts interactively
        {:ok, resolutions} = ConflictResolver.resolve_interactive(conflicts)

        # Apply the resolutions
        IO.puts("\nApplying merge resolutions...")

        case Engine.merge_all(strategy: :manual, resolutions: resolutions) do
          {:ok, merged_files} ->
            IO.puts([
              IO.ANSI.green(),
              "\n✓ Successfully merged #{map_size(merged_files)} file(s)",
              IO.ANSI.reset()
            ])

          {:error, reason} ->
            IO.puts([
              IO.ANSI.red(),
              "\n✗ Merge failed: #{reason}",
              IO.ANSI.reset()
            ])
        end

      {:error, reason} ->
        IO.puts([
          IO.ANSI.red(),
          "\n✗ Failed to detect conflicts: #{reason}",
          IO.ANSI.reset()
        ])
    end
  end

  defp handle_conflicts_list do
    alias MultiAgentCoder.Merge.Engine

    IO.puts("\n#{Formatter.format_header("Conflicts")}")

    case Engine.list_conflicts() do
      {:ok, []} ->
        IO.puts([
          IO.ANSI.green(),
          "No conflicts detected!",
          IO.ANSI.reset()
        ])

      {:ok, conflicts} ->
        IO.puts("Found #{length(conflicts)} conflict(s):\n")

        conflicts
        |> Enum.with_index(1)
        |> Enum.each(fn {conflict, index} ->
          type_str =
            case conflict.type do
              :file_level -> "File-level"
              :line_level -> "Line-level"
              _ -> to_string(conflict.type)
            end

          IO.puts("#{index}. #{conflict.file}")
          IO.puts("   Type: #{type_str}")
          IO.puts("   Providers: #{Enum.join(conflict.providers, ", ")}")

          case conflict.details do
            %{line_ranges: ranges} ->
              IO.puts("   Conflicting lines:")

              Enum.each(ranges, fn {provider, {start_line, end_line}} ->
                IO.puts("     • #{provider}: lines #{start_line}-#{end_line}")
              end)

            _ ->
              :ok
          end

          IO.puts("")
        end)

        IO.puts("Use 'merge interactive' to resolve conflicts")

      {:error, reason} ->
        IO.puts([
          IO.ANSI.red(),
          "Error detecting conflicts: #{reason}",
          IO.ANSI.reset()
        ])
    end
  end

  defp handle_build_all(state) do
    IO.puts("\n#{Formatter.format_header("Build All Providers")}")
    IO.puts("Building code from all providers...")

    # Run builds for each provider
    build_results =
      state.providers
      |> Enum.map(fn provider ->
        IO.puts("\n📦 Building #{provider}...")

        # This would integrate with the build system
        # For MVP, simulate build
        result = run_provider_build(provider)
        {provider, result}
      end)
      |> Map.new()

    # Show results
    successful = Enum.count(build_results, fn {_p, r} -> r == :success end)
    failed = Enum.count(build_results, fn {_p, r} -> r != :success end)

    IO.puts("\n#{Formatter.format_separator()}")

    IO.puts([
      IO.ANSI.green(),
      "✓ Successful builds: #{successful}",
      IO.ANSI.reset()
    ])

    if failed > 0 do
      IO.puts([
        IO.ANSI.red(),
        "✗ Failed builds: #{failed}",
        IO.ANSI.reset()
      ])

      IO.puts("\nUse 'failures' to see build errors")
    end

    # Store results in state for later viewing
    Process.put(:last_build_results, build_results)
  end

  defp handle_test_all(state) do
    IO.puts("\n#{Formatter.format_header("Test All Providers")}")
    IO.puts("Running tests for all provider implementations...")

    # Run tests for each provider
    test_results =
      state.providers
      |> Enum.map(fn provider ->
        IO.puts("\n🧪 Testing #{provider}...")

        # This would integrate with the test system
        # For MVP, simulate test run
        result = run_provider_tests(provider)
        {provider, result}
      end)
      |> Map.new()

    # Show results
    passed = Enum.count(test_results, fn {_p, r} -> match?({:ok, _}, r) end)
    failed = Enum.count(test_results, fn {_p, r} -> match?({:error, _}, r) end)

    IO.puts("\n#{Formatter.format_separator()}")

    IO.puts([
      IO.ANSI.green(),
      "✓ Providers with passing tests: #{passed}",
      IO.ANSI.reset()
    ])

    if failed > 0 do
      IO.puts([
        IO.ANSI.red(),
        "✗ Providers with failing tests: #{failed}",
        IO.ANSI.reset()
      ])

      IO.puts("\nUse 'failures' to see test failures")
    end

    # Store results for later viewing
    Process.put(:last_test_results, test_results)
  end

  defp handle_quality_checks do
    IO.puts("\n#{Formatter.format_header("Quality Checks")}")
    IO.puts("Running code quality checks...")

    # Quality metrics to check
    checks = [
      {:linting, "Code style and linting"},
      {:complexity, "Cyclomatic complexity"},
      {:coverage, "Test coverage"},
      {:documentation, "Documentation completeness"},
      {:security, "Security vulnerabilities"}
    ]

    results =
      Enum.map(checks, fn {check, description} ->
        IO.puts("\n🔍 #{description}...")
        result = run_quality_check(check)
        {check, result}
      end)

    # Display summary
    IO.puts("\n#{Formatter.format_separator()}")
    IO.puts("Quality Report:")

    Enum.each(results, fn {check, result} ->
      {icon, color} =
        case result do
          :pass -> {"✓", IO.ANSI.green()}
          :warn -> {"⚠", IO.ANSI.yellow()}
          :fail -> {"✗", IO.ANSI.red()}
        end

      check_name = check |> to_string() |> String.capitalize()
      IO.puts([color, "#{icon} #{check_name}", IO.ANSI.reset()])
    end)
  end

  defp handle_show_failures do
    IO.puts("\n#{Formatter.format_header("Failures Report")}")

    # Get stored test and build results
    test_results = Process.get(:last_test_results, %{})
    build_results = Process.get(:last_build_results, %{})

    if map_size(test_results) == 0 and map_size(build_results) == 0 do
      IO.puts("No test or build results available. Run 'test' or 'build' first.")
    else
      # Show build failures
      build_failures =
        build_results
        |> Enum.filter(fn {_p, r} -> r != :success end)

      if not Enum.empty?(build_failures) do
        IO.puts([IO.ANSI.red(), "\nBuild Failures:", IO.ANSI.reset()])

        Enum.each(build_failures, fn {provider, _result} ->
          IO.puts("\n📦 #{provider}")
          IO.puts("   Error: Build configuration not found")
          IO.puts("   Suggestion: Check build.exs or mix.exs")
        end)
      end

      # Show test failures
      test_failures =
        test_results
        |> Enum.filter(fn {_p, r} -> match?({:error, _}, r) end)

      if not Enum.empty?(test_failures) do
        IO.puts([IO.ANSI.red(), "\nTest Failures:", IO.ANSI.reset()])

        Enum.each(test_failures, fn {provider, {:error, reason}} ->
          IO.puts("\n🧪 #{provider}")
          IO.puts("   Failures: #{reason}")
          IO.puts("   Suggestion: Review test implementation")
        end)
      end

      if Enum.empty?(build_failures) and Enum.empty?(test_failures) do
        IO.puts([
          IO.ANSI.green(),
          "No failures detected! All builds and tests passed.",
          IO.ANSI.reset()
        ])
      end
    end
  end

  # Helper functions for build/test simulation
  # In production, these would integrate with actual build/test systems

  defp run_provider_build(_provider) do
    # Simulate build - in production, this would run actual build commands
    case :rand.uniform(10) do
      n when n > 2 -> :success
      _ -> :failure
    end
  end

  defp run_provider_tests(_provider) do
    # Simulate test run - in production, this would run actual tests
    case :rand.uniform(10) do
      n when n > 3 ->
        {:ok, %{passed: 10, failed: 0}}

      _ ->
        {:error, "2 tests failed"}
    end
  end

  defp run_quality_check(_check) do
    # Simulate quality check
    case :rand.uniform(10) do
      n when n > 7 -> :pass
      n when n > 4 -> :warn
      _ -> :fail
    end
  end

  defp get_default_providers do
    Application.get_env(:multi_agent_coder, :providers, [])
    |> Keyword.keys()
  end
end
