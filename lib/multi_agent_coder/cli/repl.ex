defmodule MultiAgentCoder.CLI.REPL do
  @moduledoc """
  Rich REPL (Read-Eval-Print Loop) functionality for interactive mode.

  Provides an enhanced interactive experience with:
  - Multi-line input support (backslash continuation)
  - Command history navigation
  - Tab completion hints
  - Input validation
  - Helpful error messages

  ## Multi-line Input

  Use a backslash `\\` at the end of a line to continue to the next line:

      > ask write a function to\\
      ... parse CSV files and\\
      ... convert to JSON

  ## History

  Access previous commands:
  - Type `history` to see recent commands
  - Type `history search <term>` to search history
  - Use arrow keys in compatible terminals

  ## Tab Completion

  Type a partial command and see available completions displayed below the prompt.
  """

  alias MultiAgentCoder.CLI.{Completion, Formatter, History}

  @prompt "> "
  @continuation_prompt "... "

  @doc """
  Starts an enhanced REPL session.

  Loads command history and provides an interactive loop with
  multi-line support and command completion hints.
  """
  def start do
    # Load history
    History.load()

    # Display welcome message
    display_welcome()

    # Start the REPL loop
    repl_loop([])
  end

  @doc """
  Reads input from the user, supporting multi-line input.

  Returns `{:ok, command}` for valid input or `:exit` to quit.
  """
  @spec read_input() :: {:ok, String.t()} | :exit | {:error, term()}
  def read_input do
    read_lines([])
  end

  @doc """
  Displays helpful completion hints based on partial input.
  """
  @spec show_completions(String.t()) :: :ok
  def show_completions(input) when is_binary(input) do
    completions = Completion.complete(input)

    if length(completions) > 0 and length(completions) <= 10 do
      IO.puts([
        IO.ANSI.faint(),
        "  Suggestions: ",
        Enum.join(completions, ", "),
        IO.ANSI.reset()
      ])
    end

    :ok
  end

  # Private functions

  defp repl_loop(_history) do
    case read_input() do
      {:ok, command} ->
        # Save to history
        History.append(command)

        # Process the command
        case process_command(command) do
          :continue ->
            repl_loop([])

          :exit ->
            IO.puts("\nGoodbye! 👋")
            :ok
        end

      :exit ->
        IO.puts("\nGoodbye! 👋")
        :ok

      {:error, reason} ->
        IO.puts([
          IO.ANSI.red(),
          "Error reading input: #{inspect(reason)}",
          IO.ANSI.reset()
        ])

        repl_loop([])
    end
  end

  defp read_lines(lines) do
    prompt = if Enum.empty?(lines), do: @prompt, else: @continuation_prompt

    case IO.gets(prompt) do
      :eof ->
        :exit

      {:error, reason} ->
        {:error, reason}

      line ->
        line = String.trim_trailing(line, "\n")

        cond do
          # Ctrl+D on empty line = exit
          line == "" and Enum.empty?(lines) ->
            :exit

          # Backslash continuation
          String.ends_with?(line, "\\") ->
            # Remove backslash and continue
            line = String.trim_trailing(line, "\\")
            read_lines(lines ++ [line])

          # Check for unclosed quotes or brackets
          needs_continuation?(lines ++ [line]) ->
            read_lines(lines ++ [line])

          # Complete input
          true ->
            full_command = Enum.join(lines ++ [line], " ")
            {:ok, String.trim(full_command)}
        end
    end
  end

  defp needs_continuation?(lines) do
    text = Enum.join(lines, " ")

    # Count quotes
    quote_balanced = rem(String.graphemes(text) |> Enum.count(&(&1 == "\"")), 2) == 0
    single_quote_balanced = rem(String.graphemes(text) |> Enum.count(&(&1 == "'")), 2) == 0

    # Count brackets/parentheses
    open_parens = String.graphemes(text) |> Enum.count(&(&1 == "("))
    close_parens = String.graphemes(text) |> Enum.count(&(&1 == ")"))
    open_brackets = String.graphemes(text) |> Enum.count(&(&1 == "["))
    close_brackets = String.graphemes(text) |> Enum.count(&(&1 == "]"))
    open_braces = String.graphemes(text) |> Enum.count(&(&1 == "{"))
    close_braces = String.graphemes(text) |> Enum.count(&(&1 == "}"))

    parens_balanced = open_parens == close_parens
    brackets_balanced = open_brackets == close_brackets
    braces_balanced = open_braces == close_braces

    # Need continuation if anything is unbalanced
    not (quote_balanced and single_quote_balanced and parens_balanced and brackets_balanced and
           braces_balanced)
  end

  defp process_command(command) do
    case parse_repl_command(command) do
      {:exit} ->
        :exit

      {:history, :list} ->
        display_history()
        :continue

      {:history, :clear} ->
        History.clear()
        IO.puts("History cleared.")
        :continue

      {:history, {:search, pattern}} ->
        search_history(pattern)
        :continue

      {:help} ->
        display_help()
        :continue

      {:completions, prefix} ->
        completions = Completion.complete(prefix)

        IO.puts([
          IO.ANSI.cyan(),
          "Completions for '#{prefix}':",
          IO.ANSI.reset()
        ])

        Enum.each(completions, &IO.puts("  - #{&1}"))
        :continue

      {:command, cmd} ->
        # Return the command to be executed by the main CLI
        # For now, just echo it
        IO.puts([IO.ANSI.yellow(), "Executing: #{cmd}", IO.ANSI.reset()])
        :continue

      {:unknown} ->
        IO.puts([
          IO.ANSI.red(),
          "Unknown command. Type 'help' for available commands.",
          IO.ANSI.reset()
        ])

        :continue
    end
  end

  defp parse_repl_command(command) do
    command = String.trim(command)

    cond do
      command in ["exit", "quit", "q"] ->
        {:exit}

      command == "history" ->
        {:history, :list}

      command == "history clear" ->
        {:history, :clear}

      String.starts_with?(command, "history search ") ->
        pattern = String.replace_prefix(command, "history search ", "")
        {:history, {:search, pattern}}

      command in ["help", "?"] ->
        {:help}

      String.starts_with?(command, "complete ") ->
        prefix = String.replace_prefix(command, "complete ", "")
        {:completions, prefix}

      command == "" ->
        {:unknown}

      true ->
        {:command, command}
    end
  end

  defp display_welcome do
    IO.puts([
      IO.ANSI.cyan(),
      IO.ANSI.bright(),
      "\n╔═══════════════════════════════════════════════════════╗",
      IO.ANSI.reset()
    ])

    IO.puts([
      IO.ANSI.cyan(),
      IO.ANSI.bright(),
      "║  Multi-Agent Coder - Interactive REPL                ║",
      IO.ANSI.reset()
    ])

    IO.puts([
      IO.ANSI.cyan(),
      IO.ANSI.bright(),
      "╚═══════════════════════════════════════════════════════╝",
      IO.ANSI.reset()
    ])

    IO.puts([
      IO.ANSI.faint(),
      "\nEnhanced REPL features:",
      "  • Multi-line input (use \\ for line continuation)",
      "  • Command history (type 'history' to view)",
      "  • Auto-detection of unclosed quotes and brackets",
      "  • Type 'help' for available commands",
      "  • Press Ctrl+D or type 'exit' to quit\n",
      IO.ANSI.reset()
    ])
  end

  defp display_help do
    IO.puts(Formatter.format_header("REPL Commands"))

    IO.puts("""
    #{IO.ANSI.cyan()}Navigation & Control:#{IO.ANSI.reset()}
      exit, quit, q      Exit the REPL
      help, ?            Show this help message
      clear              Clear the screen (if supported)

    #{IO.ANSI.cyan()}History Management:#{IO.ANSI.reset()}
      history            Show recent command history
      history clear      Clear all history
      history search <pattern>  Search history for commands matching pattern

    #{IO.ANSI.cyan()}Multi-line Input:#{IO.ANSI.reset()}
      Use \\ at end of line to continue on next line
      Unclosed quotes and brackets automatically continue to next line

    #{IO.ANSI.cyan()}Interactive Commands:#{IO.ANSI.reset()}
      ask <prompt>       Query all providers
      compare            Compare responses
      dialectic <prompt> Use dialectical reasoning
      save <name>        Save current session
      load <name>        Load a saved session
      providers          List configured providers
      accept <n>         Accept response from provider N

    #{IO.ANSI.cyan()}Examples:#{IO.ANSI.reset()}
      > ask write a hello world function

      > ask write a function to \\
      ... parse CSV files and \\
      ... convert them to JSON

      > history search "parse"
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
end
