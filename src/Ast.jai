// Port of bootstrap/src/Ast.zig.

Node_Index :: int;
Extra_Index :: int;
NULL_NODE :: -1;

Ast_Node_Tag :: enum {
    root;
    import_decl;
    load_decl;
    scope_decl;
    add_context_decl;
    proc_decl;
    const_decl;
    param_list;
    block;
    expr_stmt;
    var_decl;
    return_stmt;
    stmt_list;
    type_expr;
    pointer_type;
    proc_type;
    array_type;
    struct_type;
    union_type;
    enum_type;
    if_stmt;
    ifx_expr;
    for_stmt;
    while_stmt;
    defer_stmt;
    break_stmt;
    continue_stmt;
    aggregate_literal;
    typed_aggregate_literal;
    typed_array_literal;
    field_access;
    index_expr;
    call_expr;
    assign_stmt;
    char_literal;
    type_of_expr;
    size_of_expr;
    run_expr;
    meta_expr;
    meta_stmt;
    is_constant_expr;
    unary_expr;
    binary_expr;
    identifier;
    string_literal;
    integer_literal;
    float_literal;
    bool_literal;
    null_literal;
    undefined_literal;
    unsupported;
}

Ast_Node_Data :: struct {
    lhs: int;
    rhs: int;
}

Ast_Node :: struct {
    tag: Ast_Node_Tag;
    main_token: Token_Index;
    data: Ast_Node_Data;
}

Ast :: struct {
    source: string;
    root: Node_Index;
    node_count: int;
    token_count: int;
    extra_count: int;
}

ast_init :: (source: string) -> Ast {
    ast: Ast;
    ast.source = source;
    ast.root = NULL_NODE;
    ast.node_count = 0;
    ast.token_count = 0;
    ast.extra_count = 0;
    return ast;
}

ast_add_node :: (ast: *Ast, node_tag: Ast_Node_Tag, main_token: Token_Index, data: Ast_Node_Data) -> Node_Index {
    index := ast.node_count;
    ast.node_count += 1;
    return index;
}

ast_add_extra_slice :: (ast: *Ast, count: int) -> Extra_Index {
    start := ast.extra_count;
    ast.extra_count += count + 1;
    return start;
}

ast_empty_data :: () -> Ast_Node_Data {
    data: Ast_Node_Data;
    data.lhs = 0;
    data.rhs = 0;
    return data;
}

