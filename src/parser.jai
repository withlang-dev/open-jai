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
    if parser_match_discard(parser, .arrow) {
        parser_parse_opaque_type_until_init_or_terminator(parser);
    }
    if parser_check(parser, .l_brace) body = parser_parse_balanced_node(parser, .l_brace, .r_brace, .block);
    else parser_match_discard(parser, .semicolon);

    sig_values: [..] int;
    array_add(*sig_values, params);
    array_add(*sig_values, NULL_NODE);
    sig_extra := ast_add_extra_values(*parser.ast, sig_values);

    data := ast_empty_data();
    data.lhs = body;
    data.rhs = sig_extra;
    return ast_add_node(*parser.ast, .proc_decl, name_tok, data);
}

parser_parse_balanced_node :: (parser: *Parser, open_tag: Token_Tag, close_tag: Token_Tag, node_tag: Ast_Node_Tag) -> Node_Index {
    open_tok := parser_expect(parser, open_tag, "expected balanced construct");
    depth := 1;
    while depth > 0 && !parser_check(parser, .eof) {
        tag := parser_peek_tag(parser, 0);
        parser.index += 1;
        if tag == open_tag depth += 1;
        else if tag == close_tag depth -= 1;
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
        parser.index += 1;
        if tag == .l_paren parens += 1;
        else if tag == .r_paren && parens > 0 parens -= 1;
        else if tag == .l_bracket brackets += 1;
        else if tag == .r_bracket && brackets > 0 brackets -= 1;
    }
    return ast_add_node(*parser.ast, .type_expr, start, ast_empty_data());
}

parser_skip_to_expr_boundary :: (parser: *Parser) {
    parens := 0;
    braces := 0;
    brackets := 0;
    while !parser_check(parser, .eof) {
        tag := parser_peek_tag(parser, 0);
        if parens == 0 && braces == 0 && brackets == 0 && (tag == .semicolon || tag == .r_brace) break;
        parser.index += 1;
        if tag == .l_paren parens += 1;
        else if tag == .r_paren && parens > 0 parens -= 1;
        else if tag == .l_brace braces += 1;
        else if tag == .r_brace && braces > 0 braces -= 1;
        else if tag == .l_bracket brackets += 1;
        else if tag == .r_bracket && brackets > 0 brackets -= 1;
    }
}

parser_skip_to_decl_boundary :: (parser: *Parser) {
    while !parser_check(parser, .eof) {
        tag := parser_peek_tag(parser, 0);
        if tag == .semicolon {
            parser.index += 1;
            return;
        }
        parser.index += 1;
    }
}

parser_match :: (parser: *Parser, tag: Token_Tag) -> bool {
    if !parser_check(parser, tag) return false;
    parser.index += 1;
    return true;
}

parser_match_discard :: (parser: *Parser, tag: Token_Tag) -> bool {
    return parser_match(parser, tag);
}

parser_expect :: (parser: *Parser, tag: Token_Tag, message: string) -> Token_Index {
    if parser_check(parser, tag) {
        tok := parser.index;
        parser.index += 1;
        return tok;
    }
    parser_fail_current(parser, message);
    tok := parser.index;
    if !parser_check(parser, .eof) parser.index += 1;
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
