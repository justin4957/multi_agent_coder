defmodule MultiAgentCoder.Tools.ApprovalHistoryTest do
  use ExUnit.Case, async: false

  alias MultiAgentCoder.Tools.ApprovalHistory

  setup do
    # Clear history to ensure clean state
    # ApprovalHistory is already started by the application
    ApprovalHistory.clear()
    :ok
  end

  describe "add_approval/4" do
    test "adds an approval to history" do
      ApprovalHistory.add_approval("mix test", :openai, :safe, :auto)

      # Give the cast time to process
      :timer.sleep(10)

      approvals = ApprovalHistory.list_approvals()
      assert length(approvals) == 1

      [approval] = approvals
      assert approval.command == "mix test"
      assert approval.provider == :openai
      assert approval.danger_level == :safe
      assert approval.approved_by == :auto
      assert %DateTime{} = approval.timestamp
    end

    test "adds multiple approvals" do
      ApprovalHistory.add_approval("mix test", :openai, :safe, :auto)
      ApprovalHistory.add_approval("mix deps.get", :anthropic, :warning, :user)
      ApprovalHistory.add_approval("git commit", :deepseek, :warning, :user)

      :timer.sleep(10)

      approvals = ApprovalHistory.list_approvals()
      assert length(approvals) == 3
    end

    test "records approval source (user or auto)" do
      ApprovalHistory.add_approval("mix test", :openai, :safe, :auto)
      ApprovalHistory.add_approval("mix deps.get", :anthropic, :warning, :user)

      :timer.sleep(10)

      approvals = ApprovalHistory.list_approvals()
      auto_approval = Enum.find(approvals, &(&1.command == "mix test"))
      user_approval = Enum.find(approvals, &(&1.command == "mix deps.get"))

      assert auto_approval.approved_by == :auto
      assert user_approval.approved_by == :user
    end
  end

  describe "previously_approved?/1" do
    test "returns true for previously approved command" do
      ApprovalHistory.add_approval("mix test", :openai, :safe, :auto)
      :timer.sleep(10)

      assert ApprovalHistory.previously_approved?("mix test") == true
    end

    test "returns false for non-approved command" do
      assert ApprovalHistory.previously_approved?("mix test") == false
    end

    test "returns true for exact command match only" do
      ApprovalHistory.add_approval("mix test", :openai, :safe, :auto)
      :timer.sleep(10)

      assert ApprovalHistory.previously_approved?("mix test") == true
      assert ApprovalHistory.previously_approved?("mix test --failed") == false
    end
  end

  describe "pattern_approved?/1" do
    test "returns true for same base command" do
      ApprovalHistory.add_approval("mix test", :openai, :safe, :auto)
      :timer.sleep(10)

      assert ApprovalHistory.pattern_approved?("mix") == true
    end

    test "returns false when base command not approved" do
      ApprovalHistory.add_approval("git status", :openai, :safe, :auto)
      :timer.sleep(10)

      assert ApprovalHistory.pattern_approved?("mix") == false
    end

    test "matches on first word of command" do
      ApprovalHistory.add_approval("git status", :openai, :safe, :auto)
      :timer.sleep(10)

      assert ApprovalHistory.pattern_approved?("git diff") == true
      assert ApprovalHistory.pattern_approved?("git log") == true
    end
  end

  describe "list_approvals/0" do
    test "returns empty list when no approvals" do
      assert ApprovalHistory.list_approvals() == []
    end

    test "returns all approvals in chronological order" do
      ApprovalHistory.add_approval("command1", :openai, :safe, :auto)
      ApprovalHistory.add_approval("command2", :anthropic, :warning, :user)
      ApprovalHistory.add_approval("command3", :deepseek, :dangerous, :user)

      :timer.sleep(10)

      approvals = ApprovalHistory.list_approvals()
      assert length(approvals) == 3

      # Should be in chronological order (first added comes first)
      assert Enum.at(approvals, 0).command == "command1"
      assert Enum.at(approvals, 1).command == "command2"
      assert Enum.at(approvals, 2).command == "command3"
    end

    test "includes all approval metadata" do
      ApprovalHistory.add_approval("mix test", :openai, :safe, :auto)
      :timer.sleep(10)

      [approval] = ApprovalHistory.list_approvals()

      assert Map.has_key?(approval, :command)
      assert Map.has_key?(approval, :provider)
      assert Map.has_key?(approval, :danger_level)
      assert Map.has_key?(approval, :timestamp)
      assert Map.has_key?(approval, :approved_by)
    end
  end

  describe "list_approvals/1 with provider filter" do
    test "returns approvals for specific provider" do
      ApprovalHistory.add_approval("command1", :openai, :safe, :auto)
      ApprovalHistory.add_approval("command2", :anthropic, :warning, :user)
      ApprovalHistory.add_approval("command3", :openai, :warning, :user)

      :timer.sleep(10)

      openai_approvals = ApprovalHistory.list_approvals(:openai)
      assert length(openai_approvals) == 2
      assert Enum.all?(openai_approvals, &(&1.provider == :openai))

      anthropic_approvals = ApprovalHistory.list_approvals(:anthropic)
      assert length(anthropic_approvals) == 1
      assert Enum.all?(anthropic_approvals, &(&1.provider == :anthropic))
    end

    test "returns empty list for provider with no approvals" do
      ApprovalHistory.add_approval("command1", :openai, :safe, :auto)
      :timer.sleep(10)

      assert ApprovalHistory.list_approvals(:deepseek) == []
    end
  end

  describe "count/0" do
    test "returns 0 when no approvals" do
      assert ApprovalHistory.count() == 0
    end

    test "returns correct count of approvals" do
      ApprovalHistory.add_approval("command1", :openai, :safe, :auto)
      ApprovalHistory.add_approval("command2", :anthropic, :warning, :user)
      ApprovalHistory.add_approval("command3", :deepseek, :dangerous, :user)

      :timer.sleep(10)

      assert ApprovalHistory.count() == 3
    end

    test "increments count as approvals are added" do
      assert ApprovalHistory.count() == 0

      ApprovalHistory.add_approval("command1", :openai, :safe, :auto)
      :timer.sleep(10)
      assert ApprovalHistory.count() == 1

      ApprovalHistory.add_approval("command2", :anthropic, :warning, :user)
      :timer.sleep(10)
      assert ApprovalHistory.count() == 2
    end
  end

  describe "clear/0" do
    test "clears all approvals" do
      ApprovalHistory.add_approval("command1", :openai, :safe, :auto)
      ApprovalHistory.add_approval("command2", :anthropic, :warning, :user)

      :timer.sleep(10)
      assert ApprovalHistory.count() == 2

      ApprovalHistory.clear()
      assert ApprovalHistory.count() == 0
      assert ApprovalHistory.list_approvals() == []
    end

    test "allows adding approvals after clear" do
      ApprovalHistory.add_approval("command1", :openai, :safe, :auto)
      :timer.sleep(10)

      ApprovalHistory.clear()

      ApprovalHistory.add_approval("command2", :anthropic, :warning, :user)
      :timer.sleep(10)

      assert ApprovalHistory.count() == 1
      [approval] = ApprovalHistory.list_approvals()
      assert approval.command == "command2"
    end
  end

  describe "session tracking" do
    test "tracks approvals across providers" do
      ApprovalHistory.add_approval("mix test", :openai, :safe, :auto)
      ApprovalHistory.add_approval("mix test", :anthropic, :safe, :auto)
      ApprovalHistory.add_approval("git status", :deepseek, :safe, :auto)

      :timer.sleep(10)

      assert ApprovalHistory.count() == 3

      openai_approvals = ApprovalHistory.list_approvals(:openai)
      anthropic_approvals = ApprovalHistory.list_approvals(:anthropic)
      deepseek_approvals = ApprovalHistory.list_approvals(:deepseek)

      assert length(openai_approvals) == 1
      assert length(anthropic_approvals) == 1
      assert length(deepseek_approvals) == 1
    end

    test "tracks multiple danger levels" do
      ApprovalHistory.add_approval("mix test", :openai, :safe, :auto)
      ApprovalHistory.add_approval("mix deps.get", :openai, :warning, :user)
      ApprovalHistory.add_approval("rm -rf tmp", :openai, :dangerous, :user)

      :timer.sleep(10)

      approvals = ApprovalHistory.list_approvals()
      assert length(approvals) == 3

      levels = Enum.map(approvals, & &1.danger_level)
      assert :safe in levels
      assert :warning in levels
      assert :dangerous in levels
    end
  end
end
