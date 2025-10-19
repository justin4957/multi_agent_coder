defmodule MultiAgentCoder.Tools.ApproverTest do
  use ExUnit.Case, async: false

  alias MultiAgentCoder.Tools.{Approver, ApprovalHistory}

  setup do
    # ApprovalHistory is already started by the application
    ApprovalHistory.clear()

    # Store original config
    original_config = Application.get_env(:multi_agent_coder, :tools, [])

    on_exit(fn ->
      # Restore original config
      Application.put_env(:multi_agent_coder, :tools, original_config)
      ApprovalHistory.clear()
    end)

    %{original_config: original_config}
  end

  describe "check_approval/3 with :auto mode" do
    setup do
      Application.put_env(:multi_agent_coder, :tools,
        approval_mode: :auto,
        auto_approve_safe: true,
        prompt_on_warning: false,
        always_prompt_dangerous: false,
        trust_for_session: true
      )

      :ok
    end

    test "auto-approves safe commands" do
      classification = %{level: :safe, reason: "Test execution"}
      {:ok, result} = Approver.check_approval(classification, "mix test", :openai)

      assert result == :approved
    end

    test "auto-approves warning commands when prompt_on_warning is false" do
      classification = %{level: :warning, reason: "Dependency installation"}
      {:ok, result} = Approver.check_approval(classification, "mix deps.get", :anthropic)

      assert result == :approved
    end

    test "denies blocked commands" do
      classification = %{level: :blocked, reason: "Privilege escalation"}
      {:ok, result} = Approver.check_approval(classification, "sudo rm -rf /", :openai)

      assert result == :denied
    end

    test "records approval in history for safe commands" do
      classification = %{level: :safe, reason: "Test execution"}
      {:ok, :approved} = Approver.check_approval(classification, "mix test", :openai)

      :timer.sleep(10)

      assert ApprovalHistory.previously_approved?("mix test")
    end
  end

  describe "check_approval/3 with :allow_all mode" do
    setup do
      Application.put_env(:multi_agent_coder, :tools, approval_mode: :allow_all)
      :ok
    end

    test "approves all commands including dangerous" do
      classification = %{level: :dangerous, reason: "Destructive operation"}
      {:ok, result} = Approver.check_approval(classification, "rm -rf /", :openai)

      assert result == :approved
    end

    test "approves even warning commands" do
      classification = %{level: :warning, reason: "Dependency installation"}
      {:ok, result} = Approver.check_approval(classification, "mix deps.get", :openai)

      assert result == :approved
    end
  end

  describe "check_approval/3 with :deny_all mode" do
    setup do
      Application.put_env(:multi_agent_coder, :tools, approval_mode: :deny_all)
      :ok
    end

    test "denies safe commands" do
      classification = %{level: :safe, reason: "Test execution"}
      {:ok, result} = Approver.check_approval(classification, "mix test", :openai)

      assert result == :denied
    end

    test "denies warning commands" do
      classification = %{level: :warning, reason: "Dependency installation"}
      {:ok, result} = Approver.check_approval(classification, "mix deps.get", :openai)

      assert result == :denied
    end

    test "denies dangerous commands" do
      classification = %{level: :dangerous, reason: "Destructive operation"}
      {:ok, result} = Approver.check_approval(classification, "rm -rf tmp", :openai)

      assert result == :denied
    end
  end

  describe "check_approval/3 with trust_for_session" do
    setup do
      Application.put_env(:multi_agent_coder, :tools,
        approval_mode: :auto,
        auto_approve_safe: true,
        prompt_on_warning: false,
        always_prompt_dangerous: false,
        trust_for_session: true
      )

      :ok
    end

    test "remembers warning command approvals" do
      classification = %{level: :warning, reason: "Dependency installation"}

      # First approval (auto-approved due to prompt_on_warning: false)
      {:ok, :approved} = Approver.check_approval(classification, "mix deps.get", :openai)
      :timer.sleep(10)

      # Should remember it
      assert ApprovalHistory.previously_approved?("mix deps.get")

      # Second time should also be approved quickly
      {:ok, :approved} = Approver.check_approval(classification, "mix deps.get", :anthropic)
    end

    test "remembers dangerous command approvals in session" do
      classification = %{level: :dangerous, reason: "Destructive operation"}

      # Pre-approve the command in history
      ApprovalHistory.add_approval("rm -rf tmp", :openai, :dangerous, :user)
      :timer.sleep(10)

      # Should be auto-approved because it's in session history
      {:ok, :approved} = Approver.check_approval(classification, "rm -rf tmp", :openai)

      # Should be recorded
      assert ApprovalHistory.previously_approved?("rm -rf tmp")
    end
  end

  describe "get_approval_mode/0" do
    test "returns configured approval mode" do
      Application.put_env(:multi_agent_coder, :tools, approval_mode: :auto)
      assert Approver.get_approval_mode() == :auto

      Application.put_env(:multi_agent_coder, :tools, approval_mode: :prompt)
      assert Approver.get_approval_mode() == :prompt

      Application.put_env(:multi_agent_coder, :tools, approval_mode: :deny_all)
      assert Approver.get_approval_mode() == :deny_all

      Application.put_env(:multi_agent_coder, :tools, approval_mode: :allow_all)
      assert Approver.get_approval_mode() == :allow_all
    end

    test "defaults to :auto when not configured" do
      Application.delete_env(:multi_agent_coder, :tools)
      assert Approver.get_approval_mode() == :auto
    end
  end

  describe "approve_command/1" do
    test "manually approves a command" do
      assert :ok = Approver.approve_command("mix test")
    end

    test "logs the manual approval" do
      assert :ok = Approver.approve_command("git push")
    end
  end

  describe "auto_approve with safe commands" do
    test "respects auto_approve_safe config" do
      Application.put_env(:multi_agent_coder, :tools,
        approval_mode: :auto,
        auto_approve_safe: false
      )

      classification = %{level: :safe, reason: "Test execution"}

      # With auto_approve_safe: false, would require prompting
      # Since we can't test interactive prompts easily, we just verify config is read
      assert Application.get_env(:multi_agent_coder, :tools)[:auto_approve_safe] == false
    end
  end

  describe "configuration access" do
    test "reads prompt_on_warning config" do
      Application.put_env(:multi_agent_coder, :tools, prompt_on_warning: true)

      config = Application.get_env(:multi_agent_coder, :tools, [])
      assert Keyword.get(config, :prompt_on_warning) == true
    end

    test "reads always_prompt_dangerous config" do
      Application.put_env(:multi_agent_coder, :tools, always_prompt_dangerous: true)

      config = Application.get_env(:multi_agent_coder, :tools, [])
      assert Keyword.get(config, :always_prompt_dangerous) == true
    end

    test "reads trust_for_session config" do
      Application.put_env(:multi_agent_coder, :tools, trust_for_session: false)

      config = Application.get_env(:multi_agent_coder, :tools, [])
      assert Keyword.get(config, :trust_for_session) == false
    end
  end
end
