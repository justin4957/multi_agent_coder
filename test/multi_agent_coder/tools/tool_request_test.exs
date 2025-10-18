defmodule MultiAgentCoder.Tools.ToolRequestTest do
  use ExUnit.Case, async: true

  alias MultiAgentCoder.Tools.ToolRequest

  describe "new/4" do
    test "creates a valid bash request" do
      {:ok, request} = ToolRequest.new(:bash, "echo hello", :openai)

      assert request.type == :bash
      assert request.command == "echo hello"
      assert request.provider_id == :openai
      assert request.args == []
      assert request.timeout == 30_000
      assert is_binary(request.id)
    end

    test "creates request with options" do
      {:ok, request} =
        ToolRequest.new(:bash, "ls", :anthropic,
          timeout: 5000,
          args: ["arg1", "arg2"],
          working_dir: "/tmp",
          env: %{"VAR" => "value"},
          metadata: %{key: "value"}
        )

      assert request.timeout == 5000
      assert request.args == ["arg1", "arg2"]
      assert request.working_dir == "/tmp"
      assert request.env == %{"VAR" => "value"}
      assert request.metadata == %{key: "value"}
    end

    test "validates tool type" do
      assert {:error, _} = ToolRequest.new(:invalid_type, "cmd", :openai)
    end

    test "validates command is non-empty string" do
      assert {:error, _} = ToolRequest.new(:bash, "", :openai)
      assert {:error, _} = ToolRequest.new(:bash, nil, :openai)
    end

    test "validates provider_id is atom" do
      assert {:error, _} = ToolRequest.new(:bash, "cmd", "not_atom")
    end

    test "generates unique IDs" do
      {:ok, req1} = ToolRequest.new(:bash, "cmd1", :openai)
      {:ok, req2} = ToolRequest.new(:bash, "cmd2", :openai)

      assert req1.id != req2.id
    end
  end

  describe "new!/4" do
    test "creates request or raises on error" do
      request = ToolRequest.new!(:bash, "echo test", :openai)

      assert request.command == "echo test"
    end

    test "raises on invalid input" do
      assert_raise ArgumentError, fn ->
        ToolRequest.new!(:invalid, "cmd", :openai)
      end
    end
  end

  describe "bash/3" do
    test "creates bash command request" do
      {:ok, request} = ToolRequest.bash("pwd", :deepseek)

      assert request.type == :bash
      assert request.command == "pwd"
      assert request.provider_id == :deepseek
    end

    test "accepts options" do
      {:ok, request} = ToolRequest.bash("ls", :openai, timeout: 1000)

      assert request.timeout == 1000
    end
  end

  describe "file_read/3" do
    test "creates file read request" do
      {:ok, request} = ToolRequest.file_read("/path/to/file", :anthropic)

      assert request.type == :file_read
      assert request.command == "/path/to/file"
      assert request.provider_id == :anthropic
    end
  end

  describe "file_write/4" do
    test "creates file write request with content" do
      {:ok, request} = ToolRequest.file_write("/path/to/file", "content", :openai)

      assert request.type == :file_write
      assert request.command == "/path/to/file"
      assert request.args == ["content"]
      assert request.provider_id == :openai
    end
  end

  describe "git/3" do
    test "creates git command request" do
      {:ok, request} = ToolRequest.git("status", :deepseek)

      assert request.type == :git
      assert request.command == "status"
      assert request.provider_id == :deepseek
    end

    test "accepts git command with args" do
      {:ok, request} = ToolRequest.git("commit -m 'message'", :anthropic)

      assert request.command == "commit -m 'message'"
    end
  end

  describe "supported tool types" do
    test "supports all documented types" do
      types = [:bash, :file_read, :file_write, :file_delete, :git]

      for type <- types do
        {:ok, request} = ToolRequest.new(type, "test_cmd", :openai)
        assert request.type == type
      end
    end
  end
end
