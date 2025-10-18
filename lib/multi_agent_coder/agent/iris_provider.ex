defmodule MultiAgentCoder.Agent.IrisProvider do
  @moduledoc """
  High-performance local LLM provider using Iris Broadway pipeline.

  Provides:
  - Concurrent request processing with Broadway
  - Response caching for duplicate prompts
  - Circuit breakers and automatic failover
  - Comprehensive telemetry and monitoring
  - Support for multiple Ollama models simultaneously

  This module wraps Iris functionality to match the MultiAgentCoder
  agent interface, making it a drop-in replacement for Agent.Local.
  """

  require Logger

  alias MultiAgentCoder.Agent.{ContextFormatter, TokenCounter}

  @doc """
  Makes an API call to local LLM via Iris pipeline.

  ## Parameters
    * `state` - Agent worker state containing configuration
    * `prompt` - The user prompt/task
    * `context` - Additional context (previous results, files, etc.)

  ## Returns
    * `{:ok, response, usage}` - Successful response with usage statistics
    * `{:error, reason}` - Classified error with details

  ## Examples

      iex> IrisProvider.call(state, "Write a hello function", %{})
      {:ok, "def hello()...", %{input_tokens: 10, output_tokens: 50, cost: 0.0}}
  """
  def call(state, prompt, context \\ %{}) do
    Logger.info("IrisProvider: Calling #{state.model} via Iris pipeline")

    with {:ok, iris_available?} <- check_iris_availability(),
         :ok <- verify_iris_available(iris_available?),
         {:ok, enhanced_prompt} <- build_prompt(prompt, context),
         {:ok, iris_request} <- build_iris_request(state, enhanced_prompt),
         {:ok, response} <- send_request_via_iris(iris_request) do
      extract_response(response, state, prompt)
    else
      {:error, :iris_not_available} ->
        Logger.warning("IrisProvider: Iris not available, falling back to Local provider")
        {:error, {:iris_unavailable, "Iris not compiled or started"}}

      {:error, reason} = error ->
        Logger.error("IrisProvider: Request failed - #{inspect(reason)}")
        error
    end
  end

  @doc """
  Makes a streaming API call via Iris pipeline.

  Returns a stream that yields response chunks as they are generated.
  """
  def call_streaming(state, prompt, context \\ %{}) do
    Logger.info("IrisProvider: Starting streaming call with #{state.model}")

    with {:ok, iris_available?} <- check_iris_availability(),
         :ok <- verify_iris_available(iris_available?),
         {:ok, enhanced_prompt} <- build_prompt(prompt, context),
         {:ok, iris_request} <- build_iris_request(state, enhanced_prompt, stream: true),
         {:ok, stream} <- send_streaming_request_via_iris(iris_request) do
      {:ok, stream}
    end
  end

  @doc """
  Checks if Iris is available and can be used.
  """
  def check_iris_availability do
    # Check if Iris module exists and is loaded
    iris_available =
      Code.ensure_loaded?(Iris.Producer) &&
        Code.ensure_loaded?(Iris.Types.Request) &&
        Code.ensure_loaded?(Iris.Types.Response)

    {:ok, iris_available}
  end

  @doc """
  Validates that Iris is available.
  """
  def validate_iris do
    case check_iris_availability() do
      {:ok, true} -> :ok
      {:ok, false} -> {:error, :iris_not_available}
    end
  end

  # Private Functions

  defp verify_iris_available(true), do: :ok
  defp verify_iris_available(false), do: {:error, :iris_not_available}

  defp build_prompt(prompt, context) do
    system_prompt = ContextFormatter.build_system_prompt(context)
    enhanced_prompt = ContextFormatter.build_enhanced_prompt(prompt, context)

    full_prompt = """
    #{system_prompt}

    User request: #{enhanced_prompt}
    """

    {:ok, full_prompt}
  end

  defp build_iris_request(state, prompt, opts \\ []) do
    # Convert state to Iris request format
    request_params = %{
      messages: [%{role: "user", content: prompt}],
      model: state.model,
      temperature: state.temperature || 0.7,
      stream: Keyword.get(opts, :stream, false)
    }

    # Add max_tokens if specified
    request_params =
      if state.max_tokens do
        Map.put(request_params, :max_tokens, state.max_tokens)
      else
        request_params
      end

    # Create Iris request using the Types.Request module
    request = apply(Iris.Types.Request, :new, [request_params])
    {:ok, request}
  rescue
    error ->
      Logger.error("IrisProvider: Failed to build request - #{Exception.message(error)}")
      {:error, {:request_build_failed, Exception.message(error)}}
  end

  defp send_request_via_iris(iris_request) do
    # Push request to Iris Broadway pipeline
    case apply(Iris.Producer, :push_request, [iris_request]) do
      {:ok, response} ->
        {:ok, response}

      {:error, reason} ->
        {:error, {:iris_pipeline_error, reason}}

      other ->
        Logger.warning("IrisProvider: Unexpected response from Iris - #{inspect(other)}")
        {:error, {:unexpected_response, other}}
    end
  rescue
    error ->
      Logger.error("IrisProvider: Pipeline error - #{Exception.message(error)}")
      {:error, {:pipeline_error, Exception.message(error)}}
  end

  defp send_streaming_request_via_iris(iris_request) do
    # Use Iris router for streaming requests
    case apply(Iris.Providers.Router, :route_request, [iris_request]) do
      {:ok, stream} ->
        {:ok, stream}

      {:error, reason} ->
        {:error, {:iris_streaming_error, reason}}
    end
  rescue
    error ->
      Logger.error("IrisProvider: Streaming error - #{Exception.message(error)}")
      {:error, {:streaming_error, Exception.message(error)}}
  end

  defp extract_response(iris_response, state, original_prompt) do
    # Extract content from Iris response
    content =
      case iris_response do
        %{content: content} when is_binary(content) ->
          content

        %{response: content} when is_binary(content) ->
          content

        other ->
          Logger.warning("IrisProvider: Unexpected response structure - #{inspect(other)}")
          inspect(other)
      end

    # Calculate usage statistics
    # Iris may provide token counts; if not, we estimate
    usage = extract_usage(iris_response, state.model, original_prompt, content)

    Logger.info("IrisProvider: Request successful - #{usage.total_tokens} tokens")
    {:ok, content, usage}
  end

  defp extract_usage(response, model, input_text, output_text) do
    # Try to get usage from Iris response
    case response do
      %{usage: %{input_tokens: input, output_tokens: output}} ->
        %{
          input_tokens: input,
          output_tokens: output,
          total_tokens: input + output,
          model: model,
          cost: 0.0
        }

      _ ->
        # Fall back to estimation
        TokenCounter.create_usage_summary(:local, model, input_text, output_text)
    end
  end
end
