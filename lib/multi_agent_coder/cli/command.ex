defmodule MultiAgentCoder.CLI.Command do
  @moduledoc """
  Command-line interface for multi-agent coding tasks.

  Provides both single-command and interactive modes for
  querying multiple AI agents concurrently.
  """

  alias MultiAgentCoder.CLI.{Formatter, ConfigSetup, InteractiveSession}
  alias MultiAgentCoder.Router.TaskRouter
  alias MultiAgentCoder.Monitor.Realtime

  def main(args \\ []) do
    # Parse args first to check for setup command
    {opts, command_args, _} =
      OptionParser.parse(args,
        switches: [
          strategy: :string,
          providers: :string,
          context: :string,
          output: :string,
          interactive: :boolean,
          help: :boolean,
          setup: :boolean
        ],
        aliases: [
          s: :strategy,
          p: :providers,
          c: :context,
          o: :output,
          i: :interactive,
          h: :help
        ]
      )

    # Handle setup command separately
    if opts[:setup] do
      ConfigSetup.run_interactive_setup()
      System.halt(0)
    end

    # Ensure configuration is set up before starting
    ConfigSetup.ensure_configured!()

    # Ensure application is started
    {:ok, _} = Application.ensure_all_started(:multi_agent_coder)

    # Continue with normal flow
    execute_command(opts, command_args)
  end

  defp execute_command(opts, command_args) do
    cond do
      opts[:help] ->
        show_help()

      opts[:interactive] ->
        run_interactive_mode(opts)

      length(command_args) > 0 ->
        run_single_command(command_args, opts)

      true ->
        show_help()
    end
  end

  defp run_single_command(command_args, opts) do
    task = Enum.join(command_args, " ")
    strategy = parse_strategy(opts[:strategy] || "all")
    context = parse_context(opts[:context])

    IO.puts(Formatter.format_header("Multi-Agent Coding Task"))
    IO.puts("Task: #{task}")
    IO.puts("Strategy: #{inspect(strategy)}")
    IO.puts(Formatter.format_separator())

    # Subscribe to real-time updates
    Realtime.subscribe_all()

    # Execute task
    results = TaskRouter.route_task(task, strategy, context: context)

    # Display results
    Formatter.display_results(results, opts)

    # Save to file if requested
    if opts[:output] do
      write_results_to_file(results, opts[:output])
    end
  end

  defp run_interactive_mode(opts) do
    providers = parse_providers(opts[:providers])

    InteractiveSession.start(
      providers: providers,
      display_mode: :stacked
    )
  end

  defp interactive_loop do
    prompt = IO.gets("\n> ") |> String.trim()

    case parse_interactive_command(prompt) do
      {:exit} ->
        IO.puts("Goodbye!")
        :ok

      {:help} ->
        show_interactive_help()
        interactive_loop()

      {:config} ->
        ConfigSetup.run_interactive_setup()
        IO.puts("\n⚠️  Please restart the CLI for new configuration to take effect.")
        interactive_loop()

      {:ask, task} ->
        results = TaskRouter.route_task(task, :all)
        Formatter.display_results(results, [])
        interactive_loop()

      {:compare, task} ->
        results = TaskRouter.route_task(task, :all)
        Formatter.display_comparison(results)
        interactive_loop()

      {:dialectic, task} ->
        results = TaskRouter.route_task(task, :dialectical)
        Formatter.display_dialectical(results)
        interactive_loop()

      {:error, msg} ->
        IO.puts("Error: #{msg}")
        interactive_loop()
    end
  end

  defp parse_interactive_command("exit"), do: {:exit}
  defp parse_interactive_command("help"), do: {:help}
  defp parse_interactive_command("config"), do: {:config}

  defp parse_interactive_command("ask " <> task), do: {:ask, task}
  defp parse_interactive_command("compare " <> task), do: {:compare, task}
  defp parse_interactive_command("dialectic " <> task), do: {:dialectic, task}

  defp parse_interactive_command(_), do: {:error, "Unknown command. Type 'help' for usage."}

  defp show_help do
    IO.puts("""
    MultiAgent Coder - Concurrent AI Coding Assistant

    Usage:
      multi_agent_coder [options] <task>

    Options:
      -s, --strategy STRATEGY    Routing strategy (all, sequential, dialectical)
      -p, --providers LIST       Comma-separated provider list (openai,anthropic,deepseek,local)
      -c, --context JSON         Additional context as JSON
      -o, --output FILE          Save results to file
      -i, --interactive          Start interactive mode
      --setup                    Run configuration setup (add/update API keys)
      -h, --help                 Show this help

    Examples:
      # First time setup
      multi_agent_coder --setup

      # Query all agents
      multi_agent_coder "Write a function to reverse a linked list"

      # Use specific strategy
      multi_agent_coder -s dialectical "Implement quicksort in Elixir"

      # Specific providers only
      multi_agent_coder -p openai,anthropic "Refactor this code"

      # Interactive mode
      multi_agent_coder -i
    """)
  end

  defp show_interactive_help do
    IO.puts("""
    Interactive Commands:
      ask <prompt>       - Query all agents with a prompt
      compare <prompt>   - Compare responses from all agents
      dialectic <prompt> - Run thesis/antithesis/synthesis workflow
      config             - Reconfigure API keys and providers
      help               - Show this help
      exit               - Exit interactive mode
    """)
  end

  defp parse_strategy("all"), do: :all
  defp parse_strategy("parallel"), do: :parallel
  defp parse_strategy("sequential"), do: :sequential
  defp parse_strategy("dialectical"), do: :dialectical

  defp parse_strategy(providers) do
    providers
    |> String.split(",")
    |> Enum.map(&String.to_atom/1)
  end

  defp parse_providers(nil) do
    # Return all configured providers
    Application.get_env(:multi_agent_coder, :providers, [])
    |> Keyword.keys()
  end

  defp parse_providers(provider_string) do
    provider_string
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.map(&String.to_atom/1)
  end

  defp parse_context(nil), do: %{}

  defp parse_context(json_string) do
    case Jason.decode(json_string) do
      {:ok, context} -> context
      {:error, _} -> %{}
    end
  end

  defp write_results_to_file(results, file_path) do
    content = Formatter.format_results_for_file(results)

    case File.write(file_path, content) do
      :ok ->
        IO.puts("\nResults saved to: #{file_path}")

      {:error, reason} ->
        IO.puts("\nFailed to write file: #{inspect(reason)}")
    end
  end
end
