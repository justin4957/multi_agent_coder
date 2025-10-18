defmodule MultiAgentCoder.Utils.CodeExtractor do
  @moduledoc """
  Extracts code blocks from AI provider responses.

  Parses markdown-formatted responses and extracts code blocks,
  creating proper file structures with appropriate file names.
  """

  require Logger

  @doc """
  Extracts all code blocks from a markdown response.

  ## Returns
    List of tuples: `{language, code_content, suggested_filename}`
  """
  def extract_code_blocks(response_text) do
    # Match markdown code blocks: ```language\ncode\n```
    pattern = ~r/```(\w+)?\n(.*?)```/s

    Regex.scan(pattern, response_text)
    |> Enum.map(fn
      [_, lang, code] ->
        language = if lang == "", do: "text", else: lang
        suggested_filename = suggest_filename(code, language)
        {language, String.trim(code), suggested_filename}

      [_, code] ->
        suggested_filename = suggest_filename(code, "text")
        {"text", String.trim(code), suggested_filename}
    end)
  end

  @doc """
  Extracts code blocks and writes them to files in the specified directory.

  ## Parameters
    - response_text: The AI provider's response containing code blocks
    - output_dir: Directory to write files to
    - opts: Options
      - `:overwrite` - Whether to overwrite existing files (default: false)
      - `:create_subdirs` - Create language-specific subdirectories (default: true)

  ## Returns
    `{:ok, written_files}` or `{:error, reason}`
  """
  def extract_and_write(response_text, output_dir, opts \\ []) do
    overwrite = Keyword.get(opts, :overwrite, false)
    create_subdirs = Keyword.get(opts, :create_subdirs, true)

    code_blocks = extract_code_blocks(response_text)

    if Enum.empty?(code_blocks) do
      {:ok, []}
    else
      # Ensure output directory exists
      File.mkdir_p!(output_dir)

      written_files =
        code_blocks
        |> Enum.with_index()
        |> Enum.map(fn {{lang, code, suggested_name}, index} ->
          file_path = build_file_path(output_dir, lang, suggested_name, index, create_subdirs)

          if File.exists?(file_path) and not overwrite do
            Logger.warning("File already exists, skipping: #{file_path}")
            {:skipped, file_path}
          else
            # Ensure parent directory exists
            file_path |> Path.dirname() |> File.mkdir_p!()

            File.write!(file_path, code)
            Logger.info("Wrote code to: #{file_path}")
            {:created, file_path}
          end
        end)

      {:ok, written_files}
    end
  end

  @doc """
  Analyzes a response and creates a complete project structure.

  For responses containing multiple related files (e.g., lib/, test/, mix.exs),
  this function intelligently organizes them into a proper project structure.
  """
  def create_project_structure(response_text, project_dir, language \\ :elixir) do
    code_blocks = extract_code_blocks(response_text)

    case language do
      :elixir ->
        create_elixir_project(code_blocks, project_dir)

      :python ->
        create_python_project(code_blocks, project_dir)

      _ ->
        # Generic structure
        extract_and_write(response_text, project_dir, create_subdirs: false)
    end
  end

  # Private Functions

  defp suggest_filename(code, language) do
    # Try to extract module/class name from code
    case extract_identifier(code, language) do
      {:ok, name} -> "#{name}#{extension_for_language(language)}"
      :error -> "code#{extension_for_language(language)}"
    end
  end

  defp extract_identifier(code, language) do
    pattern =
      case language do
        lang when lang in ["elixir", "ex"] -> ~r/defmodule\s+(\w+(?:\.\w+)*)/
        "python" -> ~r/class\s+(\w+)|def\s+(\w+)/
        "ruby" -> ~r/class\s+(\w+)|module\s+(\w+)/
        "javascript" -> ~r/class\s+(\w+)|function\s+(\w+)/
        "typescript" -> ~r/class\s+(\w+)|interface\s+(\w+)|function\s+(\w+)/
        "go" -> ~r/type\s+(\w+)|func\s+(\w+)/
        "rust" -> ~r/struct\s+(\w+)|fn\s+(\w+)/
        "java" -> ~r/class\s+(\w+)|interface\s+(\w+)/
        _ -> nil
      end

    if pattern do
      case Regex.run(pattern, code) do
        [_, name | _] when is_binary(name) and name != "" ->
          # Convert CamelCase/PascalCase to snake_case for file names
          snake_case_name =
            name
            |> String.replace(~r/([A-Z]+)([A-Z][a-z])/, "\\1_\\2")
            |> String.replace(~r/([a-z\d])([A-Z])/, "\\1_\\2")
            |> String.replace(".", "_")
            |> String.downcase()

          {:ok, snake_case_name}

        _ ->
          :error
      end
    else
      :error
    end
  end

  defp extension_for_language(language) do
    case language do
      lang when lang in ["elixir", "ex"] -> ".ex"
      lang when lang in ["elixir_test", "exs"] -> ".exs"
      "python" -> ".py"
      "ruby" -> ".rb"
      lang when lang in ["javascript", "js"] -> ".js"
      lang when lang in ["typescript", "ts"] -> ".ts"
      "go" -> ".go"
      "rust" -> ".rs"
      "java" -> ".java"
      "c" -> ".c"
      "cpp" -> ".cpp"
      "shell" -> ".sh"
      "bash" -> ".sh"
      "yaml" -> ".yaml"
      "json" -> ".json"
      _ -> ".txt"
    end
  end

  defp build_file_path(base_dir, _lang, suggested_name, _index, false) do
    Path.join(base_dir, suggested_name)
  end

  defp build_file_path(base_dir, lang, suggested_name, _index, true) do
    # Determine subdirectory based on file type
    subdir =
      cond do
        String.ends_with?(suggested_name, "_test.exs") -> "test"
        String.ends_with?(suggested_name, ".exs") and suggested_name != "mix.exs" -> "test"
        suggested_name == "mix.exs" -> ""
        lang in ["elixir", "ex"] -> "lib"
        lang == "python" and String.contains?(suggested_name, "test_") -> "tests"
        lang == "python" -> "src"
        true -> lang
      end

    if subdir == "" do
      Path.join(base_dir, suggested_name)
    else
      Path.join([base_dir, subdir, suggested_name])
    end
  end

  defp create_elixir_project(code_blocks, project_dir) do
    File.mkdir_p!(project_dir)
    File.mkdir_p!(Path.join(project_dir, "lib"))
    File.mkdir_p!(Path.join(project_dir, "test"))

    # Ensure test_helper.exs exists
    test_helper_path = Path.join([project_dir, "test", "test_helper.exs"])

    unless File.exists?(test_helper_path) do
      File.write!(test_helper_path, "ExUnit.start()\n")
      Logger.info("Created test_helper.exs")
    end

    # Process code blocks
    written_files =
      code_blocks
      |> Enum.map(fn {lang, code, suggested_name} ->
        file_path =
          cond do
            suggested_name == "mix.exs" ->
              Path.join(project_dir, "mix.exs")

            String.ends_with?(suggested_name, "_test.exs") ->
              Path.join([project_dir, "test", suggested_name])

            String.ends_with?(suggested_name, ".exs") ->
              Path.join([project_dir, "test", suggested_name])

            lang in ["elixir", "ex"] ->
              Path.join([project_dir, "lib", suggested_name])

            true ->
              Path.join(project_dir, suggested_name)
          end

        File.write!(file_path, code)
        Logger.info("Wrote #{file_path}")
        {:created, file_path}
      end)

    {:ok, written_files}
  end

  defp create_python_project(code_blocks, project_dir) do
    File.mkdir_p!(project_dir)
    File.mkdir_p!(Path.join(project_dir, "src"))
    File.mkdir_p!(Path.join(project_dir, "tests"))

    written_files =
      code_blocks
      |> Enum.map(fn {_lang, code, suggested_name} ->
        file_path =
          cond do
            String.starts_with?(suggested_name, "test_") ->
              Path.join([project_dir, "tests", suggested_name])

            suggested_name in ["setup.py", "requirements.txt", "README.md"] ->
              Path.join(project_dir, suggested_name)

            true ->
              Path.join([project_dir, "src", suggested_name])
          end

        File.write!(file_path, code)
        Logger.info("Wrote #{file_path}")
        {:created, file_path}
      end)

    {:ok, written_files}
  end
end
