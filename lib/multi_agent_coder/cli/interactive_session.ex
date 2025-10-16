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

  defp get_default_providers do
    Application.get_env(:multi_agent_coder, :providers, [])
    |> Keyword.keys()
  end
end
