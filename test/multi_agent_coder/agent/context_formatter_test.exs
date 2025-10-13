defmodule MultiAgentCoder.Agent.ContextFormatterTest do
  use ExUnit.Case, async: true

  alias MultiAgentCoder.Agent.ContextFormatter

  describe "build_system_prompt/2" do
    test "returns base prompt with no context" do
      prompt = ContextFormatter.build_system_prompt(%{})
      assert is_binary(prompt)
      assert String.contains?(prompt, "expert software engineer")
    end

    test "includes previous results in prompt" do
      context = %{
        previous_results: %{
          openai: {:ok, "Solution from OpenAI"},
          anthropic: {:ok, "Solution from Anthropic"}
        }
      }

      prompt = ContextFormatter.build_system_prompt(context)
      assert String.contains?(prompt, "PREVIOUS")
      assert String.contains?(prompt, "OPENAI")
    end

    test "accepts custom base prompt" do
      custom = "Custom system prompt"
      prompt = ContextFormatter.build_system_prompt(%{}, custom)
      assert String.contains?(prompt, custom)
    end
  end

  describe "format_previous_results/1" do
    test "formats successful results" do
      results = %{
        openai: {:ok, "Response 1"},
        anthropic: {:ok, "Response 2"}
      }

      formatted = ContextFormatter.format_previous_results(results)
      assert String.contains?(formatted, "OPENAI")
      assert String.contains?(formatted, "Response 1")
      assert String.contains?(formatted, "ANTHROPIC")
    end

    test "handles error results" do
      results = %{
        openai: {:ok, "Success"},
        anthropic: {:error, :timeout}
      }

      formatted = ContextFormatter.format_previous_results(results)
      assert String.contains?(formatted, "Success")
      assert String.contains?(formatted, "Error")
    end

    test "returns empty string for non-map input" do
      assert ContextFormatter.format_previous_results(nil) == ""
      assert ContextFormatter.format_previous_results([]) == ""
    end
  end

  describe "extract_file_context/1" do
    test "extracts file information" do
      context = %{
        files: [
          %{path: "test.ex", content: "defmodule Test do\nend"}
        ]
      }

      result = ContextFormatter.extract_file_context(context)
      assert String.contains?(result, "test.ex")
      assert String.contains?(result, "defmodule")
    end

    test "returns empty for no files" do
      assert ContextFormatter.extract_file_context(%{}) == ""
    end
  end

  describe "build_enhanced_prompt/2" do
    test "combines prompt with context" do
      prompt = "Write a function"
      context = %{
        files: [%{path: "lib/test.ex", content: "# existing code"}],
        previous_results: %{openai: {:ok, "Previous solution"}}
      }

      enhanced = ContextFormatter.build_enhanced_prompt(prompt, context)
      assert String.contains?(enhanced, "Write a function")
      assert String.contains?(enhanced, "lib/test.ex")
    end

    test "returns base prompt when context is empty" do
      prompt = "Write a function"
      enhanced = ContextFormatter.build_enhanced_prompt(prompt, %{})
      assert enhanced == prompt
    end
  end

  describe "default_system_prompt/0" do
    test "returns a coding-focused prompt" do
      prompt = ContextFormatter.default_system_prompt()
      assert is_binary(prompt)
      assert String.length(prompt) > 50
      assert String.contains?(prompt, "software engineer")
    end
  end
end
