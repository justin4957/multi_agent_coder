defmodule MultiAgentCoder.Agent.DeepSeek do
  @moduledoc """
  DeepSeek API integration for DeepSeek Coder models.

  Provides enhanced API integration with:
  - Automatic retry logic with exponential backoff
  - Comprehensive error handling and classification
  - Token counting and cost tracking
  - Streaming response support
  - Context management for multi-turn conversations

  DeepSeek offers specialized code generation models with competitive
  performance and pricing.
  """

  require Logger

  alias MultiAgentCoder.Agent.{ContextFormatter, HTTPClient, Streaming, TokenCounter}

  @api_base "https://api.deepseek.com/v1"

  @doc """
  Makes an API call to DeepSeek with automatic retry and error handling.

  ## Parameters
    * `state` - Agent worker state containing configuration
    * `prompt` - The user prompt/task
    * `context` - Additional context (previous results, files, etc.)

  ## Returns
    * `{:ok, response, usage}` - Successful response with usage statistics
    * `{:error, reason}` - Classified error with details

  ## Examples

      iex> DeepSeek.call(state, "Write a hello world function", %{})
      {:ok, "def hello_world()...", %{input_tokens: 10, output_tokens: 50, cost: 0.001}}
  """
  def call(state, prompt, context \\ %{}) do
    Logger.info("DeepSeek: Calling #{state.model}")

    with {:ok, messages} <- build_messages(prompt, context),
         {:ok, body} <- make_request(state, messages),
         {:ok, response, usage} <- extract_response(body, state, prompt) do
      Logger.info(
        "DeepSeek: Request successful - #{usage.total_tokens} tokens, #{usage.formatted_cost}"
      )

      {:ok, response, usage}
    else
      {:error, reason} = error ->
        Logger.error("DeepSeek: Request failed - #{inspect(reason)}")
        error
    end
  end

  @doc """
  Makes a streaming API call to DeepSeek.

  Returns an async stream of response chunks.
  """
  def call_streaming(state, prompt, context \\ %{}) do
    Logger.info("DeepSeek: Starting streaming call with #{state.model}")

    with {:ok, messages} <- build_messages(prompt, context) do
      stream_request(state, messages)
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
      model: "deepseek-chat",
      messages: [%{role: "user", content: "test"}],
      max_tokens: 10
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
    Logger.info("DeepSeek: Starting streaming request")

    headers = [
      {"Authorization", "Bearer #{state.api_key}"},
      {"Content-Type", "application/json"}
    ]

    body = %{
      model: state.model,
      messages: messages,
      temperature: state.temperature,
      max_tokens: state.max_tokens,
      stream: true
    }

    url = "#{@api_base}/chat/completions"
    accumulated_content = ""
    original_prompt = List.last(messages)[:content]

    try do
      case Req.post(url, headers: headers, json: body) do
        {:ok, %Req.Response{status: 200, body: response_body}} ->
          # Parse SSE stream (DeepSeek uses OpenAI-compatible format)
          full_response = parse_stream_response(response_body, :deepseek, accumulated_content)

          # Calculate usage statistics
          usage =
            TokenCounter.create_usage_summary(
              :deepseek,
              state.model,
              original_prompt,
              full_response
            )

          Streaming.broadcast_complete(:deepseek, full_response, usage)
          {:ok, full_response, usage}

        {:ok, %Req.Response{status: status, body: error_body}} ->
          error_msg = "HTTP #{status}: #{inspect(error_body)}"
          Streaming.broadcast_error(:deepseek, :http_error, error_msg)
          {:error, {:http_error, error_msg}}

        {:error, reason} ->
          error_msg = "Request failed: #{inspect(reason)}"
          Streaming.broadcast_error(:deepseek, :request_failed, error_msg)
          {:error, classify_error({:network_error, reason})}
      end
    rescue
      error ->
        error_msg = "Streaming failed: #{Exception.message(error)}"
        Logger.error("DeepSeek: #{error_msg}")
        Streaming.broadcast_error(:deepseek, :stream_error, error_msg)
        {:error, {:stream_error, error_msg}}
    end
  end

  defp parse_stream_response(body, provider, accumulated) do
    # DeepSeek uses OpenAI-compatible SSE format
    body
    |> String.split("\n")
    |> Enum.reduce(accumulated, fn line, acc ->
      process_sse_line(Streaming.parse_sse_line(line), provider, acc)
    end)
  end

  defp process_sse_line({:ok, data}, provider, acc) do
    # Extract content delta from OpenAI-compatible format
    case get_in(data, ["choices", Access.at(0), "delta", "content"]) do
      nil ->
        acc

      delta ->
        Streaming.broadcast_chunk(provider, delta)
        acc <> delta
    end
  end

  defp process_sse_line(:done, _provider, acc), do: acc
  defp process_sse_line(:skip, _provider, acc), do: acc

  defp extract_response(body, state, original_prompt) do
    with {:ok, content} <- extract_content(body),
         {:ok, usage_data} <- extract_usage(body) do
      # Calculate usage statistics
      input_text = original_prompt
      output_text = content

      usage = TokenCounter.create_usage_summary(:deepseek, state.model, input_text, output_text)

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
    # DeepSeek uses OpenAI-compatible format
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
