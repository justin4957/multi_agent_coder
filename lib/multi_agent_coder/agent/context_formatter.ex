defmodule MultiAgentCoder.Agent.ContextFormatter do
  @moduledoc """
  Utilities for formatting conversation context and previous results.

  Provides reusable context formatting functions for all AI providers.
  """

  @doc """
  Builds a system prompt with optional context from previous results.
  """
  @spec build_system_prompt(map(), String.t()) :: String.t()
  def build_system_prompt(context, base_prompt \\ default_system_prompt()) do
    case Map.get(context, :previous_results) do
      nil ->
        base_prompt

      results when map_size(results) > 0 ->
        """
        #{base_prompt}

        PREVIOUS AGENT RESPONSES FOR CONTEXT:
        #{format_previous_results(results)}

        Use these previous responses to inform your answer, but provide your own unique perspective and solution.
        """

      _ ->
        base_prompt
    end
  end

  @doc """
  Formats previous agent results for inclusion in prompts.
  """
  @spec format_previous_results(map()) :: String.t()
  def format_previous_results(results) when is_map(results) do
    results
    |> Enum.map(&format_single_result/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.join("\n\n---\n\n")
  end

  def format_previous_results(_), do: ""

  @doc """
  Extracts file context from the context map.
  """
  @spec extract_file_context(map()) :: String.t()
  def extract_file_context(context) do
    case Map.get(context, :files) do
      nil ->
        ""

      files when is_list(files) ->
        """

        RELEVANT FILES:
        #{format_files(files)}
        """

      _ ->
        ""
    end
  end

  @doc """
  Builds a complete enhanced prompt with all context.
  """
  @spec build_enhanced_prompt(String.t(), map()) :: String.t()
  def build_enhanced_prompt(base_prompt, context) do
    file_context = extract_file_context(context)
    previous_context = format_previous_context(context)

    [base_prompt, file_context, previous_context]
    |> Enum.reject(&(&1 == ""))
    |> Enum.join("\n\n")
  end

  @doc """
  Default system prompt for coding tasks.
  """
  @spec default_system_prompt() :: String.t()
  def default_system_prompt do
    """
    You are an expert software engineer with deep knowledge of multiple programming languages and paradigms.

    When providing code solutions:
    - Use descriptive variable names for clarity
    - Prioritize composability and reusability
    - Aim for abstraction that facilitates future application
    - Include clear documentation and comments
    - Consider edge cases and error handling
    - Follow best practices and idiomatic patterns

    Provide clear, well-documented, and production-ready code.
    """
  end

  # Private functions

  defp format_single_result({provider, {:ok, response}}) when is_binary(response) do
    """
    [#{format_provider_name(provider)}]
    #{String.slice(response, 0, 1000)}#{if String.length(response) > 1000, do: "...", else: ""}
    """
  end

  defp format_single_result({provider, {:error, reason}}) do
    "[#{format_provider_name(provider)}] Error: #{inspect(reason)}"
  end

  defp format_single_result(_), do: nil

  defp format_provider_name(provider) do
    provider
    |> to_string()
    |> String.upcase()
  end

  defp format_files(files) when is_list(files) do
    files
    |> Enum.map(&format_file/1)
    |> Enum.join("\n\n")
  end

  defp format_file(%{path: path, content: content}) do
    """
    File: #{path}
    ```
    #{content}
    ```
    """
  end

  defp format_file(path) when is_binary(path) do
    "File: #{path}"
  end

  defp format_file(_), do: ""

  defp format_previous_context(context) do
    case Map.get(context, :previous_results) do
      nil -> ""
      results when map_size(results) == 0 -> ""
      results -> "\n\nPREVIOUS RESPONSES:\n#{format_previous_results(results)}"
    end
  end
end
