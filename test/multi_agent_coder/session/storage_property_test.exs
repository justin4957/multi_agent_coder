defmodule MultiAgentCoder.Session.StoragePropertyTest do
  use ExUnit.Case, async: false
  use ExUnitProperties

  alias MultiAgentCoder.Session.Storage

  setup do
    # Start the storage if not already started (same approach as storage_test.exs)
    case GenServer.whereis(Storage) do
      nil -> {:ok, _} = start_supervised(Storage)
      _pid -> :ok
    end

    :ok
  end

  describe "Session creation properties" do
    property "creates sessions with unique IDs" do
      check all(
              metadata <-
                fixed_map(%{
                  tags:
                    list_of(string(:alphanumeric, min_length: 1, max_length: 10), max_length: 3)
                }),
              max_runs: 20
            ) do
        {:ok, id1} = Storage.create_session(metadata)
        {:ok, id2} = Storage.create_session(metadata)

        assert id1 != id2
        assert is_binary(id1)
        assert is_binary(id2)
      end
    end

    property "created sessions can be retrieved" do
      check all(
              tags <-
                list_of(string(:alphanumeric, min_length: 1, max_length: 10), max_length: 3),
              max_runs: 20
            ) do
        metadata = %{tags: tags}
        {:ok, session_id} = Storage.create_session(metadata)

        {:ok, session} = Storage.get_session(session_id)
        assert session.id == session_id
        assert session.metadata.tags == tags
      end
    end

    property "new sessions start with empty messages" do
      check all(
              metadata <- fixed_map(%{}),
              max_runs: 20
            ) do
        {:ok, session_id} = Storage.create_session(metadata)
        {:ok, session} = Storage.get_session(session_id)

        assert Enum.empty?(session.messages)
      end
    end

    property "new sessions have zero token count" do
      check all(
              metadata <- fixed_map(%{}),
              max_runs: 20
            ) do
        {:ok, session_id} = Storage.create_session(metadata)
        {:ok, session} = Storage.get_session(session_id)

        assert session.total_tokens == 0
        assert session.estimated_cost == 0.0
      end
    end
  end

  describe "Message addition properties" do
    property "adding messages increases message count" do
      check all(
              role <- member_of(["user", "assistant"]),
              content <- string(:ascii, min_length: 1, max_length: 200),
              provider <- member_of([:openai, :anthropic, :deepseek]),
              max_runs: 20
            ) do
        {:ok, session_id} = Storage.create_session(%{})
        {:ok, session_before} = Storage.get_session(session_id)

        message_params = %{
          role: role,
          content: content,
          provider: provider,
          tokens: 10
        }

        {:ok, _message_id} = Storage.add_message(session_id, message_params)
        {:ok, session_after} = Storage.get_session(session_id)

        assert length(session_after.messages) == length(session_before.messages) + 1
      end
    end

    property "adding messages accumulates tokens" do
      check all(
              messages <-
                list_of(
                  tuple({
                    member_of(["user", "assistant"]),
                    string(:ascii, min_length: 1, max_length: 100),
                    integer(1..100)
                  }),
                  min_length: 1,
                  max_length: 5
                ),
              max_runs: 20
            ) do
        {:ok, session_id} = Storage.create_session(%{})

        total_tokens =
          Enum.reduce(messages, 0, fn {role, content, tokens}, acc ->
            Storage.add_message(session_id, %{
              role: role,
              content: content,
              provider: :openai,
              tokens: tokens
            })

            acc + tokens
          end)

        {:ok, session} = Storage.get_session(session_id)
        assert session.total_tokens == total_tokens
      end
    end

    property "messages preserve content and metadata" do
      check all(
              role <- member_of(["user", "assistant"]),
              content <- string(:ascii, min_length: 1, max_length: 200),
              provider <- member_of([:openai, :anthropic, :deepseek]),
              tokens <- integer(1..1000),
              max_runs: 20
            ) do
        {:ok, session_id} = Storage.create_session(%{})

        message_params = %{
          role: role,
          content: content,
          provider: provider,
          tokens: tokens,
          metadata: %{test: "data"}
        }

        {:ok, message_id} = Storage.add_message(session_id, message_params)
        {:ok, session} = Storage.get_session(session_id)

        message = List.last(session.messages)
        assert message.id == message_id
        assert message.role == role
        assert message.content == content
        assert message.provider == provider
        assert message.tokens == tokens
        assert message.metadata == %{test: "data"}
      end
    end
  end

  describe "Session forking properties" do
    property "forked sessions have different IDs" do
      check all(
              content <- string(:ascii, min_length: 1, max_length: 100),
              max_runs: 20
            ) do
        {:ok, parent_id} = Storage.create_session(%{})
        Storage.add_message(parent_id, %{role: "user", content: content, provider: :openai})

        {:ok, fork_id} = Storage.fork_session(parent_id)

        assert parent_id != fork_id
      end
    end

    property "forked sessions copy messages" do
      check all(
              messages <-
                list_of(
                  tuple(
                    {member_of(["user", "assistant"]),
                     string(:ascii, min_length: 1, max_length: 50)}
                  ),
                  min_length: 1,
                  max_length: 3
                ),
              max_runs: 20
            ) do
        {:ok, parent_id} = Storage.create_session(%{})

        Enum.each(messages, fn {role, content} ->
          Storage.add_message(parent_id, %{role: role, content: content, provider: :openai})
        end)

        {:ok, parent} = Storage.get_session(parent_id)
        {:ok, fork_id} = Storage.fork_session(parent_id)
        {:ok, fork} = Storage.get_session(fork_id)

        assert length(fork.messages) == length(parent.messages)
        assert fork.parent_id == parent_id
      end
    end

    property "can retrieve parent from fork" do
      check all(
              content <- string(:ascii, min_length: 1, max_length: 100),
              max_runs: 20
            ) do
        {:ok, parent_id} = Storage.create_session(%{})
        Storage.add_message(parent_id, %{role: "user", content: content, provider: :openai})

        {:ok, fork_id} = Storage.fork_session(parent_id)
        {:ok, retrieved_parent_id} = Storage.get_session_parent(fork_id)

        assert retrieved_parent_id == parent_id
      end
    end

    property "can retrieve forks from parent" do
      check all(
              fork_count <- integer(1..5),
              max_runs: 20
            ) do
        {:ok, parent_id} = Storage.create_session(%{})

        fork_ids =
          Enum.map(1..fork_count, fn _ ->
            {:ok, fork_id} = Storage.fork_session(parent_id)
            fork_id
          end)

        {:ok, retrieved_forks} = Storage.get_session_forks(parent_id)

        assert length(retrieved_forks) == fork_count
        assert Enum.sort(retrieved_forks) == Enum.sort(fork_ids)
      end
    end
  end

  describe "Session listing and search properties" do
    property "listed sessions include all created sessions" do
      check all(
              session_count <- integer(1..5),
              max_runs: 20
            ) do
        created_ids =
          Enum.map(1..session_count, fn i ->
            {:ok, id} = Storage.create_session(%{index: i})
            id
          end)

        {:ok, sessions} = Storage.list_sessions()
        session_ids = Enum.map(sessions, & &1.id)

        Enum.each(created_ids, fn id ->
          assert id in session_ids
        end)
      end
    end

    property "sessions can be found by tags" do
      check all(
              tag <- string(:alphanumeric, min_length: 1, max_length: 10),
              max_runs: 20
            ) do
        {:ok, session_id} = Storage.create_session(%{tags: [tag]})
        {:ok, found_sessions} = Storage.find_sessions_by_tag(tag)

        found_ids = Enum.map(found_sessions, & &1.id)
        assert session_id in found_ids
      end
    end
  end

  describe "Session deletion properties" do
    property "deleted sessions cannot be retrieved" do
      check all(
              content <- string(:ascii, min_length: 1, max_length: 100),
              max_runs: 20
            ) do
        {:ok, session_id} = Storage.create_session(%{})
        Storage.add_message(session_id, %{role: "user", content: content, provider: :openai})

        {:ok, _session} = Storage.get_session(session_id)

        :ok = Storage.delete_session(session_id)

        assert {:error, _} = Storage.get_session(session_id)
      end
    end

    property "deleting with forks removes all" do
      check all(
              fork_count <- integer(1..3),
              max_runs: 20
            ) do
        {:ok, parent_id} = Storage.create_session(%{})

        fork_ids =
          Enum.map(1..fork_count, fn _ ->
            {:ok, fork_id} = Storage.fork_session(parent_id)
            fork_id
          end)

        Storage.delete_session(parent_id, delete_forks: true)

        # Parent and all forks should be gone
        assert {:error, _} = Storage.get_session(parent_id)

        Enum.each(fork_ids, fn fork_id ->
          assert {:error, _} = Storage.get_session(fork_id)
        end)
      end
    end
  end

  describe "Storage statistics properties" do
    property "stats reflect actual session count" do
      check all(
              session_count <- integer(0..10),
              max_runs: 20
            ) do
        # Note: Other tests may have created sessions, so we just check
        # that adding sessions increases the count
        stats_before = Storage.get_stats()

        Enum.each(1..session_count, fn _ ->
          Storage.create_session(%{})
        end)

        stats_after = Storage.get_stats()

        assert stats_after.total_sessions >= stats_before.total_sessions + session_count
      end
    end
  end
end
