defmodule MultiAgentCoder.Monitor.Collector do
  @moduledoc """
  Collects and aggregates results from multiple agents.

  Provides utilities for comparing, ranking, and analyzing
  responses from different AI providers.
  """

  @doc """
  Compares results from multiple agents.
  """
  def compare_results(results) when is_map(results) do
    Enum.map(results, fn {provider, result} ->
      %{
        provider: provider,
        result: result,
        length: calculate_length(result),
        has_code: contains_code?(result)
      }
    end)
  end

  @doc """
  Ranks results by a given criterion.
  """
  def rank_by(results, criterion) when is_map(results) do
    results
    |> Enum.map(fn {provider, result} ->
      {provider, result, score(result, criterion)}
    end)
    |> Enum.sort_by(fn {_provider, _result, score} -> score end, :desc)
  end

  @doc """
  Finds common themes or patterns across results.
  """
  def find_commonalities(results) when is_map(results) do
    # Simple implementation - can be enhanced with NLP
    all_text =
      results
      |> Enum.map_join(" ", fn {_provider, {:ok, text}} -> text end)

    %{
      total_length: String.length(all_text),
      provider_count: map_size(results)
    }
  end

  # Private functions

  defp calculate_length({:ok, text}), do: String.length(text)
  defp calculate_length({:error, _}), do: 0

  defp contains_code?({:ok, text}) do
    String.contains?(text, "```") or
      String.contains?(text, "def ") or
      String.contains?(text, "function ")
  end

  defp contains_code?({:error, _}), do: false

  defp score({:ok, text}, :length), do: String.length(text)
  defp score({:ok, text}, :code_blocks), do: count_code_blocks(text)
  defp score({:error, _}, _), do: 0

  defp count_code_blocks(text) do
    text
    |> String.split("```")
    |> length()
    |> Kernel.-(1)
    |> div(2)
  end
end
