defmodule MultiAgentCoder.Session.Manager do
  @moduledoc """
  Manages conversation sessions and context.

  Maintains history of prompts and responses, allowing for
  multi-turn conversations with context awareness.
  """

  use GenServer
  require Logger

  defstruct sessions: %{}

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Creates a new session.
  """
  def new_session(session_id \\ generate_id()) do
    GenServer.call(__MODULE__, {:new_session, session_id})
  end

  @doc """
  Adds a message to a session's history.
  """
  def add_message(session_id, role, content) do
    GenServer.call(__MODULE__, {:add_message, session_id, role, content})
  end

  @doc """
  Gets the full history for a session.
  """
  def get_history(session_id) do
    GenServer.call(__MODULE__, {:get_history, session_id})
  end

  @doc """
  Clears a session's history.
  """
  def clear_session(session_id) do
    GenServer.call(__MODULE__, {:clear_session, session_id})
  end

  @impl true
  def init(_opts) do
    {:ok, %__MODULE__{}}
  end

  @impl true
  def handle_call({:new_session, session_id}, _from, state) do
    new_session = %{
      id: session_id,
      created_at: DateTime.utc_now(),
      history: []
    }

    new_state = put_in(state.sessions[session_id], new_session)
    {:reply, {:ok, session_id}, new_state}
  end

  @impl true
  def handle_call({:add_message, session_id, role, content}, _from, state) do
    case Map.get(state.sessions, session_id) do
      nil ->
        {:reply, {:error, :session_not_found}, state}

      session ->
        message = %{
          role: role,
          content: content,
          timestamp: DateTime.utc_now()
        }

        updated_session = Map.update!(session, :history, &(&1 ++ [message]))
        new_state = put_in(state.sessions[session_id], updated_session)
        {:reply, :ok, new_state}
    end
  end

  @impl true
  def handle_call({:get_history, session_id}, _from, state) do
    case Map.get(state.sessions, session_id) do
      nil -> {:reply, {:error, :session_not_found}, state}
      session -> {:reply, {:ok, session.history}, state}
    end
  end

  @impl true
  def handle_call({:clear_session, session_id}, _from, state) do
    case Map.get(state.sessions, session_id) do
      nil ->
        {:reply, {:error, :session_not_found}, state}

      session ->
        cleared_session = Map.put(session, :history, [])
        new_state = put_in(state.sessions[session_id], cleared_session)
        {:reply, :ok, new_state}
    end
  end

  defp generate_id do
    :crypto.strong_rand_bytes(16)
    |> Base.url_encode64()
    |> binary_part(0, 16)
  end
end
