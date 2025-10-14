defmodule MultiAgentCoder.Agent.Perplexity do
  @moduledoc """
  Perplexity AI API integration with web search capabilities.

  Provides enhanced API integration with:
  - Real-time web search during inference
  - Citation and source tracking
  - Automatic retry logic with exponential backoff
  - Comprehensive error handling
  - Token counting and cost tracking
  - Streaming response support

  Perplexity's unique feature is the ability to search the web for current
  information, making it ideal for research-driven coding tasks that require
  up-to-date documentation, library usage examples, and best practices.
  """

  require Logger

  alias MultiAgentCoder.Agent.{HTTPClient, TokenCounter, ContextFormatter}

  @api_base "https://api.perplexity.ai"

  @doc """
  Makes an API call to Perplexity with automatic retry and error handling.

  ## Parameters
    * `state` - Agent worker state containing configuration
    * `prompt` - The user prompt/task
    * `context` - Additional context (previous results, files, etc.)

  ## Returns
    * `{:ok, response, usage}` - Successful response with usage statistics
    * `{:error, reason}` - Classified error with details

  ## Examples

      iex> Perplexity.call(state, "What are the latest Phoenix LiveView features?", %{})
      {:ok, "Based on recent documentation...\\n\\nSources: [1] hexdocs.pm...", %{input_tokens: 10, output_tokens: 50, cost: 0.002}}
  """
  def call(state, prompt, context \\ %{}) do
    Logger.info("Perplexity: Calling #{state.model}")

    with {:ok, messages} <- build_messages(prompt, context),
         {:ok, body} <- make_request(state, messages),
         {:ok, response, usage} <- extract_response(body, state, prompt) do
      Logger.info(
        "Perplexity: Request successful - #{usage.total_tokens} tokens, #{usage.formatted_cost}"
      )

      {:ok, response, usage}
    else
      {:error, reason} = error ->
        Logger.error("Perplexity: Request failed - #{inspect(reason)}")
        error
    end
  end

  @doc """
  Validates the API key by making a test request.
  """
  def validate_credentials(api_key) do
    headers = [
      {"Authorization", "Bearer #{api_key}"},
      {"Content-Type", "application/json"}
    ]

    # Make a minimal test request
    body = %{
      model: "sonar",
      messages: [%{role: "user", content: "test"}]
    }

    case HTTPClient.post_with_retry("#{@api_base}/chat/completions", body, headers,
           timeout: 30_000
         ) do
      {:ok, _response} -> :ok
      {:error, {:unauthorized, _}} -> {:error, :invalid_api_key}
      {:error, reason} -> {:error, reason}
    end
  end

  # Private functions

  defp build_messages(prompt, context) do
    system_content = ContextFormatter.build_system_prompt(context)
    enhanced_prompt = ContextFormatter.build_enhanced_prompt(prompt, context)

    # Perplexity uses OpenAI-style message format
    messages = [
      %{
        role: "system",
        content: """
        #{system_content}

        You are an expert software engineer with access to real-time web search.
        Use web search to find current documentation, best practices, and examples when helpful.
        Write clean, efficient, well-documented code based on the latest information available.
        When you use web sources, cite them clearly in your response.
        """
      },
      %{
        role: "user",
        content: enhanced_prompt
      }
    ]

    {:ok, messages}
  end

  defp make_request(state, messages) do
    headers = [
      {"Authorization", "Bearer #{state.api_key}"},
      {"Content-Type", "application/json"}
    ]

    body = %{
      model: state.model,
      messages: messages,
      temperature: state.temperature,
      max_tokens: state.max_tokens,
      # Enable web search and citations
      return_citations: true,
      return_related_questions: false
    }

    url = "#{@api_base}/chat/completions"

    case HTTPClient.post_with_retry(url, body, headers) do
      {:ok, response_body} ->
        {:ok, response_body}

      {:error, reason} ->
        {:error, classify_error(reason)}
    end
  end

  defp extract_response(body, state, original_prompt) do
    with {:ok, content} <- extract_content(body),
         {:ok, citations} <- extract_citations(body),
         {:ok, usage_data} <- extract_usage(body) do
      # Add citations to response if present
      response_with_citations =
        if citations && length(citations) > 0 do
          format_response_with_citations(content, citations)
        else
          content
        end

      # Calculate usage statistics
      input_text = original_prompt
      output_text = content

      usage =
        TokenCounter.create_usage_summary(:perplexity, state.model, input_text, output_text)

      # Merge with actual usage data if available
      usage =
        if usage_data do
          Map.merge(usage, %{
            input_tokens: usage_data["prompt_tokens"] || usage.input_tokens,
            output_tokens: usage_data["completion_tokens"] || usage.output_tokens,
            total_tokens: usage_data["total_tokens"] || usage.total_tokens
          })
        else
          usage
        end

      {:ok, response_with_citations, usage}
    end
  end

  defp extract_content(body) do
    # Perplexity uses OpenAI-style response format
    case get_in(body, ["choices", Access.at(0), "message", "content"]) do
      nil ->
        {:error, :no_content_in_response}

      content when is_binary(content) ->
        {:ok, content}

      _ ->
        {:error, :invalid_response_format}
    end
  end

  defp extract_citations(body) do
    # Perplexity returns citations in the response
    citations = get_in(body, ["citations"]) || []
    {:ok, citations}
  end

  defp extract_usage(body) do
    usage = get_in(body, ["usage"])
    {:ok, usage}
  end

  defp format_response_with_citations(content, citations) when is_list(citations) do
    if Enum.empty?(citations) do
      content
    else
      citation_text =
        citations
        |> Enum.with_index(1)
        |> Enum.map(fn {url, idx} -> "  [#{idx}] #{url}" end)
        |> Enum.join("\n")

      """
      #{content}

      🔍 Sources:
      #{citation_text}
      """
    end
  end

  defp classify_error({:unauthorized, msg}), do: {:authentication_error, msg}
  defp classify_error({:rate_limited, msg}), do: {:rate_limit_error, msg}
  defp classify_error({:bad_request, msg}), do: {:invalid_request, msg}
  defp classify_error({:service_unavailable, msg}), do: {:service_unavailable, msg}
  defp classify_error({:network_error, reason}), do: {:network_error, reason}
  defp classify_error(reason), do: {:unknown_error, reason}
end
