defmodule MultiAgentCoder.Tools.ApprovalHistory do
  @moduledoc """
  Tracks command approval history for the current session.

  Maintains a record of approved commands to enable "trust for session"
  functionality and approval history queries.

  ## Usage

      # Add an approved command
      ApprovalHistory.add_approval("mix deps.get", :openai, :warning)

      # Check if command was previously approved
      ApprovalHistory.previously_approved?("mix deps.get")

      # Get approval history
      ApprovalHistory.list_approvals()

      # Clear history
      ApprovalHistory.clear()
  """

  use GenServer
  require Logger

  @type approval_entry :: %{
          command: String.t(),
          provider: atom(),
          danger_level: atom(),
          timestamp: DateTime.t(),
          approved_by: :user | :auto
        }

  # Client API

  @doc """
  Start the approval history GenServer.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Add a command approval to the history.

  ## Examples

      iex> ApprovalHistory.add_approval("mix test", :anthropic, :safe, :auto)
      :ok
  """
  @spec add_approval(String.t(), atom(), atom(), :user | :auto) :: :ok
  def add_approval(command, provider, danger_level, approved_by \\ :user) do
    GenServer.cast(__MODULE__, {:add_approval, command, provider, danger_level, approved_by})
  end

  @doc """
  Check if a command was previously approved in this session.

  Returns `true` if the exact command was approved before.

  ## Examples

      iex> ApprovalHistory.previously_approved?("mix test")
      false
  """
  @spec previously_approved?(String.t()) :: boolean()
  def previously_approved?(command) do
    GenServer.call(__MODULE__, {:previously_approved?, command})
  end

  @doc """
  Check if a command pattern was previously approved.

  Uses pattern matching to check if similar commands were approved.
  """
  @spec pattern_approved?(String.t()) :: boolean()
  def pattern_approved?(command) do
    GenServer.call(__MODULE__, {:pattern_approved?, command})
  end

  @doc """
  Get the list of all approvals in this session.

  ## Examples

      iex> ApprovalHistory.list_approvals()
      [%{command: "mix test", provider: :anthropic, ...}]
  """
  @spec list_approvals() :: list(approval_entry())
  def list_approvals do
    GenServer.call(__MODULE__, :list_approvals)
  end

  @doc """
  Get approvals filtered by provider.

  ## Examples

      iex> ApprovalHistory.list_approvals(:openai)
      [%{command: "mix test", provider: :openai, ...}]
  """
  @spec list_approvals(atom()) :: list(approval_entry())
  def list_approvals(provider) do
    GenServer.call(__MODULE__, {:list_approvals_by_provider, provider})
  end

  @doc """
  Get the count of approvals in this session.
  """
  @spec count() :: non_neg_integer()
  def count do
    GenServer.call(__MODULE__, :count)
  end

  @doc """
  Clear all approval history.

  ## Examples

      iex> ApprovalHistory.clear()
      :ok
  """
  @spec clear() :: :ok
  def clear do
    GenServer.call(__MODULE__, :clear)
  end

  # Server Callbacks

  @impl true
  def init(_opts) do
    Logger.debug("ApprovalHistory started")
    {:ok, %{approvals: [], commands: MapSet.new()}}
  end

  @impl true
  def handle_cast({:add_approval, command, provider, danger_level, approved_by}, state) do
    entry = %{
      command: command,
      provider: provider,
      danger_level: danger_level,
      timestamp: DateTime.utc_now(),
      approved_by: approved_by
    }

    new_state = %{
      approvals: [entry | state.approvals],
      commands: MapSet.put(state.commands, command)
    }

    Logger.debug("Added approval: #{command} (#{danger_level}) for #{provider} by #{approved_by}")

    {:noreply, new_state}
  end

  @impl true
  def handle_call({:previously_approved?, command}, _from, state) do
    approved = MapSet.member?(state.commands, command)
    {:reply, approved, state}
  end

  @impl true
  def handle_call({:pattern_approved?, command}, _from, state) do
    # Check if any approved command starts with the same base command
    base_command = extract_base_command(command)

    approved =
      Enum.any?(state.commands, fn approved_cmd ->
        extract_base_command(approved_cmd) == base_command
      end)

    {:reply, approved, state}
  end

  @impl true
  def handle_call(:list_approvals, _from, state) do
    {:reply, Enum.reverse(state.approvals), state}
  end

  @impl true
  def handle_call({:list_approvals_by_provider, provider}, _from, state) do
    approvals =
      state.approvals
      |> Enum.filter(&(&1.provider == provider))
      |> Enum.reverse()

    {:reply, approvals, state}
  end

  @impl true
  def handle_call(:count, _from, state) do
    {:reply, length(state.approvals), state}
  end

  @impl true
  def handle_call(:clear, _from, _state) do
    Logger.info("Approval history cleared")
    {:reply, :ok, %{approvals: [], commands: MapSet.new()}}
  end

  # Private Functions

  defp extract_base_command(command) do
    command
    |> String.split(" ")
    |> List.first()
    |> to_string()
  end
end
