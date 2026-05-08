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
    tokens: Token_List;
    root: Node_Index;
    node_tags: [..] Ast_Node_Tag;
    node_main_tokens: [..] Token_Index;
    node_data: [..] Ast_Node_Data;
    extra_data: [..] int;
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
    array_add(*ast.node_tags, node_tag);
    array_add(*ast.node_main_tokens, main_token);
    array_add(*ast.node_data, data);
    ast.node_count += 1;
    return index;
}

ast_add_extra_slice :: (ast: *Ast, count: int) -> Extra_Index {
    start := ast.extra_count;
    array_add(*ast.extra_data, count);
    i := 0;
    while i < count {
        array_add(*ast.extra_data, 0);
        i += 1;
    }
    ast.extra_count += count + 1;
    return start;
}

ast_add_extra_values :: (ast: *Ast, values: [..] int) -> Extra_Index {
    start := ast.extra_count;
    array_add(*ast.extra_data, values.count);
    i := 0;
    while i < values.count {
        array_add(*ast.extra_data, values[i]);
        i += 1;
    }
    ast.extra_count += values.count + 1;
    return start;
}

ast_extra_count :: (ast: *Ast, start: Extra_Index) -> int {
    if start < 0 || start >= ast.extra_data.count return 0;
    return ast.extra_data[start];
}

ast_extra_at :: (ast: *Ast, start: Extra_Index, index: int) -> int {
    count := ast_extra_count(ast, start);
    if index < 0 || index >= count return 0;
    return ast.extra_data[start + 1 + index];
}

ast_tag :: (ast: *Ast, node: Node_Index) -> Ast_Node_Tag {
    if node < 0 || node >= ast.node_tags.count return .unsupported;
    return ast.node_tags[node];
}

ast_main_token :: (ast: *Ast, node: Node_Index) -> Token_Index {
    if node < 0 || node >= ast.node_main_tokens.count return 0;
    return ast.node_main_tokens[node];
}

ast_data :: (ast: *Ast, node: Node_Index) -> Ast_Node_Data {
    if node < 0 || node >= ast.node_data.count return ast_empty_data();
    return ast.node_data[node];
}

ast_token_slice :: (ast: *Ast, token_index: Token_Index) -> string {
    if token_index < 0 || token_index >= ast.tokens.items.count return "";
    tok := ast.tokens.items[token_index];
    return string_slice(ast.source, tok.start, tok.end);
}

ast_string_token_contents :: (ast: *Ast, token_index: Token_Index) -> string {
    text := ast_token_slice(ast, token_index);
    if text.count >= 2 && text[0] == #char "\"" {
        return string_slice(text, 1, text.count - 1);
    }
    if text.count > 0 && text[text.count - 1] == #char "\n" {
        return string_slice(text, 0, text.count - 1);
    }
    return text;
}

ast_empty_data :: () -> Ast_Node_Data {
    data: Ast_Node_Data;
    data.lhs = 0;
    data.rhs = 0;
    return data;
}
