defmodule MultiAgentCoder.CLI.CommandParser do
  @moduledoc """
  Parses interactive commands from user input into structured command tuples.

  Provides comprehensive command parsing for all task control, inspection,
  workflow management, and utility commands in the interactive session.

  ## Command Categories
  - Task Control: pause, resume, cancel, restart, priority
  - Inspection: status, tasks, providers, logs, stats, inspect
  - Workflow Management: strategy, allocate, redistribute, focus, compare
  - File Management: files, diff, history, lock, conflicts, merge, revert
  - Provider Management: enable, disable, switch, config
  - Session Management: save, load, sessions, export
  - Utility: clear, set, watch, follow, help, exit

  ## Examples

      iex> CommandParser.parse("pause anthropic")
      {:pause, :anthropic}

      iex> CommandParser.parse("status")
      {:status}

      iex> CommandParser.parse("help merge")
      {:help, "merge"}
  """

  # Task control
  @type command ::
          {:pause, :all | atom()}
          | {:resume, :all | atom()}
          | {:cancel, String.t()}
          | {:restart, String.t()}
          | {:priority, String.t(), :high | :normal | :low}
          # Inspection
          | {:status}
          | {:tasks}
          | {:providers}
          | {:logs, atom()}
          | {:stats}
          | {:inspect, String.t()}
          # Workflow management
          | {:strategy, :all | :sequential | :dialectical}
          | {:allocate, String.t(), list(atom())}
          | {:redistribute}
          | {:focus, atom()}
          | {:compare}
          # File management
          | {:files}
          | {:diff, String.t()}
          | {:file_history, String.t()}
          | {:lock, String.t()}
          | {:conflicts}
          | {:merge, :auto | :interactive}
          | {:revert, String.t(), atom()}
          # Provider management
          | {:enable, atom()}
          | {:disable, atom()}
          | {:switch, atom(), String.t()}
          | {:config, atom()}
          # Session management
          | {:save, String.t()}
          | {:load, String.t()}
          | {:sessions}
          | {:export, String.t()}
          # Utility commands
          | {:clear}
          | {:set, String.t(), String.t()}
          | {:watch, String.t()}
          | {:follow, atom()}
          | {:interactive, String.t()}
          # Help and navigation
          | {:help}
          | {:help, String.t()}
          | {:commands}
          | {:history, :list | :clear | {:search, String.t()}}
          | {:exit}
          # Query
          | {:query, String.t()}
          # Error
          | {:error, String.t()}

  @doc """
  Parses a command string into a structured command tuple.
  """
  @spec parse(String.t()) :: command()
  def parse(input) when is_binary(input) do
    input = String.trim(input)
    parse_command(input)
  end

  # Exit commands
  defp parse_command(cmd) when cmd in ["exit", "quit", "q"], do: {:exit}

  # Help commands
  defp parse_command("help"), do: {:help}
  defp parse_command("?"), do: {:help}
  defp parse_command("commands"), do: {:commands}

  defp parse_command("help " <> topic) do
    {:help, String.trim(topic)}
  end

  # Task control commands
  defp parse_command("pause all"), do: {:pause, :all}
  defp parse_command("p all"), do: {:pause, :all}

  defp parse_command("pause " <> provider) do
    {:pause, parse_provider(provider)}
  end

  defp parse_command("p " <> provider) do
    {:pause, parse_provider(provider)}
  end

  defp parse_command("resume all"), do: {:resume, :all}
  defp parse_command("r all"), do: {:resume, :all}

  defp parse_command("resume " <> provider) do
    {:resume, parse_provider(provider)}
  end

  defp parse_command("r " <> provider) do
    {:resume, parse_provider(provider)}
  end

  defp parse_command("cancel " <> task_id) do
    {:cancel, String.trim(task_id)}
  end

  defp parse_command("c " <> task_id) do
    {:cancel, String.trim(task_id)}
  end

  defp parse_command("restart " <> task_id) do
    {:restart, String.trim(task_id)}
  end

  defp parse_command("priority " <> rest) do
    case String.split(rest, " ", parts: 2) do
      [task_id, priority_str] ->
        case parse_priority(priority_str) do
          {:ok, priority} -> {:priority, String.trim(task_id), priority}
          {:error, _} -> {:error, "Invalid priority. Use: high, normal, or low"}
        end

      _ ->
        {:error, "Usage: priority <task-id> <high|normal|low>"}
    end
  end

  # Inspection commands
  defp parse_command("status"), do: {:status}
  defp parse_command("s"), do: {:status}

  defp parse_command("tasks"), do: {:tasks}
  defp parse_command("t"), do: {:tasks}

  defp parse_command("providers"), do: {:providers}

  defp parse_command("logs " <> provider) do
    {:logs, parse_provider(provider)}
  end

  defp parse_command("stats"), do: {:stats}

  defp parse_command("inspect " <> task_id) do
    {:inspect, String.trim(task_id)}
  end

  # Workflow management commands
  defp parse_command("strategy " <> strategy_name) do
    case parse_strategy(strategy_name) do
      {:ok, strategy} -> {:strategy, strategy}
      {:error, _} -> {:error, "Invalid strategy. Use: all, sequential, or dialectical"}
    end
  end

  defp parse_command("allocate " <> rest) do
    # Expected format: allocate "task description" to provider1,provider2
    case parse_allocate_command(rest) do
      {:ok, task_desc, providers} -> {:allocate, task_desc, providers}
      {:error, msg} -> {:error, msg}
    end
  end

  defp parse_command("redistribute"), do: {:redistribute}

  defp parse_command("focus " <> provider) do
    {:focus, parse_provider(provider)}
  end

  defp parse_command("compare"), do: {:compare}

  # File management commands
  defp parse_command("files"), do: {:files}
  defp parse_command("f"), do: {:files}

  defp parse_command("diff " <> file_path) do
    {:diff, String.trim(file_path)}
  end

  defp parse_command("history " <> file_path) when byte_size(file_path) > 0 do
    # Distinguish between command history and file history
    case String.trim(file_path) do
      "" -> {:history, :list}
      "clear" -> {:history, :clear}
      "search " <> pattern -> {:history, {:search, pattern}}
      path -> {:file_history, path}
    end
  end

  defp parse_command("history"), do: {:history, :list}

  defp parse_command("lock " <> file_path) do
    {:lock, String.trim(file_path)}
  end

  defp parse_command("conflicts"), do: {:conflicts}

  defp parse_command("merge auto"), do: {:merge, :auto}
  defp parse_command("merge interactive"), do: {:merge, :interactive}
  defp parse_command("m auto"), do: {:merge, :auto}
  defp parse_command("m interactive"), do: {:merge, :interactive}

  defp parse_command("revert " <> rest) do
    case String.split(rest, " ", parts: 2) do
      [file_path, provider_str] ->
        {:revert, String.trim(file_path), parse_provider(provider_str)}

      _ ->
        {:error, "Usage: revert <file> <provider>"}
    end
  end

  # Provider management commands
  defp parse_command("enable " <> provider) do
    {:enable, parse_provider(provider)}
  end

  defp parse_command("disable " <> provider) do
    {:disable, parse_provider(provider)}
  end

  defp parse_command("switch " <> rest) do
    case String.split(rest, " ", parts: 2) do
      [provider_str, model] ->
        {:switch, parse_provider(provider_str), String.trim(model)}

      _ ->
        {:error, "Usage: switch <provider> <model>"}
    end
  end

  defp parse_command("config " <> provider) do
    {:config, parse_provider(provider)}
  end

  defp parse_command("config"), do: {:config, :all}

  # Session management commands
  defp parse_command("save " <> name) do
    {:save, String.trim(name)}
  end

  defp parse_command("load " <> name) do
    {:load, String.trim(name)}
  end

  defp parse_command("sessions"), do: {:sessions}

  defp parse_command("export " <> format) do
    {:export, String.trim(format)}
  end

  # Utility commands
  defp parse_command("clear"), do: {:clear}

  defp parse_command("set " <> rest) do
    case String.split(rest, " ", parts: 2) do
      [option, value] ->
        {:set, String.trim(option), String.trim(value)}

      _ ->
        {:error, "Usage: set <option> <value>"}
    end
  end

  defp parse_command("watch " <> task_id) do
    {:watch, String.trim(task_id)}
  end

  defp parse_command("follow " <> provider) do
    {:follow, parse_provider(provider)}
  end

  defp parse_command("interactive " <> task_id) do
    {:interactive, String.trim(task_id)}
  end

  # Task queue commands (from existing implementation)
  defp parse_command("task list"), do: {:tasks}
  defp parse_command("task status"), do: {:status}
  defp parse_command("task track"), do: {:task, :track}

  defp parse_command("task queue " <> description) do
    {:task, {:queue, description}}
  end

  defp parse_command("task cancel " <> task_id) do
    {:cancel, String.trim(task_id)}
  end

  # Build and quality commands (from existing implementation)
  defp parse_command("build"), do: {:build}
  defp parse_command("test"), do: {:test}
  defp parse_command("quality"), do: {:quality}
  defp parse_command("failures"), do: {:failures}

  # Existing accept command
  defp parse_command("accept " <> index_str) do
    case Integer.parse(index_str) do
      {index, _} -> {:accept, index}
      :error -> {:error, "Invalid index"}
    end
  end

  # Default: treat as query
  defp parse_command(question) when byte_size(question) > 0 do
    {:query, question}
  end

  defp parse_command(_), do: {:error, "Unknown command. Type 'help' for usage."}

  # Helper functions

  @spec parse_provider(String.t()) :: atom()
  defp parse_provider(provider_str) do
    provider_str
    |> String.trim()
    |> String.downcase()
    |> String.to_atom()
  end

  @spec parse_priority(String.t()) :: {:ok, :high | :normal | :low} | {:error, String.t()}
  defp parse_priority(priority_str) do
    case String.trim(priority_str) |> String.downcase() do
      "high" -> {:ok, :high}
      "normal" -> {:ok, :normal}
      "low" -> {:ok, :low}
      _ -> {:error, "Invalid priority"}
    end
  end

  @spec parse_strategy(String.t()) :: {:ok, atom()} | {:error, String.t()}
  defp parse_strategy(strategy_str) do
    case String.trim(strategy_str) |> String.downcase() do
      "all" -> {:ok, :all}
      "sequential" -> {:ok, :sequential}
      "dialectical" -> {:ok, :dialectical}
      _ -> {:error, "Invalid strategy"}
    end
  end

  @spec parse_allocate_command(String.t()) ::
          {:ok, String.t(), list(atom())} | {:error, String.t()}
  defp parse_allocate_command(rest) do
    # Try to parse: "task description" to provider1,provider2
    # or: task description to provider1,provider2
    case Regex.run(~r/^"([^"]+)"\s+to\s+(.+)$/, rest) do
      [_, task_desc, providers_str] ->
        providers = parse_provider_list(providers_str)
        {:ok, task_desc, providers}

      nil ->
        # Try without quotes
        case String.split(rest, " to ", parts: 2) do
          [task_desc, providers_str] ->
            providers = parse_provider_list(providers_str)
            {:ok, String.trim(task_desc), providers}

          _ ->
            {:error, "Usage: allocate \"<task>\" to <providers>"}
        end
    end
  end

  @spec parse_provider_list(String.t()) :: list(atom())
  defp parse_provider_list(providers_str) do
    providers_str
    |> String.split(",")
    |> Enum.map(&parse_provider/1)
  end

  @doc """
  Returns a list of all available command names for tab completion.
  """
  @spec all_commands() :: list(String.t())
  def all_commands do
    [
      # Task control
      "pause",
      "resume",
      "cancel",
      "restart",
      "priority",
      # Inspection
      "status",
      "tasks",
      "providers",
      "logs",
      "stats",
      "inspect",
      # Workflow
      "strategy",
      "allocate",
      "redistribute",
      "focus",
      "compare",
      # File management
      "files",
      "diff",
      "history",
      "lock",
      "conflicts",
      "merge",
      "revert",
      # Provider management
      "enable",
      "disable",
      "switch",
      "config",
      # Session management
      "save",
      "load",
      "sessions",
      "export",
      # Utility
      "clear",
      "set",
      "watch",
      "follow",
      "interactive",
      # Build/test
      "build",
      "test",
      "quality",
      "failures",
      # Help
      "help",
      "commands",
      # Exit
      "exit",
      "quit"
    ]
  end

  @doc """
  Returns command aliases (short forms).
  """
  @spec aliases() :: %{String.t() => String.t()}
  def aliases do
    %{
      "p" => "pause",
      "r" => "resume",
      "c" => "cancel",
      "s" => "status",
      "t" => "tasks",
      "f" => "files",
      "m" => "merge",
      "h" => "help",
      "q" => "quit"
    }
  end
end
