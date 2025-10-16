defmodule MultiAgentCoder.Monitor.Dashboard do
  @moduledoc """
  Real-time coding progress dashboard for monitoring multiple providers.

  Provides a comprehensive view of all active providers, their tasks,
  file operations, progress, and resource usage.

  ## Features
  - Real-time provider status panels
  - Task progress indicators
  - File operation tracking
  - Token usage and cost monitoring
  - Error highlighting without disrupting other providers
  - Concurrent task visualization

  ## Usage

      # Start monitoring with dashboard
      Dashboard.start_monitoring([:openai, :anthropic, :deepseek],
        task: "Build Phoenix API with Auth"
      )

      # Update provider status
      Dashboard.update_provider_status(:openai, :active,
        file: "lib/my_app/user.ex",
        progress: 45,
        lines_generated: 89
      )

      # Stop monitoring and show summary
      Dashboard.stop_monitoring()

  ## Example Output

      ═══════════════════════════════════════════════════════════════
        Multi-Agent Coder - Concurrent Task Monitor
        Task: "Build Phoenix API" | Elapsed: 3m 42s
      ═══════════════════════════════════════════════════════════════

      ┌─ Anthropic (Claude) ─────────────────── ⚡ ACTIVE ──────────┐
      │ Task: Create schema [████████████████░░] 85%                 │
      │ File: lib/my_app/accounts/user.ex                            │
      │ Stats: 147 lines | 2,341 tokens | $0.03 | 1m 23s            │
      └───────────────────────────────────────────────────────────────┘

      Overall Progress: [███████████░░░░░] 55% | 2/3 tasks complete
      Total: 281 lines | 4,217 tokens | $0.08
  """

  use GenServer
  require Logger

  alias MultiAgentCoder.Monitor.{FileTracker, ProgressCalculator}

  defstruct [
    :task_name,
    :start_time,
    :providers,
    :provider_states,
    :display_mode,
    :refresh_rate_ms,
    :display_pid
  ]

  @type provider_state :: %{
          status: :idle | :active | :completed | :error,
          current_task: String.t() | nil,
          current_file: String.t() | nil,
          progress_percentage: float(),
          lines_generated: integer(),
          tokens_used: integer(),
          estimated_cost: float(),
          elapsed_ms: integer(),
          error: String.t() | nil,
          start_time: integer() | nil
        }

  @type t :: %__MODULE__{
          task_name: String.t() | nil,
          start_time: integer() | nil,
          providers: list(atom()),
          provider_states: %{atom() => provider_state()},
          display_mode: :full | :compact | :minimal,
          refresh_rate_ms: integer(),
          display_pid: pid() | nil
        }

  # Public API

  @doc """
  Starts the dashboard GenServer.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Starts monitoring providers with the dashboard.
  """
  @spec start_monitoring(list(atom()), keyword()) :: :ok | {:error, term()}
  def start_monitoring(providers, opts \\ []) do
    GenServer.call(__MODULE__, {:start_monitoring, providers, opts})
  end

  @doc """
  Updates a provider's status and progress.
  """
  @spec update_provider_status(atom(), atom(), keyword()) :: :ok
  def update_provider_status(provider, status, opts \\ []) do
    GenServer.cast(__MODULE__, {:update_provider_status, provider, status, opts})
  end

  @doc """
  Records a file operation for a provider.
  """
  @spec record_file_operation(atom(), String.t(), atom(), keyword()) :: :ok
  def record_file_operation(provider, file_path, operation, opts \\ []) do
    GenServer.cast(__MODULE__, {:record_file_operation, provider, file_path, operation, opts})
  end

  @doc """
  Updates token usage for a provider.
  """
  @spec update_token_usage(atom(), integer(), float()) :: :ok
  def update_token_usage(provider, tokens, cost) do
    GenServer.cast(__MODULE__, {:update_token_usage, provider, tokens, cost})
  end

  @doc """
  Stops monitoring and returns final statistics.
  """
  @spec stop_monitoring() :: map()
  def stop_monitoring do
    GenServer.call(__MODULE__, :stop_monitoring)
  end

  @doc """
  Gets current dashboard state.
  """
  @spec get_state() :: map()
  def get_state do
    GenServer.call(__MODULE__, :get_state)
  end

  @doc """
  Changes the display mode.
  """
  @spec set_display_mode(:full | :compact | :minimal) :: :ok
  def set_display_mode(mode) when mode in [:full, :compact, :minimal] do
    GenServer.cast(__MODULE__, {:set_display_mode, mode})
  end

  # GenServer Callbacks

  @impl true
  def init(opts) do
    # Start FileTracker if not already started
    case GenServer.whereis(FileTracker) do
      nil -> {:ok, _} = FileTracker.start_link()
      _pid -> :ok
    end

    state = %__MODULE__{
      task_name: nil,
      start_time: nil,
      providers: [],
      provider_states: %{},
      display_mode: Keyword.get(opts, :display_mode, :full),
      refresh_rate_ms: Keyword.get(opts, :refresh_rate_ms, 500),
      display_pid: nil
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:start_monitoring, providers, opts}, _from, state) do
    task_name = Keyword.get(opts, :task, "Coding Task")

    # Initialize provider states
    provider_states =
      providers
      |> Enum.map(fn provider ->
        {provider,
         %{
           status: :idle,
           current_task: nil,
           current_file: nil,
           progress_percentage: 0.0,
           lines_generated: 0,
           tokens_used: 0,
           estimated_cost: 0.0,
           elapsed_ms: 0,
           error: nil,
           start_time: nil
         }}
      end)
      |> Enum.into(%{})

    # Subscribe to provider events
    Enum.each(providers, fn provider ->
      Phoenix.PubSub.subscribe(MultiAgentCoder.PubSub, "agent:#{provider}")
    end)

    new_state = %{
      state
      | task_name: task_name,
        start_time: System.monotonic_time(:millisecond),
        providers: providers,
        provider_states: provider_states
    }

    # Start display loop
    display_pid = spawn_link(fn -> display_loop(self(), new_state.refresh_rate_ms) end)

    final_state = %{new_state | display_pid: display_pid}

    # Render initial dashboard
    render_dashboard(final_state)

    {:reply, :ok, final_state}
  end

  @impl true
  def handle_call(:stop_monitoring, _from, state) do
    # Stop display loop
    if state.display_pid do
      Process.exit(state.display_pid, :normal)
    end

    # Unsubscribe from events
    Enum.each(state.providers, fn provider ->
      Phoenix.PubSub.unsubscribe(MultiAgentCoder.PubSub, "agent:#{provider}")
    end)

    # Calculate final statistics
    stats = calculate_final_stats(state)

    # Render final summary
    render_final_summary(state, stats)

    {:reply, stats, %{state | display_pid: nil}}
  end

  @impl true
  def handle_call(:get_state, _from, state) do
    state_map = %{
      task_name: state.task_name,
      elapsed_ms: elapsed_time_ms(state.start_time),
      providers: state.providers,
      provider_states: state.provider_states,
      display_mode: state.display_mode
    }

    {:reply, state_map, state}
  end

  @impl true
  def handle_cast({:update_provider_status, provider, status, opts}, state) do
    current_state = Map.get(state.provider_states, provider, %{})

    updated_provider_state =
      current_state
      |> Map.put(:status, status)
      |> maybe_update(:current_task, Keyword.get(opts, :task))
      |> maybe_update(:current_file, Keyword.get(opts, :file))
      |> maybe_update(
        :progress_percentage,
        Keyword.get(opts, :progress, current_state[:progress_percentage])
      )
      |> maybe_update(
        :lines_generated,
        Keyword.get(opts, :lines_generated, current_state[:lines_generated])
      )
      |> maybe_update(:error, Keyword.get(opts, :error))

    # Set start time if provider just became active
    updated_provider_state =
      if status == :active and is_nil(current_state[:start_time]) do
        Map.put(updated_provider_state, :start_time, System.monotonic_time(:millisecond))
      else
        updated_provider_state
      end

    # Update elapsed time if active
    updated_provider_state =
      if status in [:active, :completed, :error] and updated_provider_state[:start_time] do
        elapsed = System.monotonic_time(:millisecond) - updated_provider_state[:start_time]
        Map.put(updated_provider_state, :elapsed_ms, elapsed)
      else
        updated_provider_state
      end

    new_provider_states = Map.put(state.provider_states, provider, updated_provider_state)

    {:noreply, %{state | provider_states: new_provider_states}}
  end

  @impl true
  def handle_cast({:record_file_operation, provider, file_path, operation, opts}, state) do
    # Track file operation
    FileTracker.track_operation(provider, file_path, operation, opts)

    # Update current file for provider
    current_state = Map.get(state.provider_states, provider, %{})
    updated_provider_state = Map.put(current_state, :current_file, file_path)

    new_provider_states = Map.put(state.provider_states, provider, updated_provider_state)

    {:noreply, %{state | provider_states: new_provider_states}}
  end

  @impl true
  def handle_cast({:update_token_usage, provider, tokens, cost}, state) do
    current_state = Map.get(state.provider_states, provider, %{})

    updated_provider_state =
      current_state
      |> Map.update(:tokens_used, tokens, &(&1 + tokens))
      |> Map.update(:estimated_cost, cost, &(&1 + cost))

    new_provider_states = Map.put(state.provider_states, provider, updated_provider_state)

    {:noreply, %{state | provider_states: new_provider_states}}
  end

  @impl true
  def handle_cast({:set_display_mode, mode}, state) do
    {:noreply, %{state | display_mode: mode}}
  end

  @impl true
  def handle_info(:refresh_display, state) do
    render_dashboard(state)
    {:noreply, state}
  end

  # Private Functions

  defp display_loop(parent_pid, refresh_rate_ms) do
    Process.sleep(refresh_rate_ms)
    send(parent_pid, :refresh_display)
    display_loop(parent_pid, refresh_rate_ms)
  end

  defp render_dashboard(state) do
    # Clear screen and move cursor to top
    IO.write([IO.ANSI.clear(), IO.ANSI.home()])

    # Render header
    render_header(state)

    # Render provider panels based on display mode
    case state.display_mode do
      :full -> render_full_panels(state)
      :compact -> render_compact_panels(state)
      :minimal -> render_minimal_panels(state)
    end

    # Render overall progress
    render_overall_progress(state)

    # Render footer with controls
    render_footer(state)
  end

  defp render_header(state) do
    elapsed = elapsed_time_ms(state.start_time)
    elapsed_str = ProgressCalculator.format_estimated_remaining(elapsed)

    IO.puts([
      IO.ANSI.bright(),
      IO.ANSI.blue(),
      "═" |> String.duplicate(75),
      IO.ANSI.reset(),
      "\n",
      IO.ANSI.bright(),
      "  Multi-Agent Coder - Concurrent Task Monitor\n",
      IO.ANSI.reset(),
      "  Task: \"#{state.task_name}\" | Elapsed: #{elapsed_str}\n",
      IO.ANSI.bright(),
      IO.ANSI.blue(),
      "═" |> String.duplicate(75),
      IO.ANSI.reset(),
      "\n"
    ])
  end

  defp render_full_panels(state) do
    state.providers
    |> Enum.each(fn provider ->
      render_provider_panel(provider, state.provider_states[provider])
    end)
  end

  defp render_compact_panels(state) do
    state.providers
    |> Enum.each(fn provider ->
      render_provider_compact(provider, state.provider_states[provider])
    end)
  end

  defp render_minimal_panels(state) do
    state.providers
    |> Enum.map(fn provider ->
      render_provider_minimal(provider, state.provider_states[provider])
    end)
    |> Enum.join(" | ")
    |> IO.puts()

    IO.puts("")
  end

  defp render_provider_panel(provider, provider_state) do
    {status_text, status_color} = format_status(provider_state.status)
    provider_name = provider |> to_string() |> String.capitalize()

    # Panel header
    IO.puts([
      "\n",
      IO.ANSI.bright(),
      "┌─ #{provider_name} ",
      "─" |> String.duplicate(max(40 - String.length(provider_name), 0)),
      " ",
      status_color,
      status_text,
      IO.ANSI.reset(),
      IO.ANSI.bright(),
      " ",
      "─" |> String.duplicate(15),
      "┐"
    ])

    # Task and progress
    if provider_state.current_task do
      progress_bar = ProgressCalculator.format_progress_bar(provider_state.progress_percentage)
      IO.puts(["│ Task: #{provider_state.current_task} #{progress_bar}"])
    end

    # Current file
    if provider_state.current_file do
      IO.puts(["│ File: #{provider_state.current_file}"])
    end

    # Error message
    if provider_state.error do
      IO.puts([
        "│ ",
        IO.ANSI.red(),
        "Error: #{provider_state.error}",
        IO.ANSI.reset()
      ])
    end

    # Statistics
    elapsed_str = ProgressCalculator.format_estimated_remaining(provider_state.elapsed_ms)
    cost_str = :erlang.float_to_binary(provider_state.estimated_cost, decimals: 3)

    IO.puts([
      "│ Stats: #{provider_state.lines_generated} lines | ",
      "#{provider_state.tokens_used} tokens | ",
      "$#{cost_str} | ",
      elapsed_str
    ])

    # Panel footer
    IO.puts([
      IO.ANSI.bright(),
      "└",
      "─" |> String.duplicate(73),
      "┘",
      IO.ANSI.reset()
    ])
  end

  defp render_provider_compact(provider, provider_state) do
    {status_text, status_color} = format_status(provider_state.status)
    provider_name = provider |> to_string() |> String.capitalize()
    progress_bar = ProgressCalculator.format_progress_bar(provider_state.progress_percentage, 10)

    IO.puts([
      status_color,
      status_text,
      IO.ANSI.reset(),
      " #{provider_name}: #{progress_bar} | ",
      "#{provider_state.lines_generated} lines"
    ])
  end

  defp render_provider_minimal(provider, provider_state) do
    {_status_text, status_color} = format_status(provider_state.status)
    provider_name = provider |> to_string() |> String.capitalize()

    [
      status_color,
      provider_name,
      " #{trunc(provider_state.progress_percentage)}%",
      IO.ANSI.reset()
    ]
    |> IO.iodata_to_binary()
  end

  defp render_overall_progress(state) do
    # Calculate overall progress
    progress_results =
      state.provider_states
      |> Enum.map(fn {_provider, pstate} ->
        %{
          percentage: pstate.progress_percentage,
          status:
            case pstate.status do
              :completed -> :completed
              :error -> :error
              :active -> :in_progress
              _ -> :not_started
            end,
          estimated_remaining_ms: nil
        }
      end)

    overall = ProgressCalculator.calculate_overall_progress(progress_results)

    completed_count = Enum.count(state.provider_states, fn {_, ps} -> ps.status == :completed end)
    total_count = length(state.providers)

    # Calculate totals
    total_lines = Enum.sum(Enum.map(state.provider_states, fn {_, ps} -> ps.lines_generated end))
    total_tokens = Enum.sum(Enum.map(state.provider_states, fn {_, ps} -> ps.tokens_used end))
    total_cost = Enum.sum(Enum.map(state.provider_states, fn {_, ps} -> ps.estimated_cost end))

    progress_bar = ProgressCalculator.format_progress_bar(overall.percentage, 25)
    cost_str = :erlang.float_to_binary(total_cost, decimals: 2)

    IO.puts([
      "\n",
      IO.ANSI.bright(),
      "Overall Progress: #{progress_bar} | #{completed_count}/#{total_count} providers complete\n",
      "Total: #{total_lines} lines | #{total_tokens} tokens | $#{cost_str}",
      IO.ANSI.reset()
    ])
  end

  defp render_footer(_state) do
    IO.puts([
      "\n",
      IO.ANSI.faint(),
      "Press Ctrl+C to stop monitoring",
      IO.ANSI.reset()
    ])
  end

  defp render_final_summary(state, stats) do
    IO.write([IO.ANSI.clear(), IO.ANSI.home()])

    IO.puts([
      IO.ANSI.bright(),
      IO.ANSI.green(),
      "\n✓ Monitoring Complete\n",
      IO.ANSI.reset()
    ])

    IO.puts("Task: #{state.task_name}")
    IO.puts("Duration: #{ProgressCalculator.format_estimated_remaining(stats.total_elapsed_ms)}")
    IO.puts("Providers: #{stats.total_providers}")
    IO.puts("Completed: #{stats.completed_providers}")
    IO.puts("Failed: #{stats.failed_providers}")
    IO.puts("\nTotals:")
    IO.puts("  Lines Generated: #{stats.total_lines}")
    IO.puts("  Tokens Used: #{stats.total_tokens}")
    IO.puts("  Estimated Cost: $#{:erlang.float_to_binary(stats.total_cost, decimals: 2)}")

    file_stats = FileTracker.get_stats()
    IO.puts("\nFile Operations:")
    IO.puts("  Files Modified: #{file_stats.total_files_touched}")
    IO.puts("  Total Operations: #{file_stats.total_operations}")
    IO.puts("  Conflicts: #{file_stats.conflicts}")

    IO.puts("")
  end

  defp calculate_final_stats(state) do
    total_lines = Enum.sum(Enum.map(state.provider_states, fn {_, ps} -> ps.lines_generated end))
    total_tokens = Enum.sum(Enum.map(state.provider_states, fn {_, ps} -> ps.tokens_used end))
    total_cost = Enum.sum(Enum.map(state.provider_states, fn {_, ps} -> ps.estimated_cost end))

    completed = Enum.count(state.provider_states, fn {_, ps} -> ps.status == :completed end)
    failed = Enum.count(state.provider_states, fn {_, ps} -> ps.status == :error end)

    %{
      total_elapsed_ms: elapsed_time_ms(state.start_time),
      total_providers: length(state.providers),
      completed_providers: completed,
      failed_providers: failed,
      total_lines: total_lines,
      total_tokens: total_tokens,
      total_cost: total_cost,
      provider_details: state.provider_states
    }
  end

  defp format_status(:idle), do: {"○ IDLE", IO.ANSI.cyan()}
  defp format_status(:active), do: {"⚡ ACTIVE", IO.ANSI.yellow()}
  defp format_status(:completed), do: {"✓ COMPLETED", IO.ANSI.green()}
  defp format_status(:error), do: {"✗ ERROR", IO.ANSI.red()}

  defp elapsed_time_ms(nil), do: 0

  defp elapsed_time_ms(start_time) do
    System.monotonic_time(:millisecond) - start_time
  end

  defp maybe_update(map, _key, nil), do: map
  defp maybe_update(map, key, value), do: Map.put(map, key, value)
end
