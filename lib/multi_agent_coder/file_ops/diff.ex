defmodule MultiAgentCoder.FileOps.Diff do
  @moduledoc """
  Generates and manages file diffs for tracking changes.

  Provides utilities for creating line-by-line diffs between file versions,
  formatting diffs for display, and extracting change statistics.
  """

  @type line_change ::
          {:add, non_neg_integer(), String.t()}
          | {:delete, non_neg_integer(), String.t()}
          | {:modify, non_neg_integer(), String.t(), String.t()}
          | {:unchanged, non_neg_integer(), String.t()}

  @type diff :: %{
          file: String.t(),
          old_content: String.t() | nil,
          new_content: String.t() | nil,
          changes: list(line_change()),
          stats: %{
            additions: non_neg_integer(),
            deletions: non_neg_integer(),
            modifications: non_neg_integer()
          }
        }

  @doc """
  Generates a diff between two versions of a file.

  Returns a structured diff with line-by-line changes and statistics.

  ## Examples

      iex> old = "line 1\\nline 2\\nline 3"
      iex> new = "line 1\\nmodified line 2\\nline 3\\nline 4"
      iex> diff = Diff.generate("file.ex", old, new)
      iex> diff.stats.additions
      1
  """
  @spec generate(String.t(), String.t() | nil, String.t() | nil) :: diff()
  def generate(file_path, old_content, new_content) do
    old_lines = split_lines(old_content)
    new_lines = split_lines(new_content)

    changes = compute_changes(old_lines, new_lines)
    stats = compute_stats(changes)

    %{
      file: file_path,
      old_content: old_content,
      new_content: new_content,
      changes: changes,
      stats: stats
    }
  end

  @doc """
  Formats a diff for display with ANSI colors.

  ## Options
  - `:color` - Enable/disable colors (default: true)
  - `:context` - Number of context lines to show (default: 3)
  """
  @spec format(diff(), keyword()) :: String.t()
  def format(diff, opts \\ []) do
    color? = Keyword.get(opts, :color, true)
    context = Keyword.get(opts, :context, 3)

    lines = [
      header(diff, color?),
      stats_line(diff, color?),
      changes_block(diff.changes, context, color?)
    ]

    Enum.join(lines, "\n")
  end

  @doc """
  Applies a diff to reconstruct content.

  Returns the new content that results from applying the diff.
  """
  @spec apply_diff(String.t() | nil, list(line_change())) :: String.t()
  def apply_diff(_old_content, changes) do
    changes
    |> Enum.map(fn
      {:add, _, line} -> line
      {:modify, _, _, new_line} -> new_line
      {:unchanged, _, line} -> line
      {:delete, _, _} -> nil
    end)
    |> Enum.reject(&is_nil/1)
    |> Enum.join("\n")
  end

  # Private Functions

  defp split_lines(nil), do: []
  defp split_lines(content), do: String.split(content, "\n")

  defp compute_changes(old_lines, new_lines) do
    # Simple line-based diff algorithm
    # For production, consider using a proper diff library like Myers diff
    max_len = max(length(old_lines), length(new_lines))

    0..(max_len - 1)
    |> Enum.map(fn index ->
      old_line = Enum.at(old_lines, index)
      new_line = Enum.at(new_lines, index)

      case {old_line, new_line} do
        {nil, line} when is_binary(line) ->
          {:add, index + 1, line}

        {line, nil} when is_binary(line) ->
          {:delete, index + 1, line}

        {same, same} when is_binary(same) ->
          {:unchanged, index + 1, same}

        {old, new} when is_binary(old) and is_binary(new) ->
          {:modify, index + 1, old, new}

        _ ->
          nil
      end
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp compute_stats(changes) do
    Enum.reduce(changes, %{additions: 0, deletions: 0, modifications: 0}, fn
      {:add, _, _}, acc -> %{acc | additions: acc.additions + 1}
      {:delete, _, _}, acc -> %{acc | deletions: acc.deletions + 1}
      {:modify, _, _, _}, acc -> %{acc | modifications: acc.modifications + 1}
      _, acc -> acc
    end)
  end

  defp header(diff, color?) do
    if color? do
      IO.ANSI.cyan() <> "--- " <> diff.file <> IO.ANSI.reset()
    else
      "--- " <> diff.file
    end
  end

  defp stats_line(diff, color?) do
    %{additions: adds, deletions: dels, modifications: mods} = diff.stats

    stats =
      [
        if(adds > 0, do: "+#{adds}", else: nil),
        if(dels > 0, do: "-#{dels}", else: nil),
        if(mods > 0, do: "~#{mods}", else: nil)
      ]
      |> Enum.reject(&is_nil/1)
      |> Enum.join(", ")

    if color? do
      IO.ANSI.yellow() <> "@@ #{stats} @@" <> IO.ANSI.reset()
    else
      "@@ #{stats} @@"
    end
  end

  defp changes_block(changes, _context, color?) do
    changes
    |> Enum.map(&format_change(&1, color?))
    |> Enum.join("\n")
  end

  defp format_change({:add, line_num, line}, color?) do
    prefix = "+#{String.pad_leading(Integer.to_string(line_num), 4)} | "

    if color? do
      IO.ANSI.green() <> prefix <> line <> IO.ANSI.reset()
    else
      prefix <> line
    end
  end

  defp format_change({:delete, line_num, line}, color?) do
    prefix = "-#{String.pad_leading(Integer.to_string(line_num), 4)} | "

    if color? do
      IO.ANSI.red() <> prefix <> line <> IO.ANSI.reset()
    else
      prefix <> line
    end
  end

  defp format_change({:modify, line_num, old_line, new_line}, color?) do
    old_prefix = "-#{String.pad_leading(Integer.to_string(line_num), 4)} | "
    new_prefix = "+#{String.pad_leading(Integer.to_string(line_num), 4)} | "

    if color? do
      [
        IO.ANSI.red() <> old_prefix <> old_line <> IO.ANSI.reset(),
        IO.ANSI.green() <> new_prefix <> new_line <> IO.ANSI.reset()
      ]
      |> Enum.join("\n")
    else
      [old_prefix <> old_line, new_prefix <> new_line] |> Enum.join("\n")
    end
  end

  defp format_change({:unchanged, line_num, line}, color?) do
    prefix = " #{String.pad_leading(Integer.to_string(line_num), 4)} | "

    if color? do
      IO.ANSI.faint() <> prefix <> line <> IO.ANSI.reset()
    else
      prefix <> line
    end
  end
end
