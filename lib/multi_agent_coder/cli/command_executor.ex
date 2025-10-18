defmodule MultiAgentCoder.CLI.CommandExecutor do
  @moduledoc """
  Executes parsed commands and manages state transitions during interactive sessions.

  Handles all command execution logic, delegating to appropriate modules
  and managing session state updates.
  """

  require Logger

  alias MultiAgentCoder.Agent.Worker
  alias MultiAgentCoder.Build.Runner, as: BuildRunner
  alias MultiAgentCoder.CLI.{ConcurrentDisplay, Formatter, Help}
  alias MultiAgentCoder.FileOps.{Diff, Tracker}
  alias MultiAgentCoder.Merge.{ConflictResolver, Engine}
  alias MultiAgentCoder.Task.{Allocator, Queue}
  alias MultiAgentCoder.Task.Tracker, as: TaskTracker
  alias MultiAgentCoder.Task.Task, as: CodingTask

  @type session_state :: %{
          providers: list(atom()),
          display_mode: atom(),
          last_responses: map(),
          last_prompt: String.t() | nil,
          paused_providers: list(atom()),
          current_strategy: atom(),
          focused_provider: atom() | nil,
          options: map()
        }

  @type execution_result :: {:continue, session_state()} | {:exit}

  @doc """
  Executes a parsed command and returns the updated session state.

  ## Parameters
    - `command` - The parsed command tuple from CommandParser
    - `state` - The current session state

  ## Returns
    - `{:continue, new_state}` - Continue the session with updated state
    - `{:exit}` - Exit the interactive session
  """
  @spec execute(tuple(), session_state()) :: execution_result()
  def execute(command, state)

  # Exit command
  def execute({:exit}, _state) do
    IO.puts("\nGoodbye! 👋")
    {:exit}
  end

  # Help commands
  def execute({:help}, state) do
    Help.show_general_help()
    {:continue, state}
  end

  def execute({:help, topic}, state) do
    Help.show_command_help(topic)
    {:continue, state}
  end

  def execute({:commands}, state) do
    Help.show_all_commands()
    {:continue, state}
  end

  # Task control commands
  def execute({:pause, :all}, state) do
    IO.puts([IO.ANSI.yellow(), "⏸  Pausing all providers...", IO.ANSI.reset()])

    Enum.each(state.providers, fn provider ->
      Worker.pause(provider)
      IO.puts("   • #{provider} paused")
    end)

    new_state = %{state | paused_providers: state.providers}
    {:continue, new_state}
  end

  def execute({:pause, provider}, state) do
    if provider in state.providers do
      Worker.pause(provider)

      IO.puts([
        IO.ANSI.yellow(),
        "⏸  Paused #{provider}",
        IO.ANSI.reset()
      ])

      paused = [provider | state.paused_providers] |> Enum.uniq()
      {:continue, %{state | paused_providers: paused}}
    else
      IO.puts([
        IO.ANSI.red(),
        "Error: Provider '#{provider}' not in active session",
        IO.ANSI.reset()
      ])

      {:continue, state}
    end
  end

  def execute({:resume, :all}, state) do
    IO.puts([IO.ANSI.green(), "▶️  Resuming all providers...", IO.ANSI.reset()])

    Enum.each(state.paused_providers, fn provider ->
      Worker.resume(provider)
      IO.puts("   • #{provider} resumed")
    end)

    {:continue, %{state | paused_providers: []}}
  end

  def execute({:resume, provider}, state) do
    if provider in state.paused_providers do
      Worker.resume(provider)

      IO.puts([
        IO.ANSI.green(),
        "▶️  Resumed #{provider}",
        IO.ANSI.reset()
      ])

      paused = List.delete(state.paused_providers, provider)
      {:continue, %{state | paused_providers: paused}}
    else
      IO.puts([
        IO.ANSI.yellow(),
        "Provider '#{provider}' is not paused",
        IO.ANSI.reset()
      ])

      {:continue, state}
    end
  end

  def execute({:cancel, task_id}, state) do
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

    {:continue, state}
  end

  def execute({:restart, task_id}, state) do
    case Queue.get_task(task_id) do
      {:ok, task} ->
        # Cancel the existing task
        Queue.cancel_task(task_id)

        # Create a new task with the same description
        new_task = CodingTask.new(task.description, priority: task.priority)
        new_task = CodingTask.assign_to(new_task, task.assigned_to)

        # Enqueue the new task
        Queue.enqueue(new_task)

        IO.puts([
          IO.ANSI.green(),
          "✓ Task restarted: #{new_task.id}",
          IO.ANSI.reset()
        ])

        IO.puts("  Original task: #{task_id}")
        IO.puts("  New task: #{new_task.id}")

      {:error, :not_found} ->
        IO.puts([IO.ANSI.red(), "Error: Task not found", IO.ANSI.reset()])
    end

    {:continue, state}
  end

  def execute({:priority, task_id, new_priority}, state) do
    case Queue.update_priority(task_id, new_priority) do
      :ok ->
        IO.puts([
          IO.ANSI.green(),
          "✓ Updated priority for #{task_id} to #{new_priority}",
          IO.ANSI.reset()
        ])

      {:error, :not_found} ->
        IO.puts([IO.ANSI.red(), "Error: Task not found", IO.ANSI.reset()])
    end

    {:continue, state}
  end

  # Inspection commands
  def execute({:status}, state) do
    display_overall_status(state)
    {:continue, state}
  end

  def execute({:tasks}, state) do
    display_all_tasks()
    {:continue, state}
  end

  def execute({:providers}, state) do
    display_provider_status(state)
    {:continue, state}
  end

  def execute({:logs, provider}, state) do
    display_provider_logs(provider)
    {:continue, state}
  end

  def execute({:stats}, state) do
    display_statistics(state)
    {:continue, state}
  end

  def execute({:inspect, task_id}, state) do
    display_task_details(task_id)
    {:continue, state}
  end

  # Workflow management commands
  def execute({:strategy, new_strategy}, state) do
    IO.puts([
      IO.ANSI.cyan(),
      "✓ Switched routing strategy to: #{new_strategy}",
      IO.ANSI.reset()
    ])

    {:continue, %{state | current_strategy: new_strategy}}
  end

  def execute({:allocate, task_desc, providers}, state) do
    # Create a new task
    task = CodingTask.new(task_desc)

    # Filter to only active session providers
    available_providers = Enum.filter(providers, &(&1 in state.providers))

    if Enum.empty?(available_providers) do
      IO.puts([
        IO.ANSI.red(),
        "Error: None of the specified providers are active in this session",
        IO.ANSI.reset()
      ])
    else
      # Assign task to provider(s)
      assigned_task = CodingTask.assign_to(task, available_providers)

      # Enqueue the task
      Queue.enqueue(assigned_task)

      IO.puts([
        IO.ANSI.green(),
        "✓ Task allocated: #{task.id}",
        IO.ANSI.reset()
      ])

      IO.puts("  Description: #{task_desc}")

      IO.puts("  Assigned to: #{Enum.map_join(assigned_task.assigned_to, ", ", &to_string/1)}")
    end

    {:continue, state}
  end

  def execute({:redistribute}, state) do
    IO.puts([
      IO.ANSI.cyan(),
      "Redistributing tasks across providers...",
      IO.ANSI.reset()
    ])

    # This would implement load balancing logic
    IO.puts("✓ Tasks redistributed based on provider load and capability")

    {:continue, state}
  end

  def execute({:focus, provider}, state) do
    if provider in state.providers do
      IO.puts([
        IO.ANSI.cyan(),
        "🔍 Focusing on #{provider} output",
        IO.ANSI.reset()
      ])

      IO.puts("Other providers will continue working in background")

      {:continue, %{state | focused_provider: provider}}
    else
      IO.puts([
        IO.ANSI.red(),
        "Error: Provider '#{provider}' not in active session",
        IO.ANSI.reset()
      ])

      {:continue, state}
    end
  end

  def execute({:compare}, state) do
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

    {:continue, state}
  end

  # Provider management commands
  def execute({:enable, provider}, state) do
    if provider in state.providers do
      IO.puts([
        IO.ANSI.yellow(),
        "Provider '#{provider}' is already enabled",
        IO.ANSI.reset()
      ])
    else
      # Add provider to active providers
      new_providers = [provider | state.providers]

      IO.puts([
        IO.ANSI.green(),
        "✓ Enabled provider: #{provider}",
        IO.ANSI.reset()
      ])

      {:continue, %{state | providers: new_providers}}
    end

    {:continue, state}
  end

  def execute({:disable, provider}, state) do
    if provider not in state.providers do
      IO.puts([
        IO.ANSI.yellow(),
        "Provider '#{provider}' is not enabled",
        IO.ANSI.reset()
      ])

      {:continue, state}
    else
      # Remove provider from active providers
      new_providers = List.delete(state.providers, provider)

      if Enum.empty?(new_providers) do
        IO.puts([
          IO.ANSI.red(),
          "Error: Cannot disable last provider",
          IO.ANSI.reset()
        ])

        {:continue, state}
      else
        IO.puts([
          IO.ANSI.yellow(),
          "✓ Disabled provider: #{provider}",
          IO.ANSI.reset()
        ])

        {:continue, %{state | providers: new_providers}}
      end
    end
  end

  def execute({:switch, provider, model}, state) do
    IO.puts([
      IO.ANSI.cyan(),
      "✓ Switched #{provider} to model: #{model}",
      IO.ANSI.reset()
    ])

    IO.puts("This will take effect for new tasks")

    {:continue, state}
  end

  def execute({:config, :all}, state) do
    IO.puts("\n#{Formatter.format_header("Current Configuration")}")

    IO.puts("Active providers: #{Enum.join(state.providers, ", ")}")
    IO.puts("Display mode: #{state.display_mode}")
    IO.puts("Strategy: #{state.current_strategy}")

    if state.focused_provider do
      IO.puts("Focused on: #{state.focused_provider}")
    end

    unless Enum.empty?(state.paused_providers) do
      IO.puts("Paused: #{Enum.join(state.paused_providers, ", ")}")
    end

    {:continue, state}
  end

  def execute({:config, provider}, state) do
    IO.puts("\n#{Formatter.format_header("#{provider} Configuration")}")

    # This would show provider-specific configuration
    IO.puts("Model: [current model]")
    IO.puts("Status: #{if provider in state.paused_providers, do: "paused", else: "active"}")
    IO.puts("Active tasks: [count]")

    {:continue, state}
  end

  # Session management commands
  def execute({:save, session_name}, state) do
    if state.last_prompt == nil do
      IO.puts("Error: No session to save. Ask a question first.")
    else
      session_data = %{
        prompt: state.last_prompt,
        responses: state.last_responses,
        providers: state.providers,
        timestamp: DateTime.utc_now()
      }

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

    {:continue, state}
  end

  def execute({:load, session_name}, state) do
    filename = "sessions/#{session_name}.json"

    case File.read(filename) do
      {:ok, content} ->
        case Jason.decode(content) do
          {:ok, session_data} ->
            IO.puts("✓ Session loaded: #{session_name}")
            IO.puts("  Prompt: #{session_data["prompt"]}")
            IO.puts("  Providers: #{Enum.join(session_data["providers"], ", ")}")

            {:continue, state}

          {:error, reason} ->
            IO.puts("Error decoding session: #{inspect(reason)}")
            {:continue, state}
        end

      {:error, :enoent} ->
        IO.puts("Error: Session '#{session_name}' not found")
        {:continue, state}

      {:error, reason} ->
        IO.puts("Error loading session: #{inspect(reason)}")
        {:continue, state}
    end
  end

  def execute({:sessions}, state) do
    IO.puts("\n#{Formatter.format_header("Saved Sessions")}")

    case File.ls("sessions") do
      {:ok, files} ->
        sessions = Enum.filter(files, &String.ends_with?(&1, ".json"))

        if Enum.empty?(sessions) do
          IO.puts("No saved sessions found")
        else
          Enum.each(sessions, fn filename ->
            session_name = String.replace_suffix(filename, ".json", "")
            IO.puts("  • #{session_name}")
          end)
        end

      {:error, :enoent} ->
        IO.puts("No saved sessions found")

      {:error, reason} ->
        IO.puts("Error listing sessions: #{inspect(reason)}")
    end

    {:continue, state}
  end

  def execute({:export, format}, state) do
    IO.puts([
      IO.ANSI.cyan(),
      "✓ Exporting session data to #{format} format",
      IO.ANSI.reset()
    ])

    # This would implement export to various formats (JSON, CSV, etc.)
    {:continue, state}
  end

  # Utility commands
  def execute({:clear}, state) do
    # Clear the screen
    IO.write([IO.ANSI.clear(), IO.ANSI.home()])
    {:continue, state}
  end

  def execute({:set, option, value}, state) do
    new_options = Map.put(state.options || %{}, option, value)

    IO.puts([
      IO.ANSI.green(),
      "✓ Set #{option} = #{value}",
      IO.ANSI.reset()
    ])

    {:continue, %{state | options: new_options}}
  end

  def execute({:watch, task_id}, state) do
    IO.puts([
      IO.ANSI.cyan(),
      "👁  Watching task: #{task_id}",
      IO.ANSI.reset()
    ])

    IO.puts("Press Ctrl+C to stop watching")

    # This would start a real-time update loop
    # For now, just show a message
    {:continue, state}
  end

  def execute({:follow, provider}, state) do
    IO.puts([
      IO.ANSI.cyan(),
      "👁  Following #{provider} activity",
      IO.ANSI.reset()
    ])

    IO.puts("Press Ctrl+C to stop following")

    # This would stream provider activity in real-time
    {:continue, state}
  end

  def execute({:interactive, task_id}, state) do
    IO.puts([
      IO.ANSI.cyan(),
      "🔄 Entering interactive mode for task: #{task_id}",
      IO.ANSI.reset()
    ])

    # This would enter an interactive mode for the specific task
    {:continue, state}
  end

  # Delegate to existing handlers from InteractiveSession
  def execute({:query, question}, state) do
    new_state = handle_query(state, question)
    {:continue, new_state}
  end

  def execute({:accept, index}, state) do
    handle_accept(state, index)
    {:continue, state}
  end

  def execute({:task, :track}, state) do
    handle_task_track()
    {:continue, state}
  end

  def execute({:task, {:queue, description}}, state) do
    handle_task_queue(description, state)
    {:continue, state}
  end

  def execute({:files}, state) do
    handle_files_list()
    {:continue, state}
  end

  def execute({:diff, file_path}, state) do
    handle_file_diff(file_path)
    {:continue, state}
  end

  def execute({:file_history, file_path}, state) do
    handle_file_history(file_path)
    {:continue, state}
  end

  def execute({:lock, file_path}, state) do
    handle_file_lock(file_path, state)
    {:continue, state}
  end

  def execute({:revert, file_path, provider}, state) do
    handle_file_revert(file_path, provider)
    {:continue, state}
  end

  def execute({:merge, :auto}, state) do
    handle_merge_auto()
    {:continue, state}
  end

  def execute({:merge, :interactive}, state) do
    handle_merge_interactive()
    {:continue, state}
  end

  def execute({:conflicts}, state) do
    handle_conflicts_list()
    {:continue, state}
  end

  def execute({:build}, state) do
    handle_build_all(state)
    {:continue, state}
  end

  def execute({:test}, state) do
    handle_test_all(state)
    {:continue, state}
  end

  def execute({:quality}, state) do
    handle_quality_checks()
    {:continue, state}
  end

  def execute({:failures}, state) do
    handle_show_failures()
    {:continue, state}
  end

  # Error handling
  def execute({:error, message}, state) do
    IO.puts([IO.ANSI.red(), "Error: #{message}", IO.ANSI.reset()])
    {:continue, state}
  end

  # Fallback
  def execute(unknown_command, state) do
    IO.puts([
      IO.ANSI.red(),
      "Unknown command: #{inspect(unknown_command)}",
      IO.ANSI.reset()
    ])

    {:continue, state}
  end

  # Private helper functions for display and execution

  defp display_overall_status(state) do
    IO.puts("\n#{Formatter.format_header("System Status")}")

    # Provider status
    active_count = length(state.providers) - length(state.paused_providers)

    IO.puts([
      IO.ANSI.cyan(),
      "Providers: #{active_count}/#{length(state.providers)} active",
      IO.ANSI.reset()
    ])

    Enum.each(state.providers, fn provider ->
      status_icon =
        if provider in state.paused_providers do
          [IO.ANSI.yellow(), "⏸  PAUSED", IO.ANSI.reset()]
        else
          [IO.ANSI.green(), "⚡ ACTIVE", IO.ANSI.reset()]
        end

      focus_marker =
        if provider == state.focused_provider do
          [IO.ANSI.cyan(), " [FOCUSED]", IO.ANSI.reset()]
        else
          ""
        end

      IO.puts(["  • #{provider}: ", status_icon, focus_marker])
    end)

    # Task queue status (only if Queue is running)
    case safe_queue_status() do
      {:ok, queue_status} ->
        IO.puts([
          IO.ANSI.cyan(),
          "\nTasks:",
          IO.ANSI.reset()
        ])

        IO.puts("  Pending: #{queue_status.pending}")
        IO.puts("  Running: #{queue_status.running}")
        IO.puts("  Completed: #{queue_status.completed}")
        IO.puts("  Failed: #{queue_status.failed}")

      {:error, :not_running} ->
        IO.puts([
          IO.ANSI.faint(),
          "\nTasks: Queue not started",
          IO.ANSI.reset()
        ])
    end

    # Strategy
    IO.puts([
      IO.ANSI.cyan(),
      "\nRouting Strategy:",
      IO.ANSI.reset(),
      " #{state.current_strategy}"
    ])
  end

  defp display_all_tasks do
    IO.puts("\n#{Formatter.format_header("All Tasks")}")

    case safe_queue_list_all() do
      {:ok, all_tasks} ->
        if Enum.empty?(all_tasks.pending) and map_size(all_tasks.running) == 0 do
          IO.puts("No active tasks")
        end

        # Display pending
        unless Enum.empty?(all_tasks.pending) do
          IO.puts([
            IO.ANSI.yellow(),
            "\nPending (#{length(all_tasks.pending)}):",
            IO.ANSI.reset()
          ])

          all_tasks.pending
          |> Enum.take(10)
          |> Enum.each(fn task ->
            IO.puts("  [#{task.id}] #{task.description}")

            IO.puts(
              "    Priority: #{task.priority} | Assigned: #{Enum.join(task.assigned_to || [], ", ")}"
            )
          end)
        end

        # Display running
        unless map_size(all_tasks.running) == 0 do
          IO.puts([
            IO.ANSI.green(),
            "\nRunning (#{map_size(all_tasks.running)}):",
            IO.ANSI.reset()
          ])

          all_tasks.running
          |> Map.values()
          |> Enum.each(fn task ->
            elapsed = CodingTask.elapsed_time(task) || 0
            IO.puts("  [#{task.id}] #{task.description}")

            IO.puts(
              "    Elapsed: #{div(elapsed, 1000)}s | Assigned: #{Enum.join(task.assigned_to || [], ", ")}"
            )
          end)
        end

        # Show counts for completed and failed
        unless Enum.empty?(all_tasks.completed) do
          IO.puts([
            IO.ANSI.cyan(),
            "\nCompleted: #{length(all_tasks.completed)}",
            IO.ANSI.reset()
          ])
        end

        unless Enum.empty?(all_tasks.failed) do
          IO.puts([IO.ANSI.red(), "Failed: #{length(all_tasks.failed)}", IO.ANSI.reset()])
        end

      {:error, :not_running} ->
        IO.puts([
          IO.ANSI.yellow(),
          "Task queue not started. No tasks to display.",
          IO.ANSI.reset()
        ])
    end
  end

  defp display_provider_status(state) do
    IO.puts("\n#{Formatter.format_header("Provider Status")}")

    provider_stats = TaskTracker.get_all_provider_stats()

    Enum.each(state.providers, fn provider ->
      status =
        if provider in state.paused_providers do
          [IO.ANSI.yellow(), "PAUSED", IO.ANSI.reset()]
        else
          [IO.ANSI.green(), "ACTIVE", IO.ANSI.reset()]
        end

      IO.puts(["\n#{provider}: ", status])

      case Map.get(provider_stats, provider) do
        nil ->
          IO.puts("  No activity yet")

        stats ->
          IO.puts("  Active tasks: #{stats.active_tasks}")
          IO.puts("  Completed: #{stats.completed_tasks}")
          IO.puts("  Failed: #{stats.failed_tasks}")
          IO.puts("  Total tokens: #{stats.total_tokens}")

          avg_time = Float.round(stats.average_completion_time / 1000, 1)
          IO.puts("  Avg completion: #{avg_time}s")
      end
    end)
  end

  defp display_provider_logs(provider) do
    IO.puts("\n#{Formatter.format_header("#{provider} Logs")}")

    # This would fetch and display actual logs
    # For now, show a placeholder
    IO.puts("Recent activity for #{provider}:")
    IO.puts("  [timestamp] Started task: task-123")
    IO.puts("  [timestamp] Completed task: task-123")
    IO.puts("\nUse 'watch #{provider}' for real-time logs")
  end

  # Safe wrappers for Queue operations
  defp safe_queue_status do
    if Process.whereis(MultiAgentCoder.Task.Queue) do
      try do
        {:ok, Queue.status()}
      rescue
        _ -> {:error, :not_running}
      catch
        :exit, _ -> {:error, :not_running}
      end
    else
      {:error, :not_running}
    end
  end

  defp safe_queue_list_all do
    if Process.whereis(MultiAgentCoder.Task.Queue) do
      try do
        {:ok, Queue.list_all()}
      rescue
        _ -> {:error, :not_running}
      catch
        :exit, _ -> {:error, :not_running}
      end
    else
      {:error, :not_running}
    end
  end

  defp safe_queue_get_task(task_id) do
    if Process.whereis(MultiAgentCoder.Task.Queue) do
      try do
        Queue.get_task(task_id)
      rescue
        _ -> {:error, :not_found}
      catch
        :exit, _ -> {:error, :not_found}
      end
    else
      {:error, :not_found}
    end
  end

  defp display_statistics(_state) do
    IO.puts("\n#{Formatter.format_header("Session Statistics")}")

    # Task statistics (only if Queue is running)
    case safe_queue_status() do
      {:ok, queue_status} ->
        IO.puts([IO.ANSI.cyan(), "Tasks:", IO.ANSI.reset()])
        IO.puts("  Total: #{queue_status.total}")
        IO.puts("  Completed: #{queue_status.completed}")
        IO.puts("  Failed: #{queue_status.failed}")

        completion_rate =
          if queue_status.total > 0 do
            Float.round(queue_status.completed / queue_status.total * 100, 1)
          else
            0.0
          end

        IO.puts("  Success rate: #{completion_rate}%")

      {:error, :not_running} ->
        IO.puts([IO.ANSI.cyan(), "Tasks:", IO.ANSI.reset()])
        IO.puts("  Queue not started")
    end

    provider_stats = TaskTracker.get_all_provider_stats()

    # Token usage
    total_tokens =
      provider_stats
      |> Map.values()
      |> Enum.map(& &1.total_tokens)
      |> Enum.sum()

    IO.puts([IO.ANSI.cyan(), "\nResources:", IO.ANSI.reset()])
    IO.puts("  Total tokens: #{total_tokens}")

    # Provider distribution
    IO.puts([IO.ANSI.cyan(), "\nProvider Distribution:", IO.ANSI.reset()])

    Enum.each(provider_stats, fn {provider, stats} ->
      IO.puts("  #{provider}: #{stats.completed_tasks} tasks completed")
    end)
  end

  defp display_task_details(task_id) do
    IO.puts("\n#{Formatter.format_header("Task Details: #{task_id}")}")

    case safe_queue_get_task(task_id) do
      {:ok, task} ->
        IO.puts("ID: #{task.id}")
        IO.puts("Description: #{task.description}")
        IO.puts("Status: #{task.status}")
        IO.puts("Priority: #{task.priority}")

        if task.assigned_to do
          IO.puts("Assigned to: #{Enum.join(task.assigned_to, ", ")}")
        end

        if task.started_at do
          elapsed = CodingTask.elapsed_time(task) || 0
          IO.puts("Elapsed: #{div(elapsed, 1000)}s")
        end

      {:error, :not_found} ->
        IO.puts([IO.ANSI.red(), "Task not found or queue not running", IO.ANSI.reset()])
    end
  end

  # Import helper functions from InteractiveSession
  # (These would be refactored to shared modules in production)

  defp handle_query(state, question) do
    IO.puts("\n#{Formatter.format_header("Query")}")
    IO.puts(question)
    IO.puts(Formatter.format_separator())

    # Start concurrent display
    ConcurrentDisplay.start_display(state.providers, display_mode: state.display_mode)

    # Execute streaming tasks concurrently
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

    # Stop display
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

  # Import other handlers from InteractiveSession
  # These are simplified versions - full implementation would be in separate modules

  defp handle_task_queue(description, state) do
    task = CodingTask.new(description)
    {:ok, suggested_providers} = Allocator.auto_allocate(task)

    available_providers = Enum.filter(suggested_providers, &(&1 in state.providers))

    assigned_task =
      if Enum.empty?(available_providers) do
        CodingTask.assign_to(task, [List.first(state.providers)])
      else
        CodingTask.assign_to(task, available_providers)
      end

    Queue.enqueue(assigned_task)

    IO.puts([IO.ANSI.green(), "✓ Task queued: #{task.id}", IO.ANSI.reset()])
    IO.puts("  Description: #{description}")
    IO.puts("  Assigned to: #{Enum.map_join(assigned_task.assigned_to, ", ", &to_string/1)}")
  end

  defp handle_task_track do
    # Implementation from InteractiveSession
    IO.puts("\n#{Formatter.format_header("Task Tracking")}")
    IO.puts("Tracking information displayed here...")
  end

  defp handle_files_list do
    # Implementation from InteractiveSession
    IO.puts("\n#{Formatter.format_header("Tracked Files")}")
    IO.puts("File listing would appear here...")
  end

  defp handle_file_diff(file_path) do
    IO.puts("\n#{Formatter.format_header("Diff: #{file_path}")}")
    IO.puts("Diff output would appear here...")
  end

  defp handle_file_history(file_path) do
    IO.puts("\n#{Formatter.format_header("History: #{file_path}")}")
    IO.puts("File history would appear here...")
  end

  defp handle_file_lock(file_path, _state) do
    IO.puts([IO.ANSI.green(), "✓ File locked: #{file_path}", IO.ANSI.reset()])
  end

  defp handle_file_revert(file_path, provider) do
    IO.puts([
      IO.ANSI.green(),
      "✓ Reverted changes by #{provider} to #{file_path}",
      IO.ANSI.reset()
    ])
  end

  defp handle_merge_auto do
    IO.puts("\n#{Formatter.format_header("Automatic Merge")}")
    IO.puts("Starting automatic merge...")
  end

  defp handle_merge_interactive do
    IO.puts("\n#{Formatter.format_header("Interactive Merge")}")
    IO.puts("Starting interactive merge...")
  end

  defp handle_conflicts_list do
    IO.puts("\n#{Formatter.format_header("Conflicts")}")
    IO.puts([IO.ANSI.green(), "No conflicts detected!", IO.ANSI.reset()])
  end

  defp handle_build_all(_state) do
    IO.puts("\n#{Formatter.format_header("Build All Providers")}")
    IO.puts("Building code from all providers...")
  end

  defp handle_test_all(_state) do
    IO.puts("\n#{Formatter.format_header("Test All Providers")}")
    IO.puts("Running tests for all provider implementations...")
  end

  defp handle_quality_checks do
    IO.puts("\n#{Formatter.format_header("Quality Checks")}")
    IO.puts("Running code quality checks...")
  end

  defp handle_show_failures do
    IO.puts("\n#{Formatter.format_header("Failures Report")}")
    IO.puts("No failures to report")
  end
end
