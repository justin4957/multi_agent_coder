defmodule MultiAgentCoder.CLI.CommandParserTest do
  use ExUnit.Case, async: true
  alias MultiAgentCoder.CLI.CommandParser

  describe "parse/1 - task control commands" do
    test "parses pause all command" do
      assert CommandParser.parse("pause all") == {:pause, :all}
      assert CommandParser.parse("p all") == {:pause, :all}
    end

    test "parses pause specific provider" do
      assert CommandParser.parse("pause anthropic") == {:pause, :anthropic}
      assert CommandParser.parse("p openai") == {:pause, :openai}
    end

    test "parses resume all command" do
      assert CommandParser.parse("resume all") == {:resume, :all}
      assert CommandParser.parse("r all") == {:resume, :all}
    end

    test "parses resume specific provider" do
      assert CommandParser.parse("resume anthropic") == {:resume, :anthropic}
      assert CommandParser.parse("r deepseek") == {:resume, :deepseek}
    end

    test "parses cancel command" do
      assert CommandParser.parse("cancel task-123") == {:cancel, "task-123"}
      assert CommandParser.parse("c task-456") == {:cancel, "task-456"}
    end

    test "parses restart command" do
      assert CommandParser.parse("restart task-123") == {:restart, "task-123"}
    end

    test "parses priority command" do
      assert CommandParser.parse("priority task-123 high") == {:priority, "task-123", :high}

      assert CommandParser.parse("priority task-456 normal") ==
               {:priority, "task-456", :normal}

      assert CommandParser.parse("priority task-789 low") == {:priority, "task-789", :low}
    end

    test "returns error for invalid priority" do
      assert {:error, _} = CommandParser.parse("priority task-123 invalid")
    end
  end

  describe "parse/1 - inspection commands" do
    test "parses status command" do
      assert CommandParser.parse("status") == {:status}
      assert CommandParser.parse("s") == {:status}
    end

    test "parses tasks command" do
      assert CommandParser.parse("tasks") == {:tasks}
      assert CommandParser.parse("t") == {:tasks}
    end

    test "parses providers command" do
      assert CommandParser.parse("providers") == {:providers}
    end

    test "parses logs command" do
      assert CommandParser.parse("logs anthropic") == {:logs, :anthropic}
      assert CommandParser.parse("logs openai") == {:logs, :openai}
    end

    test "parses stats command" do
      assert CommandParser.parse("stats") == {:stats}
    end

    test "parses inspect command" do
      assert CommandParser.parse("inspect task-123") == {:inspect, "task-123"}
    end
  end

  describe "parse/1 - workflow management commands" do
    test "parses strategy command" do
      assert CommandParser.parse("strategy all") == {:strategy, :all}
      assert CommandParser.parse("strategy sequential") == {:strategy, :sequential}
      assert CommandParser.parse("strategy dialectical") == {:strategy, :dialectical}
    end

    test "returns error for invalid strategy" do
      assert {:error, _} = CommandParser.parse("strategy invalid")
    end

    test "parses allocate command with quotes" do
      assert CommandParser.parse("allocate \"Build auth\" to anthropic,openai") ==
               {:allocate, "Build auth", [:anthropic, :openai]}
    end

    test "parses allocate command without quotes" do
      assert CommandParser.parse("allocate Build auth to anthropic") ==
               {:allocate, "Build auth", [:anthropic]}
    end

    test "parses redistribute command" do
      assert CommandParser.parse("redistribute") == {:redistribute}
    end

    test "parses focus command" do
      assert CommandParser.parse("focus anthropic") == {:focus, :anthropic}
    end

    test "parses compare command" do
      assert CommandParser.parse("compare") == {:compare}
    end
  end

  describe "parse/1 - file management commands" do
    test "parses files command" do
      assert CommandParser.parse("files") == {:files}
      assert CommandParser.parse("f") == {:files}
    end

    test "parses diff command" do
      assert CommandParser.parse("diff lib/auth.ex") == {:diff, "lib/auth.ex"}
    end

    test "parses lock command" do
      assert CommandParser.parse("lock lib/auth.ex") == {:lock, "lib/auth.ex"}
    end

    test "parses conflicts command" do
      assert CommandParser.parse("conflicts") == {:conflicts}
    end

    test "parses merge commands" do
      assert CommandParser.parse("merge auto") == {:merge, :auto}
      assert CommandParser.parse("merge interactive") == {:merge, :interactive}
      assert CommandParser.parse("m auto") == {:merge, :auto}
    end

    test "parses revert command" do
      assert CommandParser.parse("revert lib/auth.ex anthropic") ==
               {:revert, "lib/auth.ex", :anthropic}
    end
  end

  describe "parse/1 - provider management commands" do
    test "parses enable command" do
      assert CommandParser.parse("enable deepseek") == {:enable, :deepseek}
    end

    test "parses disable command" do
      assert CommandParser.parse("disable local") == {:disable, :local}
    end

    test "parses switch command" do
      assert CommandParser.parse("switch anthropic claude-3-opus") ==
               {:switch, :anthropic, "claude-3-opus"}
    end

    test "parses config command" do
      assert CommandParser.parse("config") == {:config, :all}
      assert CommandParser.parse("config anthropic") == {:config, :anthropic}
    end
  end

  describe "parse/1 - session management commands" do
    test "parses save command" do
      assert CommandParser.parse("save my-session") == {:save, "my-session"}
    end

    test "parses load command" do
      assert CommandParser.parse("load my-session") == {:load, "my-session"}
    end

    test "parses sessions command" do
      assert CommandParser.parse("sessions") == {:sessions}
    end

    test "parses export command" do
      assert CommandParser.parse("export json") == {:export, "json"}
    end
  end

  describe "parse/1 - utility commands" do
    test "parses clear command" do
      assert CommandParser.parse("clear") == {:clear}
    end

    test "parses set command" do
      assert CommandParser.parse("set display_mode split") == {:set, "display_mode", "split"}
    end

    test "parses watch command" do
      assert CommandParser.parse("watch task-123") == {:watch, "task-123"}
    end

    test "parses follow command" do
      assert CommandParser.parse("follow anthropic") == {:follow, :anthropic}
    end

    test "parses interactive command" do
      assert CommandParser.parse("interactive task-123") == {:interactive, "task-123"}
    end
  end

  describe "parse/1 - help and navigation" do
    test "parses help command" do
      assert CommandParser.parse("help") == {:help}
      assert CommandParser.parse("?") == {:help}
    end

    test "parses help with topic" do
      assert CommandParser.parse("help merge") == {:help, "merge"}
      assert CommandParser.parse("help status") == {:help, "status"}
    end

    test "parses commands command" do
      assert CommandParser.parse("commands") == {:commands}
    end

    test "parses exit commands" do
      assert CommandParser.parse("exit") == {:exit}
      assert CommandParser.parse("quit") == {:exit}
      assert CommandParser.parse("q") == {:exit}
    end
  end

  describe "parse/1 - history commands" do
    test "parses history list command" do
      assert CommandParser.parse("history") == {:history, :list}
    end

    test "parses file history command" do
      assert CommandParser.parse("history lib/auth.ex") == {:file_history, "lib/auth.ex"}
    end
  end

  describe "parse/1 - build and test commands" do
    test "parses build command" do
      assert CommandParser.parse("build") == {:build}
    end

    test "parses test command" do
      assert CommandParser.parse("test") == {:test}
    end

    test "parses quality command" do
      assert CommandParser.parse("quality") == {:quality}
    end

    test "parses failures command" do
      assert CommandParser.parse("failures") == {:failures}
    end
  end

  describe "parse/1 - query commands" do
    test "treats unknown input as query" do
      assert CommandParser.parse("Write a hello world function") ==
               {:query, "Write a hello world function"}

      assert CommandParser.parse("How do I implement authentication?") ==
               {:query, "How do I implement authentication?"}
    end
  end

  describe "parse/1 - edge cases" do
    test "handles empty strings" do
      assert {:error, _} = CommandParser.parse("")
      assert {:error, _} = CommandParser.parse("   ")
    end

    test "handles commands with extra whitespace" do
      assert CommandParser.parse("  pause   all  ") == {:pause, :all}
      assert CommandParser.parse("  status  ") == {:status}
    end

    test "handles case sensitivity" do
      # Provider names should be lowercased
      assert CommandParser.parse("pause ANTHROPIC") == {:pause, :anthropic}
      assert CommandParser.parse("logs OpenAI") == {:logs, :openai}
    end
  end

  describe "all_commands/0" do
    test "returns list of all available commands" do
      commands = CommandParser.all_commands()

      assert is_list(commands)
      assert "pause" in commands
      assert "status" in commands
      assert "merge" in commands
      assert "help" in commands
    end
  end

  describe "aliases/0" do
    test "returns command aliases map" do
      aliases = CommandParser.aliases()

      assert is_map(aliases)
      assert aliases["p"] == "pause"
      assert aliases["s"] == "status"
      assert aliases["m"] == "merge"
    end
  end
end
