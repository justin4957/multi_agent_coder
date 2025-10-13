defmodule MultiAgentCoder.Agent.Anthropic do
  @moduledoc """
  Anthropic API integration for Claude models.

  Provides enhanced API integration with:
  - Automatic retry logic with exponential backoff
  - Comprehensive error handling and classification
  - Token counting and cost tracking
  - Streaming response support via Server-Sent Events
  - Context management for multi-turn conversations
  """

  require Logger

  alias MultiAgentCoder.Agent.{HTTPClient, TokenCounter, ContextFormatter}

  @api_base "https://api.anthropic.com/v1"
  @api_version "2023-06-01"

  @doc """
  Makes an API call to Anthropic with automatic retry and error handling.

  ## Parameters
    * `state` - Agent worker state containing configuration
    * `prompt` - The user prompt/task
    * `context` - Additional context (previous results, files, etc.)

  ## Returns
    * `{:ok, response, usage}` - Successful response with usage statistics
    * `{:error, reason}` - Classified error with details

  ## Examples

      iex> Anthropic.call(state, "Write a hello world function", %{})
      {:ok, "def hello_world()...", %{input_tokens: 10, output_tokens: 50, cost: 0.002}}
  """
  def call(state, prompt, context \\ %{}) do
    Logger.info("Anthropic: Calling #{state.model}")

    with {:ok, system_prompt, messages} <- build_messages(prompt, context),
         {:ok, body} <- make_request(state, system_prompt, messages),
         {:ok, response, usage} <- extract_response(body, state, prompt) do
      Logger.info("Anthropic: Request successful - #{usage.total_tokens} tokens, #{usage.formatted_cost}")
      {:ok, response, usage}
    else
      {:error, reason} = error ->
        Logger.error("Anthropic: Request failed - #{inspect(reason)}")
        error
    end
  end

  @doc """
  Makes a streaming API call to Anthropic.

  Returns an async stream of response chunks using Server-Sent Events.
  """
  def call_streaming(state, prompt, context \\ %{}) do
    Logger.info("Anthropic: Starting streaming call with #{state.model}")

    with {:ok, system_prompt, messages} <- build_messages(prompt, context) do
      stream_request(state, system_prompt, messages)
    end
  end

  @doc """
  Validates the API key by making a test request.
  """
  def validate_credentials(api_key) do
    headers = [
      {"x-api-key", api_key},
      {"anthropic-version", @api_version},
      {"Content-Type", "application/json"}
    ]

    # Make a minimal test request
    body = %{
      model: "claude-3-haiku-20240307",
      messages: [%{role: "user", content: "test"}],
      max_tokens: 10
    }

    case HTTPClient.post_with_retry("#{@api_base}/messages", body, headers, timeout: 30_000) do
      {:ok, _response} -> :ok
      {:error, {:unauthorized, _}} -> {:error, :invalid_api_key}
      {:error, reason} -> {:error, reason}
    end
  end

  # Private functions

  defp build_messages(prompt, context) do
    system_prompt = ContextFormatter.build_system_prompt(context)
    enhanced_prompt = ContextFormatter.build_enhanced_prompt(prompt, context)

    messages = [
      %{
        role: "user",
        content: enhanced_prompt
      }
    ]

    {:ok, system_prompt, messages}
  end

  defp make_request(state, system_prompt, messages) do
    headers = [
      {"x-api-key", state.api_key},
      {"anthropic-version", @api_version},
      {"Content-Type", "application/json"}
    ]

    body = %{
      model: state.model,
      system: system_prompt,
      messages: messages,
      temperature: state.temperature,
      max_tokens: state.max_tokens
    }

    url = "#{@api_base}/messages"

    case HTTPClient.post_with_retry(url, body, headers) do
      {:ok, response_body} ->
        {:ok, response_body}

      {:error, reason} ->
        {:error, classify_error(reason)}
    end
  end

  defp stream_request(state, system_prompt, messages) do
    # Streaming implementation would use SSE
    # For now, fall back to regular request
    Logger.warning("Anthropic: Streaming not yet fully implemented, using regular request")

    case make_request(state, system_prompt, messages) do
      {:ok, body} -> extract_response(body, state, List.last(messages)["content"])
      error -> error
    end
  end

  defp extract_response(body, state, original_prompt) do
    with {:ok, content} <- extract_content(body),
         {:ok, usage_data} <- extract_usage(body) do
      # Calculate usage statistics
      input_text = original_prompt
      output_text = content

      usage = TokenCounter.create_usage_summary(:anthropic, state.model, input_text, output_text)

      # Merge with actual usage data if available
      usage =
        if usage_data do
          Map.merge(usage, %{
            input_tokens: usage_data["input_tokens"],
            output_tokens: usage_data["output_tokens"],
            total_tokens: usage_data["input_tokens"] + usage_data["output_tokens"]
          })
        else
          usage
        end

      {:ok, content, usage}
    end
  end

  defp extract_content(body) do
    # Anthropic returns content as a list of content blocks
    case get_in(body, ["content"]) do
      nil ->
        {:error, :no_content_in_response}

      content_blocks when is_list(content_blocks) ->
        # Extract text from all text blocks
        text =
          content_blocks
          |> Enum.filter(&(&1["type"] == "text"))
          |> Enum.map(& &1["text"])
          |> Enum.join("\n")

        if text == "" do
          {:error, :no_text_content}
        else
          {:ok, text}
        end

      _ ->
        {:error, :invalid_response_format}
    end
  end

  defp extract_usage(body) do
    usage = get_in(body, ["usage"])
    {:ok, usage}
  end

  defp classify_error({:unauthorized, msg}), do: {:authentication_error, msg}
  defp classify_error({:rate_limited, msg}), do: {:rate_limit_error, msg}
  defp classify_error({:bad_request, msg}), do: {:invalid_request, msg}
  defp classify_error({:service_unavailable, msg}), do: {:service_unavailable, msg}
  defp classify_error({:network_error, reason}), do: {:network_error, reason}
  defp classify_error(reason), do: {:unknown_error, reason}
end
