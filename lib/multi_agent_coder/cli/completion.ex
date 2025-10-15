defmodule MultiAgentCoder.CLI.Completion do
  @moduledoc """
  Tab completion functionality for the interactive REPL.

  Provides intelligent autocompletion for:
  - Interactive commands
  - Provider names
  - Strategy names
  - File paths
  - Common patterns
  """

  @commands [
    "ask",
    "compare",
    "dialectic",
    "save",
    "load",
    "history",
    "help",
    "exit",
    "clear",
    "providers",
    "strategies",
    "accept"
  ]

  @strategies [
    "all",
    "fastest",
    "round_robin",
    "weighted",
    "fallback",
    "dialectical"
  ]

  @doc """
  Provides completion suggestions for a given input string.

  Returns a list of possible completions based on the input prefix.

  ## Examples

      iex> Completion.complete("as")
      ["ask"]

      iex> Completion.complete("ask ")
      [] # No completions after command

      iex> Completion.complete("di")
      ["dialectic"]
  """
  @spec complete(String.t()) :: [String.t()]
  def complete(input) when is_binary(input) do
    input = String.trim_leading(input)

    cond do
      # Empty input - show all commands
      input == "" ->
        @commands

      # Input contains space - might be completing arguments
      String.contains?(input, " ") ->
        complete_arguments(input)

      # Input is a partial command
      true ->
        complete_command(input)
    end
  end

  @doc """
  Gets all available commands.
  """
  @spec commands() :: [String.t()]
  def commands, do: @commands

  @doc """
  Gets all available strategies.
  """
  @spec strategies() :: [String.t()]
  def strategies, do: @strategies

  @doc """
  Gets all configured provider names.
  """
  @spec providers() :: [String.t()]
  def providers do
    Application.get_env(:multi_agent_coder, :providers, [])
    |> Keyword.keys()
    |> Enum.map(&to_string/1)
  end

  # Private functions

  defp complete_command(prefix) do
    @commands
    |> Enum.filter(&String.starts_with?(&1, prefix))
    |> Enum.sort()
  end

  defp complete_arguments(input) do
    [command | _args] = String.split(input, " ", parts: 2)

    case command do
      "ask" ->
        # Could complete common prompt patterns
        []

      "dialectic" ->
        # Could complete strategy names
        complete_strategies(input)

      "save" ->
        # Could complete file paths
        []

      "load" ->
        # Could complete session names from ~/.multi_agent_coder/sessions/
        complete_session_names()

      "providers" ->
        # Complete provider actions: list, add, remove, configure
        ["list", "configure"]

      "accept" ->
        # Complete provider numbers or names
        providers()

      _ ->
        []
    end
  end

  defp complete_strategies(input) do
    parts = String.split(input, " ")
    last_part = List.last(parts) || ""

    @strategies
    |> Enum.filter(&String.starts_with?(&1, last_part))
    |> Enum.sort()
  end

  defp complete_session_names do
    session_dir = Path.expand("~/.multi_agent_coder/sessions")

    if File.dir?(session_dir) do
      session_dir
      |> File.ls!()
      |> Enum.filter(&String.ends_with?(&1, ".json"))
      |> Enum.map(&String.replace_suffix(&1, ".json", ""))
      |> Enum.sort()
    else
      []
    end
  end
end
