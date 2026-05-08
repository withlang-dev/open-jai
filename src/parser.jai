// Port of bootstrap/src/parser.zig.

Parser :: struct {
    source: string;
    tokens: Token_List;
    diag: *Diagnostic;
    index: Token_Index;
    ast: Ast;
}

parse :: (source: string, tokens: Token_List, diag: *Diagnostic) -> Ast {
    ast := ast_init(source);
    ast.tokens = tokens;
    ast.token_count = tokens.count;
    if tokens.count == 0 {
        diagnostic_fail_at(diag, 0, "parser received no tokens");
    }

    parser: Parser;
    parser.source = source;
    parser.tokens = tokens;
    parser.diag = diag;
    parser.index = 0;
    parser.ast = ast;
    parser_parse_root(*parser);
    return parser.ast;
}

parser_parse_root :: (parser: *Parser) {
    decls: [..] int;
    while !parser_check(parser, .eof) {
        decl := parser_parse_top_level_decl(parser);
        if decl != NULL_NODE array_add(*decls, decl);
        parser_match_discard(parser, .semicolon);
    }
    extra := ast_add_extra_values(*parser.ast, decls);
    data := ast_empty_data();
    data.lhs = extra;
    data.rhs = decls.count;
    parser.ast.root = ast_add_node(*parser.ast, .root, 0, data);
}

parser_parse_top_level_decl :: (parser: *Parser) -> Node_Index {
    if parser_match(parser, .directive_import) {
        tok := parser.index - 1;
        return parser_parse_import(parser, tok);
    }
    if parser_match(parser, .directive_load) {
        tok := parser.index - 1;
        return parser_parse_load(parser, tok);
    }
    if parser_check(parser, .identifier) {
        if parser_peek_tag(parser, 1) == .colon_colon {
            return parser_parse_identifier_const_or_proc(parser);
        }
        if parser_peek_tag(parser, 1) == .colon || parser_peek_tag(parser, 1) == .colon_equal {
            return parser_parse_identifier_var(parser);
        }
    }

    tok := parser.index;
    parser_skip_to_decl_boundary(parser);
    return ast_add_node(*parser.ast, .unsupported, tok, ast_empty_data());
}

parser_parse_import :: (parser: *Parser, tok: Token_Index) -> Node_Index {
    str_tok := parser_expect(parser, .string_literal, "expected module string after #import");
    parser_expect(parser, .semicolon, "expected semicolon after import");
    data := ast_empty_data();
    data.lhs = str_tok;
    return ast_add_node(*parser.ast, .import_decl, tok, data);
}

parser_parse_load :: (parser: *Parser, tok: Token_Index) -> Node_Index {
    str_tok := parser_expect(parser, .string_literal, "expected file string after #load");
    parser_expect(parser, .semicolon, "expected semicolon after #load");
    data := ast_empty_data();
    data.lhs = str_tok;
    return ast_add_node(*parser.ast, .load_decl, tok, data);
}

parser_parse_identifier_const_or_proc :: (parser: *Parser) -> Node_Index {
    name_tok := parser_expect(parser, .identifier, "expected declaration name");
    parser_expect(parser, .colon_colon, "expected '::' after declaration name");
    if parser_check(parser, .l_paren) {
        return parser_parse_proc_decl_after_name(parser, name_tok);
    }

    value := parser_parse_opaque_expr_until_terminator(parser);
    parser_match_discard(parser, .semicolon);
    data := ast_empty_data();
    data.lhs = value;
    return ast_add_node(*parser.ast, .const_decl, name_tok, data);
}

parser_parse_identifier_var :: (parser: *Parser) -> Node_Index {
    name_tok := parser_expect(parser, .identifier, "expected declaration name");
    if parser_match_discard(parser, .colon_equal) {
        init := parser_parse_opaque_expr_until_terminator(parser);
        parser_match_discard(parser, .semicolon);
        data := ast_empty_data();
        data.lhs = NULL_NODE;
        data.rhs = init;
        return ast_add_node(*parser.ast, .var_decl, name_tok, data);
    }

    parser_expect(parser, .colon, "expected ':' in declaration");
    type_expr := parser_parse_opaque_type_until_init_or_terminator(parser);
    init := NULL_NODE;
    if parser_match_discard(parser, .equal) init = parser_parse_opaque_expr_until_terminator(parser);
    parser_match_discard(parser, .semicolon);
    data := ast_empty_data();
    data.lhs = type_expr;
    data.rhs = init;
    return ast_add_node(*parser.ast, .var_decl, name_tok, data);
}

parser_parse_proc_decl_after_name :: (parser: *Parser, name_tok: Token_Index) -> Node_Index {
    params := parser_parse_balanced_node(parser, .l_paren, .r_paren, .param_list);
    body := NULL_NODE;
    return_type := NULL_NODE;
    if parser_match_discard(parser, .arrow) {
        return_type = parser_parse_opaque_type_until_body_or_terminator(parser);
    }
    if parser_check(parser, .l_brace) body = parser_parse_block(parser);
    else parser_match_discard(parser, .semicolon);

    sig_values: [..] int;
    array_add(*sig_values, params);
    array_add(*sig_values, return_type);
    sig_extra := ast_add_extra_values(*parser.ast, sig_values);

    data := ast_empty_data();
    data.lhs = body;
    data.rhs = sig_extra;
    return ast_add_node(*parser.ast, .proc_decl, name_tok, data);
}

parser_parse_block :: (parser: *Parser) -> Node_Index {
    open_tok := parser_expect(parser, .l_brace, "expected block");
    statements: [..] int;
    while !parser_check(parser, .r_brace) && !parser_check(parser, .eof) {
        stmt := parser_parse_statement(parser);
        if stmt != NULL_NODE array_add(*statements, stmt);
        parser_match_discard(parser, .semicolon);
    }
    parser_expect(parser, .r_brace, "expected '}' after block");
    extra := ast_add_extra_values(*parser.ast, statements);
    data := ast_empty_data();
    data.lhs = extra;
    data.rhs = statements.count;
    return ast_add_node(*parser.ast, .block, open_tok, data);
}

parser_parse_statement :: (parser: *Parser) -> Node_Index {
    if parser_match(parser, .keyword_if) {
        tok := parser.index - 1;
        return parser_parse_if_statement(parser, tok);
    }
    if parser_match(parser, .keyword_while) {
        tok := parser.index - 1;
        return parser_parse_while_statement(parser, tok);
    }
    if parser_match(parser, .keyword_return) {
        tok := parser.index - 1;
        expr := NULL_NODE;
        if !parser_check(parser, .semicolon) && !parser_check(parser, .r_brace) expr = parser_parse_expression(parser, 0);
        parser_match_discard(parser, .semicolon);
        data := ast_empty_data();
        data.lhs = expr;
        return ast_add_node(*parser.ast, .return_stmt, tok, data);
    }
    if parser_match(parser, .keyword_break) {
        tok := parser.index - 1;
        parser_match_discard(parser, .semicolon);
        return ast_add_node(*parser.ast, .break_stmt, tok, ast_empty_data());
    }
    if parser_match(parser, .keyword_continue) {
        tok := parser.index - 1;
        parser_match_discard(parser, .semicolon);
        return ast_add_node(*parser.ast, .continue_stmt, tok, ast_empty_data());
    }
    if parser_match(parser, .keyword_defer) {
        tok := parser.index - 1;
        child := parser_parse_statement(parser);
        data := ast_empty_data();
        data.lhs = child;
        return ast_add_node(*parser.ast, .defer_stmt, tok, data);
    }
    if parser_match(parser, .directive_run) {
        tok := parser.index - 1;
        operand := NULL_NODE;
        if parser_check(parser, .l_brace) operand = parser_parse_block(parser);
        else operand = parser_parse_expression(parser, 0);
        parser_match_discard(parser, .semicolon);
        data := ast_empty_data();
        data.lhs = operand;
        return ast_add_node(*parser.ast, .run_expr, tok, data);
    }
    if parser_match(parser, .directive_import) {
        tok := parser.index - 1;
        return parser_parse_import(parser, tok);
    }
    if parser_match(parser, .directive_load) {
        tok := parser.index - 1;
        return parser_parse_load(parser, tok);
    }

    if parser_check(parser, .identifier) {
        if parser_peek_tag(parser, 1) == .colon || parser_peek_tag(parser, 1) == .colon_equal {
            return parser_parse_identifier_var(parser);
        }
    }

    expr := parser_parse_expression(parser, 0);
    if parser_is_assignment_token(parser_peek_tag(parser, 0)) {
        op_tok := parser.index;
        op_tag := parser_peek_tag(parser, 0);
        parser.index = parser.index + 1;
        rhs := parser_parse_expression(parser, 0);
        if op_tag != .equal {
            rhs = parser_make_compound_assignment_rhs(parser, expr, rhs, op_tok);
        }
        parser_match_discard(parser, .semicolon);
        data := ast_empty_data();
        data.lhs = expr;
        data.rhs = rhs;
        return ast_add_node(*parser.ast, .assign_stmt, op_tok, data);
    }

    parser_match_discard(parser, .semicolon);
    data := ast_empty_data();
    data.lhs = expr;
    return ast_add_node(*parser.ast, .expr_stmt, ast_main_token(*parser.ast, expr), data);
}

parser_parse_if_statement :: (parser: *Parser, tok: Token_Index) -> Node_Index {
    cond := parser_parse_expression(parser, 0);
    then_block := NULL_NODE;
    else_block := NULL_NODE;
    if parser_check(parser, .l_brace) then_block = parser_parse_block(parser);
    else then_block = parser_parse_statement_as_block(parser);

    if parser_match(parser, .keyword_else) {
        if parser_check(parser, .keyword_if) {
            nested := parser_parse_statement(parser);
            values: [..] int;
            array_add(*values, nested);
            extra := ast_add_extra_values(*parser.ast, values);
            data := ast_empty_data();
            data.lhs = extra;
            data.rhs = 1;
            else_block = ast_add_node(*parser.ast, .block, tok, data);
        } else if parser_check(parser, .l_brace) {
            else_block = parser_parse_block(parser);
        } else {
            else_block = parser_parse_statement_as_block(parser);
        }
    }

    values: [..] int;
    array_add(*values, then_block);
    array_add(*values, else_block);
    extra := ast_add_extra_values(*parser.ast, values);
    data := ast_empty_data();
    data.lhs = cond;
    data.rhs = extra;
    return ast_add_node(*parser.ast, .if_stmt, tok, data);
}

parser_parse_while_statement :: (parser: *Parser, tok: Token_Index) -> Node_Index {
    cond := parser_parse_expression(parser, 0);
    body := NULL_NODE;
    if parser_check(parser, .l_brace) body = parser_parse_block(parser);
    else body = parser_parse_statement_as_block(parser);
    data := ast_empty_data();
    data.lhs = cond;
    data.rhs = body;
    return ast_add_node(*parser.ast, .while_stmt, tok, data);
}

parser_parse_statement_as_block :: (parser: *Parser) -> Node_Index {
    stmt := parser_parse_statement(parser);
    values: [..] int;
    if stmt != NULL_NODE array_add(*values, stmt);
    extra := ast_add_extra_values(*parser.ast, values);
    data := ast_empty_data();
    data.lhs = extra;
    data.rhs = values.count;
    return ast_add_node(*parser.ast, .block, ast_main_token(*parser.ast, stmt), data);
}

parser_parse_balanced_node :: (parser: *Parser, open_tag: Token_Tag, close_tag: Token_Tag, node_tag: Ast_Node_Tag) -> Node_Index {
    open_tok := parser_expect(parser, open_tag, "expected balanced construct");
    depth := 1;
    while depth > 0 && !parser_check(parser, .eof) {
        tag := parser_peek_tag(parser, 0);
        parser.index = parser.index + 1;
        if tag == open_tag depth = depth + 1;
        else if tag == close_tag depth = depth - 1;
    }
    data := ast_empty_data();
    return ast_add_node(*parser.ast, node_tag, open_tok, data);
}

parser_parse_opaque_expr_until_terminator :: (parser: *Parser) -> Node_Index {
    start := parser.index;
    parser_skip_to_expr_boundary(parser);
    return ast_add_node(*parser.ast, .unsupported, start, ast_empty_data());
}

parser_parse_opaque_type_until_init_or_terminator :: (parser: *Parser) -> Node_Index {
    start := parser.index;
    parens := 0;
    brackets := 0;
    while !parser_check(parser, .eof) {
        tag := parser_peek_tag(parser, 0);
        if parens == 0 && brackets == 0 && (tag == .semicolon || tag == .equal || tag == .l_brace) break;
        parser.index = parser.index + 1;
        if tag == .l_paren parens = parens + 1;
        else if tag == .r_paren && parens > 0 parens = parens - 1;
        else if tag == .l_bracket brackets = brackets + 1;
        else if tag == .r_bracket && brackets > 0 brackets = brackets - 1;
    }
    return ast_add_node(*parser.ast, .type_expr, start, ast_empty_data());
}

parser_parse_opaque_type_until_body_or_terminator :: (parser: *Parser) -> Node_Index {
    start := parser.index;
    parens := 0;
    brackets := 0;
    while !parser_check(parser, .eof) {
        tag := parser_peek_tag(parser, 0);
        if parens == 0 && brackets == 0 && (tag == .semicolon || tag == .l_brace) break;
        parser.index = parser.index + 1;
        if tag == .l_paren parens = parens + 1;
        else if tag == .r_paren && parens > 0 parens = parens - 1;
        else if tag == .l_bracket brackets = brackets + 1;
        else if tag == .r_bracket && brackets > 0 brackets = brackets - 1;
    }
    return ast_add_node(*parser.ast, .type_expr, start, ast_empty_data());
}

parser_parse_expression :: (parser: *Parser, min_prec: int) -> Node_Index {
    lhs := parser_parse_unary(parser);
    done := false;
    while !done {
        tag := parser_peek_tag(parser, 0);
        prec := parser_binary_precedence(tag);
        if prec < min_prec {
            done = true;
        } else {
            op_tok := parser.index;
            parser.index = parser.index + 1;
            rhs := parser_parse_expression(parser, prec + 1);
            data := ast_empty_data();
            data.lhs = lhs;
            data.rhs = rhs;
            lhs = ast_add_node(*parser.ast, .binary_expr, op_tok, data);
        }
    }
    return lhs;
}

parser_parse_unary :: (parser: *Parser) -> Node_Index {
    tag := parser_peek_tag(parser, 0);
    if tag == .bang || tag == .minus || tag == .ampersand || tag == .star || tag == .tilde {
        tok := parser.index;
        parser.index = parser.index + 1;
        operand := parser_parse_unary(parser);
        data := ast_empty_data();
        data.lhs = operand;
        return ast_add_node(*parser.ast, .unary_expr, tok, data);
    }
    return parser_parse_postfix(parser);
}

parser_parse_postfix :: (parser: *Parser) -> Node_Index {
    expr := parser_parse_primary(parser);
    done := false;
    while !done {
        if parser_match(parser, .l_paren) {
            args: [..] int;
            if !parser_check(parser, .r_paren) {
                args_done := false;
                while !args_done {
                    arg := parser_parse_expression(parser, 0);
                    array_add(*args, arg);
                    if !parser_match_discard(parser, .comma) args_done = true;
                }
            }
            parser_expect(parser, .r_paren, "expected ')' after arguments");
            extra := ast_add_extra_values(*parser.ast, args);
            data := ast_empty_data();
            data.lhs = expr;
            data.rhs = extra;
            expr = ast_add_node(*parser.ast, .call_expr, ast_main_token(*parser.ast, expr), data);
        } else if parser_match(parser, .dot) {
            field_tok := parser_expect(parser, .identifier, "expected field name after '.'");
            field := ast_add_node(*parser.ast, .identifier, field_tok, ast_empty_data());
            data := ast_empty_data();
            data.lhs = expr;
            data.rhs = field;
            expr = ast_add_node(*parser.ast, .field_access, field_tok, data);
        } else if parser_match(parser, .l_bracket) {
            index := parser_parse_expression(parser, 0);
            parser_expect(parser, .r_bracket, "expected ']' after index");
            data := ast_empty_data();
            data.lhs = expr;
            data.rhs = index;
            expr = ast_add_node(*parser.ast, .index_expr, ast_main_token(*parser.ast, expr), data);
        } else {
            done = true;
        }
    }
    return expr;
}

parser_parse_primary :: (parser: *Parser) -> Node_Index {
    tok := parser.index;
    tag := parser_peek_tag(parser, 0);
    if tag == .identifier {
        parser.index = parser.index + 1;
        return ast_add_node(*parser.ast, .identifier, tok, ast_empty_data());
    }
    if tag == .string_literal {
        parser.index = parser.index + 1;
        return ast_add_node(*parser.ast, .string_literal, tok, ast_empty_data());
    }
    if tag == .integer_literal {
        parser.index = parser.index + 1;
        return ast_add_node(*parser.ast, .integer_literal, tok, ast_empty_data());
    }
    if tag == .float_literal {
        parser.index = parser.index + 1;
        return ast_add_node(*parser.ast, .float_literal, tok, ast_empty_data());
    }
    if tag == .keyword_true || tag == .keyword_false {
        parser.index = parser.index + 1;
        return ast_add_node(*parser.ast, .bool_literal, tok, ast_empty_data());
    }
    if tag == .keyword_null {
        parser.index = parser.index + 1;
        return ast_add_node(*parser.ast, .null_literal, tok, ast_empty_data());
    }
    if tag == .triple_minus {
        parser.index = parser.index + 1;
        return ast_add_node(*parser.ast, .undefined_literal, tok, ast_empty_data());
    }
    if tag == .l_paren {
        parser.index = parser.index + 1;
        expr := parser_parse_expression(parser, 0);
        parser_expect(parser, .r_paren, "expected ')' after expression");
        return expr;
    }
    if tag == .dot {
        parser.index = parser.index + 1;
        field_tok := parser_expect(parser, .identifier, "expected enum value after '.'");
        field := ast_add_node(*parser.ast, .identifier, field_tok, ast_empty_data());
        data := ast_empty_data();
        data.lhs = NULL_NODE;
        data.rhs = field;
        return ast_add_node(*parser.ast, .field_access, field_tok, data);
    }
    if tag == .keyword_size_of {
        parser.index = parser.index + 1;
        parser_expect(parser, .l_paren, "expected '(' after size_of");
        operand := parser_parse_expression(parser, 0);
        parser_expect(parser, .r_paren, "expected ')' after size_of operand");
        data := ast_empty_data();
        data.lhs = operand;
        return ast_add_node(*parser.ast, .size_of_expr, tok, data);
    }
    if tag == .keyword_type_of {
        parser.index = parser.index + 1;
        parser_expect(parser, .l_paren, "expected '(' after type_of");
        operand := parser_parse_expression(parser, 0);
        parser_expect(parser, .r_paren, "expected ')' after type_of operand");
        data := ast_empty_data();
        data.lhs = operand;
        return ast_add_node(*parser.ast, .type_of_expr, tok, data);
    }

    parser_fail_current(parser, "expected expression");
    if !parser_check(parser, .eof) parser.index = parser.index + 1;
    return ast_add_node(*parser.ast, .unsupported, tok, ast_empty_data());
}

parser_binary_precedence :: (tag: Token_Tag) -> int {
    if tag == .pipe_pipe return 1;
    if tag == .ampersand_ampersand return 2;
    if tag == .equal_equal || tag == .bang_equal return 3;
    if tag == .less_than || tag == .less_equal || tag == .greater_than || tag == .greater_equal return 4;
    if tag == .plus || tag == .minus || tag == .pipe || tag == .caret return 5;
    if tag == .star || tag == .slash || tag == .percent || tag == .ampersand || tag == .shift_left || tag == .shift_right return 6;
    return -1;
}

parser_is_assignment_token :: (tag: Token_Tag) -> bool {
    if tag == .equal return true;
    if tag == .plus_equal return true;
    if tag == .minus_equal return true;
    if tag == .star_equal return true;
    if tag == .slash_equal return true;
    if tag == .ampersand_equal return true;
    if tag == .pipe_equal return true;
    if tag == .caret_equal return true;
    return false;
}

parser_make_compound_assignment_rhs :: (parser: *Parser, lhs: Node_Index, rhs: Node_Index, op_tok: Token_Index) -> Node_Index {
    data := ast_empty_data();
    data.lhs = lhs;
    data.rhs = rhs;
    return ast_add_node(*parser.ast, .binary_expr, op_tok, data);
}

parser_skip_to_expr_boundary :: (parser: *Parser) {
    parens := 0;
    braces := 0;
    brackets := 0;
    while !parser_check(parser, .eof) {
        tag := parser_peek_tag(parser, 0);
        if parens == 0 && braces == 0 && brackets == 0 && (tag == .semicolon || tag == .r_brace) break;
        parser.index = parser.index + 1;
        if tag == .l_paren parens = parens + 1;
        else if tag == .r_paren && parens > 0 parens = parens - 1;
        else if tag == .l_brace braces = braces + 1;
        else if tag == .r_brace && braces > 0 braces = braces - 1;
        else if tag == .l_bracket brackets = brackets + 1;
        else if tag == .r_bracket && brackets > 0 brackets = brackets - 1;
    }
}

parser_skip_to_decl_boundary :: (parser: *Parser) {
    while !parser_check(parser, .eof) {
        tag := parser_peek_tag(parser, 0);
        if tag == .semicolon {
            parser.index = parser.index + 1;
            return;
        }
        parser.index = parser.index + 1;
    }
}

parser_match :: (parser: *Parser, tag: Token_Tag) -> bool {
    if !parser_check(parser, tag) return false;
    parser.index = parser.index + 1;
    return true;
}

parser_match_discard :: (parser: *Parser, tag: Token_Tag) -> bool {
    return parser_match(parser, tag);
}

parser_expect :: (parser: *Parser, tag: Token_Tag, message: string) -> Token_Index {
    if parser_check(parser, tag) {
        tok := parser.index;
        parser.index = parser.index + 1;
        return tok;
    }
    parser_fail_current(parser, message);
    tok := parser.index;
    if !parser_check(parser, .eof) parser.index = parser.index + 1;
    return tok;
}

parser_check :: (parser: *Parser, tag: Token_Tag) -> bool {
    return parser_peek_tag(parser, 0) == tag;
}

parser_peek_tag :: (parser: *Parser, offset: int) -> Token_Tag {
    index := parser.index + offset;
    if index < 0 || index >= parser.tokens.items.count return .eof;
    return parser.tokens.items[index].tag;
}

parser_fail_current :: (parser: *Parser, message: string) {
    offset := parser.source.count;
    if parser.index >= 0 && parser.index < parser.tokens.items.count offset = parser.tokens.items[parser.index].start;
    diagnostic_fail_at(parser.diag, offset, message);
}
