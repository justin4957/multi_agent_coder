defmodule MultiAgentCoder.Agent.OpenAI do
  @moduledoc """
  OpenAI API integration for GPT models.

  Provides enhanced API integration with:
  - Automatic retry logic with exponential backoff
  - Comprehensive error handling and classification
  - Token counting and cost tracking
  - Streaming response support
  - Context management for multi-turn conversations
  """

  require Logger

  alias MultiAgentCoder.Agent.{HTTPClient, TokenCounter, ContextFormatter}

  @api_base "https://api.openai.com/v1"

  @doc """
  Makes an API call to OpenAI with automatic retry and error handling.

  ## Parameters
    * `state` - Agent worker state containing configuration
    * `prompt` - The user prompt/task
    * `context` - Additional context (previous results, files, etc.)

  ## Returns
    * `{:ok, response}` - Successful response with content
    * `{:ok, response, usage}` - Successful response with usage statistics
    * `{:error, reason}` - Classified error with details

  ## Examples

      iex> OpenAI.call(state, "Write a hello world function", %{})
      {:ok, "def hello_world()...", %{input_tokens: 10, output_tokens: 50, cost: 0.002}}
  """
  def call(state, prompt, context \\ %{}) do
    Logger.info("OpenAI: Calling #{state.model}")

    with {:ok, messages} <- build_messages(prompt, context),
         {:ok, body} <- make_request(state, messages),
         {:ok, response, usage} <- extract_response(body, state, prompt) do
      Logger.info("OpenAI: Request successful - #{usage.total_tokens} tokens, #{usage.formatted_cost}")
      {:ok, response, usage}
    else
      {:error, reason} = error ->
        Logger.error("OpenAI: Request failed - #{inspect(reason)}")
        error
    end
  end

  @doc """
  Makes a streaming API call to OpenAI.

  Returns an async stream of response chunks.
  """
  def call_streaming(state, prompt, context \\ %{}) do
    Logger.info("OpenAI: Starting streaming call with #{state.model}")

    with {:ok, messages} <- build_messages(prompt, context) do
      stream_request(state, messages)
    end
  end

  @doc """
  Validates the API key and model availability.
  """
  def validate_credentials(api_key, model) do
    headers = [
      {"Authorization", "Bearer #{api_key}"},
      {"Content-Type", "application/json"}
    ]

    case HTTPClient.get_with_retry("#{@api_base}/models/#{model}", headers) do
      {:ok, _model_info} -> :ok
      {:error, {:unauthorized, _}} -> {:error, :invalid_api_key}
      {:error, {:not_found, _}} -> {:error, :model_not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  # Private functions

  defp build_messages(prompt, context) do
    system_prompt = ContextFormatter.build_system_prompt(context)
    enhanced_prompt = ContextFormatter.build_enhanced_prompt(prompt, context)

    messages = [
      %{
        role: "system",
        content: system_prompt
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
      max_tokens: state.max_tokens
    }

    url = "#{@api_base}/chat/completions"

    case HTTPClient.post_with_retry(url, body, headers) do
      {:ok, response_body} ->
        {:ok, response_body}

      {:error, reason} ->
        {:error, classify_error(reason)}
    end
  end

  defp stream_request(state, messages) do
    # Streaming implementation would go here
    # For now, fall back to regular request
    # In a full implementation, this would use Server-Sent Events
    Logger.warning("OpenAI: Streaming not yet implemented, using regular request")

    case make_request(state, messages) do
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

      usage = TokenCounter.create_usage_summary(:openai, state.model, input_text, output_text)

      # Merge with actual usage data if available
      usage =
        if usage_data do
          Map.merge(usage, %{
            input_tokens: usage_data["prompt_tokens"],
            output_tokens: usage_data["completion_tokens"],
            total_tokens: usage_data["total_tokens"]
          })
        else
          usage
        end

      {:ok, content, usage}
    end
  end

  defp extract_content(body) do
    case get_in(body, ["choices", Access.at(0), "message", "content"]) do
      nil ->
        {:error, :no_content_in_response}

      content when is_binary(content) ->
        {:ok, content}

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
