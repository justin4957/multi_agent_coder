defmodule MultiAgentCoder.CLI.Formatter do
  @moduledoc """
  Output formatting utilities for the CLI.

  Provides colored, formatted output for different result types.
  """

  @doc """
  Formats a header with decorative borders.
  """
  def format_header(text) do
    width = 70
    padding = div(width - String.length(text), 2)

    [
      "\n",
      IO.ANSI.blue(),
      IO.ANSI.bright(),
      String.duplicate("=", width),
      "\n",
      String.duplicate(" ", padding),
      text,
      "\n",
      String.duplicate("=", width),
      IO.ANSI.reset(),
      "\n"
    ]
    |> IO.iodata_to_binary()
  end

  @doc """
  Formats a separator line.
  """
  def format_separator do
    [IO.ANSI.blue(), String.duplicate("-", 70), IO.ANSI.reset()]
    |> IO.iodata_to_binary()
  end

  @doc """
  Displays results from multiple agents.
  """
  def display_results(results, _opts) when is_map(results) do
    # Check if this is a dialectical result
    if Map.has_key?(results, :thesis) do
      display_dialectical(results)
    else
      display_standard_results(results)
    end
  end

  @doc """
  Displays standard results from agents.
  """
  def display_standard_results(results) do
    Enum.each(results, fn {provider, result} ->
      IO.puts([
        "\n",
        IO.ANSI.cyan(),
        IO.ANSI.bright(),
        "╔═══ #{String.upcase(to_string(provider))} ═══╗",
        IO.ANSI.reset(),
        "\n"
      ])

      case result do
        {:ok, content} ->
          IO.puts(format_code_block(content))

        {:error, reason} ->
          IO.puts([
            IO.ANSI.red(),
            "Error: #{inspect(reason)}",
            IO.ANSI.reset()
          ])
      end

      IO.puts("")
    end)
  end

  @doc """
  Displays dialectical workflow results.
  """
  def display_dialectical(results) do
    IO.puts(format_header("DIALECTICAL ANALYSIS"))

    # Thesis
    IO.puts(["\n", IO.ANSI.green(), IO.ANSI.bright(), "PHASE 1: THESIS", IO.ANSI.reset()])
    display_standard_results(results.thesis)

    # Antithesis
    IO.puts(["\n", IO.ANSI.yellow(), IO.ANSI.bright(), "PHASE 2: ANTITHESIS (Critiques)", IO.ANSI.reset()])
    display_standard_results(results.antithesis)

    # Synthesis
    IO.puts(["\n", IO.ANSI.magenta(), IO.ANSI.bright(), "PHASE 3: SYNTHESIS (Final Solution)", IO.ANSI.reset()])
    display_standard_results(results.synthesis)
  end

  @doc """
  Displays a comparison of results.
  """
  def display_comparison(results) do
    IO.puts(format_header("RESPONSE COMPARISON"))

    comparison_data =
      Enum.map(results, fn {provider, result} ->
        case result do
          {:ok, content} ->
            [
              to_string(provider),
              "#{String.length(content)} chars",
              "#{count_code_blocks(content)} blocks",
              "Success"
            ]

          {:error, _} ->
            [to_string(provider), "N/A", "N/A", "Error"]
        end
      end)

    headers = ["Provider", "Length", "Code Blocks", "Status"]

    # Simple table display (could be enhanced with TableRex)
    IO.puts("\n")
    display_table(headers, comparison_data)
  end

  @doc """
  Formats results for file output.
  """
  def format_results_for_file(results) when is_map(results) do
    if Map.has_key?(results, :thesis) do
      format_dialectical_for_file(results)
    else
      format_standard_for_file(results)
    end
  end

  # Private functions

  defp format_code_block(code) do
    code
    |> String.split("\n")
    |> Enum.map(&("  " <> &1))
    |> Enum.join("\n")
  end

  defp count_code_blocks(text) do
    text
    |> String.split("```")
    |> length()
    |> Kernel.-(1)
    |> div(2)
  end

  defp display_table(headers, rows) do
    # Simple table implementation
    col_widths = calculate_column_widths([headers | rows])

    # Header
    print_row(headers, col_widths)
    IO.puts(String.duplicate("-", Enum.sum(col_widths) + length(col_widths) * 3))

    # Rows
    Enum.each(rows, fn row ->
      print_row(row, col_widths)
    end)
  end

  defp calculate_column_widths(rows) do
    rows
    |> Enum.zip()
    |> Enum.map(fn col_tuple ->
      col_tuple
      |> Tuple.to_list()
      |> Enum.map(&String.length/1)
      |> Enum.max()
    end)
  end

  defp print_row(cells, widths) do
    cells
    |> Enum.zip(widths)
    |> Enum.map(fn {cell, width} ->
      String.pad_trailing(cell, width)
    end)
    |> Enum.join(" | ")
    |> IO.puts()
  end

  defp format_standard_for_file(results) do
    results
    |> Enum.map(fn {provider, result} ->
      """
      ====================================
      #{String.upcase(to_string(provider))}
      ====================================

      #{format_result_content(result)}
      """
    end)
    |> Enum.join("\n\n")
  end

  defp format_dialectical_for_file(results) do
    """
    =====================================
    DIALECTICAL ANALYSIS
    =====================================

    PHASE 1: THESIS
    #{format_standard_for_file(results.thesis)}

    PHASE 2: ANTITHESIS (Critiques)
    #{format_standard_for_file(results.antithesis)}

    PHASE 3: SYNTHESIS (Final Solution)
    #{format_standard_for_file(results.synthesis)}
    """
  end

  defp format_result_content({:ok, content}), do: content
  defp format_result_content({:error, reason}), do: "Error: #{inspect(reason)}"
end
