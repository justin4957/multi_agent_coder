defmodule MultiAgentCoder.Agent.Local do
  @moduledoc """
  Local LLM integration (Ollama).

  Handles communication with locally-hosted language models via Ollama.
  """

  require Logger

  @doc """
  Makes an API call to a local LLM server.

  ## Parameters
    * `state` - Agent worker state containing configuration
    * `prompt` - The user prompt/task
    * `context` - Additional context (previous results, files, etc.)

  ## Returns
    * `{:ok, response}` - Successful response
    * `{:error, reason}` - Error details
  """
  def call(state, prompt, context) do
    Logger.info("Local: Making API call to #{state.endpoint} with model #{state.model}")

    endpoint = state.endpoint || "http://localhost:11434"

    headers = [
      {"Content-Type", "application/json"}
    ]

    body = %{
      model: state.model,
      prompt: build_prompt(prompt, context),
      temperature: state.temperature,
      stream: false
    }

    case Req.post("#{endpoint}/api/generate", json: body, headers: headers) do
      {:ok, %{status: 200, body: response_body}} ->
        content = Map.get(response_body, "response")
        {:ok, content}

      {:ok, %{status: status, body: error_body}} ->
        Logger.error("Local API error (#{status}): #{inspect(error_body)}")
        {:error, "API returned status #{status}"}

      {:error, reason} ->
        Logger.error("Local request failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp build_prompt(prompt, context) do
    system = "You are an expert software engineer. Provide clear, well-documented, and composable code solutions."

    case Map.get(context, :previous_results) do
      nil ->
        "#{system}\n\n#{prompt}"

      results ->
        """
        #{system}

        Previous agent responses for context:
        #{format_previous_results(results)}

        User request: #{prompt}
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
