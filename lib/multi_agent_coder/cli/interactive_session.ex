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

  alias MultiAgentCoder.CLI.{ConcurrentDisplay, Formatter}
  alias MultiAgentCoder.Agent.Worker

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
    prompt = IO.gets("\n> ") |> String.trim()

    case parse_command(prompt) do
      {:exit} ->
        IO.puts("Goodbye!")
        :ok

      {:help} ->
        show_help()
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

      {:query, question} ->
        new_state = handle_query(state, question)
        interactive_loop(new_state)

      {:error, msg} ->
        IO.puts("Error: #{msg}")
        interactive_loop(state)
    end
  end

  defp parse_command("exit"), do: {:exit}
  defp parse_command("help"), do: {:help}
  defp parse_command("compare"), do: {:compare}

  defp parse_command("accept " <> index_str) do
    case Integer.parse(index_str) do
      {index, _} -> {:accept, index}
      :error -> {:error, "Invalid index"}
    end
  end

  defp parse_command("save " <> name), do: {:save, name}

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
      help               - Show this help message
      exit               - Exit interactive mode

    Examples:
      > Write a Python function to reverse a linked list
      > accept 2
      > compare
      > save linkedlist-session
      > exit
    """)
  end

  defp get_default_providers do
    Application.get_env(:multi_agent_coder, :providers, [])
    |> Keyword.keys()
  end
end
