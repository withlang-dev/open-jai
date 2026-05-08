// Port of bootstrap/src/resolve.zig.

Resolved :: struct {
    require_main: bool;
    main_proc: Node_Index;
    imports_basic: bool;
    symbols: [..] Symbol_Binding;
}

Symbol_Kind :: enum {
    none;
    proc;
    placeholder;
    builtin_print;
    builtin_assert;
    builtin_array_add;
    builtin_array_free;
    builtin_alloc;
    builtin_free;
    builtin_exit;
    const_value;
}

Symbol :: struct {
    kind: Symbol_Kind;
    node: Node_Index;
}

Symbol_Binding :: struct {
    name: string;
    symbol: Symbol;
}

resolve :: (ast: *Ast, diag: *Diagnostic, require_main: bool) -> Resolved {
    r: Resolved;
    r.require_main = require_main;
    r.main_proc = NULL_NODE;
    resolved_add_builtin(*r, "print", .builtin_print);
    resolved_add_builtin(*r, "assert", .builtin_assert);
    resolved_add_builtin(*r, "array_add", .builtin_array_add);
    resolved_add_builtin(*r, "array_free", .builtin_array_free);
    resolved_add_builtin(*r, "alloc", .builtin_alloc);
    resolved_add_builtin(*r, "free", .builtin_free);
    resolved_add_builtin(*r, "exit", .builtin_exit);

    if ast.root == NULL_NODE {
        if require_main diagnostic_fail_at(diag, 0, "No program entry point was found. (The designated entry point name is 'main'.)");
        return r;
    }

    root_data := ast_data(ast, ast.root);
    count := ast_extra_count(ast, root_data.lhs);
    i := 0;
    while i < count {
        decl := ast_extra_at(ast, root_data.lhs, i);
        resolve_top_level_decl(ast, *r, decl, diag);
        i += 1;
    }

    if require_main && r.main_proc == NULL_NODE {
        diagnostic_fail_at(diag, 0, "No program entry point was found. (The designated entry point name is 'main'.)");
    }
    return r;
}

resolve_top_level_decl :: (ast: *Ast, r: *Resolved, decl: Node_Index, diag: *Diagnostic) {
    tag := ast_tag(ast, decl);
    if tag == .import_decl {
        module_name := ast_string_token_contents(ast, ast_data(ast, decl).lhs);
        resolve_import(ast, r, module_name);
        return;
    }

    if tag == .proc_decl {
        name := ast_token_slice(ast, ast_main_token(ast, decl));
        sym: Symbol;
        sym.kind = .proc;
        sym.node = decl;
        resolved_put(r, name, sym);
        if name == "main" r.main_proc = decl;
        return;
    }

    if tag == .const_decl || tag == .var_decl {
        name := ast_token_slice(ast, ast_main_token(ast, decl));
        sym: Symbol;
        sym.kind = .const_value;
        if tag == .const_decl sym.node = ast_data(ast, decl).lhs;
        else sym.node = decl;
        resolved_put(r, name, sym);
        return;
    }

    if tag == .unsupported {
        diagnostic_note_at(diag, ast.tokens.items[ast_main_token(ast, decl)].start, "resolver saw an unsupported top-level node");
    }
}

resolve_import :: (ast: *Ast, r: *Resolved, module_name: string) {
    if module_name == "Basic" {
        r.imports_basic = true;
        resolved_add_builtin(r, "print", .builtin_print);
        resolved_add_builtin(r, "assert", .builtin_assert);
        resolved_add_builtin(r, "array_add", .builtin_array_add);
        resolved_add_builtin(r, "array_free", .builtin_array_free);
        resolved_add_builtin(r, "alloc", .builtin_alloc);
        resolved_add_builtin(r, "free", .builtin_free);
        resolved_add_builtin(r, "exit", .builtin_exit);
        resolved_add_placeholder(r, "context");
        resolved_add_placeholder(r, "temp");
        resolved_add_placeholder(r, "String_Builder");
        return;
    }

    if module_name == "Compiler" {
        resolved_add_placeholder(r, "Workspace");
        resolved_add_placeholder(r, "Build_Options");
        resolved_add_placeholder(r, "Code");
        resolved_add_placeholder(r, "Code_Node");
        resolved_add_placeholder(r, "compiler_create_workspace");
        resolved_add_placeholder(r, "compiler_get_nodes");
        resolved_add_placeholder(r, "compiler_get_code");
        resolved_add_placeholder(r, "code_to_string");
        return;
    }

    resolved_add_placeholder(r, module_name);
}

resolved_add_builtin :: (r: *Resolved, name: string, kind: Symbol_Kind) {
    sym: Symbol;
    sym.kind = kind;
    sym.node = NULL_NODE;
    resolved_put(r, name, sym);
}

resolved_add_placeholder :: (r: *Resolved, name: string) {
    sym: Symbol;
    sym.kind = .placeholder;
    sym.node = NULL_NODE;
    resolved_put(r, name, sym);
}

resolved_put :: (r: *Resolved, name: string, symbol: Symbol) {
    i := 0;
    while i < r.symbols.count {
        if r.symbols[i].name == name {
            r.symbols[i].symbol = symbol;
            return;
        }
        i += 1;
    }
    binding: Symbol_Binding;
    binding.name = name;
    binding.symbol = symbol;
    array_add(*r.symbols, binding);
}

resolved_lookup :: (r: *Resolved, name: string) -> Symbol {
    i := 0;
    while i < r.symbols.count {
        if r.symbols[i].name == name return r.symbols[i].symbol;
        i += 1;
    }
    sym: Symbol;
    sym.kind = .none;
    sym.node = NULL_NODE;
    return sym;
}
