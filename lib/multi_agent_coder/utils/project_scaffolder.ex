defmodule MultiAgentCoder.Utils.ProjectScaffolder do
  @moduledoc """
  Creates project scaffolding for various programming languages.

  Automatically generates boilerplate files and directory structures
  for new projects, including:
  - Build configuration (mix.exs, package.json, etc.)
  - Test infrastructure
  - Configuration files
  - README templates
  """

  require Logger

  @doc """
  Creates a complete project scaffold for the specified language.

  ## Parameters
    - project_name: Name of the project
    - output_dir: Directory to create the project in
    - language: Programming language (:elixir, :python, :javascript, etc.)
    - opts: Additional options

  ## Returns
    `{:ok, created_files}` or `{:error, reason}`
  """
  def scaffold_project(project_name, output_dir, language, opts \\ []) do
    project_dir = Path.join(output_dir, project_name)

    if File.exists?(project_dir) and not Keyword.get(opts, :force, false) do
      {:error, :directory_exists}
    else
      File.mkdir_p!(project_dir)

      created_files =
        case language do
          :elixir -> scaffold_elixir_project(project_name, project_dir, opts)
          :python -> scaffold_python_project(project_name, project_dir, opts)
          :javascript -> scaffold_javascript_project(project_name, project_dir, opts)
          :ruby -> scaffold_ruby_project(project_name, project_dir, opts)
          _ -> {:error, :unsupported_language}
        end

      case created_files do
        files when is_list(files) ->
          Logger.info("Created project scaffold for #{project_name} at #{project_dir}")
          {:ok, files}

        error ->
          error
      end
    end
  end

  # Elixir Project Scaffolding

  defp scaffold_elixir_project(project_name, project_dir, _opts) do
    module_name = Macro.camelize(project_name)

    files = [
      create_mix_exs(project_dir, project_name, module_name),
      create_elixir_lib_file(project_dir, project_name, module_name),
      create_test_helper(project_dir),
      create_elixir_test_file(project_dir, project_name, module_name),
      create_elixir_formatter(project_dir),
      create_gitignore(project_dir, :elixir),
      create_readme(project_dir, project_name, :elixir)
    ]

    Enum.filter(files, &(&1 != nil))
  end

  defp create_mix_exs(project_dir, project_name, module_name) do
    app_name = String.to_atom(project_name)

    content = """
    defmodule #{module_name}.MixProject do
      use Mix.Project

      def project do
        [
          app: :#{app_name},
          version: "0.1.0",
          elixir: "~> 1.18",
          start_permanent: Mix.env() == :prod,
          deps: deps()
        ]
      end

      def application do
        [
          extra_applications: [:logger]
        ]
      end

      defp deps do
        [
          # Add your dependencies here
        ]
      end
    end
    """

    file_path = Path.join(project_dir, "mix.exs")
    File.write!(file_path, content)
    file_path
  end

  defp create_elixir_lib_file(project_dir, project_name, module_name) do
    content = """
    defmodule #{module_name} do
      @moduledoc \"\"\"
      Documentation for `#{module_name}`.
      \"\"\"

      @doc \"\"\"
      Hello world.

      ## Examples

          iex> #{module_name}.hello()
          :world

      \"\"\"
      def hello do
        :world
      end
    end
    """

    lib_dir = Path.join(project_dir, "lib")
    File.mkdir_p!(lib_dir)

    file_path = Path.join(lib_dir, "#{project_name}.ex")
    File.write!(file_path, content)
    file_path
  end

  defp create_test_helper(project_dir) do
    content = "ExUnit.start()\n"

    test_dir = Path.join(project_dir, "test")
    File.mkdir_p!(test_dir)

    file_path = Path.join(test_dir, "test_helper.exs")
    File.write!(file_path, content)
    file_path
  end

  defp create_elixir_test_file(project_dir, project_name, module_name) do
    content = """
    defmodule #{module_name}Test do
      use ExUnit.Case
      doctest #{module_name}

      test "greets the world" do
        assert #{module_name}.hello() == :world
      end
    end
    """

    test_dir = Path.join(project_dir, "test")
    File.mkdir_p!(test_dir)

    file_path = Path.join(test_dir, "#{project_name}_test.exs")
    File.write!(file_path, content)
    file_path
  end

  defp create_elixir_formatter(project_dir) do
    content = """
    [
      inputs: ["{mix,.formatter}.exs", "{config,lib,test}/**/*.{ex,exs}"]
    ]
    """

    file_path = Path.join(project_dir, ".formatter.exs")
    File.write!(file_path, content)
    file_path
  end

  # Python Project Scaffolding

  defp scaffold_python_project(project_name, project_dir, _opts) do
    files = [
      create_python_src_file(project_dir, project_name),
      create_python_init(project_dir, project_name),
      create_python_test_file(project_dir, project_name),
      create_setup_py(project_dir, project_name),
      create_requirements_txt(project_dir),
      create_gitignore(project_dir, :python),
      create_readme(project_dir, project_name, :python)
    ]

    Enum.filter(files, &(&1 != nil))
  end

  defp create_python_src_file(project_dir, project_name) do
    content = """
    \"\"\"
    #{project_name} module
    \"\"\"

    def hello():
        \"\"\"Return a greeting.\"\"\"
        return "Hello, World!"
    """

    src_dir = Path.join([project_dir, "src", project_name])
    File.mkdir_p!(src_dir)

    file_path = Path.join(src_dir, "main.py")
    File.write!(file_path, content)
    file_path
  end

  defp create_python_init(project_dir, project_name) do
    content = """
    \"\"\"#{project_name} package\"\"\"

    from .main import hello

    __version__ = "0.1.0"
    """

    src_dir = Path.join([project_dir, "src", project_name])
    File.mkdir_p!(src_dir)

    file_path = Path.join(src_dir, "__init__.py")
    File.write!(file_path, content)
    file_path
  end

  defp create_python_test_file(project_dir, project_name) do
    content = """
    \"\"\"Tests for #{project_name}\"\"\"

    import pytest
    from #{project_name}.main import hello


    def test_hello():
        assert hello() == "Hello, World!"
    """

    tests_dir = Path.join(project_dir, "tests")
    File.mkdir_p!(tests_dir)

    file_path = Path.join(tests_dir, "test_main.py")
    File.write!(file_path, content)
    file_path
  end

  defp create_setup_py(project_dir, project_name) do
    content = """
    from setuptools import setup, find_packages

    setup(
        name="#{project_name}",
        version="0.1.0",
        packages=find_packages(where="src"),
        package_dir={"": "src"},
        python_requires=">=3.8",
        install_requires=[
            # Add your dependencies here
        ],
        extras_require={
            "dev": ["pytest>=7.0"],
        },
    )
    """

    file_path = Path.join(project_dir, "setup.py")
    File.write!(file_path, content)
    file_path
  end

  defp create_requirements_txt(project_dir) do
    content = "# Add your dependencies here\npytest>=7.0\n"

    file_path = Path.join(project_dir, "requirements.txt")
    File.write!(file_path, content)
    file_path
  end

  # JavaScript/Node.js Project Scaffolding

  defp scaffold_javascript_project(project_name, project_dir, _opts) do
    files = [
      create_package_json(project_dir, project_name),
      create_javascript_index(project_dir),
      create_javascript_test(project_dir),
      create_gitignore(project_dir, :javascript),
      create_readme(project_dir, project_name, :javascript)
    ]

    Enum.filter(files, &(&1 != nil))
  end

  defp create_package_json(project_dir, project_name) do
    content = """
    {
      "name": "#{project_name}",
      "version": "0.1.0",
      "description": "",
      "main": "src/index.js",
      "scripts": {
        "test": "jest"
      },
      "keywords": [],
      "author": "",
      "license": "ISC",
      "devDependencies": {
        "jest": "^29.0.0"
      }
    }
    """

    file_path = Path.join(project_dir, "package.json")
    File.write!(file_path, content)
    file_path
  end

  defp create_javascript_index(project_dir) do
    content = """
    function hello() {
      return 'Hello, World!';
    }

    module.exports = { hello };
    """

    src_dir = Path.join(project_dir, "src")
    File.mkdir_p!(src_dir)

    file_path = Path.join(src_dir, "index.js")
    File.write!(file_path, content)
    file_path
  end

  defp create_javascript_test(project_dir) do
    content = """
    const { hello } = require('../src/index');

    test('hello returns greeting', () => {
      expect(hello()).toBe('Hello, World!');
    });
    """

    tests_dir = Path.join(project_dir, "tests")
    File.mkdir_p!(tests_dir)

    file_path = Path.join(tests_dir, "index.test.js")
    File.write!(file_path, content)
    file_path
  end

  # Ruby Project Scaffolding

  defp scaffold_ruby_project(project_name, project_dir, _opts) do
    files = [
      create_ruby_lib_file(project_dir, project_name),
      create_ruby_test_file(project_dir, project_name),
      create_gemfile(project_dir, project_name),
      create_gitignore(project_dir, :ruby),
      create_readme(project_dir, project_name, :ruby)
    ]

    Enum.filter(files, &(&1 != nil))
  end

  defp create_ruby_lib_file(project_dir, project_name) do
    module_name = Macro.camelize(project_name)

    content = """
    module #{module_name}
      VERSION = "0.1.0"

      def self.hello
        "Hello, World!"
      end
    end
    """

    lib_dir = Path.join(project_dir, "lib")
    File.mkdir_p!(lib_dir)

    file_path = Path.join(lib_dir, "#{project_name}.rb")
    File.write!(file_path, content)
    file_path
  end

  defp create_ruby_test_file(project_dir, project_name) do
    module_name = Macro.camelize(project_name)

    content = """
    require 'minitest/autorun'
    require_relative '../lib/#{project_name}'

    class Test#{module_name} < Minitest::Test
      def test_hello
        assert_equal "Hello, World!", #{module_name}.hello
      end
    end
    """

    test_dir = Path.join(project_dir, "test")
    File.mkdir_p!(test_dir)

    file_path = Path.join(test_dir, "test_#{project_name}.rb")
    File.write!(file_path, content)
    file_path
  end

  defp create_gemfile(project_dir, project_name) do
    content = """
    source 'https://rubygems.org'

    gem '#{project_name}', path: '.'

    group :test do
      gem 'minitest', '~> 5.0'
    end
    """

    file_path = Path.join(project_dir, "Gemfile")
    File.write!(file_path, content)
    file_path
  end

  # Common Files

  defp create_gitignore(project_dir, language) do
    content =
      case language do
        :elixir ->
          """
          /_build/
          /cover/
          /deps/
          /doc/
          /.fetch
          erl_crash.dump
          *.ez
          *.beam
          .elixir_ls/
          """

        :python ->
          """
          __pycache__/
          *.py[cod]
          *$py.class
          *.so
          .Python
          env/
          venv/
          *.egg-info/
          dist/
          build/
          .pytest_cache/
          """

        :javascript ->
          """
          node_modules/
          npm-debug.log*
          yarn-debug.log*
          yarn-error.log*
          .DS_Store
          dist/
          coverage/
          """

        :ruby ->
          """
          *.gem
          *.rbc
          .bundle
          .config
          coverage
          InstalledFiles
          lib/bundler/man
          pkg
          spec/reports
          test/tmp
          test/version_tmp
          tmp
          """

        _ ->
          ""
      end

    if content != "" do
      file_path = Path.join(project_dir, ".gitignore")
      File.write!(file_path, content)
      file_path
    else
      nil
    end
  end

  defp create_readme(project_dir, project_name, language) do
    content = """
    # #{String.capitalize(project_name)}

    A #{language} project.

    ## Installation

    #{installation_instructions(language)}

    ## Usage

    #{usage_instructions(language, project_name)}

    ## Testing

    #{test_instructions(language)}

    ## License

    MIT
    """

    file_path = Path.join(project_dir, "README.md")
    File.write!(file_path, content)
    file_path
  end

  defp installation_instructions(:elixir) do
    """
    ```bash
    mix deps.get
    ```
    """
  end

  defp installation_instructions(:python) do
    """
    ```bash
    pip install -r requirements.txt
    # Or for development:
    pip install -e .[dev]
    ```
    """
  end

  defp installation_instructions(:javascript) do
    """
    ```bash
    npm install
    ```
    """
  end

  defp installation_instructions(:ruby) do
    """
    ```bash
    bundle install
    ```
    """
  end

  defp installation_instructions(_), do: "See language-specific documentation"

  defp usage_instructions(:elixir, project_name) do
    module_name = Macro.camelize(project_name)

    """
    ```elixir
    iex> #{module_name}.hello()
    :world
    ```
    """
  end

  defp usage_instructions(:python, project_name) do
    """
    ```python
    from #{project_name} import hello
    print(hello())
    ```
    """
  end

  defp usage_instructions(:javascript, _project_name) do
    """
    ```javascript
    const { hello } = require('./src/index');
    console.log(hello());
    ```
    """
  end

  defp usage_instructions(:ruby, project_name) do
    module_name = Macro.camelize(project_name)

    """
    ```ruby
    require '#{project_name}'
    puts #{module_name}.hello
    ```
    """
  end

  defp usage_instructions(_, _), do: "See documentation"

  defp test_instructions(:elixir), do: "```bash\nmix test\n```"
  defp test_instructions(:python), do: "```bash\npytest\n```"
  defp test_instructions(:javascript), do: "```bash\nnpm test\n```"
  defp test_instructions(:ruby), do: "```bash\nruby test/test_*.rb\n```"
  defp test_instructions(_), do: "See language-specific documentation"
end
