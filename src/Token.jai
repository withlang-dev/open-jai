// Port of bootstrap/src/Token.zig.

Token_Tag :: enum {
    invalid;
    eof;
    identifier;
    integer_literal;
    float_literal;
    string_literal;
    char_literal;
    keyword_true;
    keyword_false;
    keyword_null;
    keyword_if;
    keyword_else;
    keyword_for;
    keyword_while;
    keyword_return;
    keyword_break;
    keyword_continue;
    keyword_struct;
    keyword_enum;
    keyword_union;
    keyword_cast;
    keyword_using;
    keyword_defer;
    keyword_push_context;
    directive_import;
    directive_load;
    directive_run;
    directive_assert;
    directive_if;
    directive_ifx;
    directive_string;
    directive_insert;
    directive_code;
    directive_expand;
    directive_location;
    directive_caller_code;
    directive_caller_location;
    l_paren;
    r_paren;
    l_brace;
    r_brace;
    l_bracket;
    r_bracket;
    comma;
    semicolon;
    colon;
    colon_colon;
    dot;
    dot_dot;
    plus;
    minus;
    star;
    slash;
    percent;
    equal;
    equal_equal;
    bang;
    bang_equal;
    less;
    less_equal;
    greater;
    greater_equal;
    arrow;
}

Token :: struct {
    tag: Token_Tag;
    start: int;
    end: int;
}

token_tag_name :: (tag: Token_Tag) -> string {
    if tag == .identifier return "identifier";
    if tag == .integer_literal return "integer_literal";
    if tag == .string_literal return "string_literal";
    if tag == .eof return "eof";
    return "token";
}

