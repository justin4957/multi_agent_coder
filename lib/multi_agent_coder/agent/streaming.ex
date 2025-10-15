defmodule MultiAgentCoder.Agent.Streaming do
  @moduledoc """
  Streaming protocol for real-time AI response delivery.

  Defines callbacks and utilities for streaming responses from AI providers
  with real-time PubSub broadcasting of chunks.

  ## Streaming Protocol

  Providers implementing streaming should:
  1. Break responses into chunks as they arrive from the API
  2. Broadcast chunks via PubSub to agent topic
  3. Accumulate chunks to build complete response
  4. Broadcast completion with full response and usage stats

  ## Message Format

  Streaming chunks:
  ```elixir
  {:chunk, %{
    provider: :openai,
    chunk: "text content",
    timestamp: System.monotonic_time(:millisecond)
  }}
  ```

  Completion:
  ```elixir
  {:complete, %{
    provider: :openai,
    response: "full response text",
    usage: %{input_tokens: 100, output_tokens: 200, ...}
  }}
  ```

  Error:
  ```elixir
  {:error, %{
    provider: :openai,
    reason: :network_error,
    message: "Connection failed"
  }}
  ```
  """

  @doc """
  Broadcasts a streaming chunk to subscribers.

  ## Parameters
    * `provider` - The provider name (atom)
    * `chunk` - The text chunk to broadcast
    * `metadata` - Optional metadata map
  """
  def broadcast_chunk(provider, chunk, metadata \\ %{}) do
    message =
      {:chunk,
       Map.merge(metadata, %{
         provider: provider,
         chunk: chunk,
         timestamp: System.monotonic_time(:millisecond)
       })}

    Phoenix.PubSub.broadcast(
      MultiAgentCoder.PubSub,
      "agent:#{provider}",
      message
    )
  end

  @doc """
  Broadcasts streaming completion.

  ## Parameters
    * `provider` - The provider name (atom)
    * `response` - The complete response text
    * `usage` - Usage statistics map
  """
  def broadcast_complete(provider, response, usage) do
    message =
      {:complete,
       %{
         provider: provider,
         response: response,
         usage: usage,
         timestamp: System.monotonic_time(:millisecond)
       }}

    Phoenix.PubSub.broadcast(
      MultiAgentCoder.PubSub,
      "agent:#{provider}",
      message
    )
  end

  @doc """
  Broadcasts an error during streaming.

  ## Parameters
    * `provider` - The provider name (atom)
    * `reason` - Error reason (atom)
    * `message` - Human-readable error message
  """
  def broadcast_error(provider, reason, message) do
    error_message =
      {:error,
       %{
         provider: provider,
         reason: reason,
         message: message,
         timestamp: System.monotonic_time(:millisecond)
       }}

    Phoenix.PubSub.broadcast(
      MultiAgentCoder.PubSub,
      "agent:#{provider}",
      error_message
    )
  end

  @doc """
  Handles Server-Sent Events (SSE) stream parsing.

  Parses SSE format used by OpenAI, Anthropic, and other providers.

  ## Format
  ```
  data: {"chunk": "text"}

  data: [DONE]
  ```
  """
  def parse_sse_line("data: [DONE]"), do: :done

  def parse_sse_line("data: " <> json) do
    case Jason.decode(json) do
      {:ok, data} -> {:ok, data}
      {:error, _} -> :skip
    end
  end

  def parse_sse_line(_), do: :skip

  @doc """
  Creates a streaming HTTP request with the Req library.

  Returns a stream that yields response chunks.
  """
  def create_stream_request(url, headers, body) do
    Stream.resource(
      fn -> start_stream(url, headers, body) end,
      &process_stream/1,
      &cleanup_stream/1
    )
  end

  # Private stream handling functions

  defp start_stream(url, headers, body) do
    case Req.post(url,
           headers: headers,
           json: body,
           into: :self,
           receive_timeout: 60_000
         ) do
      {:ok, %Req.Response{status: 200} = response} ->
        {:ok, response}

      {:ok, %Req.Response{status: status, body: error_body}} ->
        {:error, {status, error_body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp process_stream({:ok, response}) do
    receive do
      {:data, data} ->
        {[data], {:ok, response}}

      {:done} ->
        {:halt, {:ok, response}}

      {:error, reason} ->
        {:halt, {:error, reason}}
    after
      60_000 ->
        {:halt, {:error, :timeout}}
    end
  end

  defp process_stream({:error, _} = error) do
    {:halt, error}
  end

  defp cleanup_stream(_state) do
    :ok
  end
end
