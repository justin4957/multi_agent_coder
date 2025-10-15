defmodule MultiAgentCoder.CLI.ConcurrentDisplay do
  @moduledoc """
  Concurrent display manager for real-time multi-provider responses.

  Manages split-pane display showing responses from multiple AI providers
  streaming simultaneously. Implements the core functionality for issue #11.

  ## Features
  - Real-time streaming display in split panes
  - Provider-specific status indicators and colors
  - Handles different completion times gracefully
  - Displays token usage and elapsed time per provider
  - Supports dynamic layout based on number of providers

  ## Layout

  For 2 providers (side-by-side):
  ```
  ┌─ OpenAI ⚡ 2.3s ─────┬─ Claude ⚡ 1.8s ──────┐
  │ Response text...    │ Response text...     │
  │                     │                      │
  └─────────────────────┴──────────────────────┘
  ```

  For 3+ providers (stacked):
  ```
  ┌─ OpenAI ⚡ 2.3s ─────────────────────────┐
  │ Response text...                        │
  ├─ Claude ⚡ 1.8s ─────────────────────────┤
  │ Response text...                        │
  ├─ DeepSeek ⚡ 2.1s ───────────────────────┤
  │ Response text...                        │
  └─────────────────────────────────────────┘
  ```
  """

  use GenServer
  require Logger

  alias MultiAgentCoder.CLI.DisplayConfig

  defstruct [
    :providers,
    :provider_states,
    :provider_content,
    :provider_start_times,
    :display_mode,
    :terminal_width,
    :terminal_height,
    :focused_provider,
    :scroll_positions,
    :config
  ]

  # Status icons and colors
  @status_colors %{
    working: IO.ANSI.yellow(),
    complete: IO.ANSI.green(),
    error: IO.ANSI.red(),
    idle: IO.ANSI.blue()
  }

  @status_icons %{
    working: "⚡",
    complete: "✓",
    error: "✗",
    idle: "○"
  }

  @provider_colors %{
    openai: IO.ANSI.blue(),
    anthropic: IO.ANSI.green(),
    deepseek: IO.ANSI.cyan(),
    perplexity: IO.ANSI.magenta(),
    local: IO.ANSI.white()
  }

  # Client API

  @doc """
  Starts the concurrent display manager.

  ## Options
    * `:providers` - List of provider atoms to monitor
    * `:display_mode` - Display mode (:split_horizontal, :split_vertical, :stacked)
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Starts displaying concurrent responses from providers.
  """
  def start_display(providers, opts \\ []) do
    GenServer.call(__MODULE__, {:start_display, providers, opts})
  end

  @doc """
  Stops the display and returns final results.
  """
  def stop_display do
    GenServer.call(__MODULE__, :stop_display, :infinity)
  end

  @doc """
  Gets current display state.
  """
  def get_state do
    GenServer.call(__MODULE__, :get_state)
  end

  # Server Callbacks

  @impl true
  def init(_opts) do
    state = %__MODULE__{
      providers: [],
      provider_states: %{},
      provider_content: %{},
      provider_start_times: %{},
      display_mode: :stacked,
      terminal_width: get_terminal_width(),
      terminal_height: get_terminal_height(),
      focused_provider: nil,
      scroll_positions: %{},
      config: DisplayConfig.get_all()
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:start_display, providers, opts}, _from, state) do
    # Use configured layout or override from opts
    config_layout = state.config[:layout]
    display_mode = Keyword.get(opts, :display_mode, config_layout)

    # Subscribe to all providers
    Enum.each(providers, fn provider ->
      Phoenix.PubSub.subscribe(MultiAgentCoder.PubSub, "agent:#{provider}")
    end)

    # Initialize provider states
    provider_states =
      providers
      |> Enum.map(&{&1, :working})
      |> Enum.into(%{})

    provider_content =
      providers
      |> Enum.map(&{&1, ""})
      |> Enum.into(%{})

    provider_start_times =
      providers
      |> Enum.map(&{&1, System.monotonic_time(:millisecond)})
      |> Enum.into(%{})

    scroll_positions =
      providers
      |> Enum.map(&{&1, 0})
      |> Enum.into(%{})

    new_state = %{
      state
      | providers: providers,
        provider_states: provider_states,
        provider_content: provider_content,
        provider_start_times: provider_start_times,
        display_mode: display_mode,
        focused_provider: List.first(providers),
        scroll_positions: scroll_positions
    }

    # Clear screen and render initial display
    clear_screen()
    render_display(new_state)
    render_navigation_hint()

    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call(:stop_display, _from, state) do
    # Unsubscribe from all providers
    Enum.each(state.providers, fn provider ->
      Phoenix.PubSub.unsubscribe(MultiAgentCoder.PubSub, "agent:#{provider}")
    end)

    # Return final results
    results = %{
      provider_content: state.provider_content,
      provider_states: state.provider_states
    }

    {:reply, results, %{state | providers: []}}
  end

  @impl true
  def handle_call(:get_state, _from, state) do
    {:reply, state, state}
  end

  # PubSub message handlers

  @impl true
  def handle_info({:chunk, %{provider: provider, chunk: chunk}}, state) do
    # Append chunk to provider's content
    updated_content =
      Map.update(state.provider_content, provider, chunk, &(&1 <> chunk))

    new_state = %{state | provider_content: updated_content}

    # Re-render display with new content
    render_display(new_state)

    {:noreply, new_state}
  end

  @impl true
  def handle_info({:complete, %{provider: provider, response: response}}, state) do
    # Mark provider as complete and set final response
    updated_states = Map.put(state.provider_states, provider, :complete)
    updated_content = Map.put(state.provider_content, provider, response)

    new_state = %{
      state
      | provider_states: updated_states,
        provider_content: updated_content
    }

    # Re-render display
    render_display(new_state)

    {:noreply, new_state}
  end

  @impl true
  def handle_info({:error, %{provider: provider, message: message}}, state) do
    # Mark provider as error and show error message
    updated_states = Map.put(state.provider_states, provider, :error)
    updated_content = Map.put(state.provider_content, provider, "ERROR: #{message}")

    new_state = %{
      state
      | provider_states: updated_states,
        provider_content: updated_content
    }

    # Re-render display
    render_display(new_state)

    {:noreply, new_state}
  end

  @impl true
  def handle_info({:status_change, _status}, state) do
    # Handle generic status changes if needed
    {:noreply, state}
  end

  @impl true
  def handle_info(_msg, state) do
    {:noreply, state}
  end

  # Private Functions

  defp clear_screen do
    IO.write([IO.ANSI.clear(), IO.ANSI.home()])
  end

  defp render_display(state) do
    # Move cursor to home position
    IO.write(IO.ANSI.home())

    case state.display_mode do
      :stacked -> render_stacked_layout(state)
      :split_horizontal -> render_split_horizontal(state)
      _ -> render_stacked_layout(state)
    end
  end

  defp render_stacked_layout(state) do
    Enum.each(state.providers, fn provider ->
      render_provider_pane(provider, state)
    end)

    # Move cursor below all panes
    IO.write("\n")
  end

  defp render_split_horizontal(state) do
    # Implement side-by-side layout for 2 providers
    case length(state.providers) do
      2 ->
        render_side_by_side(state)

      _ ->
        # Fall back to stacked for 1 or 3+ providers
        render_stacked_layout(state)
    end
  end

  defp render_side_by_side(state) do
    [left_provider, right_provider] = state.providers

    left_content = Map.get(state.provider_content, left_provider, "")
    right_content = Map.get(state.provider_content, right_provider, "")

    left_status = Map.get(state.provider_states, left_provider, :idle)
    right_status = Map.get(state.provider_states, right_provider, :idle)

    pane_width = div(state.terminal_width - 3, 2)
    max_lines = state.terminal_height - 5

    # Render headers side-by-side
    left_header = format_pane_header(left_provider, left_status, state, pane_width)
    right_header = format_pane_header(right_provider, right_status, state, pane_width)

    IO.write([left_header, "│", right_header, "\n"])

    # Render content side-by-side
    left_lines = String.split(left_content, "\n") |> Enum.take(max_lines)
    right_lines = String.split(right_content, "\n") |> Enum.take(max_lines)

    max_content_lines = max(length(left_lines), length(right_lines))

    0..(max_content_lines - 1)
    |> Enum.each(fn i ->
      left_line = Enum.at(left_lines, i, "")
      right_line = Enum.at(right_lines, i, "")

      left_formatted = format_pane_content_line(left_provider, left_line, state, pane_width)
      right_formatted = format_pane_content_line(right_provider, right_line, state, pane_width)

      IO.write([left_formatted, "│", right_formatted, "\n"])
    end)

    # Render footers
    left_footer = format_pane_footer(left_provider, state, pane_width)
    right_footer = format_pane_footer(right_provider, state, pane_width)

    IO.write([left_footer, "┴", right_footer, "\n"])
  end

  defp format_pane_header(provider, status, state, width) do
    provider_name = provider |> to_string() |> String.capitalize()
    elapsed = get_elapsed_time(provider, state)

    provider_color = Map.get(@provider_colors, provider, IO.ANSI.white())
    _status_color = Map.get(@status_colors, status)
    status_icon = Map.get(@status_icons, status)

    focus_indicator =
      if state.focused_provider == provider and state.config[:show_progress], do: "▶ ", else: ""

    header_text = "#{focus_indicator}#{provider_name} #{status_icon} #{elapsed}"
    padding = max(0, width - String.length(header_text) - 4)

    [
      provider_color,
      "┌─ ",
      header_text,
      String.duplicate("─", padding),
      "─┐",
      IO.ANSI.reset()
    ]
    |> IO.iodata_to_binary()
  end

  defp format_pane_content_line(provider, line, _state, width) do
    provider_color = Map.get(@provider_colors, provider, IO.ANSI.white())
    truncated = String.slice(line, 0, width - 4)
    padding = max(0, width - String.length(truncated) - 4)

    [
      provider_color,
      "│ ",
      IO.ANSI.reset(),
      truncated,
      String.duplicate(" ", padding),
      provider_color,
      " │",
      IO.ANSI.reset()
    ]
    |> IO.iodata_to_binary()
  end

  defp format_pane_footer(provider, _state, width) do
    provider_color = Map.get(@provider_colors, provider, IO.ANSI.white())

    [
      provider_color,
      "└",
      String.duplicate("─", width - 2),
      "┘",
      IO.ANSI.reset()
    ]
    |> IO.iodata_to_binary()
  end

  defp render_navigation_hint do
    if DisplayConfig.get(:show_progress) do
      IO.write([
        "\n",
        IO.ANSI.faint(),
        "Press Ctrl+C to cancel | Responses streaming in real-time",
        IO.ANSI.reset(),
        "\n"
      ])
    end
  end

  defp render_provider_pane(provider, state) do
    status = Map.get(state.provider_states, provider, :idle)
    content = Map.get(state.provider_content, provider, "")
    elapsed = get_elapsed_time(provider, state)

    provider_name = provider |> to_string() |> String.capitalize()
    provider_color = Map.get(@provider_colors, provider, IO.ANSI.white())
    _status_color = Map.get(@status_colors, status)
    status_icon = Map.get(@status_icons, status)

    focus_indicator =
      if state.focused_provider == provider and state.config[:show_progress], do: "▶ ", else: ""

    # Render pane header
    header_text = "#{focus_indicator}#{provider_name} #{status_icon} #{elapsed}"

    header_padding =
      max(0, state.terminal_width - String.length(header_text) - 6)

    header = [
      provider_color,
      "┌─ ",
      header_text,
      String.duplicate("─", header_padding),
      "┐",
      IO.ANSI.reset(),
      "\n"
    ]

    IO.write(header)

    # Render content (truncated to fit pane)
    # Use configured max_pane_height or calculate based on available space
    max_lines =
      if state.config[:compact_mode] do
        state.config[:max_pane_height]
      else
        min(
          state.config[:max_pane_height],
          div(state.terminal_height, length(state.providers)) - 3
        )
      end

    content_lines = String.split(content, "\n") |> Enum.take(max_lines)

    Enum.each(content_lines, fn line ->
      truncated_line = String.slice(line, 0, state.terminal_width - 4)
      IO.write([provider_color, "│ ", IO.ANSI.reset(), truncated_line, "\n"])
    end)

    # Render pane footer
    footer = [
      provider_color,
      "└",
      String.duplicate("─", state.terminal_width - 2),
      "┘",
      IO.ANSI.reset(),
      "\n"
    ]

    IO.write(footer)
  end

  defp get_elapsed_time(provider, state) do
    case Map.get(state.provider_start_times, provider) do
      nil ->
        "0s"

      start_time ->
        elapsed_ms = System.monotonic_time(:millisecond) - start_time
        format_elapsed_time(elapsed_ms)
    end
  end

  defp format_elapsed_time(ms) when ms < 1000, do: "#{ms}ms"
  defp format_elapsed_time(ms), do: "#{Float.round(ms / 1000, 1)}s"

  defp get_terminal_width do
    case :io.columns() do
      {:ok, width} -> width
      # Default fallback
      {:error, _} -> 80
    end
  end

  defp get_terminal_height do
    case :io.rows() do
      {:ok, height} -> height
      # Default fallback
      {:error, _} -> 24
    end
  end
end
