# Script to get AI feedback on issue #13

# Ensure application is started
{:ok, _} = Application.ensure_all_started(:multi_agent_coder)

issue_title = "Real-time Coding Progress Monitor with Multi-Provider Dashboard"

issue_description = """
Build a comprehensive real-time monitoring dashboard that displays the coding progress of multiple providers working concurrently. Show what each provider is working on, files being modified, code being generated, and overall task completion status.

## Goals
- Provide real-time visibility into what each provider is doing
- Display file-level changes as they happen
- Show code generation progress with streaming updates
- Monitor resource usage (tokens, API calls, time)
- Alert on errors or blockers without stopping other providers

## Tasks
- Create interactive dashboard layout with provider status panels
- Implement real-time streaming updates via PubSub
- Add file operation tracking
- Create alert system for errors
- Implement navigation controls
- Add summary statistics

## Technical Context
- This is an Elixir/Phoenix application
- Already has: PubSub for real-time updates, Worker module for AI agents, Task allocation system (#12)
- Uses multiple AI providers concurrently (OpenAI, Anthropic, DeepSeek, Perplexity, Local)
- Current monitoring is basic - needs comprehensive dashboard
"""

prompt = """
You are reviewing a feature request for an Elixir/Phoenix multi-agent coding application.

Issue Title: #{issue_title}

Issue Description:
#{issue_description}

Please provide constructive feedback on this feature request. Consider:
1. Implementation complexity and feasibility
2. Potential technical challenges or gotchas
3. Architecture recommendations
4. Suggestions for breaking it into smaller tasks
5. Any missing requirements or edge cases
6. Performance considerations for real-time updates
7. User experience improvements

Keep your feedback concise and actionable (300-500 words).
"""

IO.puts("Getting feedback from DeepSeek...")

deepseek_result =
  MultiAgentCoder.Agent.Worker.execute_task(:deepseek, prompt, %{})

IO.puts("\nGetting feedback from OpenAI...")

openai_result =
  MultiAgentCoder.Agent.Worker.execute_task(:openai, prompt, %{})

# Format the results
deepseek_feedback =
  case deepseek_result do
    {:ok, content} -> content
    {:error, reason} -> "Error: #{inspect(reason)}"
  end

openai_feedback =
  case openai_result do
    {:ok, content} -> content
    {:error, reason} -> "Error: #{inspect(reason)}"
  end

# Create formatted output
output = """
## AI Provider Feedback on Issue #13

### DeepSeek Feedback

#{deepseek_feedback}

---

### OpenAI (GPT-4) Feedback

#{openai_feedback}

---

*Feedback generated via multi_agent_coder API*
"""

IO.puts("\n" <> String.duplicate("=", 80))
IO.puts("FEEDBACK COLLECTED")
IO.puts(String.duplicate("=", 80))
IO.puts(output)

# Write to file
File.write!("/tmp/issue_13_feedback.md", output)
IO.puts("\n✓ Feedback saved to /tmp/issue_13_feedback.md")
