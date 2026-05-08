// Port of bootstrap/src/Ast.zig.

Ast_Node_Tag :: enum {
    root;
    import_decl;
    load_decl;
    const_decl;
    var_decl;
    proc_decl;
    block;
    expr_stmt;
    return_stmt;
    identifier;
    integer_literal;
    float_literal;
    string_literal;
    bool_literal;
    call_expr;
    binary_expr;
    unary_expr;
    run_expr;
}

Ast_Node :: struct {
    tag: Ast_Node_Tag;
    main_token: Token_Index;
    lhs: Node_Index;
    rhs: Node_Index;
}

Ast :: struct {
    source: string;
    node_count: int;
    token_count: int;
}

ast_init :: (source: string) -> Ast {
    ast: Ast;
    ast.source = source;
    ast.node_count = 1;
    ast.token_count = 0;
    return ast;
}

