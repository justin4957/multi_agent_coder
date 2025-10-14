defmodule MultiAgentCoder.Session.StorageTest do
  use ExUnit.Case, async: false

  alias MultiAgentCoder.Session.Storage

  setup do
    # Start the storage if not already started
    case GenServer.whereis(Storage) do
      nil -> {:ok, _} = start_supervised(Storage)
      _pid -> :ok
    end

    :ok
  end

  describe "session management" do
    test "creates a session with metadata" do
      {:ok, session_id} = Storage.create_session(%{
        tags: ["test", "feature"],
        description: "Test session"
      })

      assert is_binary(session_id)
      assert String.starts_with?(session_id, "session_")
    end

    test "retrieves a session by ID" do
      {:ok, session_id} = Storage.create_session(%{tags: ["test"]})
      {:ok, session} = Storage.get_session(session_id)

      assert session.id == session_id
      assert session.messages == []
      assert session.total_tokens == 0
    end

    test "lists all sessions" do
      {:ok, _id1} = Storage.create_session(%{tags: ["test1"]})
      {:ok, _id2} = Storage.create_session(%{tags: ["test2"]})

      {:ok, sessions} = Storage.list_sessions()

      assert length(sessions) >= 2
    end

    test "finds sessions by tag" do
      {:ok, id1} = Storage.create_session(%{tags: ["feature", "important"]})
      {:ok, _id2} = Storage.create_session(%{tags: ["bugfix"]})

      {:ok, sessions} = Storage.find_sessions_by_tag("feature")

      assert length(sessions) >= 1
      assert Enum.any?(sessions, fn s -> s.id == id1 end)
    end

    test "deletes a session" do
      {:ok, session_id} = Storage.create_session(%{tags: ["test"]})

      assert :ok = Storage.delete_session(session_id)
      assert {:error, _} = Storage.get_session(session_id)
    end
  end

  describe "message management" do
    test "adds a message to a session" do
      {:ok, session_id} = Storage.create_session(%{})

      {:ok, message_id} = Storage.add_message(session_id, %{
        role: :user,
        content: "Test message",
        provider: :openai,
        tokens: 10
      })

      assert is_binary(message_id)

      {:ok, session} = Storage.get_session(session_id)
      assert length(session.messages) == 1
      assert session.total_tokens == 10
    end

    test "tracks multiple providers used" do
      {:ok, session_id} = Storage.create_session(%{})

      Storage.add_message(session_id, %{
        role: :user,
        content: "Test",
        provider: :openai,
        tokens: 5
      })

      Storage.add_message(session_id, %{
        role: :assistant,
        content: "Response",
        provider: :anthropic,
        tokens: 8
      })

      {:ok, session} = Storage.get_session(session_id)
      assert :openai in session.providers_used
      assert :anthropic in session.providers_used
      assert session.total_tokens == 13
    end
  end

  describe "session forking" do
    test "forks a session" do
      {:ok, parent_id} = Storage.create_session(%{tags: ["parent"]})

      Storage.add_message(parent_id, %{
        role: :user,
        content: "Message 1",
        provider: :openai,
        tokens: 5
      })

      Storage.add_message(parent_id, %{
        role: :assistant,
        content: "Response 1",
        provider: :openai,
        tokens: 10
      })

      {:ok, fork_id} = Storage.fork_session(parent_id,
        at_message: 1,
        metadata: %{fork_reason: "exploring alternative"}
      )

      {:ok, fork} = Storage.get_session(fork_id)

      assert fork.parent_id == parent_id
      assert fork.fork_point == 1
      assert length(fork.messages) == 1
    end

    test "tracks fork relationships" do
      {:ok, parent_id} = Storage.create_session(%{})
      {:ok, fork1_id} = Storage.fork_session(parent_id)
      {:ok, fork2_id} = Storage.fork_session(parent_id)

      {:ok, forks} = Storage.get_session_forks(parent_id)

      assert length(forks) == 2
      assert fork1_id in forks
      assert fork2_id in forks
    end

    test "gets parent of a fork" do
      {:ok, parent_id} = Storage.create_session(%{})
      {:ok, fork_id} = Storage.fork_session(parent_id)

      {:ok, parent} = Storage.get_session_parent(fork_id)

      assert parent == parent_id
    end
  end

  describe "persistence" do
    test "saves and loads session from disk" do
      {:ok, session_id} = Storage.create_session(%{tags: ["persistent"]})

      Storage.add_message(session_id, %{
        role: :user,
        content: "Persistent message",
        provider: :openai,
        tokens: 7
      })

      {:ok, file_path} = Storage.save_session_to_disk(session_id)
      assert File.exists?(file_path)

      # Remove from ETS directly (without deleting file)
      :ets.delete(:mac_sessions, session_id)

      # Load back from disk
      {:ok, loaded_session} = Storage.load_session_from_disk(session_id)

      assert loaded_session.id == session_id
      assert length(loaded_session.messages) == 1
      assert loaded_session.total_tokens == 7

      # Cleanup
      Storage.delete_session(session_id)
    end

    test "exports and imports sessions" do
      {:ok, session_id} = Storage.create_session(%{tags: ["export-test"]})

      Storage.add_message(session_id, %{
        role: :user,
        content: "Export this",
        provider: :anthropic,
        tokens: 5
      })

      export_path = "/tmp/test_export_#{System.unique_integer([:positive])}.json"
      {:ok, ^export_path} = Storage.export_session(session_id, export_path)

      assert File.exists?(export_path)

      # Import creates new session with new ID
      {:ok, new_id} = Storage.import_session(export_path)

      assert new_id != session_id

      {:ok, imported} = Storage.get_session(new_id)
      assert length(imported.messages) == 1

      # Cleanup
      File.rm(export_path)
    end
  end

  describe "statistics" do
    test "returns storage statistics" do
      {:ok, _} = Storage.create_session(%{})
      {:ok, _} = Storage.create_session(%{})

      stats = Storage.get_stats()

      assert stats.total_sessions >= 2
      assert is_integer(stats.memory_usage.sessions)
      assert is_integer(stats.memory_usage.indexes)
    end
  end
end
