defmodule MultiAgentCoder.Utils.CodeValidator do
  @moduledoc """
  Validates and tests AI-generated code.

  Provides functionality to:
  - Compile/syntax check generated code
  - Run tests automatically
  - Report results back to AI providers for iteration
  """

  require Logger

  @doc """
  Validates code for a specific language.

  ## Parameters
    - language: Programming language (:elixir, :python, etc.)
    - project_dir: Directory containing the code to validate

  ## Returns
    `{:ok, validation_results}` or `{:error, reason}`
  """
  def validate_code(language, project_dir) do
    case language do
      :elixir -> validate_elixir_code(project_dir)
      :python -> validate_python_code(project_dir)
      :javascript -> validate_javascript_code(project_dir)
      _ -> {:error, :unsupported_language}
    end
  end

  @doc """
  Runs tests for a specific language.

  ## Returns
    `{:ok, test_results}` or `{:error, reason}`
  """
  def run_tests(language, project_dir) do
    case language do
      :elixir -> run_elixir_tests(project_dir)
      :python -> run_python_tests(project_dir)
      :javascript -> run_javascript_tests(project_dir)
      _ -> {:error, :unsupported_language}
    end
  end

  @doc """
  Performs complete validation: syntax check + tests.

  Returns detailed results suitable for feedback to AI providers.
  """
  def full_validation(language, project_dir) do
    with {:ok, compile_result} <- validate_code(language, project_dir),
         {:ok, test_result} <- run_tests(language, project_dir) do
      {:ok,
       %{
         compilation: compile_result,
         tests: test_result,
         passed: compile_result.success and test_result.passed
       }}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  # Elixir Validation

  defp validate_elixir_code(project_dir) do
    Logger.info("Compiling Elixir code...")

    result =
      System.cmd("mix", ["compile"],
        cd: project_dir,
        stderr_to_stdout: true
      )

    case result do
      {output, 0} ->
        {:ok, %{success: true, output: output, warnings: extract_warnings(output)}}

      {output, _exit_code} ->
        {:ok, %{success: false, output: output, errors: extract_errors(output)}}
    end
  rescue
    error ->
      {:error, {:compilation_failed, Exception.message(error)}}
  end

  defp run_elixir_tests(project_dir) do
    Logger.info("Running Elixir tests...")

    result =
      System.cmd("mix", ["test"],
        cd: project_dir,
        stderr_to_stdout: true
      )

    case result do
      {output, 0} ->
        test_stats = parse_elixir_test_output(output)

        {:ok,
         %{
           passed: true,
           output: output,
           total: test_stats.total,
           failures: 0,
           errors: []
         }}

      {output, _exit_code} ->
        test_stats = parse_elixir_test_output(output)
        failures = extract_test_failures(output)

        {:ok,
         %{
           passed: false,
           output: output,
           total: test_stats.total,
           failures: test_stats.failures,
           errors: failures
         }}
    end
  rescue
    error ->
      {:error, {:test_failed, Exception.message(error)}}
  end

  defp parse_elixir_test_output(output) do
    # Parse "3 tests, 1 failure"
    case Regex.run(~r/(\d+) tests?, (\d+) failures?/, output) do
      [_, total, failures] ->
        %{total: String.to_integer(total), failures: String.to_integer(failures)}

      _ ->
        %{total: 0, failures: 0}
    end
  end

  defp extract_test_failures(output) do
    # Extract failure messages from test output
    Regex.scan(~r/\d+\) (.+?)\n\s+(.+?:\d+)/s, output)
    |> Enum.map(fn [_, test_name, location] ->
      %{test: String.trim(test_name), location: String.trim(location)}
    end)
  end

  # Python Validation

  defp validate_python_code(project_dir) do
    Logger.info("Checking Python code syntax...")

    # Run python -m py_compile on all .py files
    result =
      System.cmd("python", ["-m", "compileall", project_dir], stderr_to_stdout: true)

    case result do
      {output, 0} ->
        {:ok, %{success: true, output: output, warnings: []}}

      {output, _} ->
        {:ok, %{success: false, output: output, errors: [output]}}
    end
  rescue
    _ ->
      {:error, :python_not_available}
  end

  defp run_python_tests(project_dir) do
    Logger.info("Running Python tests...")

    result =
      System.cmd("pytest", ["-v"],
        cd: project_dir,
        stderr_to_stdout: true
      )

    case result do
      {output, 0} ->
        {:ok, %{passed: true, output: output, failures: 0, errors: []}}

      {output, _} ->
        {:ok, %{passed: false, output: output, failures: 1, errors: [output]}}
    end
  rescue
    _ ->
      {:error, :pytest_not_available}
  end

  # JavaScript Validation

  defp validate_javascript_code(project_dir) do
    Logger.info("Checking JavaScript code syntax...")

    # Simple syntax check - try to parse with node
    result =
      System.cmd("node", ["--check", "src/index.js"],
        cd: project_dir,
        stderr_to_stdout: true
      )

    case result do
      {output, 0} ->
        {:ok, %{success: true, output: output, warnings: []}}

      {output, _} ->
        {:ok, %{success: false, output: output, errors: [output]}}
    end
  rescue
    _ ->
      {:error, :node_not_available}
  end

  defp run_javascript_tests(project_dir) do
    Logger.info("Running JavaScript tests...")

    result =
      System.cmd("npm", ["test"],
        cd: project_dir,
        stderr_to_stdout: true
      )

    case result do
      {output, 0} ->
        {:ok, %{passed: true, output: output, failures: 0, errors: []}}

      {output, _} ->
        {:ok, %{passed: false, output: output, failures: 1, errors: [output]}}
    end
  rescue
    _ ->
      {:error, :npm_not_available}
  end

  # Helper Functions

  defp extract_warnings(output) do
    Regex.scan(~r/warning: (.+)/, output)
    |> Enum.map(fn [_, warning] -> String.trim(warning) end)
  end

  defp extract_errors(output) do
    Regex.scan(~r/\*\* \((.+?)\) (.+)/, output)
    |> Enum.map(fn [_, error_type, message] ->
      "#{error_type}: #{String.trim(message)}"
    end)
  end
end
