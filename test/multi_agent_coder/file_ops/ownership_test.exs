defmodule MultiAgentCoder.FileOps.OwnershipTest do
  use ExUnit.Case, async: false

  alias MultiAgentCoder.FileOps.Ownership

  setup do
    {:ok, _pid} = start_supervised(Ownership)
    Ownership.reset()
    :ok
  end

  describe "assign_owner/2" do
    test "assigns owner to a file" do
      assert Ownership.assign_owner("lib/user.ex", :openai) == :ok
      assert Ownership.get_owner("lib/user.ex") == :openai
    end

    test "prevents reassigning ownership" do
      Ownership.assign_owner("lib/user.ex", :openai)
      assert Ownership.assign_owner("lib/user.ex", :anthropic) == {:error, :already_owned}
    end

    test "allows different files to have different owners" do
      Ownership.assign_owner("lib/user.ex", :openai)
      Ownership.assign_owner("lib/auth.ex", :anthropic)

      assert Ownership.get_owner("lib/user.ex") == :openai
      assert Ownership.get_owner("lib/auth.ex") == :anthropic
    end
  end

  describe "get_owner/1" do
    test "returns nil for unowned file" do
      assert Ownership.get_owner("lib/unknown.ex") == nil
    end
  end

  describe "add_contributor/2 and get_contributors/1" do
    test "adds contributor to a file" do
      Ownership.assign_owner("lib/user.ex", :openai)
      Ownership.add_contributor("lib/user.ex", :anthropic)

      contributors = Ownership.get_contributors("lib/user.ex")
      assert :anthropic in contributors
    end

    test "does not add owner as contributor" do
      Ownership.assign_owner("lib/user.ex", :openai)
      Ownership.add_contributor("lib/user.ex", :openai)

      contributors = Ownership.get_contributors("lib/user.ex")
      assert :openai not in contributors
    end

    test "tracks multiple contributors" do
      Ownership.assign_owner("lib/user.ex", :openai)
      Ownership.add_contributor("lib/user.ex", :anthropic)
      Ownership.add_contributor("lib/user.ex", :deepseek)

      contributors = Ownership.get_contributors("lib/user.ex")
      assert length(contributors) == 2
    end
  end

  describe "lock_file/2 and unlock_file/2" do
    test "locks a file" do
      assert Ownership.lock_file("lib/user.ex", :openai) == :ok
      assert Ownership.is_locked?("lib/user.ex") == true
    end

    test "prevents locking already locked file" do
      Ownership.lock_file("lib/user.ex", :openai)
      assert Ownership.lock_file("lib/user.ex", :anthropic) == {:error, :locked}
    end

    test "unlocks a file" do
      Ownership.lock_file("lib/user.ex", :openai)
      assert Ownership.unlock_file("lib/user.ex", :openai) == :ok
      assert Ownership.is_locked?("lib/user.ex") == false
    end

    test "prevents unlocking by wrong provider" do
      Ownership.lock_file("lib/user.ex", :openai)
      assert Ownership.unlock_file("lib/user.ex", :anthropic) == {:error, :wrong_owner}
    end

    test "returns error when unlocking non-locked file" do
      assert Ownership.unlock_file("lib/user.ex", :openai) == {:error, :not_locked}
    end
  end

  describe "get_lock_holder/1" do
    test "returns lock holder" do
      Ownership.lock_file("lib/user.ex", :openai)
      assert Ownership.get_lock_holder("lib/user.ex") == :openai
    end

    test "returns nil for non-locked file" do
      assert Ownership.get_lock_holder("lib/user.ex") == nil
    end
  end

  describe "get_locked_files/0" do
    test "returns all locked files" do
      Ownership.lock_file("lib/user.ex", :openai)
      Ownership.lock_file("lib/auth.ex", :anthropic)

      locked = Ownership.get_locked_files()
      assert length(locked) == 2
    end
  end

  describe "get_owned_files/1" do
    test "returns files owned by provider" do
      Ownership.assign_owner("lib/user.ex", :openai)
      Ownership.assign_owner("lib/auth.ex", :openai)
      Ownership.assign_owner("lib/schema.ex", :anthropic)

      owned = Ownership.get_owned_files(:openai)
      assert length(owned) == 2
      assert "lib/user.ex" in owned
      assert "lib/auth.ex" in owned
    end
  end

  describe "transfer_ownership/2" do
    test "transfers ownership to another provider" do
      Ownership.assign_owner("lib/user.ex", :openai)
      assert Ownership.transfer_ownership("lib/user.ex", :anthropic) == :ok
      assert Ownership.get_owner("lib/user.ex") == :anthropic
    end

    test "adds old owner as contributor" do
      Ownership.assign_owner("lib/user.ex", :openai)
      Ownership.transfer_ownership("lib/user.ex", :anthropic)

      contributors = Ownership.get_contributors("lib/user.ex")
      assert :openai in contributors
    end

    test "returns error for non-existent file" do
      assert Ownership.transfer_ownership("lib/unknown.ex", :openai) == {:error, :not_found}
    end
  end
end
