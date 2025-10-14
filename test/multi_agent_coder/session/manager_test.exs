defmodule MultiAgentCoder.Session.ManagerTest do
  use ExUnit.Case, async: false

  alias MultiAgentCoder.Session.Manager

  setup do
    # Manager is already started by the application
    # Just generate a unique session ID for each test
    session_id = "test_session_#{:erlang.unique_integer([:positive])}"
    %{test_session_id: session_id}
  end

  describe "session creation" do
    test "creates a new session with generated ID" do
      {:ok, session_id} = Manager.new_session()

      assert is_binary(session_id)
      assert String.length(session_id) == 16
    end

    test "creates a session with custom ID" do
      custom_id = "custom_session_123"
      {:ok, session_id} = Manager.new_session(custom_id)

      assert session_id == custom_id
    end

    test "session starts with empty history" do
      {:ok, session_id} = Manager.new_session()
      {:ok, history} = Manager.get_history(session_id)

      assert history == []
    end
  end

  describe "message management" do
    setup do
      {:ok, session_id} = Manager.new_session()
      %{session_id: session_id}
    end

    test "adds user message to session", %{session_id: session_id} do
      :ok = Manager.add_message(session_id, :user, "Hello, agent!")
      {:ok, history} = Manager.get_history(session_id)

      assert length(history) == 1
      assert hd(history).role == :user
      assert hd(history).content == "Hello, agent!"
    end

    test "adds assistant message to session", %{session_id: session_id} do
      :ok = Manager.add_message(session_id, :assistant, "Hello, human!")
      {:ok, history} = Manager.get_history(session_id)

      assert length(history) == 1
      assert hd(history).role == :assistant
      assert hd(history).content == "Hello, human!"
    end

    test "maintains message order", %{session_id: session_id} do
      Manager.add_message(session_id, :user, "First message")
      Manager.add_message(session_id, :assistant, "Second message")
      Manager.add_message(session_id, :user, "Third message")

      {:ok, history} = Manager.get_history(session_id)

      assert length(history) == 3
      assert Enum.at(history, 0).content == "First message"
      assert Enum.at(history, 1).content == "Second message"
      assert Enum.at(history, 2).content == "Third message"
    end

    test "includes timestamps on messages", %{session_id: session_id} do
      Manager.add_message(session_id, :user, "Message with timestamp")
      {:ok, history} = Manager.get_history(session_id)

      message = hd(history)
      assert %DateTime{} = message.timestamp
    end

    test "returns error for non-existent session" do
      result = Manager.add_message("non_existent", :user, "Hello")
      assert result == {:error, :session_not_found}
    end
  end

  describe "history retrieval" do
    setup do
      {:ok, session_id} = Manager.new_session()
      Manager.add_message(session_id, :user, "Message 1")
      Manager.add_message(session_id, :assistant, "Response 1")
      %{session_id: session_id}
    end

    test "retrieves full conversation history", %{session_id: session_id} do
      {:ok, history} = Manager.get_history(session_id)

      assert length(history) == 2
      assert Enum.at(history, 0).role == :user
      assert Enum.at(history, 1).role == :assistant
    end

    test "returns error for non-existent session" do
      result = Manager.get_history("non_existent")
      assert result == {:error, :session_not_found}
    end
  end

  describe "session clearing" do
    setup do
      {:ok, session_id} = Manager.new_session()
      Manager.add_message(session_id, :user, "Message 1")
      Manager.add_message(session_id, :assistant, "Response 1")
      %{session_id: session_id}
    end

    test "clears session history", %{session_id: session_id} do
      :ok = Manager.clear_session(session_id)
      {:ok, history} = Manager.get_history(session_id)

      assert history == []
    end

    test "preserves session after clearing", %{session_id: session_id} do
      Manager.clear_session(session_id)

      # Should be able to add new messages
      :ok = Manager.add_message(session_id, :user, "New message")
      {:ok, history} = Manager.get_history(session_id)

      assert length(history) == 1
    end

    test "returns error for non-existent session" do
      result = Manager.clear_session("non_existent")
      assert result == {:error, :session_not_found}
    end
  end

  describe "multiple sessions" do
    test "manages multiple sessions independently" do
      {:ok, session1} = Manager.new_session()
      {:ok, session2} = Manager.new_session()

      Manager.add_message(session1, :user, "Session 1 message")
      Manager.add_message(session2, :user, "Session 2 message")

      {:ok, history1} = Manager.get_history(session1)
      {:ok, history2} = Manager.get_history(session2)

      assert hd(history1).content == "Session 1 message"
      assert hd(history2).content == "Session 2 message"
    end
  end
end
