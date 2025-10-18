defmodule MultiAgentCoder.Agent.ProviderHealth do
  @moduledoc """
  Provider health checking and validation.

  Provides functionality to:
  - Validate API keys before task execution
  - Check provider availability
  - Report provider status with actionable guidance
  - Pre-flight checks before routing tasks
  """

  require Logger

  alias MultiAgentCoder.Agent.{Anthropic, DeepSeek, Local, OCI, OpenAI, Perplexity}

  @doc """
  Validates all configured providers and returns a health status map.

  ## Returns
    Map with provider names as keys and status tuples as values:
    - `{:ok, :healthy}` - Provider is ready
    - `{:error, reason}` - Provider has issues
  """
  def check_all_providers do
    providers = get_configured_providers()

    providers
    |> Enum.map(fn {provider_name, config} ->
      status = check_provider(provider_name, config)
      {provider_name, status}
    end)
    |> Map.new()
  end

  @doc """
  Checks health of a specific provider.

  ## Parameters
    - provider_name: Atom representing the provider (:openai, :anthropic, etc.)
    - config: Provider configuration map

  ## Returns
    - `{:ok, :healthy}` if provider is ready
    - `{:error, reason}` if provider has issues
  """
  def check_provider(provider_name, config) do
    api_key = get_api_key(config)

    cond do
      is_nil(api_key) or api_key == "" ->
        {:error, :missing_api_key}

      provider_name == :local ->
        # Local provider doesn't need API key validation
        check_local_provider(config)

      true ->
        validate_provider_credentials(provider_name, config)
    end
  rescue
    error ->
      Logger.error("Provider health check failed for #{provider_name}: #{inspect(error)}")
      {:error, {:health_check_failed, Exception.message(error)}}
  end

  @doc """
  Filters providers to only include healthy ones.

  ## Parameters
    - requested_providers: List of requested provider names
    - health_status: Map of provider health statuses

  ## Returns
    Tuple of {healthy_providers, failed_providers}
  """
  def filter_healthy_providers(requested_providers, health_status) do
    {healthy, failed} =
      Enum.split_with(requested_providers, fn provider ->
        case Map.get(health_status, provider) do
          {:ok, :healthy} -> true
          _ -> false
        end
      end)

    {healthy, failed}
  end

  @doc """
  Gets actionable error message for a provider failure.
  """
  def get_error_guidance(provider_name, error_reason) do
    base_msg = format_error_message(provider_name, error_reason)
    guidance = get_resolution_steps(provider_name, error_reason)

    """
    #{base_msg}

    #{guidance}
    """
  end

  @doc """
  Formats provider health status for display.
  """
  def format_health_status(health_status) do
    health_status
    |> Enum.map(fn {provider, status} ->
      format_provider_status(provider, status)
    end)
    |> Enum.join("\n")
  end

  # Private Functions

  defp get_configured_providers do
    Application.get_env(:multi_agent_coder, :providers, [])
  end

  defp get_api_key(config) do
    case Keyword.get(config, :api_key) do
      {:system, env_var} -> System.get_env(env_var)
      api_key when is_binary(api_key) -> api_key
      _ -> nil
    end
  end

  defp validate_provider_credentials(provider_name, config) do
    api_key = get_api_key(config)
    model = Keyword.get(config, :model)

    result =
      case provider_name do
        :openai ->
          OpenAI.validate_credentials(api_key, model)

        :anthropic ->
          Anthropic.validate_credentials(api_key)

        :deepseek ->
          DeepSeek.validate_credentials(api_key)

        :perplexity ->
          Perplexity.validate_credentials(api_key)

        :oci ->
          endpoint = build_oci_endpoint(config)
          compartment_id = get_compartment_id(config)
          OCI.validate_credentials(api_key, endpoint, compartment_id)

        :local ->
          endpoint = Keyword.get(config, :endpoint, "http://localhost:11434")
          Local.validate_credentials(endpoint)

        _ ->
          {:error, :unsupported_provider}
      end

    case result do
      :ok -> {:ok, :healthy}
      {:error, reason} -> {:error, reason}
    end
  end

  defp check_local_provider(config) do
    endpoint = Keyword.get(config, :endpoint, "http://localhost:11434")
    Local.validate_credentials(endpoint)
  rescue
    _ -> {:error, :local_server_unavailable}
  end

  defp build_oci_endpoint(config) do
    region = get_config_value(config, :region, "us-chicago-1")
    "https://inference.generativeai.#{region}.oci.oraclecloud.com"
  end

  defp get_compartment_id(config) do
    get_config_value(config, :compartment_id, nil)
  end

  defp get_config_value(config, key, default) do
    case Keyword.get(config, key) do
      {:system, env_var} -> System.get_env(env_var) || default
      value -> value || default
    end
  end

  defp format_error_message(provider_name, error_reason) do
    provider_display = provider_name |> to_string() |> String.capitalize()

    case error_reason do
      :missing_api_key ->
        "❌ #{provider_display}: API key not configured"

      :invalid_api_key ->
        "❌ #{provider_display}: Invalid API key or authentication failed"

      :model_not_found ->
        "❌ #{provider_display}: Model not found or not accessible"

      :local_server_unavailable ->
        "❌ #{provider_display}: Local server not responding"

      {:health_check_failed, msg} ->
        "❌ #{provider_display}: Health check failed - #{msg}"

      other ->
        "❌ #{provider_display}: #{inspect(other)}"
    end
  end

  defp get_resolution_steps(provider_name, error_reason) do
    case {provider_name, error_reason} do
      {_, :missing_api_key} ->
        """
        → Set your API key in environment variables or configuration
        → Run './multi_agent_coder --setup' to configure interactively
        → Check ~/.multi_agent_coder/config.exs for current configuration
        """

      {:openai, :invalid_api_key} ->
        """
        → Verify your OpenAI API key at https://platform.openai.com/api-keys
        → Ensure the key has proper permissions
        → Run './multi_agent_coder --setup' to update your key
        """

      {:anthropic, :invalid_api_key} ->
        """
        → Verify your Anthropic API key at https://console.anthropic.com
        → Get a new key if needed
        → Run './multi_agent_coder --setup' to update your key
        """

      {:deepseek, :invalid_api_key} ->
        """
        → Verify your DeepSeek API key at https://platform.deepseek.com
        → Ensure your account has active credits
        → Run './multi_agent_coder --setup' to update your key
        """

      {:perplexity, :invalid_api_key} ->
        """
        → Verify your Perplexity API key at https://www.perplexity.ai/settings/api
        → Check if your subscription is active
        → Run './multi_agent_coder --setup' to update your key
        """

      {:local, :local_server_unavailable} ->
        """
        → Start your local LLM server (e.g., Ollama)
        → Check if the endpoint is correct in configuration
        → Verify the model is downloaded: 'ollama pull <model-name>'
        """

      {:oci, _} ->
        """
        → Verify your OCI credentials and compartment ID
        → Check https://cloud.oracle.com for account status
        → Run './multi_agent_coder --setup' to reconfigure
        """

      _ ->
        """
        → Check your internet connection
        → Verify the provider's service status
        → Run './multi_agent_coder --setup' to reconfigure
        """
    end
  end

  defp format_provider_status(provider, {:ok, :healthy}) do
    provider_display = provider |> to_string() |> String.capitalize()
    "✓ #{provider_display} - Ready"
  end

  defp format_provider_status(provider, {:error, reason}) do
    format_error_message(provider, reason)
  end
end
