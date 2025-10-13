defmodule MultiAgentCoder.Agent.TokenCounter do
  @moduledoc """
  Token counting and cost estimation utilities.

  Provides approximate token counting for different AI providers
  and cost calculations based on current pricing.
  """

  @doc """
  Estimates token count for text using a simple heuristic.

  This is an approximation. For exact counts, use provider-specific APIs.
  Rule of thumb: ~4 characters per token for English text.
  """
  @spec estimate_tokens(String.t()) :: non_neg_integer()
  def estimate_tokens(text) when is_binary(text) do
    # Simple estimation: ~4 chars per token
    # This is approximate but works well for most cases
    char_count = String.length(text)
    ceil(char_count / 4)
  end

  def estimate_tokens(_), do: 0

  @doc """
  Calculates the cost of API usage based on token counts.

  ## Parameters
    * `provider` - `:openai`, `:anthropic`, or `:local`
    * `model` - Model name
    * `input_tokens` - Number of input tokens
    * `output_tokens` - Number of output tokens

  ## Returns
    Estimated cost in USD
  """
  @spec calculate_cost(atom(), String.t(), non_neg_integer(), non_neg_integer()) :: float()
  def calculate_cost(:openai, model, input_tokens, output_tokens) do
    {input_rate, output_rate} = get_openai_rates(model)
    input_tokens * input_rate + output_tokens * output_rate
  end

  def calculate_cost(:anthropic, model, input_tokens, output_tokens) do
    {input_rate, output_rate} = get_anthropic_rates(model)
    input_tokens * input_rate + output_tokens * output_rate
  end

  def calculate_cost(:local, _model, _input_tokens, _output_tokens) do
    # Local models are free
    0.0
  end

  @doc """
  Formats cost for display.
  """
  @spec format_cost(float()) :: String.t()
  def format_cost(cost) when cost < 0.01 do
    "< $0.01"
  end

  def format_cost(cost) do
    "$#{:erlang.float_to_binary(cost, decimals: 4)}"
  end

  @doc """
  Creates a usage summary map.
  """
  @spec create_usage_summary(atom(), String.t(), String.t(), String.t()) :: map()
  def create_usage_summary(provider, model, input_text, output_text) do
    input_tokens = estimate_tokens(input_text)
    output_tokens = estimate_tokens(output_text)
    cost = calculate_cost(provider, model, input_tokens, output_tokens)

    %{
      provider: provider,
      model: model,
      input_tokens: input_tokens,
      output_tokens: output_tokens,
      total_tokens: input_tokens + output_tokens,
      estimated_cost: cost,
      formatted_cost: format_cost(cost)
    }
  end

  # Private functions - Pricing as of 2024
  # These should be updated periodically or moved to config

  defp get_openai_rates("gpt-4") do
    # $0.03 per 1K input, $0.06 per 1K output
    {0.03 / 1000, 0.06 / 1000}
  end

  defp get_openai_rates("gpt-4-turbo" <> _) do
    # $0.01 per 1K input, $0.03 per 1K output
    {0.01 / 1000, 0.03 / 1000}
  end

  defp get_openai_rates("gpt-3.5-turbo" <> _) do
    # $0.0005 per 1K input, $0.0015 per 1K output
    {0.0005 / 1000, 0.0015 / 1000}
  end

  defp get_openai_rates(_) do
    # Default to GPT-4 pricing
    {0.03 / 1000, 0.06 / 1000}
  end

  defp get_anthropic_rates("claude-3-opus" <> _) do
    # $15 per 1M input, $75 per 1M output
    {15 / 1_000_000, 75 / 1_000_000}
  end

  defp get_anthropic_rates("claude-3-sonnet" <> _) do
    # $3 per 1M input, $15 per 1M output
    {3 / 1_000_000, 15 / 1_000_000}
  end

  defp get_anthropic_rates("claude-sonnet" <> _) do
    # Claude Sonnet 4 (2025 pricing): $3 per 1M input, $15 per 1M output
    {3 / 1_000_000, 15 / 1_000_000}
  end

  defp get_anthropic_rates("claude-3-haiku" <> _) do
    # $0.25 per 1M input, $1.25 per 1M output
    {0.25 / 1_000_000, 1.25 / 1_000_000}
  end

  defp get_anthropic_rates(_) do
    # Default to Sonnet pricing
    {3 / 1_000_000, 15 / 1_000_000}
  end
end
