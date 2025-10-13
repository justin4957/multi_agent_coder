defmodule MultiAgentCoder.Agent.OpenAI do
  @moduledoc """
  OpenAI API integration for GPT models.

  Handles communication with OpenAI's Chat Completions API.
  """

  require Logger

  @api_base "https://api.openai.com/v1"

  @doc """
  Makes an API call to OpenAI.

  ## Parameters
    * `state` - Agent worker state containing configuration
    * `prompt` - The user prompt/task
    * `context` - Additional context (previous results, files, etc.)

  ## Returns
    * `{:ok, response}` - Successful response
    * `{:error, reason}` - Error details
  """
  def call(state, prompt, context) do
    Logger.info("OpenAI: Making API call with model #{state.model}")

    headers = [
      {"Authorization", "Bearer #{state.api_key}"},
      {"Content-Type", "application/json"}
    ]

    body = %{
      model: state.model,
      messages: build_messages(prompt, context),
      temperature: state.temperature,
      max_tokens: state.max_tokens
    }

    case Req.post("#{@api_base}/chat/completions", json: body, headers: headers) do
      {:ok, %{status: 200, body: response_body}} ->
        content = get_in(response_body, ["choices", Access.at(0), "message", "content"])
        {:ok, content}

      {:ok, %{status: status, body: error_body}} ->
        Logger.error("OpenAI API error (#{status}): #{inspect(error_body)}")
        {:error, "API returned status #{status}"}

      {:error, reason} ->
        Logger.error("OpenAI request failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp build_messages(prompt, context) do
    system_message = %{
      role: "system",
      content: build_system_prompt(context)
    }

    user_message = %{
      role: "user",
      content: prompt
    }

    [system_message, user_message]
  end

  defp build_system_prompt(context) do
    base = "You are an expert software engineer. Provide clear, well-documented, and composable code solutions."

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
