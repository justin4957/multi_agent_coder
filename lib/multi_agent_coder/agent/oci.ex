defmodule MultiAgentCoder.Agent.OCI do
  @moduledoc """
  Oracle Cloud Infrastructure (OCI) Generative AI API integration.

  Provides enhanced API integration with:
  - Automatic retry logic with exponential backoff
  - Comprehensive error handling and classification
  - Token counting and cost tracking
  - Streaming response support (future)
  - Support for Cohere Command and Meta Llama models

  OCI Generative AI offers enterprise-grade AI services with free tier access
  and competitive pricing for coding tasks.
  """

  require Logger

  alias MultiAgentCoder.Agent.{ContextFormatter, HTTPClient, TokenCounter}

  @default_region "us-chicago-1"
  @api_version "20231130"

  @doc """
  Makes an API call to OCI Generative AI with automatic retry and error handling.

  ## Parameters
    * `state` - Agent worker state containing configuration
    * `prompt` - The user prompt/task
    * `context` - Additional context (previous results, files, etc.)

  ## Returns
    * `{:ok, response, usage}` - Successful response with usage statistics
    * `{:error, reason}` - Classified error with details

  ## Examples

      iex> OCI.call(state, "Write a hello world function", %{})
      {:ok, "def hello_world()...", %{input_tokens: 10, output_tokens: 50, cost: 0.001}}
  """
  def call(state, prompt, context \\ %{}) do
    Logger.info("OCI: Calling #{state.model}")

    with {:ok, messages} <- build_messages(prompt, context),
         {:ok, body} <- make_request(state, messages),
         {:ok, response, usage} <- extract_response(body, state, prompt) do
      Logger.info(
        "OCI: Request successful - #{usage.total_tokens} tokens, #{usage.formatted_cost}"
      )

      {:ok, response, usage}
    else
      {:error, reason} = error ->
        Logger.error("OCI: Request failed - #{inspect(reason)}")
        error
    end
  end

  @doc """
  Makes a streaming API call to OCI Generative AI.

  Note: Streaming support is planned for future implementation.
  Currently falls back to non-streaming request.
  """
  def call_streaming(state, prompt, context \\ %{}) do
    Logger.info("OCI: Streaming not yet implemented, using regular request")
    call(state, prompt, context)
  end

  @doc """
  Validates the API key by making a test request.
  """
  def validate_credentials(api_key, endpoint, compartment_id) do
    # Validate required parameters
    cond do
      is_nil(api_key) or api_key == "" ->
        {:error, :invalid_api_key}

      is_nil(endpoint) or endpoint == "" ->
        {:error, {:configuration_error, "endpoint is required"}}

      is_nil(compartment_id) or compartment_id == "" ->
        {:error, {:configuration_error, "compartment_id is required"}}

      true ->
        perform_validation_request(api_key, endpoint, compartment_id)
    end
  end

  defp perform_validation_request(api_key, endpoint, compartment_id) do
    headers = [
      {"Authorization", "Bearer #{api_key}"},
      {"Content-Type", "application/json"}
    ]

    # Make a minimal test request
    body = %{
      compartmentId: compartment_id,
      servingMode: %{
        modelId: "cohere.command-r",
        servingType: "ON_DEMAND"
      },
      chatRequest: %{
        message: "test",
        maxTokens: 10
      }
    }

    url = "#{endpoint}/#{@api_version}/actions/chat"

    case HTTPClient.post_with_retry(url, body, headers, timeout: 30_000) do
      {:ok, _response} -> :ok
      {:error, {:unauthorized, _}} -> {:error, :invalid_api_key}
      {:error, reason} -> {:error, reason}
    end
  end

  # Private functions

  defp get_endpoint(state) do
    region = Map.get(state, :region, @default_region)
    Map.get(state, :endpoint, "https://inference.generativeai.#{region}.oci.oraclecloud.com")
  end

  defp build_messages(prompt, context) do
    system_prompt = ContextFormatter.build_system_prompt(context)
    enhanced_prompt = ContextFormatter.build_enhanced_prompt(prompt, context)

    # Combine system prompt and user prompt
    full_message =
      if system_prompt && system_prompt != "" do
        "#{system_prompt}\n\n#{enhanced_prompt}"
      else
        enhanced_prompt
      end

    {:ok, full_message}
  end

  defp make_request(state, message) do
    endpoint = get_endpoint(state)
    compartment_id = Map.get(state, :compartment_id)

    if !compartment_id do
      Logger.error("OCI: Missing compartment_id in configuration")
      {:error, {:configuration_error, "compartment_id is required"}}
    else
      headers = [
        {"Authorization", "Bearer #{state.api_key}"},
        {"Content-Type", "application/json"}
      ]

      # Extract model ID and determine serving mode
      {model_id, serving_type} = parse_model_config(state.model)

      body = %{
        compartmentId: compartment_id,
        servingMode: %{
          modelId: model_id,
          servingType: serving_type
        },
        chatRequest: %{
          message: message,
          maxTokens: state.max_tokens,
          temperature: state.temperature
        }
      }

      url = "#{endpoint}/#{@api_version}/actions/chat"

      case HTTPClient.post_with_retry(url, body, headers) do
        {:ok, response_body} ->
          {:ok, response_body}

        {:error, reason} ->
          {:error, classify_error(reason)}
      end
    end
  end

  defp parse_model_config(model) when is_binary(model) do
    # Models can be specified as:
    # - "cohere.command-r" (on-demand)
    # - "cohere.command-r-plus" (on-demand)
    # - "meta.llama-3-70b-instruct" (on-demand)
    # For MVP, we only support ON_DEMAND serving type
    {model, "ON_DEMAND"}
  end

  defp extract_response(body, state, original_prompt) do
    with {:ok, content} <- extract_content(body),
         {:ok, usage_data} <- extract_usage(body) do
      # Calculate usage statistics
      input_text = original_prompt
      output_text = content

      usage = TokenCounter.create_usage_summary(:oci, state.model, input_text, output_text)

      # Merge with actual usage data if available
      usage =
        if usage_data do
          Map.merge(usage, %{
            input_tokens: usage_data["promptTokens"] || usage_data["inputTokens"],
            output_tokens: usage_data["completionTokens"] || usage_data["outputTokens"],
            total_tokens: usage_data["totalTokens"]
          })
        else
          usage
        end

      {:ok, content, usage}
    end
  end

  defp extract_content(body) do
    # OCI response format:
    # {
    #   "chatResponse": {
    #     "text": "...",
    #     ...
    #   }
    # }
    case get_in(body, ["chatResponse", "text"]) do
      nil ->
        {:error, :no_content_in_response}

      content when is_binary(content) ->
        {:ok, content}

      _ ->
        {:error, :invalid_response_format}
    end
  end

  defp extract_usage(body) do
    # OCI may provide usage in the response
    # Format: {"chatResponse": {..., "promptTokens": 10, "completionTokens": 50}}
    usage =
      case get_in(body, ["chatResponse"]) do
        nil ->
          nil

        chat_response ->
          %{
            "promptTokens" => chat_response["promptTokens"],
            "completionTokens" => chat_response["completionTokens"],
            "totalTokens" =>
              (chat_response["promptTokens"] || 0) + (chat_response["completionTokens"] || 0)
          }
      end

    {:ok, usage}
  end

  defp classify_error({:unauthorized, msg}), do: {:authentication_error, msg}
  defp classify_error({:rate_limited, msg}), do: {:rate_limit_error, msg}
  defp classify_error({:bad_request, msg}), do: {:invalid_request, msg}
  defp classify_error({:service_unavailable, msg}), do: {:service_unavailable, msg}
  defp classify_error({:network_error, reason}), do: {:network_error, reason}
  defp classify_error({:configuration_error, msg}), do: {:configuration_error, msg}
  defp classify_error(reason), do: {:unknown_error, reason}
end
