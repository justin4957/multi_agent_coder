defmodule MultiAgentCoder.CLI.ConfigSetup do
  @moduledoc """
  Interactive configuration setup for MultiAgent Coder.

  Prompts users for API keys and configuration on first run,
  saves configuration to ~/.multi_agent_coder/config.exs,
  and loads it on subsequent runs.
  """

  require Logger

  @config_dir Path.expand("~/.multi_agent_coder")
  @config_file Path.join(@config_dir, "config.exs")

  @providers [
    %{
      name: :openai,
      display_name: "OpenAI",
      key_env: "OPENAI_API_KEY",
      key_prompt: "OpenAI API Key",
      models: ["gpt-4", "gpt-4-turbo", "gpt-3.5-turbo"],
      default_model: "gpt-4",
      optional: false
    },
    %{
      name: :anthropic,
      display_name: "Anthropic",
      key_env: "ANTHROPIC_API_KEY",
      key_prompt: "Anthropic API Key",
      models: ["claude-sonnet-4-5", "claude-3-5-sonnet-20241022", "claude-3-opus-20240229"],
      default_model: "claude-sonnet-4-5",
      optional: false
    },
    %{
      name: :deepseek,
      display_name: "DeepSeek",
      key_env: "DEEPSEEK_API_KEY",
      key_prompt: "DeepSeek API Key",
      models: ["deepseek-coder", "deepseek-chat"],
      default_model: "deepseek-coder",
      optional: true
    },
    %{
      name: :local,
      display_name: "Local LLM (Ollama)",
      key_env: nil,
      key_prompt: "Ollama Endpoint",
      models: ["codellama:latest", "llama2:latest", "mistral:latest"],
      default_model: "codellama:latest",
      optional: true
    }
  ]

  @doc """
  Ensures configuration is set up before starting the application.

  If config file doesn't exist, runs interactive setup.
  Loads configuration into application environment.
  """
  def ensure_configured! do
    if config_exists?() do
      load_config()
    else
      run_interactive_setup()
    end
  end

  @doc """
  Checks if configuration file exists.
  """
  def config_exists? do
    File.exists?(@config_file)
  end

  @doc """
  Runs interactive configuration setup.
  """
  def run_interactive_setup do
    IO.puts(IO.ANSI.cyan() <> "\n╔════════════════════════════════════════════════════════════╗")
    IO.puts("║  Welcome to MultiAgent Coder! 🤖                           ║")
    IO.puts("║  Let's configure your AI providers...                      ║")
    IO.puts("╚════════════════════════════════════════════════════════════╝\n" <> IO.ANSI.reset())

    IO.puts("Configuration will be saved to: #{@config_file}\n")

    # Check for existing environment variables first
    IO.puts(IO.ANSI.yellow() <> "Checking for existing API keys in environment variables..." <> IO.ANSI.reset())

    provider_configs = Enum.map(@providers, &configure_provider/1)
    enabled_providers = Enum.filter(provider_configs, & &1)

    if Enum.empty?(enabled_providers) do
      IO.puts(IO.ANSI.red() <> "\n⚠️  No providers configured! At least one provider is required." <> IO.ANSI.reset())
      IO.puts("Please configure at least OpenAI or Anthropic to continue.\n")
      run_interactive_setup()
    else
      save_config(enabled_providers)

      IO.puts(IO.ANSI.green() <> "\n✅ Configuration saved successfully!" <> IO.ANSI.reset())
      IO.puts("\nConfigured providers:")
      Enum.each(enabled_providers, fn config ->
        IO.puts("  • #{config.display_name} (#{config.model})")
      end)

      IO.puts(IO.ANSI.cyan() <> "\n🚀 Starting MultiAgent Coder...\n" <> IO.ANSI.reset())

      load_config()
    end
  end

  defp configure_provider(%{name: name, display_name: display_name, optional: optional} = provider) do
    IO.puts(IO.ANSI.cyan() <> "\n─────────────────────────────────────────" <> IO.ANSI.reset())
    IO.puts(IO.ANSI.bright() <> "Configure #{display_name}" <> IO.ANSI.reset())

    if optional do
      IO.puts(IO.ANSI.yellow() <> "(Optional - press Enter to skip)" <> IO.ANSI.reset())
    end

    # Check for existing API key in environment
    existing_key = if provider.key_env, do: System.get_env(provider.key_env)

    api_key = if existing_key do
      masked_key = mask_api_key(existing_key)
      IO.puts(IO.ANSI.green() <> "✓ Found existing #{provider.key_prompt}: #{masked_key}" <> IO.ANSI.reset())
      IO.write("Use this key? (Y/n): ")

      case IO.gets("") |> String.trim() |> String.downcase() do
        "" -> existing_key
        "y" -> existing_key
        "yes" -> existing_key
        _ -> prompt_for_api_key(provider, optional)
      end
    else
      prompt_for_api_key(provider, optional)
    end

    if api_key && api_key != "" do
      model = prompt_for_model(provider)

      config = %{
        name: name,
        display_name: display_name,
        model: model,
        api_key: api_key,
        temperature: 0.1,
        max_tokens: 4096
      }

      if name == :local do
        endpoint = prompt_for_endpoint()
        Map.put(config, :endpoint, endpoint)
      else
        config
      end
    else
      nil
    end
  end

  defp prompt_for_api_key(%{key_prompt: prompt, name: :local}, _optional) do
    IO.write("#{prompt} (default: http://localhost:11434): ")
    case IO.gets("") |> String.trim() do
      "" -> nil
      endpoint -> endpoint
    end
  end

  defp prompt_for_api_key(%{key_prompt: prompt}, optional) do
    IO.write("Enter your #{prompt}: ")
    input = IO.gets("") |> String.trim()

    cond do
      input == "" && optional -> nil
      input == "" ->
        IO.puts(IO.ANSI.red() <> "API key is required for this provider." <> IO.ANSI.reset())
        prompt_for_api_key(%{key_prompt: prompt}, optional)
      true -> input
    end
  end

  defp prompt_for_model(%{models: models, default_model: default}) do
    IO.puts("\nAvailable models:")
    Enum.with_index(models, 1)
    |> Enum.each(fn {model, idx} ->
      default_marker = if model == default, do: " (default)", else: ""
      IO.puts("  #{idx}. #{model}#{default_marker}")
    end)

    IO.write("Select model (1-#{length(models)} or press Enter for default): ")

    case IO.gets("") |> String.trim() do
      "" ->
        default
      input ->
        case Integer.parse(input) do
          {num, _} when num >= 1 and num <= length(models) ->
            Enum.at(models, num - 1)
          _ ->
            IO.puts(IO.ANSI.yellow() <> "Invalid selection, using default: #{default}" <> IO.ANSI.reset())
            default
        end
    end
  end

  defp prompt_for_endpoint do
    IO.write("Ollama endpoint (default: http://localhost:11434): ")
    case IO.gets("") |> String.trim() do
      "" -> "http://localhost:11434"
      endpoint -> endpoint
    end
  end

  defp mask_api_key(key) when byte_size(key) > 8 do
    prefix = String.slice(key, 0, 4)
    suffix = String.slice(key, -4, 4)
    "#{prefix}...#{suffix}"
  end
  defp mask_api_key(key), do: "#{String.slice(key, 0, 2)}..."

  defp save_config(provider_configs) do
    # Ensure config directory exists
    File.mkdir_p!(@config_dir)

    # Generate config content
    config_content = generate_config_content(provider_configs)

    # Write config file
    File.write!(@config_file, config_content)

    # Set appropriate permissions (readable only by owner)
    File.chmod!(@config_file, 0o600)
  end

  defp generate_config_content(provider_configs) do
    """
    # MultiAgent Coder Configuration
    # Generated on #{DateTime.utc_now() |> DateTime.to_string()}

    import Config

    config :multi_agent_coder,
      providers: [
    #{generate_provider_configs(provider_configs)}
      ],
      default_strategy: :all,
      timeout: 120_000
    """
  end

  defp generate_provider_configs(provider_configs) do
    provider_configs
    |> Enum.map(&format_provider_config/1)
    |> Enum.join(",\n")
  end

  defp format_provider_config(%{name: :local, endpoint: endpoint, model: model}) do
    """
        local: [
          model: #{inspect(model)},
          endpoint: #{inspect(endpoint)},
          temperature: 0.1
        ]
    """
  end

  defp format_provider_config(%{name: name, model: model, api_key: api_key}) do
    """
        #{name}: [
          model: #{inspect(model)},
          api_key: #{inspect(api_key)},
          temperature: 0.1,
          max_tokens: 4096
        ]
    """
  end

  @doc """
  Loads configuration from file into application environment.
  """
  def load_config do
    if File.exists?(@config_file) do
      Logger.info("Loading configuration from #{@config_file}")

      # Load the config file
      {config, _binding} = Code.eval_file(@config_file)

      # Apply configuration to application environment
      Enum.each(config, fn {app, app_config} ->
        Enum.each(app_config, fn {key, value} ->
          Application.put_env(app, key, value)
        end)
      end)

      :ok
    else
      Logger.warning("Configuration file not found at #{@config_file}")
      {:error, :config_not_found}
    end
  end

  @doc """
  Reconfigures a specific provider interactively.
  """
  def reconfigure_provider(provider_name) do
    provider = Enum.find(@providers, &(&1.name == provider_name))

    if provider do
      IO.puts(IO.ANSI.cyan() <> "\nReconfiguring #{provider.display_name}..." <> IO.ANSI.reset())

      if new_config = configure_provider(provider) do
        # Load existing config
        {config, _} = Code.eval_file(@config_file)
        multi_agent_config = config[:multi_agent_coder]
        existing_providers = multi_agent_config[:providers]

        # Update provider
        updated_providers = Keyword.put(existing_providers, provider_name, [
          model: new_config.model,
          api_key: new_config.api_key,
          temperature: 0.1,
          max_tokens: 4096
        ])

        # Save updated config
        save_config(Enum.map(updated_providers, fn {name, config} ->
          Map.merge(%{name: name}, Enum.into(config, %{}))
        end))

        IO.puts(IO.ANSI.green() <> "✅ #{provider.display_name} reconfigured successfully!" <> IO.ANSI.reset())
        :ok
      else
        IO.puts(IO.ANSI.yellow() <> "Configuration cancelled." <> IO.ANSI.reset())
        :cancelled
      end
    else
      IO.puts(IO.ANSI.red() <> "Unknown provider: #{provider_name}" <> IO.ANSI.reset())
      {:error, :unknown_provider}
    end
  end
end
