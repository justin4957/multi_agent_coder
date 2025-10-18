#!/usr/bin/env python3

"""
Python parser using the built-in ast module

This script parses Python files and extracts semantic information
for the MultiAgentCoder semantic analyzer.

Usage: python3 python_parser.py <file_path>
"""

import ast
import sys
import json


def extract_functions(tree):
    """Extract function definitions from AST"""
    functions = []

    for node in ast.walk(tree):
        if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)):
            # Get parameter names
            params = []
            for arg in node.args.args:
                params.append(arg.arg)

            # Add *args if present
            if node.args.vararg:
                params.append(f"*{node.args.vararg.arg}")

            # Add **kwargs if present
            if node.args.kwarg:
                params.append(f"**{node.args.kwarg.arg}")

            functions.append({
                "name": node.name,
                "arity": len(node.args.args),
                "params": params,
                "is_async": isinstance(node, ast.AsyncFunctionDef),
                "decorators": [get_decorator_name(d) for d in node.decorator_list],
                "lineno": node.lineno,
            })

    return functions


def extract_classes(tree):
    """Extract class definitions from AST"""
    classes = []

    for node in ast.walk(tree):
        if isinstance(node, ast.ClassDef):
            # Extract methods
            methods = []
            for item in node.body:
                if isinstance(item, (ast.FunctionDef, ast.AsyncFunctionDef)):
                    methods.append(item.name)

            # Extract base classes
            bases = []
            for base in node.bases:
                if isinstance(base, ast.Name):
                    bases.append(base.id)
                elif isinstance(base, ast.Attribute):
                    bases.append(f"{base.value.id}.{base.attr}")

            classes.append({
                "name": node.name,
                "methods": methods,
                "bases": bases,
                "decorators": [get_decorator_name(d) for d in node.decorator_list],
                "lineno": node.lineno,
            })

    return classes


def extract_imports(tree):
    """Extract import statements from AST"""
    imports = []

    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            for alias in node.names:
                imports.append(alias.name)
        elif isinstance(node, ast.ImportFrom):
            if node.module:
                imports.append(node.module)

    return list(set(imports))  # Deduplicate


def extract_dependencies(tree):
    """Extract function calls (dependencies) from AST"""
    dependencies = []

    for node in ast.walk(tree):
        if isinstance(node, ast.Call):
            func_name = get_call_name(node.func)
            dependencies.append({
                "function": func_name,
                "arity": len(node.args) + len(node.keywords),
            })

    return dependencies


def detect_side_effects(tree):
    """Detect operations with side effects"""
    side_effects = set()

    for node in ast.walk(tree):
        # File I/O operations
        if isinstance(node, ast.Call):
            func_name = get_call_name(node.func)
            if func_name in ['open', 'print', 'input']:
                side_effects.add('io_operation')
            elif 'write' in func_name or 'read' in func_name:
                side_effects.add('io_operation')

        # Global keyword
        if isinstance(node, ast.Global):
            side_effects.add('global_mutation')

        # Nonlocal keyword
        if isinstance(node, ast.Nonlocal):
            side_effects.add('nonlocal_mutation')

    return list(side_effects)


def calculate_complexity(tree):
    """Calculate cyclomatic complexity"""
    complexity = 1

    for node in ast.walk(tree):
        # Conditional statements
        if isinstance(node, (ast.If, ast.IfExp)):
            complexity += 1
        # Loops
        elif isinstance(node, (ast.For, ast.While, ast.AsyncFor)):
            complexity += 1
        # Exception handling
        elif isinstance(node, ast.ExceptHandler):
            complexity += 1
        # Boolean operators (and, or)
        elif isinstance(node, ast.BoolOp):
            complexity += len(node.values) - 1
        # Comprehensions
        elif isinstance(node, (ast.ListComp, ast.DictComp, ast.SetComp, ast.GeneratorExp)):
            complexity += 1

    return complexity


def get_decorator_name(decorator):
    """Get decorator name from AST node"""
    if isinstance(decorator, ast.Name):
        return decorator.id
    elif isinstance(decorator, ast.Call):
        if isinstance(decorator.func, ast.Name):
            return decorator.func.id
    return "unknown"


def get_call_name(node):
    """Get function call name from AST node"""
    if isinstance(node, ast.Name):
        return node.id
    elif isinstance(node, ast.Attribute):
        return f"{get_call_name(node.value)}.{node.attr}"
    return "unknown"


def main():
    if len(sys.argv) < 2:
        print(json.dumps({"error": "No file path provided"}))
        sys.exit(1)

    file_path = sys.argv[1]

    try:
        with open(file_path, 'r', encoding='utf-8') as f:
            code = f.read()

        tree = ast.parse(code)

        result = {
            "functions": extract_functions(tree),
            "classes": extract_classes(tree),
            "imports": extract_imports(tree),
            "dependencies": extract_dependencies(tree),
            "side_effects": detect_side_effects(tree),
            "complexity": calculate_complexity(tree),
        }

        print(json.dumps(result))
        sys.exit(0)

    except SyntaxError as e:
        print(json.dumps({
            "error": f"Syntax error at line {e.lineno}: {e.msg}"
        }))
        sys.exit(1)
    except Exception as e:
        print(json.dumps({
            "error": str(e),
            "type": type(e).__name__
        }))
        sys.exit(1)


if __name__ == "__main__":
    main()
