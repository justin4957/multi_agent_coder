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

  @doc """
  Displays execution statistics summary.
  """
  def display_statistics(stats) do
    IO.puts([
      "\n",
      IO.ANSI.cyan(),
      IO.ANSI.bright(),
      "═══════════════════════════════════════════════════════════════",
      IO.ANSI.reset(),
      "\n"
    ])

    IO.puts([
      IO.ANSI.bright(),
      "  EXECUTION SUMMARY",
      IO.ANSI.reset()
    ])

    IO.puts([
      IO.ANSI.cyan(),
      "═══════════════════════════════════════════════════════════════",
      IO.ANSI.reset(),
      "\n"
    ])

    # Total time
    IO.puts([
      "  Total Time:      ",
      IO.ANSI.bright(),
      format_time_ms(stats.total_time_ms),
      IO.ANSI.reset()
    ])

    # Agent count
    IO.puts([
      "  Total Agents:    ",
      IO.ANSI.bright(),
      "#{stats.total_agents}",
      IO.ANSI.reset()
    ])

    # Success rate
    success_rate = if stats.total_agents > 0 do
      Float.round(stats.successful / stats.total_agents * 100, 1)
    else
      0.0
    end

    success_color = if success_rate == 100.0, do: IO.ANSI.green(), else: IO.ANSI.yellow()

    IO.puts([
      "  Successful:      ",
      success_color,
      IO.ANSI.bright(),
      "#{stats.successful} (#{success_rate}%)",
      IO.ANSI.reset()
    ])

    if stats.failed > 0 do
      IO.puts([
        "  Failed:          ",
        IO.ANSI.red(),
        IO.ANSI.bright(),
        "#{stats.failed}",
        IO.ANSI.reset()
      ])
    end

    IO.puts([
      "\n",
      IO.ANSI.cyan(),
      "═══════════════════════════════════════════════════════════════",
      IO.ANSI.reset(),
      "\n"
    ])
  end

  @doc """
  Displays a progress bar.
  """
  def display_progress_bar(current, total, opts \\ []) do
    width = Keyword.get(opts, :width, 50)
    label = Keyword.get(opts, :label, "Progress")

    percentage = if total > 0, do: current / total, else: 0
    filled_width = round(width * percentage)
    empty_width = width - filled_width

    bar = [
      IO.ANSI.green(),
      String.duplicate("█", filled_width),
      IO.ANSI.blue(),
      String.duplicate("░", empty_width),
      IO.ANSI.reset()
    ]

    percent_display = :erlang.float_to_binary(percentage * 100, decimals: 1)

    IO.write([
      "\r",
      label,
      ": [",
      bar,
      "] ",
      percent_display,
      "%"
    ])
  end

  @doc """
  Displays agent status with color indicators.
  """
  def display_agent_status(provider, status, elapsed_time \\ nil) do
    provider_name = provider |> to_string() |> String.capitalize()

    {icon, color} = get_status_display(status)

    time_str = if elapsed_time do
      " (#{format_time_ms(elapsed_time)})"
    else
      ""
    end

    IO.puts([
      color,
      icon,
      " ",
      provider_name,
      time_str,
      IO.ANSI.reset()
    ])
  end

  @doc """
  Formats milliseconds into human-readable time.
  """
  def format_time_ms(ms) when ms < 1000, do: "#{ms}ms"
  def format_time_ms(ms) when ms < 60_000 do
    seconds = Float.round(ms / 1000, 1)
    "#{seconds}s"
  end
  def format_time_ms(ms) do
    minutes = div(ms, 60_000)
    seconds = div(rem(ms, 60_000), 1000)
    "#{minutes}m #{seconds}s"
  end

  defp get_status_display(:working), do: {"⚙", IO.ANSI.yellow()}
  defp get_status_display(:completed), do: {"✓", IO.ANSI.green()}
  defp get_status_display(:error), do: {"✗", IO.ANSI.red()}
  defp get_status_display(:idle), do: {"○", IO.ANSI.blue()}
  defp get_status_display(_), do: {"?", IO.ANSI.white()}
end
