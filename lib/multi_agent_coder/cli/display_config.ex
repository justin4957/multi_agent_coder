defmodule MultiAgentCoder.CLI.DisplayConfig do
  @moduledoc """
  Configuration management for concurrent display preferences.

  Provides centralized configuration for display layout, colors,
  and behavior customization.

  ## Configuration Options

  ```elixir
  config :multi_agent_coder, :display,
    layout: :stacked,           # :stacked, :split_horizontal, :split_vertical, :tiled
    show_timestamps: true,      # Show elapsed time per provider
    show_token_count: false,    # Show token usage (if available)
    color_scheme: :provider,    # :provider, :status, :monochrome
    max_pane_height: 15,        # Maximum lines per pane in stacked mode
    refresh_rate: 100,          # Display refresh rate in milliseconds
    show_progress: true,        # Show streaming progress indicators
    compact_mode: false         # Reduced spacing for more content
  ```

  ## Examples

      iex> DisplayConfig.get(:layout)
      :stacked

      iex> DisplayConfig.get(:show_timestamps)
      true

      iex> DisplayConfig.set(:layout, :split_horizontal)
      :ok
  """

  @default_config %{
    layout: :stacked,
    show_timestamps: true,
    show_token_count: false,
    color_scheme: :provider,
    max_pane_height: 15,
    refresh_rate: 100,
    show_progress: true,
    compact_mode: false
  }

  @doc """
  Gets a display configuration value.

  Returns the configured value or the default if not set.
  """
  @spec get(atom()) :: term()
  def get(key) when is_atom(key) do
    display_config = Application.get_env(:multi_agent_coder, :display, [])
    Keyword.get(display_config, key, Map.get(@default_config, key))
  end

  @doc """
  Gets all display configuration as a map.
  """
  @spec get_all() :: map()
  def get_all do
    display_config = Application.get_env(:multi_agent_coder, :display, [])
    Enum.into(display_config, @default_config)
  end

  @doc """
  Sets a display configuration value.

  Note: This only sets the value for the current session.
  For persistent configuration, update config/config.exs.
  """
  @spec set(atom(), term()) :: :ok
  def set(key, value) when is_atom(key) do
    display_config = Application.get_env(:multi_agent_coder, :display, [])
    updated_config = Keyword.put(display_config, key, value)
    Application.put_env(:multi_agent_coder, :display, updated_config)
    :ok
  end

  @doc """
  Validates a layout mode.
  """
  @spec valid_layout?(atom()) :: boolean()
  def valid_layout?(layout) do
    layout in [:stacked, :split_horizontal, :split_vertical, :tiled]
  end

  @doc """
  Validates a color scheme.
  """
  @spec valid_color_scheme?(atom()) :: boolean()
  def valid_color_scheme?(scheme) do
    scheme in [:provider, :status, :monochrome]
  end

  @doc """
  Returns the default configuration.
  """
  @spec defaults() :: map()
  def defaults, do: @default_config

  @doc """
  Resets all display configuration to defaults.
  """
  @spec reset() :: :ok
  def reset do
    Application.put_env(:multi_agent_coder, :display, Enum.into(@default_config, []))
    :ok
  end
end
