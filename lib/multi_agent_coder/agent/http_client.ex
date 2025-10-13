defmodule MultiAgentCoder.Agent.HTTPClient do
  @moduledoc """
  Shared HTTP client with retry logic and error handling.

  Provides reusable HTTP functionality for all AI provider integrations:
  - Exponential backoff retry logic
  - Rate limit handling
  - Timeout management
  - Error classification
  """

  require Logger

  @type retry_opts :: [
          max_retries: non_neg_integer(),
          initial_delay: non_neg_integer(),
          max_delay: non_neg_integer(),
          backoff_factor: float()
        ]

  @default_retry_opts [
    max_retries: 3,
    initial_delay: 1000,
    max_delay: 30_000,
    backoff_factor: 2.0
  ]

  @doc """
  Makes an HTTP POST request with automatic retry logic.

  ## Options
    * `:max_retries` - Maximum number of retry attempts (default: 3)
    * `:initial_delay` - Initial delay in milliseconds (default: 1000)
    * `:max_delay` - Maximum delay between retries (default: 30000)
    * `:backoff_factor` - Exponential backoff multiplier (default: 2.0)
    * `:timeout` - Request timeout in milliseconds (default: 120000)

  ## Returns
    * `{:ok, response}` - Successful response
    * `{:error, reason}` - Error with classification
  """
  @spec post_with_retry(String.t(), map(), keyword(), retry_opts()) ::
          {:ok, map()} | {:error, term()}
  def post_with_retry(url, body, headers, opts \\ []) do
    retry_opts = Keyword.merge(@default_retry_opts, Keyword.get(opts, :retry, []))
    timeout = Keyword.get(opts, :timeout, 120_000)

    req_opts = [
      json: body,
      headers: headers,
      receive_timeout: timeout
    ]

    do_request_with_retry(url, req_opts, retry_opts, 0)
  end

  @doc """
  Makes an HTTP GET request with automatic retry logic.
  """
  @spec get_with_retry(String.t(), keyword(), retry_opts()) ::
          {:ok, map()} | {:error, term()}
  def get_with_retry(url, headers, opts \\ []) do
    retry_opts = Keyword.merge(@default_retry_opts, Keyword.get(opts, :retry, []))
    timeout = Keyword.get(opts, :timeout, 30_000)

    req_opts = [
      headers: headers,
      receive_timeout: timeout
    ]

    do_get_with_retry(url, req_opts, retry_opts, 0)
  end

  # Private functions

  defp do_request_with_retry(url, req_opts, retry_opts, attempt) do
    max_retries = Keyword.get(retry_opts, :max_retries)

    case Req.post(url, req_opts) do
      {:ok, %{status: status, body: body}} when status in 200..299 ->
        {:ok, body}

      {:ok, %{status: 429} = response} when attempt < max_retries ->
        # Rate limited - retry with backoff
        delay = calculate_retry_delay(response, retry_opts, attempt)
        Logger.warning("Rate limited, retrying in #{delay}ms (attempt #{attempt + 1}/#{max_retries})")
        Process.sleep(delay)
        do_request_with_retry(url, req_opts, retry_opts, attempt + 1)

      {:ok, %{status: status} = response} when status in 500..599 and attempt < max_retries ->
        # Server error - retry with backoff
        delay = calculate_delay(retry_opts, attempt)
        Logger.warning("Server error (#{status}), retrying in #{delay}ms (attempt #{attempt + 1}/#{max_retries})")
        Process.sleep(delay)
        do_request_with_retry(url, req_opts, retry_opts, attempt + 1)

      {:ok, %{status: status, body: body}} ->
        # Non-retryable error
        {:error, classify_http_error(status, body)}

      {:error, %{reason: :timeout}} when attempt < max_retries ->
        delay = calculate_delay(retry_opts, attempt)
        Logger.warning("Request timeout, retrying in #{delay}ms (attempt #{attempt + 1}/#{max_retries})")
        Process.sleep(delay)
        do_request_with_retry(url, req_opts, retry_opts, attempt + 1)

      {:error, reason} ->
        {:error, {:network_error, reason}}
    end
  end

  defp do_get_with_retry(url, req_opts, retry_opts, attempt) do
    max_retries = Keyword.get(retry_opts, :max_retries)

    case Req.get(url, req_opts) do
      {:ok, %{status: status, body: body}} when status in 200..299 ->
        {:ok, body}

      {:ok, %{status: status} = response} when status in [429, 500, 502, 503, 504] and attempt < max_retries ->
        delay = calculate_delay(retry_opts, attempt)
        Logger.warning("HTTP #{status}, retrying in #{delay}ms (attempt #{attempt + 1}/#{max_retries})")
        Process.sleep(delay)
        do_get_with_retry(url, req_opts, retry_opts, attempt + 1)

      {:ok, %{status: status, body: body}} ->
        {:error, classify_http_error(status, body)}

      {:error, reason} when attempt < max_retries ->
        delay = calculate_delay(retry_opts, attempt)
        Logger.warning("Request failed, retrying in #{delay}ms (attempt #{attempt + 1}/#{max_retries})")
        Process.sleep(delay)
        do_get_with_retry(url, req_opts, retry_opts, attempt + 1)

      {:error, reason} ->
        {:error, {:network_error, reason}}
    end
  end

  defp calculate_delay(retry_opts, attempt) do
    initial_delay = Keyword.get(retry_opts, :initial_delay)
    max_delay = Keyword.get(retry_opts, :max_delay)
    backoff_factor = Keyword.get(retry_opts, :backoff_factor)

    delay = trunc(initial_delay * :math.pow(backoff_factor, attempt))
    min(delay, max_delay)
  end

  defp calculate_retry_delay(response, retry_opts, attempt) do
    # Check for Retry-After header
    case get_retry_after_header(response) do
      nil -> calculate_delay(retry_opts, attempt)
      seconds -> seconds * 1000
    end
  end

  defp get_retry_after_header(%{headers: headers}) do
    headers
    |> Enum.find(fn {key, _value} -> String.downcase(key) == "retry-after" end)
    |> case do
      {_key, value} ->
        case Integer.parse(value) do
          {seconds, _} -> seconds
          :error -> nil
        end

      nil ->
        nil
    end
  end

  defp classify_http_error(status, body) do
    case status do
      400 -> {:bad_request, extract_error_message(body)}
      401 -> {:unauthorized, "Invalid API key or authentication failed"}
      403 -> {:forbidden, "Access denied"}
      404 -> {:not_found, "Resource not found"}
      429 -> {:rate_limited, "Rate limit exceeded"}
      500 -> {:server_error, "Internal server error"}
      502 -> {:bad_gateway, "Bad gateway"}
      503 -> {:service_unavailable, "Service temporarily unavailable"}
      _ -> {:http_error, "HTTP #{status}: #{extract_error_message(body)}"}
    end
  end

  defp extract_error_message(body) when is_map(body) do
    body["error"]["message"] || body["error"] || inspect(body)
  end

  defp extract_error_message(body) when is_binary(body), do: body
  defp extract_error_message(_), do: "Unknown error"
end
