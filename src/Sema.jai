// Port of bootstrap/src/Sema.zig.

Typed :: struct {
    main_proc: Node_Index;
    node_types: [..] Type;
}

sema_analyze :: (ast: *Ast, resolved: *Resolved, pool: *Intern_Pool, diag: *Diagnostic) -> Typed {
    typed: Typed;
    typed.main_proc = resolved.main_proc;
    i := 0;
    while i < ast.node_count {
        array_add(*typed.node_types, type_void());
        i += 1;
    }

    if ast.root != NULL_NODE {
        root_data := ast_data(ast, ast.root);
        count := ast_extra_count(ast, root_data.lhs);
        main_count := 0;
        decl_index := 0;
        while decl_index < count {
            decl := ast_extra_at(ast, root_data.lhs, decl_index);
            if ast_tag(ast, decl) == .proc_decl {
                name := ast_token_slice(ast, ast_main_token(ast, decl));
                if name == "main" main_count += 1;
                sema_analyze_proc(ast, *typed, decl, diag);
            } else {
                sema_analyze_node(ast, *typed, decl, diag);
            }
            decl_index += 1;
        }
        if resolved.require_main && main_count != 1 {
            diagnostic_fail_at(diag, 0, "expected exactly one main procedure");
        }
    }
    return typed;
}

typed_type_of :: (typed: *Typed, node: Node_Index) -> Type {
    if node < 0 || node >= typed.node_types.count return type_void();
    return typed.node_types[node];
}

typed_set_type :: (typed: *Typed, node: Node_Index, ty: Type) {
    if node < 0 return;
    while node >= typed.node_types.count array_add(*typed.node_types, type_void());
    typed.node_types[node] = ty;
}

sema_analyze_proc :: (ast: *Ast, typed: *Typed, proc: Node_Index, diag: *Diagnostic) {
    typed_set_type(typed, proc, type_void());
    body := ast_data(ast, proc).lhs;
    if body != NULL_NODE sema_analyze_node(ast, typed, body, diag);
}

sema_analyze_node :: (ast: *Ast, typed: *Typed, node: Node_Index, diag: *Diagnostic) -> Type {
    if node == NULL_NODE {
        return type_void();
    }

    tag := ast_tag(ast, node);
    ty := type_void();

    if tag == .import_decl || tag == .load_decl {
        ty = type_any();
    } else if tag == .const_decl {
        ty = sema_analyze_node(ast, typed, ast_data(ast, node).lhs, diag);
    } else if tag == .var_decl {
        data := ast_data(ast, node);
        if data.rhs != NULL_NODE {
            ty = sema_analyze_node(ast, typed, data.rhs, diag);
        } else if data.lhs != NULL_NODE {
            ty = sema_type_from_type_expr(ast, data.lhs);
        }
    } else if tag == .block || tag == .stmt_list {
        data := ast_data(ast, node);
        count := ast_extra_count(ast, data.lhs);
        i := 0;
        while i < count {
            sema_analyze_node(ast, typed, ast_extra_at(ast, data.lhs, i), diag);
            i += 1;
        }
        ty = type_void();
    } else if tag == .string_literal {
        ty = type_string();
    } else if tag == .integer_literal || tag == .char_literal {
        ty = type_init(S64_TYPE);
    } else if tag == .float_literal {
        ty = type_init(FLOAT32_TYPE);
    } else if tag == .bool_literal {
        ty = type_bool();
    } else if tag == .null_literal {
        ty = type_any();
    } else if tag == .type_expr || tag == .struct_type || tag == .union_type || tag == .enum_type || tag == .proc_type {
        ty = type_init(TYPE_TYPE);
    } else if tag == .return_stmt || tag == .expr_stmt || tag == .assign_stmt || tag == .meta_stmt || tag == .run_expr {
        data := ast_data(ast, node);
        if data.lhs != NULL_NODE sema_analyze_node(ast, typed, data.lhs, diag);
        if data.rhs != NULL_NODE sema_analyze_node(ast, typed, data.rhs, diag);
        ty = type_void();
    } else {
        ty = type_any();
    }

    typed_set_type(typed, node, ty);
    return ty;
}

sema_type_from_type_expr :: (ast: *Ast, node: Node_Index) -> Type {
    if node == NULL_NODE return type_void();
    tok := ast_main_token(ast, node);
    name := ast_token_slice(ast, tok);
    if name == "void" return type_void();
    if name == "bool" return type_bool();
    if name == "string" return type_string();
    if name == "int" return type_init(S64_TYPE);
    if name == "s64" return type_init(S64_TYPE);
    if name == "u64" return type_init(U64_TYPE);
    if name == "float" return type_init(FLOAT32_TYPE);
    if name == "float32" return type_init(FLOAT32_TYPE);
    if name == "float64" return type_init(FLOAT64_TYPE);
    return type_any();
}
