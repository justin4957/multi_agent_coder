# MultiAgent Coder - Claude Code Instructions

This file contains project-specific instructions for working with Claude Code on the MultiAgent Coder project.

## Code Quality Standards

- Always use descriptive variable names
- Prioritize composability and reusability in code generation
- Aim for abstraction which facilitates easier future application and transposition

## Pre-Pull Request Checklist

Before creating a pull request, always:

1. **Format code**: Run `mix format` to ensure all code is properly formatted
2. **Verify formatting**: Run `mix format --check-formatted` to confirm no formatting issues remain
3. **Run tests**: Execute `mix test` to ensure all tests pass locally
4. **Run Credo**: Execute `mix credo` to check for code quality issues (non-blocking but should be reviewed)
5. **Build escript**: Run `mix escript.build` to verify the CLI builds successfully

## Post-Pull Request Workflow

After creating a pull request:

1. **Monitor CI**: Use `gh run list` and `gh run view` to monitor CI status
2. **Investigate failures**: If CI fails, use `gh run view <run-id> --log-failed` to investigate
3. **Fix issues**: Address any CI failures promptly
4. **Verify all checks pass**: Ensure all three CI jobs (test, quality, build) pass before considering task complete

## Testing Guidelines

- All new features must include tests
- Maintain or improve code coverage
- Use `async: true` for tests that don't require shared state
- Use `async: false` for tests that interact with application-level processes

## Documentation Standards

- Add moduledoc to all new modules
- Document all public functions with @doc
- Include examples in documentation where helpful
- Update README.md for new features or significant changes

## Elixir Conventions

- Follow the Elixir style guide
- Use pattern matching and guard clauses effectively
- Prefer pipelines for data transformations
- Keep functions small and focused
- Use descriptive function and variable names
