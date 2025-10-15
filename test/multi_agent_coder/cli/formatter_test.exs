defmodule MultiAgentCoder.CLI.FormatterTest do
  use ExUnit.Case, async: true

  alias MultiAgentCoder.CLI.Formatter

  import ExUnit.CaptureIO

  describe "format_header/1" do
    test "creates a formatted header with borders" do
      header = Formatter.format_header("TEST HEADER")

      assert header =~ "TEST HEADER"
      assert header =~ "="
    end

    test "includes ANSI color codes" do
      header = Formatter.format_header("COLORED HEADER")

      assert header =~ IO.ANSI.blue()
      assert header =~ IO.ANSI.reset()
    end
  end

  describe "format_separator/0" do
    test "creates a separator line" do
      separator = Formatter.format_separator()

      assert separator =~ "-"
      assert separator =~ IO.ANSI.blue()
      assert separator =~ IO.ANSI.reset()
    end
  end

  describe "display_standard_results/1" do
    test "displays successful results" do
      results = %{
        openai: {:ok, "OpenAI response"},
        anthropic: {:ok, "Anthropic response"}
      }

      output =
        capture_io(fn ->
          Formatter.display_standard_results(results)
        end)

      assert output =~ "OPENAI"
      assert output =~ "ANTHROPIC"
      assert output =~ "OpenAI response"
      assert output =~ "Anthropic response"
    end

    test "displays error results" do
      results = %{
        openai: {:error, :connection_failed}
      }

      output =
        capture_io(fn ->
          Formatter.display_standard_results(results)
        end)

      assert output =~ "OPENAI"
      assert output =~ "Error"
      assert output =~ "connection_failed"
    end

    test "displays mixed success and error results" do
      results = %{
        openai: {:ok, "Success"},
        anthropic: {:error, :timeout}
      }

      output =
        capture_io(fn ->
          Formatter.display_standard_results(results)
        end)

      assert output =~ "Success"
      assert output =~ "timeout"
    end
  end

  describe "display_dialectical/1" do
    test "displays all three phases" do
      results = %{
        thesis: %{openai: {:ok, "Initial solution"}},
        antithesis: %{openai: {:ok, "Critique"}},
        synthesis: %{openai: {:ok, "Final solution"}}
      }

      output =
        capture_io(fn ->
          Formatter.display_dialectical(results)
        end)

      assert output =~ "THESIS"
      assert output =~ "ANTITHESIS"
      assert output =~ "SYNTHESIS"
      assert output =~ "Initial solution"
      assert output =~ "Critique"
      assert output =~ "Final solution"
    end
  end

  describe "display_comparison/1" do
    test "displays comparison table" do
      results = %{
        openai: {:ok, "Short response"},
        anthropic: {:ok, "A much longer response with more content"}
      }

      output =
        capture_io(fn ->
          Formatter.display_comparison(results)
        end)

      assert output =~ "Provider"
      assert output =~ "Length"
      assert output =~ "openai"
      assert output =~ "anthropic"
      assert output =~ "Success"
    end

    test "handles errors in comparison" do
      results = %{
        openai: {:ok, "Success"},
        anthropic: {:error, :failed}
      }

      output =
        capture_io(fn ->
          Formatter.display_comparison(results)
        end)

      assert output =~ "Error"
      assert output =~ "N/A"
    end
  end

  describe "format_results_for_file/1" do
    test "formats standard results for file output" do
      results = %{
        openai: {:ok, "File content"}
      }

      output = Formatter.format_results_for_file(results)

      assert output =~ "OPENAI"
      assert output =~ "File content"
      # Should not contain ANSI codes
      refute output =~ "\e["
    end

    test "formats dialectical results for file output" do
      results = %{
        thesis: %{openai: {:ok, "Thesis"}},
        antithesis: %{openai: {:ok, "Antithesis"}},
        synthesis: %{openai: {:ok, "Synthesis"}}
      }

      output = Formatter.format_results_for_file(results)

      assert output =~ "DIALECTICAL ANALYSIS"
      assert output =~ "THESIS"
      assert output =~ "ANTITHESIS"
      assert output =~ "SYNTHESIS"
    end
  end

  describe "display_statistics/1" do
    test "displays execution statistics" do
      stats = %{
        total_time_ms: 5000,
        total_agents: 3,
        successful: 3,
        failed: 0
      }

      output =
        capture_io(fn ->
          Formatter.display_statistics(stats)
        end)

      assert output =~ "EXECUTION SUMMARY"
      assert output =~ "Total Time"
      assert output =~ "5.0s"
      assert output =~ "Total Agents"
      assert output =~ "3"
      assert output =~ "100.0%"
    end

    test "displays failure statistics" do
      stats = %{
        total_time_ms: 3000,
        total_agents: 2,
        successful: 1,
        failed: 1
      }

      output =
        capture_io(fn ->
          Formatter.display_statistics(stats)
        end)

      assert output =~ "Failed"
      assert output =~ "50.0%"
    end
  end

  describe "display_agent_status/3" do
    test "displays working status" do
      output =
        capture_io(fn ->
          Formatter.display_agent_status(:openai, :working, 1500)
        end)

      assert output =~ "Openai"
      assert output =~ "1.5s"
    end

    test "displays completed status" do
      output =
        capture_io(fn ->
          Formatter.display_agent_status(:anthropic, :completed, 3000)
        end)

      assert output =~ "Anthropic"
      assert output =~ "3.0s"
    end

    test "displays error status" do
      output =
        capture_io(fn ->
          Formatter.display_agent_status(:deepseek, :error)
        end)

      assert output =~ "Deepseek"
    end
  end

  describe "format_time_ms/1" do
    test "formats milliseconds" do
      assert Formatter.format_time_ms(500) == "500ms"
      assert Formatter.format_time_ms(999) == "999ms"
    end

    test "formats seconds" do
      assert Formatter.format_time_ms(1000) == "1.0s"
      assert Formatter.format_time_ms(5500) == "5.5s"
      assert Formatter.format_time_ms(59_999) == "60.0s"
    end

    test "formats minutes" do
      assert Formatter.format_time_ms(60_000) == "1m 0s"
      assert Formatter.format_time_ms(125_000) == "2m 5s"
      assert Formatter.format_time_ms(180_000) == "3m 0s"
    end
  end
end
