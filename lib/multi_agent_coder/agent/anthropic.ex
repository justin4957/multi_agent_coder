defmodule MultiAgentCoder.Agent.Anthropic do
  @moduledoc """
  Anthropic API integration for Claude models.

  Handles communication with Anthropic's Messages API.
  """

  require Logger

  @api_base "https://api.anthropic.com/v1"
  @api_version "2023-06-01"

  @doc """
  Makes an API call to Anthropic.

  ## Parameters
    * `state` - Agent worker state containing configuration
    * `prompt` - The user prompt/task
    * `context` - Additional context (previous results, files, etc.)

  ## Returns
    * `{:ok, response}` - Successful response
    * `{:error, reason}` - Error details
  """
  def call(state, prompt, context) do
    Logger.info("Anthropic: Making API call with model #{state.model}")

    headers = [
      {"x-api-key", state.api_key},
      {"anthropic-version", @api_version},
      {"Content-Type", "application/json"}
    ]

    body = %{
      model: state.model,
      messages: build_messages(prompt, context),
      system: build_system_prompt(context),
      temperature: state.temperature,
      max_tokens: state.max_tokens
    }

    case Req.post("#{@api_base}/messages", json: body, headers: headers) do
      {:ok, %{status: 200, body: response_body}} ->
        content = get_in(response_body, ["content", Access.at(0), "text"])
        {:ok, content}

      {:ok, %{status: status, body: error_body}} ->
        Logger.error("Anthropic API error (#{status}): #{inspect(error_body)}")
        {:error, "API returned status #{status}"}

      {:error, reason} ->
        Logger.error("Anthropic request failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp build_messages(prompt, _context) do
    [
      %{
        role: "user",
        content: prompt
      }
    ]
  end

  defp build_system_prompt(context) do
    base = "You are an expert software engineer. Provide clear, well-documented, and composable code solutions. Prioritize code reusability and abstraction."

    case Map.get(context, :previous_results) do
      nil ->
        base

      results ->
        """
        #{base}

        Previous agent responses for context:
        #{format_previous_results(results)}
        """
    end
  end

  defp format_previous_results(results) when is_map(results) do
    results
    |> Enum.map(fn {provider, {:ok, response}} ->
      "#{provider}: #{response}"
    end)
    |> Enum.join("\n\n")
  end

  defp format_previous_results(_), do: ""
end
