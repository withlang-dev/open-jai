const std = @import("std");
const Token = @import("Token.zig").Token;
const Tag = @import("Token.zig").Tag;
const token_mod = @import("Token.zig");
const Diagnostic = @import("diagnostics.zig").Diagnostic;

pub const TokenList = std.MultiArrayList(Token);

pub fn tokenize(allocator: std.mem.Allocator, source: []const u8, diag: Diagnostic) !TokenList {
    var lexer = Lexer{ .allocator = allocator, .source = source, .diag = diag };
    return lexer.run();
}

const Lexer = struct {
    allocator: std.mem.Allocator,
    source: []const u8,
    diag: Diagnostic,
    index: usize = 0,
    tokens: TokenList = .empty,

    fn run(l: *Lexer) !TokenList {
        errdefer l.tokens.deinit(l.allocator);
        if (std.mem.startsWith(u8, l.source, "#!")) {
            while (l.index < l.source.len and l.source[l.index] != '\n') l.index += 1;
        }
        while (true) {
            try l.skipWhitespaceAndComments();
            if (l.index >= l.source.len) break;
            const start = l.index;
            const c = l.advance();
            switch (c) {
                'a'...'z', 'A'...'Z', '_' => try l.identifier(start),
                '0'...'9' => try l.number(start),
                '"' => try l.string(start),
                '#' => try l.directive(start),
                ':' => try l.add(if (l.match(':')) .colon_colon else if (l.match('=')) .colon_equal else .colon, start),
                '=' => try l.add(if (l.match('=')) .equal_equal else if (l.match('>')) .fat_arrow else .equal, start),
                '!' => try l.add(if (l.match('=')) .bang_equal else .bang, start),
                '<' => {
                    if (l.match('=')) try l.add(.less_equal, start)
                    else if (l.match('<')) {
                        if (l.match('<')) try l.add(.shift_left_rotate, start) else try l.add(.shift_left, start);
                    } else try l.add(.less_than, start);
                },
                '>' => {
                    if (l.match('=')) try l.add(.greater_equal, start)
                    else if (l.match('>')) {
                        if (l.match('>')) try l.add(.shift_right_rotate, start) else try l.add(.shift_right, start);
                    } else try l.add(.greater_than, start);
                },
                '+' => try l.add(if (l.match('=')) .plus_equal else .plus, start),
                '-' => {
                    if (l.match('>')) try l.add(.arrow, start)
                    else if (l.match('=')) try l.add(.minus_equal, start)
                    else if (l.match('-')) {
                        if (l.match('-')) try l.add(.triple_minus, start) else return l.diag.failAt(start, "unsupported token '--'", .{});
                    } else try l.add(.minus, start);
                },
                '*' => try l.add(if (l.match('=')) .star_equal else .star, start),
                '/' => try l.add(if (l.match('=')) .slash_equal else .slash, start),
                '%' => try l.add(.percent, start),
                '&' => try l.add(if (l.match('&')) .ampersand_ampersand else if (l.match('=')) .ampersand_equal else .ampersand, start),
                '|' => {
                    if (l.match('|')) {
                        try l.add(if (l.match('=')) .pipe_pipe_equal else .pipe_pipe, start);
                    } else try l.add(if (l.match('=')) .pipe_equal else .pipe, start);
                },
                '^' => try l.add(if (l.match('=')) .caret_equal else .caret, start),
                '~' => try l.add(.tilde, start),
                '.' => {
                    if (l.index < l.source.len and std.ascii.isDigit(l.source[l.index])) try l.leadingDotFloat(start)
                    else if (l.match('.')) try l.add(.dot_dot, start)
                    else if (l.match('*')) try l.add(.dot_star, start)
                    else try l.add(.dot, start);
                },
                ',' => try l.add(.comma, start),
                ';' => try l.add(.semicolon, start),
                '(' => try l.add(.l_paren, start),
                ')' => try l.add(.r_paren, start),
                '{' => try l.add(.l_brace, start),
                '}' => try l.add(.r_brace, start),
                '[' => try l.add(.l_bracket, start),
                ']' => try l.add(.r_bracket, start),
                '$' => try l.add(if (l.match('$')) .dollar_dollar else .dollar, start),
                '@' => try l.add(.at, start),
                '`' => continue,
                else => return l.diag.failAt(start, "invalid character 0x{x}", .{c}),
            }
        }
        try l.tokens.append(l.allocator, .{ .tag = .eof, .start = @intCast(l.source.len), .end = @intCast(l.source.len) });
        return l.tokens;
    }

    fn skipWhitespaceAndComments(l: *Lexer) !void {
        while (l.index < l.source.len) {
            switch (l.source[l.index]) {
                ' ', '\t', '\r', '\n' => l.index += 1,
                '/' => {
                    if (l.index + 1 >= l.source.len) return;
                    if (l.source[l.index + 1] == '/') {
                        l.index += 2;
                        while (l.index < l.source.len and l.source[l.index] != '\n') l.index += 1;
                    } else if (l.source[l.index + 1] == '*') {
                        try l.blockComment();
                    } else return;
                },
                else => return,
            }
        }
    }

    fn blockComment(l: *Lexer) !void {
        const start = l.index;
        l.index += 2;
        var depth: usize = 1;
        while (l.index + 1 < l.source.len) {
            if (l.source[l.index] == '/' and l.source[l.index + 1] == '*') {
                depth += 1;
                l.index += 2;
            } else if (l.source[l.index] == '*' and l.source[l.index + 1] == '/') {
                depth -= 1;
                l.index += 2;
                if (depth == 0) return;
            } else l.index += 1;
        }
        return l.diag.failAt(start, "unterminated block comment", .{});
    }

    fn identifier(l: *Lexer, start: usize) !void {
        while (l.index < l.source.len) {
            if (l.source[l.index] == '\\') {
                var j = l.index + 1;
                while (j < l.source.len and l.source[j] == ' ') j += 1;
                if (j < l.source.len and isIdentContinue(l.source[j])) {
                    l.index = j + 1;
                    continue;
                }
                break;
            }
            if (isIdentContinue(l.source[l.index])) l.index += 1 else break;
        }
        try l.add(token_mod.keywordOrIdentifier(l.source[start..l.index]), start);
    }

    fn directive(l: *Lexer, start: usize) !void {
        while (l.index < l.source.len and (l.source[l.index] == ' ' or l.source[l.index] == '\t')) l.index += 1;
        if (l.index >= l.source.len or !isIdentStart(l.source[l.index])) return l.diag.failAt(start, "expected directive name after '#'", .{});
        const name_start = l.index;
        while (l.index < l.source.len and isIdentContinue(l.source[l.index])) l.index += 1;
        const name = l.source[name_start..l.index];
        const tag = token_mod.directiveNameOrInvalid(name);
        if (tag == .invalid) return l.diag.failAt(start, "unknown directive '#{s}'", .{name});
        try l.add(tag, start);
        if (tag == .directive_string) try l.multilineStringPayload(start);
    }

    fn multilineStringPayload(l: *Lexer, directive_start: usize) !void {
        while (l.index < l.source.len and (l.source[l.index] == ' ' or l.source[l.index] == '\t')) l.index += 1;
        if (l.index >= l.source.len or !isIdentStart(l.source[l.index])) return l.diag.failAt(directive_start, "#string requires a delimiter identifier", .{});
        const delim_start = l.index;
        while (l.index < l.source.len and isIdentContinue(l.source[l.index])) l.index += 1;
        const delimiter = l.source[delim_start..l.index];
        while (l.index < l.source.len and (l.source[l.index] == ' ' or l.source[l.index] == '\t' or l.source[l.index] == '\r')) l.index += 1;
        if (l.index >= l.source.len or l.source[l.index] != '\n') return l.diag.failAt(delim_start, "#string delimiter must be followed by a newline", .{});
        l.index += 1;
        const payload_start = l.index;
        while (l.index < l.source.len) {
            const line_start = l.index;
            var line_end = line_start;
            while (line_end < l.source.len and l.source[line_end] != '\n' and l.source[line_end] != '\r') line_end += 1;
            var trimmed_start = line_start;
            while (trimmed_start < line_end and (l.source[trimmed_start] == ' ' or l.source[trimmed_start] == '\t')) trimmed_start += 1;
            var trimmed_end = line_end;
            while (trimmed_end > trimmed_start and (l.source[trimmed_end - 1] == ' ' or l.source[trimmed_end - 1] == '\t')) trimmed_end -= 1;
            if (l.multilineStringDelimiterSuffix(trimmed_start, trimmed_end, delimiter)) |suffix_start| {
                try l.tokens.append(l.allocator, .{ .tag = .string_literal, .start = @intCast(payload_start), .end = @intCast(line_start) });
                l.index = suffix_start;
                if (l.index >= line_end) {
                    if (l.index < l.source.len and l.source[l.index] == '\r') l.index += 1;
                    if (l.index < l.source.len and l.source[l.index] == '\n') l.index += 1;
                }
                return;
            }
            l.index = line_end;
            if (l.index < l.source.len and l.source[l.index] == '\r') l.index += 1;
            if (l.index < l.source.len and l.source[l.index] == '\n') l.index += 1;
        }
        return l.diag.failAt(directive_start, "unterminated #string payload; expected delimiter '{s}'", .{delimiter});
    }

    fn multilineStringDelimiterSuffix(l: *const Lexer, trimmed_start: usize, trimmed_end: usize, delimiter: []const u8) ?usize {
        if (trimmed_end < trimmed_start + delimiter.len) return null;
        if (!std.mem.eql(u8, l.source[trimmed_start .. trimmed_start + delimiter.len], delimiter)) return null;
        var suffix = trimmed_start + delimiter.len;
        while (suffix < trimmed_end and (l.source[suffix] == ' ' or l.source[suffix] == '\t')) suffix += 1;
        if (suffix == trimmed_end) return trimmed_end;
        return switch (l.source[suffix]) {
            ';' => trimmed_end,
            ',', ')', ']', '}' => suffix,
            else => null,
        };
    }

    fn number(l: *Lexer, start: usize) !void {
        if (l.source[start] == '0' and l.index < l.source.len and (l.source[l.index] == 'x' or l.source[l.index] == 'X')) {
            l.index += 1;
            var digits: usize = 0;
            while (l.index < l.source.len) {
                const c = l.source[l.index];
                if (std.ascii.isHex(c)) {
                    digits += 1;
                    l.index += 1;
                } else if (c == '_') {
                    l.index += 1;
                } else break;
            }
            if (digits == 0) return l.diag.failAt(start, "hex integer literal requires at least one digit", .{});
            try l.add(.integer_literal, start);
            return;
        }
        if (l.source[start] == '0' and l.index < l.source.len and (l.source[l.index] == 'b' or l.source[l.index] == 'B')) {
            l.index += 1;
            var digits: usize = 0;
            while (l.index < l.source.len) {
                const c = l.source[l.index];
                if (c == '0' or c == '1') {
                    digits += 1;
                    l.index += 1;
                } else if (c == '_') {
                    l.index += 1;
                } else if (std.ascii.isAlphanumeric(c)) return l.diag.failAt(l.index, "invalid binary digit '{c}'", .{c})
                else break;
            }
            if (digits == 0) return l.diag.failAt(start, "binary integer literal requires at least one digit", .{});
            try l.add(.integer_literal, start);
            return;
        }

        var is_float = false;
        while (l.index < l.source.len and (std.ascii.isDigit(l.source[l.index]) or l.source[l.index] == '_')) l.index += 1;
        if (l.index < l.source.len and l.source[l.index] == '.' and !(l.index + 1 < l.source.len and l.source[l.index + 1] == '.')) {
            is_float = true;
            l.index += 1;
            while (l.index < l.source.len and (std.ascii.isDigit(l.source[l.index]) or l.source[l.index] == '_')) l.index += 1;
        }
        if (l.index < l.source.len and (l.source[l.index] == 'e' or l.source[l.index] == 'E')) {
            is_float = true;
            l.index += 1;
            if (l.index < l.source.len and (l.source[l.index] == '+' or l.source[l.index] == '-')) l.index += 1;
            var exp_digits: usize = 0;
            while (l.index < l.source.len and (std.ascii.isDigit(l.source[l.index]) or l.source[l.index] == '_')) {
                if (std.ascii.isDigit(l.source[l.index])) exp_digits += 1;
                l.index += 1;
            }
            if (exp_digits == 0) return l.diag.failAt(start, "float exponent requires at least one digit", .{});
        }
        if (l.index < l.source.len and std.ascii.isAlphabetic(l.source[l.index])) return l.diag.failAt(l.index, "invalid numeric literal suffix", .{});
        try l.add(if (is_float) .float_literal else .integer_literal, start);
    }

    fn leadingDotFloat(l: *Lexer, start: usize) !void {
        while (l.index < l.source.len and (std.ascii.isDigit(l.source[l.index]) or l.source[l.index] == '_')) l.index += 1;
        if (l.index < l.source.len and (l.source[l.index] == 'e' or l.source[l.index] == 'E')) {
            l.index += 1;
            if (l.index < l.source.len and (l.source[l.index] == '+' or l.source[l.index] == '-')) l.index += 1;
            var exp_digits: usize = 0;
            while (l.index < l.source.len and (std.ascii.isDigit(l.source[l.index]) or l.source[l.index] == '_')) {
                if (std.ascii.isDigit(l.source[l.index])) exp_digits += 1;
                l.index += 1;
            }
            if (exp_digits == 0) return l.diag.failAt(start, "float exponent requires at least one digit", .{});
        }
        if (l.index < l.source.len and std.ascii.isAlphabetic(l.source[l.index])) return l.diag.failAt(l.index, "invalid numeric literal suffix", .{});
        try l.add(.float_literal, start);
    }

    fn string(l: *Lexer, start: usize) !void {
        while (l.index < l.source.len) {
            const c = l.advance();
            if (c == '"') {
                try l.add(.string_literal, start);
                return;
            }
            if (c == '\\') {
                if (l.index >= l.source.len) break;
                _ = l.advance();
            } else if (c == '\n') return l.diag.failAt(start, "unterminated string literal", .{});
        }
        return l.diag.failAt(start, "unterminated string literal", .{});
    }

    fn add(l: *Lexer, tag: Tag, start: usize) !void {
        try l.tokens.append(l.allocator, .{ .tag = tag, .start = @intCast(start), .end = @intCast(l.index) });
    }

    fn advance(l: *Lexer) u8 {
        const c = l.source[l.index];
        l.index += 1;
        return c;
    }

    fn match(l: *Lexer, c: u8) bool {
        if (l.index >= l.source.len or l.source[l.index] != c) return false;
        l.index += 1;
        return true;
    }
};

fn isIdentStart(c: u8) bool {
    return std.ascii.isAlphabetic(c) or c == '_';
}

fn isIdentContinue(c: u8) bool {
    return isIdentStart(c) or std.ascii.isDigit(c);
}

test "lexer tokenizes hello sailor" {
    const source = "#import \"Basic\";\nmain :: () {\n print(\"Hello, Sailor from Jai!\\n\");\n}\n";
    const diag = Diagnostic.init(std.testing.allocator, "test.jai", source);
    var tokens = try tokenize(std.testing.allocator, source, diag);
    defer tokens.deinit(std.testing.allocator);
    const tags = tokens.items(.tag);
    const expected = &[_]Tag{ .directive_import, .string_literal, .semicolon, .identifier, .colon_colon, .l_paren, .r_paren, .l_brace, .identifier, .l_paren, .string_literal, .r_paren, .semicolon, .r_brace, .eof };
    try std.testing.expectEqualSlices(Tag, expected, tags);
}

test "lexer tokenizes Phase 2 numeric literal formats" {
    const source = "0xFF 0b00_01 5_069_105 5.97219e24 8.0 3.14159 1e-3 1_000.5_25";
    const diag = Diagnostic.init(std.testing.allocator, "numbers.jai", source);
    var tokens = try tokenize(std.testing.allocator, source, diag);
    defer tokens.deinit(std.testing.allocator);
    const tags = tokens.items(.tag);
    const expected = &[_]Tag{
        .integer_literal,
        .integer_literal,
        .integer_literal,
        .float_literal,
        .float_literal,
        .float_literal,
        .float_literal,
        .float_literal,
        .eof,
    };
    try std.testing.expectEqualSlices(Tag, expected, tags);
}

test "lexer tokenizes #string multiline payload and reports unterminated payload" {
    const source = "INFO :: #string STRING\n<?xml version=\"1.0\" ?>\nSTRING\n";
    const diag = Diagnostic.init(std.testing.allocator, "multiline_string.jai", source);
    var tokens = try tokenize(std.testing.allocator, source, diag);
    defer tokens.deinit(std.testing.allocator);
    const tags = tokens.items(.tag);
    const expected = &[_]Tag{ .identifier, .colon_colon, .directive_string, .string_literal, .eof };
    try std.testing.expectEqualSlices(Tag, expected, tags);

    const bad = "INFO :: #string STRING\n<?xml version=\"1.0\" ?>\n";
    const bad_diag = Diagnostic.init(std.testing.allocator, "bad_multiline_string.jai", bad);
    try std.testing.expectError(error.CompilationFailed, tokenize(std.testing.allocator, bad, bad_diag));
}

test "lexer leaves #string delimiter comma as call argument separator" {
    const source = "value :: tprint(#string STRING\nhello\nSTRING,\nname);\n";
    const diag = Diagnostic.init(std.testing.allocator, "multiline_string_comma.jai", source);
    var tokens = try tokenize(std.testing.allocator, source, diag);
    defer tokens.deinit(std.testing.allocator);
    const tags = tokens.items(.tag);
    const expected = &[_]Tag{
        .identifier,
        .colon_colon,
        .identifier,
        .l_paren,
        .directive_string,
        .string_literal,
        .comma,
        .identifier,
        .r_paren,
        .semicolon,
        .eof,
    };
    try std.testing.expectEqualSlices(Tag, expected, tags);
}

test "lexer tokenizes nested block comments and char directive" {
    const source = "#char \"1\" /* outer /* inner */ done */ 42";
    const diag = Diagnostic.init(std.testing.allocator, "comments.jai", source);
    var tokens = try tokenize(std.testing.allocator, source, diag);
    defer tokens.deinit(std.testing.allocator);
    const tags = tokens.items(.tag);
    const expected = &[_]Tag{ .directive_char, .string_literal, .integer_literal, .eof };
    try std.testing.expectEqualSlices(Tag, expected, tags);
}

test "lexer rejects invalid binary digit" {
    const source = "0b102";
    const diag = Diagnostic.init(std.testing.allocator, "bad_binary.jai", source);
    try std.testing.expectError(error.CompilationFailed, tokenize(std.testing.allocator, source, diag));
}

test "lexer rejects missing float exponent digits" {
    const source = "1e+";
    const diag = Diagnostic.init(std.testing.allocator, "bad_float.jai", source);
    try std.testing.expectError(error.CompilationFailed, tokenize(std.testing.allocator, source, diag));
}

test "lexer accepts spaced directives" {
    const source = "# import \"Basic\";\n# if OS == .MACOS return;\n";
    const diag = Diagnostic.init(std.testing.allocator, "spaced_directives.jai", source);
    var tokens = try tokenize(std.testing.allocator, source, diag);
    defer tokens.deinit(std.testing.allocator);
    const tags = tokens.items(.tag);
    const expected = &[_]Tag{
        .directive_import,
        .string_literal,
        .semicolon,
        .directive_if,
        .identifier,
        .equal_equal,
        .dot,
        .identifier,
        .keyword_return,
        .semicolon,
        .eof,
    };
    try std.testing.expectEqualSlices(Tag, expected, tags);
}
