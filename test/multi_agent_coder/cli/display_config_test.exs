defmodule MultiAgentCoder.CLI.DisplayConfigTest do
  use ExUnit.Case, async: false

  alias MultiAgentCoder.CLI.DisplayConfig

  setup do
    # Save original config
    original_config = Application.get_env(:multi_agent_coder, :display, [])

    on_exit(fn ->
      # Restore original config
      Application.put_env(:multi_agent_coder, :display, original_config)
    end)

    # Reset to defaults for each test
    DisplayConfig.reset()

    :ok
  end

  describe "get/1" do
    test "returns default values for unconfigured keys" do
      assert DisplayConfig.get(:layout) == :stacked
      assert DisplayConfig.get(:show_timestamps) == true
      assert DisplayConfig.get(:color_scheme) == :provider
    end

    test "returns configured values when set" do
      DisplayConfig.set(:layout, :split_horizontal)
      assert DisplayConfig.get(:layout) == :split_horizontal
    end

    test "returns nil for unknown keys" do
      assert DisplayConfig.get(:unknown_key) == nil
    end
  end

  describe "get_all/0" do
    test "returns all configuration as a map" do
      config = DisplayConfig.get_all()

      assert is_map(config)
      assert config[:layout] == :stacked
      assert config[:show_timestamps] == true
      assert config[:max_pane_height] == 15
    end

    test "includes custom values" do
      DisplayConfig.set(:layout, :tiled)
      config = DisplayConfig.get_all()

      assert config[:layout] == :tiled
    end
  end

  describe "set/2" do
    test "sets configuration values" do
      assert DisplayConfig.set(:layout, :split_vertical) == :ok
      assert DisplayConfig.get(:layout) == :split_vertical
    end

    test "overwrites existing values" do
      DisplayConfig.set(:max_pane_height, 20)
      assert DisplayConfig.get(:max_pane_height) == 20

      DisplayConfig.set(:max_pane_height, 25)
      assert DisplayConfig.get(:max_pane_height) == 25
    end

    test "accepts various value types" do
      DisplayConfig.set(:show_timestamps, false)
      assert DisplayConfig.get(:show_timestamps) == false

      DisplayConfig.set(:max_pane_height, 30)
      assert DisplayConfig.get(:max_pane_height) == 30

      DisplayConfig.set(:layout, :tiled)
      assert DisplayConfig.get(:layout) == :tiled
    end
  end

  describe "valid_layout?/1" do
    test "returns true for valid layouts" do
      assert DisplayConfig.valid_layout?(:stacked) == true
      assert DisplayConfig.valid_layout?(:split_horizontal) == true
      assert DisplayConfig.valid_layout?(:split_vertical) == true
      assert DisplayConfig.valid_layout?(:tiled) == true
    end

    test "returns false for invalid layouts" do
      assert DisplayConfig.valid_layout?(:invalid) == false
      assert DisplayConfig.valid_layout?(:grid) == false
    end
  end

  describe "valid_color_scheme?/1" do
    test "returns true for valid color schemes" do
      assert DisplayConfig.valid_color_scheme?(:provider) == true
      assert DisplayConfig.valid_color_scheme?(:status) == true
      assert DisplayConfig.valid_color_scheme?(:monochrome) == true
    end

    test "returns false for invalid color schemes" do
      assert DisplayConfig.valid_color_scheme?(:rainbow) == false
      assert DisplayConfig.valid_color_scheme?(:custom) == false
    end
  end

  describe "defaults/0" do
    test "returns default configuration map" do
      defaults = DisplayConfig.defaults()

      assert defaults[:layout] == :stacked
      assert defaults[:show_timestamps] == true
      assert defaults[:show_token_count] == false
      assert defaults[:color_scheme] == :provider
      assert defaults[:max_pane_height] == 15
      assert defaults[:refresh_rate] == 100
      assert defaults[:show_progress] == true
      assert defaults[:compact_mode] == false
    end
  end

  describe "reset/0" do
    test "resets all configuration to defaults" do
      # Set some custom values
      DisplayConfig.set(:layout, :tiled)
      DisplayConfig.set(:show_timestamps, false)
      DisplayConfig.set(:max_pane_height, 30)

      # Reset
      DisplayConfig.reset()

      # Verify defaults are restored
      assert DisplayConfig.get(:layout) == :stacked
      assert DisplayConfig.get(:show_timestamps) == true
      assert DisplayConfig.get(:max_pane_height) == 15
    end
  end
end
