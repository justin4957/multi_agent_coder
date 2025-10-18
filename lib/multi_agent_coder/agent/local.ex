defmodule MultiAgentCoder.Agent.Local do
  @moduledoc """
  Local LLM integration via Ollama.

  Provides enhanced integration with locally-hosted language models:
  - Automatic retry logic with exponential backoff
  - Server health checking
  - Comprehensive error handling
  - Token counting (estimated)
  - Streaming response support
  - Model availability checking
  """

  require Logger

  alias MultiAgentCoder.Agent.{ContextFormatter, HTTPClient, TokenCounter}

  @default_endpoint "http://localhost:11434"

  @doc """
  Makes an API call to a local LLM server with automatic retry and error handling.

  ## Parameters
    * `state` - Agent worker state containing configuration
    * `prompt` - The user prompt/task
    * `context` - Additional context (previous results, files, etc.)

  ## Returns
    * `{:ok, response, usage}` - Successful response with usage statistics
    * `{:error, reason}` - Classified error with details

  ## Examples

      iex> Local.call(state, "Write a hello world function", %{})
      {:ok, "def hello_world()...", %{input_tokens: 10, output_tokens: 50, cost: 0.0}}
  """
  def call(state, prompt, context \\ %{}) do
    Logger.info("Local: Calling #{state.model} at #{get_endpoint(state)}")

    with :ok <- check_server_health(state),
         {:ok, enhanced_prompt} <- build_prompt(prompt, context),
         {:ok, body} <- make_request(state, enhanced_prompt),
         {:ok, response, usage} <- extract_response(body, state, prompt) do
      Logger.info("Local: Request successful - #{usage.total_tokens} tokens (estimated)")
      {:ok, response, usage}
    else
      {:error, reason} = error ->
        Logger.error("Local: Request failed - #{inspect(reason)}")
        error
    end
  end

  @doc """
  Makes a streaming API call to the local LLM server.

  Returns chunks of the response as they are generated.
  """
  def call_streaming(state, prompt, context \\ %{}) do
    Logger.info("Local: Starting streaming call with #{state.model}")

    with :ok <- check_server_health(state),
         {:ok, enhanced_prompt} <- build_prompt(prompt, context) do
      stream_request(state, enhanced_prompt)
    end
  end

  @doc """
  Checks if the Ollama server is running and accessible.
  """
  def check_server_health(state) do
    endpoint = get_endpoint(state)
    url = "#{endpoint}/api/tags"

    case HTTPClient.get_with_retry(url, [], timeout: 5000, retry: [max_retries: 1]) do
      {:ok, _models} ->
        :ok

      {:error, {:network_error, _}} ->
        {:error, {:server_unreachable, "Ollama server not running at #{endpoint}"}}

      {:error, reason} ->
        {:error, {:server_error, reason}}
    end
  end

  @doc """
  Validates that the local server is accessible.
  """
  def validate_credentials(endpoint \\ @default_endpoint) do
    url = "#{endpoint}/api/tags"

    case HTTPClient.get_with_retry(url, [], timeout: 5_000, retry: [max_retries: 1]) do
      {:ok, _} -> :ok
      {:error, _} -> {:error, :local_server_unavailable}
    end
  end

  @doc """
  Lists available models on the Ollama server.
  """
  def list_models(endpoint \\ @default_endpoint) do
    url = "#{endpoint}/api/tags"

    case HTTPClient.get_with_retry(url, [], timeout: 5000) do
      {:ok, %{"models" => models}} ->
        {:ok, Enum.map(models, & &1["name"])}

      {:ok, _response} ->
        {:ok, []}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Pulls/downloads a model from the Ollama library.
  """
  def pull_model(model, endpoint \\ @default_endpoint) do
    Logger.info("Local: Pulling model #{model}")

    headers = [{"Content-Type", "application/json"}]

    body = %{
      name: model,
      stream: false
    }

    url = "#{endpoint}/api/pull"

    case HTTPClient.post_with_retry(url, body, headers, timeout: 300_000) do
      {:ok, _response} ->
        Logger.info("Local: Successfully pulled model #{model}")
        :ok

      {:error, reason} ->
        Logger.error("Local: Failed to pull model #{model} - #{inspect(reason)}")
        {:error, reason}
    end
  end

  # Private functions

  defp get_endpoint(state) do
    state.endpoint || @default_endpoint
  end

  defp build_prompt(prompt, context) do
    system_prompt = ContextFormatter.build_system_prompt(context)
    enhanced_prompt = ContextFormatter.build_enhanced_prompt(prompt, context)

    full_prompt = """
    #{system_prompt}

    User request: #{enhanced_prompt}
    """

    {:ok, full_prompt}
  end

  defp make_request(state, prompt) do
    endpoint = get_endpoint(state)
    headers = [{"Content-Type", "application/json"}]

    body = %{
      model: state.model,
      prompt: prompt,
      temperature: state.temperature,
      stream: false
    }

    # Add max_tokens if supported by the model
    body =
      if state.max_tokens do
        Map.put(body, :options, %{num_predict: state.max_tokens})
      else
        body
      end

    url = "#{endpoint}/api/generate"

    case HTTPClient.post_with_retry(url, body, headers, timeout: 120_000) do
      {:ok, response_body} ->
        {:ok, response_body}

      {:error, reason} ->
        {:error, classify_error(reason)}
    end
  end

  defp stream_request(state, prompt) do
    # Streaming implementation would use chunked responses
    # For now, fall back to regular request
    Logger.warning("Local: Streaming not yet fully implemented, using regular request")

    case make_request(state, prompt) do
      {:ok, body} -> extract_response(body, state, prompt)
      error -> error
    end
  end

  defp extract_response(body, state, original_prompt) do
    with {:ok, content} <- extract_content(body) do
      # Calculate estimated usage statistics
      # Local models don't return token counts, so we estimate
      input_text = original_prompt
      output_text = content

      usage = TokenCounter.create_usage_summary(:local, state.model, input_text, output_text)

      {:ok, content, usage}
    end
  end

  defp extract_content(body) do
    case Map.get(body, "response") do
      nil ->
        {:error, :no_response_in_body}

      response when is_binary(response) and response != "" ->
        {:ok, response}

      _ ->
        {:error, :empty_response}
    end
  end

  defp classify_error({:network_error, _reason}),
    do: {:server_unreachable, "Cannot connect to Ollama server"}

  defp classify_error({:server_unreachable, msg}), do: {:server_unreachable, msg}
  defp classify_error({:bad_request, msg}), do: {:invalid_request, msg}
  defp classify_error({:not_found, _}), do: {:model_not_found, "Model not found on Ollama server"}
  defp classify_error({:service_unavailable, msg}), do: {:service_unavailable, msg}
  defp classify_error(reason), do: {:unknown_error, reason}
end
