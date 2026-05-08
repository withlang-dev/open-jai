// Port of bootstrap/src/lexer.zig.

Token_List :: struct {
    items: [..] Token;
    count: int;
}

Lexer :: struct {
    source: string;
    diag: *Diagnostic;
    index: int;
    tokens: Token_List;
}

lexer_tokenize :: (source: string, diag: *Diagnostic) -> Token_List {
    lexer: Lexer;
    lexer.source = source;
    lexer.diag = diag;
    lexer.index = 0;

    if source.count >= 2 && source[0] == #char "#" && source[1] == #char "!" {
        while lexer.index < source.count && source[lexer.index] != #char "\n" lexer.index += 1;
    }

    while true {
        lexer_skip_whitespace_and_comments(*lexer);
        if lexer.index >= source.count break;

        start := lexer.index;
        c := lexer_advance(*lexer);

        if is_ident_start(c) {
            lexer_identifier(*lexer, start);
        } else if is_digit(c) {
            lexer_number(*lexer, start);
        } else if c == #char "\"" {
            lexer_string(*lexer, start);
        } else if c == #char "#" {
            lexer_directive(*lexer, start);
        } else if c == #char ":" {
            if lexer_match(*lexer, #char ":") lexer_add(*lexer, .colon_colon, start);
            else if lexer_match(*lexer, #char "=") lexer_add(*lexer, .colon_equal, start);
            else lexer_add(*lexer, .colon, start);
        } else if c == #char "=" {
            if lexer_match(*lexer, #char "=") lexer_add(*lexer, .equal_equal, start);
            else if lexer_match(*lexer, #char ">") lexer_add(*lexer, .fat_arrow, start);
            else lexer_add(*lexer, .equal, start);
        } else if c == #char "!" {
            if lexer_match(*lexer, #char "=") lexer_add(*lexer, .bang_equal, start);
            else lexer_add(*lexer, .bang, start);
        } else if c == #char "<" {
            if lexer_match(*lexer, #char "=") lexer_add(*lexer, .less_equal, start);
            else if lexer_match(*lexer, #char "<") {
                if lexer_match(*lexer, #char "<") lexer_add(*lexer, .shift_left_rotate, start);
                else lexer_add(*lexer, .shift_left, start);
            } else lexer_add(*lexer, .less_than, start);
        } else if c == #char ">" {
            if lexer_match(*lexer, #char "=") lexer_add(*lexer, .greater_equal, start);
            else if lexer_match(*lexer, #char ">") {
                if lexer_match(*lexer, #char ">") lexer_add(*lexer, .shift_right_rotate, start);
                else lexer_add(*lexer, .shift_right, start);
            } else lexer_add(*lexer, .greater_than, start);
        } else if c == #char "+" {
            if lexer_match(*lexer, #char "=") lexer_add(*lexer, .plus_equal, start);
            else lexer_add(*lexer, .plus, start);
        } else if c == #char "-" {
            if lexer_match(*lexer, #char ">") lexer_add(*lexer, .arrow, start);
            else if lexer_match(*lexer, #char "=") lexer_add(*lexer, .minus_equal, start);
            else if lexer_match(*lexer, #char "-") {
                if lexer_match(*lexer, #char "-") lexer_add(*lexer, .triple_minus, start);
                else diagnostic_fail_at(lexer.diag, start, "unsupported token '--'");
            } else lexer_add(*lexer, .minus, start);
        } else if c == #char "*" {
            if lexer_match(*lexer, #char "=") lexer_add(*lexer, .star_equal, start);
            else lexer_add(*lexer, .star, start);
        } else if c == #char "/" {
            if lexer_match(*lexer, #char "=") lexer_add(*lexer, .slash_equal, start);
            else lexer_add(*lexer, .slash, start);
        } else if c == #char "%" {
            lexer_add(*lexer, .percent, start);
        } else if c == #char "&" {
            if lexer_match(*lexer, #char "&") lexer_add(*lexer, .ampersand_ampersand, start);
            else if lexer_match(*lexer, #char "=") lexer_add(*lexer, .ampersand_equal, start);
            else lexer_add(*lexer, .ampersand, start);
        } else if c == #char "|" {
            if lexer_match(*lexer, #char "|") {
                if lexer_match(*lexer, #char "=") lexer_add(*lexer, .pipe_pipe_equal, start);
                else lexer_add(*lexer, .pipe_pipe, start);
            } else if lexer_match(*lexer, #char "=") lexer_add(*lexer, .pipe_equal, start);
            else lexer_add(*lexer, .pipe, start);
        } else if c == #char "^" {
            if lexer_match(*lexer, #char "=") lexer_add(*lexer, .caret_equal, start);
            else lexer_add(*lexer, .caret, start);
        } else if c == #char "~" {
            lexer_add(*lexer, .tilde, start);
        } else if c == #char "." {
            if lexer_index_is_digit(*lexer) {
                lexer_leading_dot_float(*lexer, start);
            } else if lexer_match(*lexer, #char ".") {
                lexer_add(*lexer, .dot_dot, start);
            } else if lexer_match(*lexer, #char "*") {
                lexer_add(*lexer, .dot_star, start);
            } else lexer_add(*lexer, .dot, start);
        } else if c == #char "," {
            lexer_add(*lexer, .comma, start);
        } else if c == #char ";" {
            lexer_add(*lexer, .semicolon, start);
        } else if c == #char "(" {
            lexer_add(*lexer, .l_paren, start);
        } else if c == #char ")" {
            lexer_add(*lexer, .r_paren, start);
        } else if c == #char "{" {
            lexer_add(*lexer, .l_brace, start);
        } else if c == #char "}" {
            lexer_add(*lexer, .r_brace, start);
        } else if c == #char "[" {
            lexer_add(*lexer, .l_bracket, start);
        } else if c == #char "]" {
            lexer_add(*lexer, .r_bracket, start);
        } else if c == #char "$" {
            if lexer_match(*lexer, #char "$") lexer_add(*lexer, .dollar_dollar, start);
            else lexer_add(*lexer, .dollar, start);
        } else if c == #char "@" {
            lexer_add(*lexer, .at, start);
        } else if c == #char "`" {
            // Backticks are accepted around generated identifiers by the
            // bootstrap lexer and are not represented as tokens.
        } else {
            diagnostic_fail_at(lexer.diag, start, "invalid character");
        }
    }

    lexer_add(*lexer, .eof, source.count);
    lexer.tokens.count = lexer.tokens.items.count;
    return lexer.tokens;
}

lexer_skip_whitespace_and_comments :: (lexer: *Lexer) {
    while lexer.index < lexer.source.count {
        c := lexer.source[lexer.index];
        if c == #char " " || c == #char "\t" || c == #char "\r" || c == #char "\n" {
            lexer.index += 1;
        } else if c == #char "/" && lexer.index + 1 < lexer.source.count && lexer.source[lexer.index + 1] == #char "/" {
            lexer.index += 2;
            while lexer.index < lexer.source.count && lexer.source[lexer.index] != #char "\n" lexer.index += 1;
        } else if c == #char "/" && lexer.index + 1 < lexer.source.count && lexer.source[lexer.index + 1] == #char "*" {
            lexer_block_comment(lexer);
        } else {
            return;
        }
    }
}

lexer_block_comment :: (lexer: *Lexer) {
    start := lexer.index;
    lexer.index += 2;
    depth := 1;
    while lexer.index + 1 < lexer.source.count {
        if lexer.source[lexer.index] == #char "/" && lexer.source[lexer.index + 1] == #char "*" {
            depth += 1;
            lexer.index += 2;
        } else if lexer.source[lexer.index] == #char "*" && lexer.source[lexer.index + 1] == #char "/" {
            depth -= 1;
            lexer.index += 2;
            if depth == 0 return;
        } else {
            lexer.index += 1;
        }
    }
    diagnostic_fail_at(lexer.diag, start, "unterminated block comment");
}

lexer_identifier :: (lexer: *Lexer, start: int) {
    while lexer.index < lexer.source.count {
        if lexer.source[lexer.index] == #char "\\" {
            j := lexer.index + 1;
            while j < lexer.source.count && lexer.source[j] == #char " " j += 1;
            if j < lexer.source.count && is_ident_continue(lexer.source[j]) {
                lexer.index = j + 1;
                continue;
            }
            break;
        }
        if is_ident_continue(lexer.source[lexer.index]) lexer.index += 1;
        else break;
    }

    text := string_slice(lexer.source, start, lexer.index);
    lexer_add(lexer, keyword_or_identifier(text), start);
}

lexer_directive :: (lexer: *Lexer, start: int) {
    while lexer.index < lexer.source.count && (lexer.source[lexer.index] == #char " " || lexer.source[lexer.index] == #char "\t") lexer.index += 1;
    if lexer.index >= lexer.source.count || !is_ident_start(lexer.source[lexer.index]) {
        diagnostic_fail_at(lexer.diag, start, "expected directive name after '#'");
        return;
    }
    name_start := lexer.index;
    while lexer.index < lexer.source.count && is_ident_continue(lexer.source[lexer.index]) lexer.index += 1;
    name := string_slice(lexer.source, name_start, lexer.index);
    tag := directive_name_or_invalid(name);
    if tag == .invalid {
        diagnostic_fail_at(lexer.diag, start, "unknown directive");
        return;
    }
    lexer_add(lexer, tag, start);
    if tag == .directive_string lexer_multiline_string_payload(lexer, start);
}

lexer_multiline_string_payload :: (lexer: *Lexer, directive_start: int) {
    while lexer.index < lexer.source.count && (lexer.source[lexer.index] == #char " " || lexer.source[lexer.index] == #char "\t") lexer.index += 1;
    if lexer.index >= lexer.source.count || !is_ident_start(lexer.source[lexer.index]) {
        diagnostic_fail_at(lexer.diag, directive_start, "#string requires a delimiter identifier");
        return;
    }
    delim_start := lexer.index;
    while lexer.index < lexer.source.count && is_ident_continue(lexer.source[lexer.index]) lexer.index += 1;
    delimiter := string_slice(lexer.source, delim_start, lexer.index);
    while lexer.index < lexer.source.count && (lexer.source[lexer.index] == #char " " || lexer.source[lexer.index] == #char "\t" || lexer.source[lexer.index] == #char "\r") lexer.index += 1;
    if lexer.index >= lexer.source.count || lexer.source[lexer.index] != #char "\n" {
        diagnostic_fail_at(lexer.diag, delim_start, "#string delimiter must be followed by a newline");
        return;
    }
    if lexer.index < lexer.source.count lexer.index += 1;
    payload_start := lexer.index;
    while lexer.index < lexer.source.count {
        line_start := lexer.index;
        line_end := line_start;
        while line_end < lexer.source.count && lexer.source[line_end] != #char "\n" && lexer.source[line_end] != #char "\r" line_end += 1;
        trimmed_start := line_start;
        while trimmed_start < line_end && (lexer.source[trimmed_start] == #char " " || lexer.source[trimmed_start] == #char "\t") trimmed_start += 1;
        trimmed_end := line_end;
        while trimmed_end > trimmed_start && (lexer.source[trimmed_end - 1] == #char " " || lexer.source[trimmed_end - 1] == #char "\t") trimmed_end -= 1;

        suffix_start := lexer_multiline_string_delimiter_suffix(lexer, trimmed_start, trimmed_end, delimiter);
        if suffix_start >= 0 {
            lexer_add_range(lexer, .string_literal, payload_start, line_start);
            lexer.index = suffix_start;
            if lexer.index >= line_end {
                if lexer.index < lexer.source.count && lexer.source[lexer.index] == #char "\r" lexer.index += 1;
                if lexer.index < lexer.source.count && lexer.source[lexer.index] == #char "\n" lexer.index += 1;
            }
            return;
        }

        lexer.index = line_end;
        if lexer.index < lexer.source.count && lexer.source[lexer.index] == #char "\r" lexer.index += 1;
        if lexer.index < lexer.source.count && lexer.source[lexer.index] == #char "\n" lexer.index += 1;
    }
    diagnostic_fail_at(lexer.diag, directive_start, "unterminated #string payload");
}

lexer_multiline_string_delimiter_suffix :: (lexer: *Lexer, trimmed_start: int, trimmed_end: int, delimiter: string) -> int {
    if trimmed_end < trimmed_start + delimiter.count return -1;
    i := 0;
    while i < delimiter.count {
        if lexer.source[trimmed_start + i] != delimiter[i] return -1;
        i += 1;
    }

    suffix := trimmed_start + delimiter.count;
    while suffix < trimmed_end && (lexer.source[suffix] == #char " " || lexer.source[suffix] == #char "\t") suffix += 1;
    if suffix == trimmed_end return trimmed_end;

    c := lexer.source[suffix];
    if c == #char ";" return trimmed_end;
    if c == #char "," return suffix;
    if c == #char ")" return suffix;
    if c == #char "]" return suffix;
    if c == #char "}" return suffix;
    return -1;
}

lexer_number :: (lexer: *Lexer, start: int) {
    if lexer.source[start] == #char "0" && lexer.index < lexer.source.count && (lexer.source[lexer.index] == #char "x" || lexer.source[lexer.index] == #char "X") {
        lexer.index += 1;
        digits := 0;
        while lexer.index < lexer.source.count {
            c := lexer.source[lexer.index];
            if is_hex_digit(c) {
                digits += 1;
                lexer.index += 1;
            } else if c == #char "_" {
                lexer.index += 1;
            } else break;
        }
        if digits == 0 {
            diagnostic_fail_at(lexer.diag, start, "hex integer literal requires at least one digit");
            return;
        }
        lexer_add(lexer, .integer_literal, start);
        return;
    }

    if lexer.source[start] == #char "0" && lexer.index < lexer.source.count && (lexer.source[lexer.index] == #char "b" || lexer.source[lexer.index] == #char "B") {
        lexer.index += 1;
        digits := 0;
        while lexer.index < lexer.source.count {
            c := lexer.source[lexer.index];
            if c == #char "0" || c == #char "1" {
                digits += 1;
                lexer.index += 1;
            } else if c == #char "_" {
                lexer.index += 1;
            } else if is_alpha_numeric(c) {
                diagnostic_fail_at(lexer.diag, lexer.index, "invalid binary digit");
                return;
            } else break;
        }
        if digits == 0 {
            diagnostic_fail_at(lexer.diag, start, "binary integer literal requires at least one digit");
            return;
        }
        lexer_add(lexer, .integer_literal, start);
        return;
    }

    is_float := false;
    while lexer.index < lexer.source.count && (is_digit(lexer.source[lexer.index]) || lexer.source[lexer.index] == #char "_") lexer.index += 1;
    if lexer.index < lexer.source.count && lexer.source[lexer.index] == #char "." && !(lexer.index + 1 < lexer.source.count && lexer.source[lexer.index + 1] == #char ".") {
        is_float = true;
        lexer.index += 1;
        while lexer.index < lexer.source.count && (is_digit(lexer.source[lexer.index]) || lexer.source[lexer.index] == #char "_") lexer.index += 1;
    }
    if lexer.index < lexer.source.count && (lexer.source[lexer.index] == #char "e" || lexer.source[lexer.index] == #char "E") {
        is_float = true;
        lexer.index += 1;
        if lexer.index < lexer.source.count && (lexer.source[lexer.index] == #char "+" || lexer.source[lexer.index] == #char "-") lexer.index += 1;
        exp_digits := 0;
        while lexer.index < lexer.source.count && (is_digit(lexer.source[lexer.index]) || lexer.source[lexer.index] == #char "_") {
            if is_digit(lexer.source[lexer.index]) exp_digits += 1;
            lexer.index += 1;
        }
        if exp_digits == 0 {
            diagnostic_fail_at(lexer.diag, start, "float exponent requires at least one digit");
            return;
        }
    }
    if lexer.index < lexer.source.count && is_alpha(lexer.source[lexer.index]) {
        diagnostic_fail_at(lexer.diag, lexer.index, "invalid numeric literal suffix");
        return;
    }
    if is_float lexer_add(lexer, .float_literal, start);
    else lexer_add(lexer, .integer_literal, start);
}

lexer_leading_dot_float :: (lexer: *Lexer, start: int) {
    while lexer.index < lexer.source.count && (is_digit(lexer.source[lexer.index]) || lexer.source[lexer.index] == #char "_") lexer.index += 1;
    if lexer.index < lexer.source.count && (lexer.source[lexer.index] == #char "e" || lexer.source[lexer.index] == #char "E") {
        lexer.index += 1;
        if lexer.index < lexer.source.count && (lexer.source[lexer.index] == #char "+" || lexer.source[lexer.index] == #char "-") lexer.index += 1;
        exp_digits := 0;
        while lexer.index < lexer.source.count && (is_digit(lexer.source[lexer.index]) || lexer.source[lexer.index] == #char "_") {
            if is_digit(lexer.source[lexer.index]) exp_digits += 1;
            lexer.index += 1;
        }
        if exp_digits == 0 {
            diagnostic_fail_at(lexer.diag, start, "float exponent requires at least one digit");
            return;
        }
    }
    if lexer.index < lexer.source.count && is_alpha(lexer.source[lexer.index]) {
        diagnostic_fail_at(lexer.diag, lexer.index, "invalid numeric literal suffix");
        return;
    }
    lexer_add(lexer, .float_literal, start);
}

lexer_string :: (lexer: *Lexer, start: int) {
    while lexer.index < lexer.source.count {
        c := lexer_advance(lexer);
        if c == #char "\"" {
            lexer_add(lexer, .string_literal, start);
            return;
        }
        if c == #char "\\" && lexer.index < lexer.source.count {
            lexer_advance(lexer);
        } else if c == #char "\n" {
            diagnostic_fail_at(lexer.diag, start, "unterminated string literal");
            return;
        }
    }
    diagnostic_fail_at(lexer.diag, start, "unterminated string literal");
}

lexer_add :: (lexer: *Lexer, tag: Token_Tag, start: int) {
    lexer_add_range(lexer, tag, start, lexer.index);
}

lexer_add_range :: (lexer: *Lexer, tag: Token_Tag, start: int, end: int) {
    token: Token;
    token.tag = tag;
    token.start = start;
    token.end = end;
    array_add(*lexer.tokens.items, token);
    lexer.tokens.count = lexer.tokens.items.count;
}

lexer_advance :: (lexer: *Lexer) -> u8 {
    c := lexer.source[lexer.index];
    lexer.index += 1;
    return c;
}

lexer_match :: (lexer: *Lexer, c: u8) -> bool {
    if lexer.index >= lexer.source.count return false;
    if lexer.source[lexer.index] != c return false;
    lexer.index += 1;
    return true;
}

lexer_index_is_digit :: (lexer: *Lexer) -> bool {
    if lexer.index >= lexer.source.count return false;
    return is_digit(lexer.source[lexer.index]);
}

is_ident_start :: (c: u8) -> bool {
    return is_alpha(c) || c == #char "_";
}

is_ident_continue :: (c: u8) -> bool {
    return is_ident_start(c) || is_digit(c);
}

is_alpha :: (c: u8) -> bool {
    return (c >= #char "a" && c <= #char "z") || (c >= #char "A" && c <= #char "Z");
}

is_digit :: (c: u8) -> bool {
    return c >= #char "0" && c <= #char "9";
}

is_hex_digit :: (c: u8) -> bool {
    return is_digit(c) || (c >= #char "a" && c <= #char "f") || (c >= #char "A" && c <= #char "F");
}

is_alpha_numeric :: (c: u8) -> bool {
    return is_alpha(c) || is_digit(c);
}

string_slice :: (source: string, start: int, end: int) -> string {
    result := source;
    advance(*result, start);
    result.count = end - start;
    return result;
}
