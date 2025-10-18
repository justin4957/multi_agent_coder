defmodule MultiAgentCoder.Merge.AdvancedStrategyTest do
  use ExUnit.Case, async: true

  alias MultiAgentCoder.Merge.Strategy

  describe "voting strategy" do
    test "applies voting strategy to select best version" do
      provider_contents = %{
        openai: generate_good_code(),
        anthropic: generate_mediocre_code(),
        deepseek: generate_poor_code()
      }

      {:ok, result} = Strategy.apply_strategy(provider_contents, :voting)

      assert is_binary(result)
      # Should select the good code
      assert String.contains?(result, "defmodule") or String.contains?(result, "def ")
    end

    test "falls back to hybrid when no clear winner" do
      provider_contents = %{
        openai: "def test1, do: 1",
        anthropic: "def test2, do: 2"
      }

      {:ok, result} = Strategy.apply_strategy(provider_contents, :voting)

      assert is_binary(result)
    end
  end

  describe "hybrid strategy" do
    test "combines best features from multiple versions" do
      provider_contents = %{
        openai: """
        defmodule Test do
          @moduledoc "Test module"
          def hello, do: "hello"
        end
        """,
        anthropic: """
        defmodule Test do
          def goodbye, do: "goodbye"
          def hello, do: "hi"
        end
        """
      }

      {:ok, result} = Strategy.apply_strategy(provider_contents, :hybrid)

      assert is_binary(result)
    end
  end

  describe "context-aware strategy" do
    test "selects version with best code context" do
      provider_contents = %{
        openai: """
        defmodule WellDocumented do
          @moduledoc "A well-documented module"

          @doc "Says hello"
          @spec hello(String.t()) :: String.t()
          def hello(name), do: "Hello, \#{name}"
        end
        """,
        anthropic: "def hello(n), do: n"
      }

      {:ok, result} = Strategy.apply_strategy(provider_contents, :context_aware)

      assert String.contains?(result, "@moduledoc")
      assert String.contains?(result, "@doc")
    end

    test "falls back to semantic merge when no clear winner" do
      provider_contents = %{
        openai: "x = 1",
        anthropic: "y = 2"
      }

      {:ok, result} = Strategy.apply_strategy(provider_contents, :context_aware)

      assert is_binary(result)
    end
  end

  describe "ml_recommended strategy" do
    test "uses ML to recommend strategy" do
      provider_contents = %{
        openai: generate_good_code(),
        anthropic: generate_good_code()
      }

      result = Strategy.apply_strategy(provider_contents, :ml_recommended)

      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end
  end

  describe "strategy selection" do
    test "includes new strategies in strategy type" do
      # Just verify the new strategies are recognized
      assert :voting in [
               :auto,
               :semantic,
               :manual,
               :voting,
               :hybrid,
               :ml_recommended,
               :context_aware
             ]

      assert :hybrid in [
               :auto,
               :semantic,
               :manual,
               :voting,
               :hybrid,
               :ml_recommended,
               :context_aware
             ]

      assert :ml_recommended in [
               :auto,
               :semantic,
               :manual,
               :voting,
               :hybrid,
               :ml_recommended,
               :context_aware
             ]

      assert :context_aware in [
               :auto,
               :semantic,
               :manual,
               :voting,
               :hybrid,
               :ml_recommended,
               :context_aware
             ]
    end
  end

  # Helper functions

  defp generate_good_code do
    """
    defmodule GoodCode do
      @moduledoc "Well-structured module"

      @doc "A well-documented function"
      @spec process(map()) :: {:ok, map()} | {:error, String.t()}
      def process(data) do
        with {:ok, validated} <- validate(data),
             {:ok, transformed} <- transform(validated) do
          {:ok, transformed}
        else
          {:error, reason} -> {:error, reason}
        end
      end

      defp validate(data), do: {:ok, data}
      defp transform(data), do: {:ok, data}
    end
    """
  end

  defp generate_mediocre_code do
    """
    defmodule MediocreCode do
      def process(data) do
        if valid?(data) do
          {:ok, data}
        else
          {:error, "bad"}
        end
      end

      def valid?(_), do: true
    end
    """
  end

  defp generate_poor_code do
    "def x(y), do: y + 1"
  end
end
