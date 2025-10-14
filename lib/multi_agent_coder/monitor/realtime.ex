defmodule MultiAgentCoder.Monitor.Realtime do
  @moduledoc """
  Real-time monitoring of agent status and progress.

  Subscribes to agent events via PubSub and provides
  live updates during task execution with visual feedback.

  Features:
  - Individual agent status tracking (working/idle/error)
  - Elapsed time tracking per agent
  - Spinner animations for active tasks
  - Colored status indicators
  - Summary statistics on completion
  - Quiet mode support
  """

  use GenServer
  require Logger

  defstruct [
    :start_time,
    :active_agents,
    :results,
    :agent_statuses,
    :agent_start_times,
    :spinner_state,
    :quiet_mode,
    :display_pid
  ]

  @spinner_frames ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"]

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Starts monitoring a task with real-time progress display.
  """
  def start_monitoring(providers, opts \\ []) do
    GenServer.call(__MODULE__, {:start_monitoring, providers, opts})
  end

  @doc """
  Stops monitoring and returns final statistics.
  """
  def stop_monitoring do
    GenServer.call(__MODULE__, :stop_monitoring)
  end

  @doc """
  Gets current monitoring status.
  """
  def get_status do
    GenServer.call(__MODULE__, :get_status)
  end

  @doc """
  Subscribes to updates from a specific agent.
  """
  def subscribe(provider) do
    Phoenix.PubSub.subscribe(MultiAgentCoder.PubSub, "agent:#{provider}")
  end

  @doc """
  Subscribes to all agent updates.
  """
  def subscribe_all do
    providers = get_active_providers()
    Enum.each(providers, &subscribe/1)
    {:ok, providers}
  end

  @doc """
  Unsubscribes from agent updates.
  """
  def unsubscribe(provider) do
    Phoenix.PubSub.unsubscribe(MultiAgentCoder.PubSub, "agent:#{provider}")
  end

  @impl true
  def init(_opts) do
    state = %__MODULE__{
      start_time: nil,
      active_agents: MapSet.new(),
      results: %{},
      agent_statuses: %{},
      agent_start_times: %{},
      spinner_state: 0,
      quiet_mode: false,
      display_pid: nil
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:start_monitoring, providers, opts}, _from, state) do
    quiet_mode = Keyword.get(opts, :quiet, false)

    # Subscribe to all providers
    Enum.each(providers, &subscribe/1)

    # Initialize agent statuses
    agent_statuses =
      providers
      |> Enum.map(&{&1, :idle})
      |> Enum.into(%{})

    new_state = %{state |
      start_time: System.monotonic_time(:millisecond),
      active_agents: MapSet.new(providers),
      agent_statuses: agent_statuses,
      agent_start_times: %{},
      results: %{},
      quiet_mode: quiet_mode
    }

    # Start display update loop
    final_state = unless quiet_mode do
      pid = spawn_link(fn -> display_loop(self()) end)
      %{new_state | display_pid: pid}
    else
      new_state
    end

    {:reply, :ok, final_state}
  end

  @impl true
  def handle_call(:stop_monitoring, _from, state) do
    # Stop display loop
    if state.display_pid do
      Process.exit(state.display_pid, :normal)
    end

    # Calculate final statistics
    total_time = elapsed_time_ms(state.start_time)
    stats = calculate_statistics(state, total_time)

    # Unsubscribe from all
    Enum.each(state.active_agents, &unsubscribe/1)

    {:reply, stats, %{state | display_pid: nil}}
  end

  @impl true
  def handle_call(:get_status, _from, state) do
    status = %{
      active_agents: MapSet.to_list(state.active_agents),
      agent_statuses: state.agent_statuses,
      elapsed_time: elapsed_time_ms(state.start_time),
      results_count: map_size(state.results)
    }
    {:reply, status, state}
  end

  @impl true
  def handle_info({:status_change, status}, state) do
    # Extract provider from PubSub metadata
    provider = extract_provider_from_topic()

    updated_statuses = Map.put(state.agent_statuses, provider, status)

    # Track start time for working agents
    updated_start_times =
      if status == :working do
        Map.put(state.agent_start_times, provider, System.monotonic_time(:millisecond))
      else
        state.agent_start_times
      end

    new_state = %{state |
      agent_statuses: updated_statuses,
      agent_start_times: updated_start_times
    }

    unless state.quiet_mode do
      display_status_update(provider, status, new_state)
    end

    {:noreply, new_state}
  end

  @impl true
  def handle_info({:task_complete, result}, state) do
    provider = extract_provider_from_topic()

    updated_results = Map.put(state.results, provider, result)
    updated_statuses = Map.put(state.agent_statuses, provider, :completed)

    new_state = %{state |
      results: updated_results,
      agent_statuses: updated_statuses
    }

    unless state.quiet_mode do
      display_completion(provider, result, new_state)
    end

    {:noreply, new_state}
  end

  @impl true
  def handle_info(:update_display, state) do
    unless state.quiet_mode do
      display_current_status(state)
    end

    new_spinner_state = rem(state.spinner_state + 1, length(@spinner_frames))
    {:noreply, %{state | spinner_state: new_spinner_state}}
  end

  @impl true
  def handle_info(_msg, state) do
    {:noreply, state}
  end

  # Private Functions

  defp display_loop(parent_pid) do
    Process.sleep(100)
    send(parent_pid, :update_display)
    display_loop(parent_pid)
  end

  defp display_current_status(state) do
    # Clear previous lines
    IO.write([IO.ANSI.clear_line(), "\r"])

    # Display each agent status on a single line
    status_line =
      state.active_agents
      |> Enum.map(fn provider ->
        status = Map.get(state.agent_statuses, provider, :idle)
        format_agent_status(provider, status, state)
      end)
      |> Enum.join(" ")

    IO.write(status_line)
  end

  defp format_agent_status(provider, status, state) do
    spinner = Enum.at(@spinner_frames, state.spinner_state)
    elapsed = get_agent_elapsed_time(provider, state)

    {icon, color} = get_status_icon_and_color(status)

    provider_name = provider |> to_string() |> String.capitalize()

    case status do
      :working ->
        [color, spinner, " ", provider_name, " (", elapsed, ")", IO.ANSI.reset(), " "]
      :completed ->
        [color, icon, " ", provider_name, " ✓", IO.ANSI.reset(), " "]
      :error ->
        [color, icon, " ", provider_name, " ✗", IO.ANSI.reset(), " "]
      _ ->
        [color, icon, " ", provider_name, IO.ANSI.reset(), " "]
    end
    |> IO.iodata_to_binary()
  end

  defp get_status_icon_and_color(:working), do: {"⚙", IO.ANSI.yellow()}
  defp get_status_icon_and_color(:completed), do: {"✓", IO.ANSI.green()}
  defp get_status_icon_and_color(:error), do: {"✗", IO.ANSI.red()}
  defp get_status_icon_and_color(:idle), do: {"○", IO.ANSI.blue()}
  defp get_status_icon_and_color(_), do: {"?", IO.ANSI.white()}

  defp get_agent_elapsed_time(provider, state) do
    case Map.get(state.agent_start_times, provider) do
      nil -> "0s"
      start_time ->
        elapsed = System.monotonic_time(:millisecond) - start_time
        format_elapsed_time(elapsed)
    end
  end

  defp format_elapsed_time(ms) when ms < 1000, do: "#{ms}ms"
  defp format_elapsed_time(ms), do: "#{div(ms, 1000)}s"

  defp display_status_update(provider, status, _state) do
    provider_name = provider |> to_string() |> String.capitalize()
    {_icon, color} = get_status_icon_and_color(status)

    Logger.debug([
      color,
      "#{provider_name}: #{status}",
      IO.ANSI.reset()
    ])
  end

  defp display_completion(provider, result, state) do
    provider_name = provider |> to_string() |> String.capitalize()
    elapsed = get_agent_elapsed_time(provider, state)

    case result do
      {:ok, _content} ->
        Logger.info([
          IO.ANSI.green(),
          "✓ #{provider_name} completed in #{elapsed}",
          IO.ANSI.reset()
        ])
      {:error, reason} ->
        Logger.error([
          IO.ANSI.red(),
          "✗ #{provider_name} failed: #{inspect(reason)}",
          IO.ANSI.reset()
        ])
    end
  end

  defp calculate_statistics(state, total_time) do
    successful =
      state.results
      |> Enum.count(fn {_provider, result} ->
        match?({:ok, _}, result)
      end)

    failed = map_size(state.results) - successful

    %{
      total_time_ms: total_time,
      total_agents: MapSet.size(state.active_agents),
      successful: successful,
      failed: failed,
      results: state.results
    }
  end

  defp elapsed_time_ms(nil), do: 0
  defp elapsed_time_ms(start_time) do
    System.monotonic_time(:millisecond) - start_time
  end

  defp get_active_providers do
    Application.get_env(:multi_agent_coder, :providers, [])
    |> Keyword.keys()
  end

  defp extract_provider_from_topic do
    # This would need to be enhanced to actually extract from PubSub metadata
    # For now, we'll track this differently through the broadcast calls
    :unknown
  end
end
