# Multi-Language Parser Support

This directory contains language-specific parsers for the MultiAgentCoder semantic analyzer. These parsers enable intelligent code merging and semantic analysis across multiple programming languages.

## Supported Languages

- **JavaScript/TypeScript** (.js, .jsx, .ts, .tsx, .mjs, .cjs)
- **Python** (.py, .pyw)
- **Go** (.go)
- **Rust** (.rs)

## Architecture

### Parser Behaviour

All language parsers implement the `ParserBehaviour` which defines a consistent interface:

```elixir
@callback parse(content :: String.t()) :: {:ok, ast()} | {:error, String.t()}
@callback extract_functions(ast()) :: list(function_info())
@callback extract_modules(ast()) :: list(module_info())
@callback extract_imports(ast()) :: list(String.t())
@callback extract_dependencies(ast()) :: list(map())
@callback detect_side_effects(ast()) :: list(atom())
@callback calculate_complexity(ast()) :: non_neg_integer()
@callback supported_extensions() :: list(String.t())
```

### Parser Registry

The `ParserRegistry` module maps file extensions to the appropriate parser module. It provides:

- `get_parser/1` - Get the parser for a specific file extension
- `supported_extensions/0` - List all supported file extensions
- `supported?/1` - Check if a file extension is supported
- `analyze/2` - Analyze code using the appropriate parser

## Adding a New Language Parser

### 1. Create the Parser Module

Create a new file in `lib/multi_agent_coder/merge/parsers/` for your language:

```elixir
defmodule MultiAgentCoder.Merge.Parsers.YourLanguageParser do
  @behaviour MultiAgentCoder.Merge.Parsers.ParserBehaviour

  @impl true
  def parse(content) do
    # Parse the code and return an AST
    # You can call external scripts/binaries here
  end

  @impl true
  def extract_functions(ast) do
    # Extract function definitions from the AST
  end

  # Implement other required callbacks...

  @impl true
  def supported_extensions do
    [".your_ext"]
  end
end
```

### 2. Create the Parser Script (Optional)

If your language requires an external parser, create a script in `scripts/`:

- **Node.js**: `scripts/your_language_parser.mjs`
- **Python**: `scripts/your_language_parser.py`
- **Go**: `scripts/your_language_parser.go`
- **Rust**: `scripts/your_language_parser.rs` + `Cargo.toml`

The script should:
1. Accept a file path as an argument
2. Parse the file
3. Extract semantic information
4. Output JSON to stdout

Example output format:
```json
{
  "functions": [
    {
      "name": "function_name",
      "arity": 2,
      "params": ["param1", "param2"],
      "exported": true
    }
  ],
  "modules": [],
  "imports": ["module1", "module2"],
  "dependencies": [],
  "side_effects": ["io_operation"],
  "complexity": 5
}
```

### 3. Register the Parser

Add your parser to the `parser_map/0` function in `parser_registry.ex`:

```elixir
defp parser_map do
  %{
    # Existing parsers...
    ".your_ext" => YourLanguageParser
  }
end
```

### 4. Add Tests

Create a test file in `test/multi_agent_coder/merge/parsers/`:

```elixir
defmodule MultiAgentCoder.Merge.Parsers.YourLanguageParserTest do
  use ExUnit.Case, async: false

  alias MultiAgentCoder.Merge.Parsers.YourLanguageParser

  describe "parse/1" do
    test "parses valid code" do
      code = "..."
      {:ok, ast} = YourLanguageParser.parse(code)
      assert is_map(ast)
    end
  end

  # Add more tests...
end
```

### 5. Update Documentation

Update this README to include your new language in the "Supported Languages" section.

## Parser Dependencies

### JavaScript/TypeScript
Requires Node.js and npm. Install dependencies:
```bash
cd lib/multi_agent_coder/merge/parsers/scripts
npm install
```

### Python
Requires Python 3.x (uses built-in `ast` module, no additional dependencies).

### Go
Requires Go compiler (uses built-in `go/parser` and `go/ast` packages).

### Rust
Requires Rust toolchain (cargo). Dependencies are managed in `scripts/Cargo.toml`.

## Testing

Run parser tests:
```bash
mix test test/multi_agent_coder/merge/parsers/
```

Run tests for a specific language:
```bash
mix test --only javascript_parser
mix test --only python_parser
```

Skip external parser tests (useful in CI):
```bash
mix test --exclude javascript_parser --exclude python_parser
```

## Complexity Calculation

All parsers calculate cyclomatic complexity by counting:
- Conditional statements (if, else if, ternary)
- Loops (for, while, do-while)
- Case/switch statements
- Boolean operators (&&, ||)
- Exception handlers

Base complexity starts at 1.

## Side Effect Detection

Parsers detect common side effects:
- `io_operation` - File I/O, console output, network requests
- `global_mutation` - Modifications to global state
- `process_operation` - Process/thread operations

## Contributing

When adding a new language parser:
1. Follow the existing parser structure
2. Ensure comprehensive test coverage
3. Document any external dependencies
4. Update this README
5. Consider edge cases and error handling
