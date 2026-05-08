// Port of bootstrap/src/parser.zig.

parse :: (source: string, tokens: Token_List, diag: *Diagnostic) -> Ast {
    ast := ast_init(source);
    ast.token_count = tokens.count;
    if tokens.count == 0 {
        diagnostic_fail_at(diag, 0, "parser received no tokens");
    }
    return ast;
}

