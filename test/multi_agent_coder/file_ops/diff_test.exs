defmodule MultiAgentCoder.FileOps.DiffTest do
  use ExUnit.Case, async: true

  alias MultiAgentCoder.FileOps.Diff

  describe "generate/3" do
    test "generates diff for new file" do
      diff = Diff.generate("lib/new.ex", nil, "line 1\nline 2")

      assert diff.file == "lib/new.ex"
      assert diff.old_content == nil
      assert diff.new_content == "line 1\nline 2"
      assert diff.stats.additions == 2
      assert diff.stats.deletions == 0
      assert diff.stats.modifications == 0
    end

    test "generates diff for deleted file" do
      diff = Diff.generate("lib/old.ex", "line 1\nline 2", nil)

      assert diff.stats.additions == 0
      assert diff.stats.deletions == 2
      assert diff.stats.modifications == 0
    end

    test "generates diff for modified file" do
      old_content = "line 1\nline 2\nline 3"
      new_content = "line 1\nmodified line 2\nline 3"

      diff = Diff.generate("lib/file.ex", old_content, new_content)

      assert diff.stats.additions == 0
      assert diff.stats.deletions == 0
      assert diff.stats.modifications == 1
    end

    test "generates diff with additions and modifications" do
      old_content = "line 1\nline 2"
      new_content = "modified line 1\nline 2\nline 3"

      diff = Diff.generate("lib/file.ex", old_content, new_content)

      assert diff.stats.additions == 1
      assert diff.stats.modifications >= 1
    end
  end

  describe "format/2" do
    test "formats diff with colors" do
      diff = Diff.generate("lib/file.ex", "old", "new")
      formatted = Diff.format(diff, color: true)

      assert is_binary(formatted)
      assert String.contains?(formatted, "lib/file.ex")
    end

    test "formats diff without colors" do
      diff = Diff.generate("lib/file.ex", "old", "new")
      formatted = Diff.format(diff, color: false)

      assert is_binary(formatted)
      assert String.contains?(formatted, "lib/file.ex")
      refute String.contains?(formatted, IO.ANSI.green())
    end
  end

  describe "apply_diff/2" do
    test "reconstructs content from diff" do
      old_content = "line 1\nline 2"
      new_content = "line 1\nmodified line 2\nline 3"

      diff = Diff.generate("lib/file.ex", old_content, new_content)
      reconstructed = Diff.apply_diff(old_content, diff.changes)

      assert String.contains?(reconstructed, "line 1")
    end
  end
end
