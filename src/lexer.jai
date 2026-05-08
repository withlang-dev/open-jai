// Port of bootstrap/src/lexer.zig.

Token_List :: struct {
    count: int;
}

lexer_tokenize :: (source: string, diag: *Diagnostic) -> Token_List {
    tokens: Token_List;
    tokens.count = 1;
    if source == "" {
        diagnostic_fail_at(diag, 0, "source file is empty");
    }
    return tokens;
}

