defmodule MultiAgentCoder.CLI.ConcurrentDisplayTest do
  use ExUnit.Case, async: false

  alias MultiAgentCoder.CLI.ConcurrentDisplay

  setup do
    # Start the ConcurrentDisplay GenServer for testing
    {:ok, _pid} = start_supervised(ConcurrentDisplay)

    :ok
  end

  describe "initialization" do
    test "starts with empty state" do
      state = ConcurrentDisplay.get_state()

      assert state.providers == []
      assert state.provider_states == %{}
      assert state.provider_content == %{}
      assert state.provider_start_times == %{}
    end

    test "loads display configuration" do
      state = ConcurrentDisplay.get_state()

      assert is_map(state.config)
      assert Map.has_key?(state.config, :layout)
      assert Map.has_key?(state.config, :show_timestamps)
    end

    test "detects terminal dimensions" do
      state = ConcurrentDisplay.get_state()

      assert is_integer(state.terminal_width)
      assert is_integer(state.terminal_height)
      assert state.terminal_width > 0
      assert state.terminal_height > 0
    end
  end

  describe "start_display/2" do
    test "initializes provider states" do
      providers = [:openai, :anthropic]

      ConcurrentDisplay.start_display(providers)

      state = ConcurrentDisplay.get_state()

      assert state.providers == providers
      assert Map.has_key?(state.provider_states, :openai)
      assert Map.has_key?(state.provider_states, :anthropic)
      assert state.provider_states[:openai] == :working
      assert state.provider_states[:anthropic] == :working
    end

    test "initializes provider content as empty strings" do
      providers = [:openai]

      ConcurrentDisplay.start_display(providers)

      state = ConcurrentDisplay.get_state()

      assert state.provider_content[:openai] == ""
    end

    test "sets display mode from options" do
      providers = [:openai, :anthropic]

      ConcurrentDisplay.start_display(providers, display_mode: :split_horizontal)

      state = ConcurrentDisplay.get_state()

      assert state.display_mode == :split_horizontal
    end

    test "sets focused provider to first provider" do
      providers = [:openai, :anthropic]

      ConcurrentDisplay.start_display(providers)

      state = ConcurrentDisplay.get_state()

      assert state.focused_provider == :openai
    end

    test "initializes scroll positions" do
      providers = [:openai, :anthropic]

      ConcurrentDisplay.start_display(providers)

      state = ConcurrentDisplay.get_state()

      assert state.scroll_positions[:openai] == 0
      assert state.scroll_positions[:anthropic] == 0
    end
  end

  describe "stop_display/0" do
    test "returns final results" do
      providers = [:openai]
      ConcurrentDisplay.start_display(providers)

      results = ConcurrentDisplay.stop_display()

      assert is_map(results)
      assert Map.has_key?(results, :provider_content)
      assert Map.has_key?(results, :provider_states)
    end

    test "clears provider list" do
      providers = [:openai]
      ConcurrentDisplay.start_display(providers)
      ConcurrentDisplay.stop_display()

      state = ConcurrentDisplay.get_state()

      assert state.providers == []
    end
  end

  describe "handle_info for chunk messages" do
    test "appends content chunks" do
      providers = [:openai]
      ConcurrentDisplay.start_display(providers)

      # Simulate receiving a chunk
      send(ConcurrentDisplay, {:chunk, %{provider: :openai, chunk: "Hello "}})
      Process.sleep(50)

      state = ConcurrentDisplay.get_state()
      assert state.provider_content[:openai] == "Hello "

      # Simulate receiving another chunk
      send(ConcurrentDisplay, {:chunk, %{provider: :openai, chunk: "World"}})
      Process.sleep(50)

      state = ConcurrentDisplay.get_state()
      assert state.provider_content[:openai] == "Hello World"
    end
  end

  describe "handle_info for complete messages" do
    test "marks provider as complete" do
      providers = [:openai]
      ConcurrentDisplay.start_display(providers)

      # Simulate completion
      send(ConcurrentDisplay, {:complete, %{provider: :openai, response: "Final response"}})
      Process.sleep(50)

      state = ConcurrentDisplay.get_state()

      assert state.provider_states[:openai] == :complete
      assert state.provider_content[:openai] == "Final response"
    end
  end

  describe "handle_info for error messages" do
    test "marks provider as error" do
      providers = [:openai]
      ConcurrentDisplay.start_display(providers)

      # Simulate error
      send(ConcurrentDisplay, {:error, %{provider: :openai, message: "API timeout"}})
      Process.sleep(50)

      state = ConcurrentDisplay.get_state()

      assert state.provider_states[:openai] == :error
      assert state.provider_content[:openai] =~ "ERROR: API timeout"
    end
  end

  describe "configuration integration" do
    test "uses configured layout by default" do
      # The display should respect configured layout
      providers = [:openai, :anthropic]

      ConcurrentDisplay.start_display(providers)

      state = ConcurrentDisplay.get_state()

      # Should use config layout (default is :stacked)
      assert state.display_mode == :stacked
    end

    test "allows override of configured layout" do
      providers = [:openai, :anthropic]

      ConcurrentDisplay.start_display(providers, display_mode: :tiled)

      state = ConcurrentDisplay.get_state()

      assert state.display_mode == :tiled
    end
  end
end
