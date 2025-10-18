#!/usr/bin/env node

/**
 * JavaScript/TypeScript parser using Babel
 *
 * This script parses JavaScript/TypeScript files and extracts semantic information
 * for the MultiAgentCoder semantic analyzer.
 *
 * Usage: node js_parser.mjs <file_path>
 */

import fs from 'fs';
import { parse } from '@babel/parser';
import traverse from '@babel/traverse';

const filePath = process.argv[2];

if (!filePath) {
  console.error(JSON.stringify({ error: 'No file path provided' }));
  process.exit(1);
}

try {
  const code = fs.readFileSync(filePath, 'utf-8');

  // Parse with all features enabled
  const ast = parse(code, {
    sourceType: 'unambiguous',
    plugins: [
      'jsx',
      'typescript',
      'decorators-legacy',
      'classProperties',
      'dynamicImport',
      'exportDefaultFrom',
      'exportNamespaceFrom',
      'asyncGenerators',
      'objectRestSpread',
      'optionalChaining',
      'nullishCoalescingOperator',
    ],
  });

  const result = {
    functions: [],
    modules: [],
    imports: [],
    dependencies: [],
    sideEffects: [],
    complexity: 1,
  };

  // Traverse the AST and extract information
  traverse.default(ast, {
    FunctionDeclaration(path) {
      const node = path.node;
      result.functions.push({
        name: node.id ? node.id.name : 'anonymous',
        arity: node.params.length,
        params: node.params.map(param => {
          if (param.type === 'Identifier') return param.name;
          if (param.type === 'RestElement') return '...' + (param.argument.name || 'rest');
          return 'param';
        }),
        async: node.async || false,
        exported: path.parent.type === 'ExportNamedDeclaration' || path.parent.type === 'ExportDefaultDeclaration',
        type: 'function',
      });
    },

    FunctionExpression(path) {
      const node = path.node;
      const name = node.id ? node.id.name :
                   (path.parent.type === 'VariableDeclarator' ? path.parent.id.name : 'anonymous');

      result.functions.push({
        name,
        arity: node.params.length,
        params: node.params.map(param => {
          if (param.type === 'Identifier') return param.name;
          if (param.type === 'RestElement') return '...' + (param.argument.name || 'rest');
          return 'param';
        }),
        async: node.async || false,
        exported: false,
        type: 'function_expression',
      });
    },

    ArrowFunctionExpression(path) {
      const node = path.node;
      const name = path.parent.type === 'VariableDeclarator' ? path.parent.id.name : 'arrow';

      result.functions.push({
        name,
        arity: node.params.length,
        params: node.params.map(param => {
          if (param.type === 'Identifier') return param.name;
          if (param.type === 'RestElement') return '...' + (param.argument.name || 'rest');
          return 'param';
        }),
        async: node.async || false,
        exported: false,
        type: 'arrow_function',
      });
    },

    ClassDeclaration(path) {
      const node = path.node;
      const methods = node.body.body.filter(m => m.type === 'ClassMethod' || m.type === 'ClassProperty');

      result.modules.push({
        name: node.id ? node.id.name : 'AnonymousClass',
        type: 'class',
        exported: path.parent.type === 'ExportNamedDeclaration' || path.parent.type === 'ExportDefaultDeclaration',
        methods: methods.map(m => m.key.name || 'unknown'),
      });
    },

    ImportDeclaration(path) {
      const node = path.node;
      const source = node.source.value;
      const specifiers = node.specifiers.map(spec => {
        if (spec.type === 'ImportDefaultSpecifier') {
          return { type: 'default', local: spec.local.name };
        } else if (spec.type === 'ImportNamespaceSpecifier') {
          return { type: 'namespace', local: spec.local.name };
        } else {
          return {
            type: 'named',
            local: spec.local.name,
            imported: spec.imported ? spec.imported.name : spec.local.name
          };
        }
      });

      result.imports.push({ source, specifiers: specifiers.map(s => s.local) });
    },

    CallExpression(path) {
      const node = path.node;
      let calleeName = 'unknown';

      if (node.callee.type === 'Identifier') {
        calleeName = node.callee.name;
      } else if (node.callee.type === 'MemberExpression') {
        const object = node.callee.object.name || 'unknown';
        const property = node.callee.property.name || 'unknown';
        calleeName = `${object}.${property}`;

        // Detect side effects
        if (['console', 'fs', 'process', 'require'].includes(object)) {
          if (!result.sideEffects.includes('io_operation')) {
            result.sideEffects.push('io_operation');
          }
        }
      }

      result.dependencies.push({
        function: calleeName,
        arity: node.arguments.length,
      });
    },

    IfStatement() {
      result.complexity += 1;
    },

    SwitchCase() {
      result.complexity += 1;
    },

    ConditionalExpression() {
      result.complexity += 1;
    },

    LogicalExpression(path) {
      if (path.node.operator === '&&' || path.node.operator === '||') {
        result.complexity += 1;
      }
    },

    WhileStatement() {
      result.complexity += 1;
    },

    ForStatement() {
      result.complexity += 1;
    },

    ForOfStatement() {
      result.complexity += 1;
    },

    ForInStatement() {
      result.complexity += 1;
    },
  });

  // Deduplicate imports
  const uniqueImports = [...new Set(result.imports.map(i => i.source))];
  result.imports = uniqueImports;

  console.log(JSON.stringify(result, null, 0));
  process.exit(0);
} catch (error) {
  console.error(JSON.stringify({
    error: error.message,
    stack: error.stack,
  }));
  process.exit(1);
}
