use serde::{Deserialize, Serialize};
use std::env;
use std::fs;
use syn::visit::{self, Visit};
use syn::{File, Item, ItemFn, ItemStruct, ItemTrait, ItemImpl, Visibility};

#[derive(Serialize, Deserialize, Debug)]
struct ParseResult {
    functions: Vec<FunctionInfo>,
    structs: Vec<TypeInfo>,
    traits: Vec<TypeInfo>,
    impls: Vec<TypeInfo>,
    imports: Vec<String>,
    dependencies: Vec<DependencyInfo>,
    side_effects: Vec<String>,
    complexity: u32,
}

#[derive(Serialize, Deserialize, Debug)]
struct FunctionInfo {
    name: String,
    arity: usize,
    params: Vec<String>,
    public: bool,
    #[serde(skip_serializing_if = "Option::is_none")]
    async_fn: Option<bool>,
}

#[derive(Serialize, Deserialize, Debug)]
struct TypeInfo {
    name: String,
    kind: String,
    public: bool,
    #[serde(skip_serializing_if = "Option::is_none")]
    fields: Option<Vec<String>>,
    #[serde(skip_serializing_if = "Option::is_none")]
    methods: Option<Vec<String>>,
}

#[derive(Serialize, Deserialize, Debug)]
struct DependencyInfo {
    function: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    module: Option<String>,
}

struct RustVisitor {
    result: ParseResult,
}

impl RustVisitor {
    fn new() -> Self {
        RustVisitor {
            result: ParseResult {
                functions: Vec::new(),
                structs: Vec::new(),
                traits: Vec::new(),
                impls: Vec::new(),
                imports: Vec::new(),
                dependencies: Vec::new(),
                side_effects: Vec::new(),
                complexity: 1,
            },
        }
    }

    fn is_public(vis: &Visibility) -> bool {
        matches!(vis, Visibility::Public(_))
    }
}

impl<'ast> Visit<'ast> for RustVisitor {
    fn visit_item(&mut self, item: &'ast Item) {
        match item {
            Item::Fn(func) => self.visit_item_fn(func),
            Item::Struct(s) => self.visit_item_struct(s),
            Item::Trait(t) => self.visit_item_trait(t),
            Item::Impl(i) => self.visit_item_impl(i),
            Item::Use(u) => {
                // Extract import path
                let import = quote::quote!(#u).to_string();
                self.result.imports.push(import);
            }
            _ => {}
        }

        visit::visit_item(self, item);
    }

    fn visit_item_fn(&mut self, func: &'ast ItemFn) {
        let name = func.sig.ident.to_string();
        let arity = func.sig.inputs.len();
        let public = Self::is_public(&func.vis);

        let params: Vec<String> = func
            .sig
            .inputs
            .iter()
            .map(|arg| match arg {
                syn::FnArg::Receiver(_) => "self".to_string(),
                syn::FnArg::Typed(pat) => {
                    quote::quote!(#pat).to_string()
                }
            })
            .collect();

        self.result.functions.push(FunctionInfo {
            name,
            arity,
            params,
            public,
            async_fn: if func.sig.asyncness.is_some() {
                Some(true)
            } else {
                None
            },
        });

        // Calculate complexity
        self.visit_block(&func.block);
    }

    fn visit_item_struct(&mut self, s: &'ast ItemStruct) {
        let name = s.ident.to_string();
        let public = Self::is_public(&s.vis);

        let fields: Vec<String> = s
            .fields
            .iter()
            .filter_map(|f| f.ident.as_ref().map(|i| i.to_string()))
            .collect();

        self.result.structs.push(TypeInfo {
            name,
            kind: "struct".to_string(),
            public,
            fields: Some(fields),
            methods: None,
        });
    }

    fn visit_item_trait(&mut self, t: &'ast ItemTrait) {
        let name = t.ident.to_string();
        let public = Self::is_public(&t.vis);

        let methods: Vec<String> = t
            .items
            .iter()
            .filter_map(|item| match item {
                syn::TraitItem::Fn(f) => Some(f.sig.ident.to_string()),
                _ => None,
            })
            .collect();

        self.result.traits.push(TypeInfo {
            name,
            kind: "trait".to_string(),
            public,
            fields: None,
            methods: Some(methods),
        });
    }

    fn visit_item_impl(&mut self, i: &'ast ItemImpl) {
        let name = match &*i.self_ty {
            syn::Type::Path(p) => {
                p.path.segments.last().map(|s| s.ident.to_string())
            }
            _ => None,
        }
        .unwrap_or_else(|| "unknown".to_string());

        let methods: Vec<String> = i
            .items
            .iter()
            .filter_map(|item| match item {
                syn::ImplItem::Fn(f) => Some(f.sig.ident.to_string()),
                _ => None,
            })
            .collect();

        self.result.impls.push(TypeInfo {
            name,
            kind: "impl".to_string(),
            public: false,
            fields: None,
            methods: Some(methods),
        });
    }

    fn visit_expr(&mut self, expr: &'ast syn::Expr) {
        match expr {
            syn::Expr::If(_) => self.result.complexity += 1,
            syn::Expr::Match(m) => {
                self.result.complexity += m.arms.len() as u32;
            }
            syn::Expr::While(_) | syn::Expr::Loop(_) | syn::Expr::ForLoop(_) => {
                self.result.complexity += 1
            }
            syn::Expr::Call(call) => {
                // Extract function calls
                let func_name = quote::quote!(#call).to_string();

                // Detect side effects
                if func_name.contains("println!")
                    || func_name.contains("print!")
                    || func_name.contains("write!")
                    || func_name.contains("File::") {
                    if !self.result.side_effects.contains(&"io_operation".to_string()) {
                        self.result.side_effects.push("io_operation".to_string());
                    }
                }

                self.result.dependencies.push(DependencyInfo {
                    function: func_name,
                    module: None,
                });
            }
            _ => {}
        }

        visit::visit_expr(self, expr);
    }
}

fn main() {
    let args: Vec<String> = env::args().collect();

    if args.len() < 2 {
        eprintln!(r#"{{"error": "No file path provided"}}"#);
        std::process::exit(1);
    }

    let file_path = &args[1];

    match fs::read_to_string(file_path) {
        Ok(content) => match syn::parse_file(&content) {
            Ok(syntax_tree) => {
                let mut visitor = RustVisitor::new();
                visitor.visit_file(&syntax_tree);

                match serde_json::to_string(&visitor.result) {
                    Ok(json) => {
                        println!("{}", json);
                        std::process::exit(0);
                    }
                    Err(e) => {
                        eprintln!(r#"{{"error": "JSON encoding failed: {}"}}"#, e);
                        std::process::exit(1);
                    }
                }
            }
            Err(e) => {
                eprintln!(r#"{{"error": "Parse error: {}"}}"#, e);
                std::process::exit(1);
            }
        },
        Err(e) => {
            eprintln!(r#"{{"error": "Failed to read file: {}"}}"#, e);
            std::process::exit(1);
        }
    }
}
