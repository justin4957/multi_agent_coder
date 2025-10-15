defmodule MultiAgentCoder.CLI.History do
  @moduledoc """
  Command history management for the interactive REPL.

  Provides persistent command history that is saved across sessions.
  History is stored in ~/.multi_agent_coder/history as a plain text file.

  ## Features
  - Persistent history across sessions
  - Configurable history size limit
  - Duplicate command detection
  - History search functionality
  """

  @history_dir Path.expand("~/.multi_agent_coder")
  @history_file Path.join(@history_dir, "history")
  @max_history_size 1000

  @doc """
  Loads command history from the history file.

  Returns a list of historical commands, most recent last.
  """
  @spec load() :: [String.t()]
  def load do
    if File.exists?(@history_file) do
      @history_file
      |> File.read!()
      |> String.split("\n", trim: true)
      |> Enum.take(-@max_history_size)
    else
      []
    end
  end

  @doc """
  Appends a command to the history file.

  Only saves non-empty commands and avoids duplicating the last command.
  """
  @spec append(String.t()) :: :ok | {:error, term()}
  def append(command) when is_binary(command) do
    command = String.trim(command)

    if command != "" and not duplicate_last?(command) do
      ensure_history_dir()

      # Append to file
      File.write(@history_file, command <> "\n", [:append])
    else
      :ok
    end
  end

  @doc """
  Clears all history.
  """
  @spec clear() :: :ok | {:error, term()}
  def clear do
    if File.exists?(@history_file) do
      File.rm(@history_file)
    else
      :ok
    end
  end

  @doc """
  Searches history for commands matching a pattern.

  Returns all commands containing the search term, most recent first.
  """
  @spec search(String.t()) :: [String.t()]
  def search(pattern) when is_binary(pattern) do
    load()
    |> Enum.filter(&String.contains?(&1, pattern))
    |> Enum.reverse()
  end

  @doc """
  Gets the last N commands from history.
  """
  @spec last(non_neg_integer()) :: [String.t()]
  def last(n) when is_integer(n) and n > 0 do
    load()
    |> Enum.take(-n)
    |> Enum.reverse()
  end

  @doc """
  Returns the total number of commands in history.
  """
  @spec count() :: non_neg_integer()
  def count do
    load() |> length()
  end

  # Private functions

  defp ensure_history_dir do
    unless File.dir?(@history_dir) do
      File.mkdir_p!(@history_dir)
    end
  end

  defp duplicate_last?(command) do
    case load() |> List.last() do
      nil -> false
      last_command -> last_command == command
    end
  end
end
