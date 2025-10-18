package main

import (
	"encoding/json"
	"fmt"
	"go/ast"
	"go/parser"
	"go/token"
	"os"
	"strings"
	"unicode"
)

// Result represents the parsing result
type Result struct {
	Functions    []FunctionInfo   `json:"functions"`
	Structs      []TypeInfo       `json:"structs"`
	Interfaces   []TypeInfo       `json:"interfaces"`
	Imports      []string         `json:"imports"`
	Dependencies []DependencyInfo `json:"dependencies"`
	SideEffects  []string         `json:"side_effects"`
	Complexity   int              `json:"complexity"`
}

// FunctionInfo represents a function declaration
type FunctionInfo struct {
	Name     string   `json:"name"`
	Arity    int      `json:"arity"`
	Params   []string `json:"params"`
	Exported bool     `json:"exported"`
	Receiver *string  `json:"receiver,omitempty"`
}

// TypeInfo represents a struct or interface
type TypeInfo struct {
	Name     string   `json:"name"`
	Exported bool     `json:"exported"`
	Kind     string   `json:"kind"`
	Fields   []string `json:"fields,omitempty"`
	Methods  []string `json:"methods,omitempty"`
}

// DependencyInfo represents a function call
type DependencyInfo struct {
	Function string  `json:"function"`
	Package  *string `json:"package,omitempty"`
}

func main() {
	if len(os.Args) < 2 {
		printError("No file path provided")
		os.Exit(1)
	}

	filePath := os.Args[1]

	content, err := os.ReadFile(filePath)
	if err != nil {
		printError(fmt.Sprintf("Failed to read file: %v", err))
		os.Exit(1)
	}

	result, err := parseGoCode(string(content))
	if err != nil {
		printError(fmt.Sprintf("Parse error: %v", err))
		os.Exit(1)
	}

	output, err := json.Marshal(result)
	if err != nil {
		printError(fmt.Sprintf("Failed to encode JSON: %v", err))
		os.Exit(1)
	}

	fmt.Println(string(output))
}

func parseGoCode(source string) (*Result, error) {
	fset := token.NewFileSet()
	file, err := parser.ParseFile(fset, "", source, parser.ParseComments)
	if err != nil {
		return nil, err
	}

	result := &Result{
		Functions:    []FunctionInfo{},
		Structs:      []TypeInfo{},
		Interfaces:   []TypeInfo{},
		Imports:      []string{},
		Dependencies: []DependencyInfo{},
		SideEffects:  []string{},
		Complexity:   1,
	}

	// Extract imports
	for _, imp := range file.Imports {
		path := strings.Trim(imp.Path.Value, `"`)
		result.Imports = append(result.Imports, path)
	}

	// Walk the AST
	ast.Inspect(file, func(n ast.Node) bool {
		switch node := n.(type) {
		case *ast.FuncDecl:
			funcInfo := extractFunction(node)
			result.Functions = append(result.Functions, funcInfo)

		case *ast.GenDecl:
			if node.Tok == token.TYPE {
				for _, spec := range node.Specs {
					if typeSpec, ok := spec.(*ast.TypeSpec); ok {
						typeInfo := extractType(typeSpec)
						if typeInfo.Kind == "struct" {
							result.Structs = append(result.Structs, typeInfo)
						} else if typeInfo.Kind == "interface" {
							result.Interfaces = append(result.Interfaces, typeInfo)
						}
					}
				}
			}

		case *ast.CallExpr:
			dep := extractDependency(node)
			result.Dependencies = append(result.Dependencies, dep)

			// Detect side effects
			funcName := getFuncName(node.Fun)
			if isSideEffectFunc(funcName) {
				if !contains(result.SideEffects, "io_operation") {
					result.SideEffects = append(result.SideEffects, "io_operation")
				}
			}

		case *ast.IfStmt:
			result.Complexity++

		case *ast.ForStmt, *ast.RangeStmt:
			result.Complexity++

		case *ast.SwitchStmt, *ast.TypeSwitchStmt:
			result.Complexity++

		case *ast.CaseClause:
			if len(node.List) > 0 {
				result.Complexity++
			}

		case *ast.BinaryExpr:
			if node.Op == token.LAND || node.Op == token.LOR {
				result.Complexity++
			}
		}

		return true
	})

	return result, nil
}

func extractFunction(node *ast.FuncDecl) FunctionInfo {
	info := FunctionInfo{
		Name:     node.Name.Name,
		Exported: isExported(node.Name.Name),
		Params:   []string{},
	}

	// Extract receiver if it's a method
	if node.Recv != nil && len(node.Recv.List) > 0 {
		receiverType := getTypeName(node.Recv.List[0].Type)
		info.Receiver = &receiverType
	}

	// Extract parameters
	if node.Type.Params != nil {
		for _, param := range node.Type.Params.List {
			paramType := getTypeName(param.Type)
			if len(param.Names) > 0 {
				for _, name := range param.Names {
					info.Params = append(info.Params, name.Name)
					info.Arity++
				}
			} else {
				info.Params = append(info.Params, paramType)
				info.Arity++
			}
		}
	}

	return info
}

func extractType(spec *ast.TypeSpec) TypeInfo {
	info := TypeInfo{
		Name:     spec.Name.Name,
		Exported: isExported(spec.Name.Name),
		Fields:   []string{},
		Methods:  []string{},
	}

	switch t := spec.Type.(type) {
	case *ast.StructType:
		info.Kind = "struct"
		if t.Fields != nil {
			for _, field := range t.Fields.List {
				if len(field.Names) > 0 {
					for _, name := range field.Names {
						info.Fields = append(info.Fields, name.Name)
					}
				}
			}
		}

	case *ast.InterfaceType:
		info.Kind = "interface"
		if t.Methods != nil {
			for _, method := range t.Methods.List {
				if len(method.Names) > 0 {
					for _, name := range method.Names {
						info.Methods = append(info.Methods, name.Name)
					}
				}
			}
		}

	default:
		info.Kind = "other"
	}

	return info
}

func extractDependency(node *ast.CallExpr) DependencyInfo {
	funcName := getFuncName(node.Fun)
	dep := DependencyInfo{
		Function: funcName,
	}

	// Try to extract package name
	if sel, ok := node.Fun.(*ast.SelectorExpr); ok {
		if ident, ok := sel.X.(*ast.Ident); ok {
			dep.Package = &ident.Name
		}
	}

	return dep
}

func getFuncName(expr ast.Expr) string {
	switch e := expr.(type) {
	case *ast.Ident:
		return e.Name
	case *ast.SelectorExpr:
		return fmt.Sprintf("%s.%s", getFuncName(e.X), e.Sel.Name)
	default:
		return "unknown"
	}
}

func getTypeName(expr ast.Expr) string {
	switch t := expr.(type) {
	case *ast.Ident:
		return t.Name
	case *ast.StarExpr:
		return "*" + getTypeName(t.X)
	case *ast.SelectorExpr:
		return fmt.Sprintf("%s.%s", getTypeName(t.X), t.Sel.Name)
	case *ast.ArrayType:
		return "[]" + getTypeName(t.Elt)
	default:
		return "unknown"
	}
}

func isExported(name string) bool {
	if len(name) == 0 {
		return false
	}
	return unicode.IsUpper(rune(name[0]))
}

func isSideEffectFunc(funcName string) bool {
	sideEffectFuncs := []string{
		"fmt.Print", "fmt.Println", "fmt.Printf",
		"log.Print", "log.Println", "log.Printf",
		"os.Create", "os.Open", "os.Remove",
		"ioutil.ReadFile", "ioutil.WriteFile",
	}

	for _, sef := range sideEffectFuncs {
		if strings.Contains(funcName, sef) {
			return true
		}
	}

	return false
}

func contains(slice []string, item string) bool {
	for _, s := range slice {
		if s == item {
			return true
		}
	}
	return false
}

func printError(msg string) {
	errorMsg := map[string]string{"error": msg}
	output, _ := json.Marshal(errorMsg)
	fmt.Println(string(output))
}
