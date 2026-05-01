const std = @import("std");
const Token = @import("Token.zig").Token;
const Tag = @import("Token.zig").Tag;
const Ast = @import("Ast.zig").Ast;
const null_node = @import("Ast.zig").null_node;
const Node = @import("Ast.zig").Node;
const NodeIndex = @import("Ast.zig").NodeIndex;
const Diagnostic = @import("diagnostics.zig").Diagnostic;

pub fn parse(allocator: std.mem.Allocator, source: []const u8, tags: []const Tag, starts: []const u32, ends: []const u32, diag: Diagnostic) !Ast {
    const tokens = try allocator.alloc(Token, tags.len);
    errdefer allocator.free(tokens);
    for (tokens, tags, starts, ends) |*tok, tag, start, end| tok.* = .{ .tag = tag, .start = start, .end = end };
    var p = Parser{ .allocator = allocator, .source = source, .tokens = tokens, .diag = diag, .ast = Ast.init(allocator, source, tokens) };
    return p.parseRoot();
}

const Parser = struct {
    allocator: std.mem.Allocator,
    source: []const u8,
    tokens: []const Token,
    diag: Diagnostic,
    index: Token.Index = 0,
    ast: Ast,

    fn parseRoot(p: *Parser) !Ast {
        errdefer p.ast.deinit();
        var decls = std.ArrayList(u32).empty;
        defer decls.deinit(p.allocator);
        while (!p.check(.eof)) {
            const decl = try p.parseTopLevelDecl();
            try decls.append(p.allocator, decl);
        }
        const extra = try p.ast.addExtraSlice(decls.items);
        const root = try p.ast.addNode(.root, 0, .{ .lhs = extra, .rhs = @intCast(decls.items.len) });
        p.ast.root = root;
        return p.ast;
    }

    fn parseTopLevelDecl(p: *Parser) !NodeIndex {
        if (p.match(.directive_import)) |tok| return p.parseImport(tok);
        if (p.check(.identifier)) {
            if (p.peekTag(1) == .colon_colon or p.peekTag(1) == .colon) return p.parseTopLevelIdentifierDecl();
        }
        return p.failCurrent("expected top-level import, constant, or procedure declaration", .{});
    }

    fn parseTopLevelIdentifierDecl(p: *Parser) !NodeIndex {
        const name_tok = try p.expect(.identifier, "expected top-level declaration name", .{});
        if (p.matchDiscard(.colon_colon)) {
            if (p.check(.l_paren)) return p.parseProcDeclAfterName(name_tok);
            const value = try p.parseExpr();
            _ = try p.expect(.semicolon, "expected semicolon after constant declaration", .{});
            return p.ast.addNode(.const_decl, name_tok, .{ .lhs = value });
        }
        _ = try p.expect(.colon, "expected ':' or '::' after declaration name", .{});
        var type_tok: Token.Index = 0;
        if (p.check(.identifier) or isTypeKeyword(p.peekTag(0))) type_tok = p.index else return p.failCurrent("expected type name in typed constant declaration", .{});
        p.index += 1;
        _ = try p.expect(.colon, "expected ':' before typed constant value", .{});
        const value = try p.parseExpr();
        _ = try p.expect(.semicolon, "expected semicolon after typed constant declaration", .{});
        return p.ast.addNode(.const_decl, name_tok, .{ .lhs = value, .rhs = type_tok });
    }

    fn parseProcDecl(p: *Parser) !NodeIndex {
        const name_tok = try p.expect(.identifier, "expected procedure name", .{});
        _ = try p.expect(.colon_colon, "expected double colon after procedure name", .{});
        return p.parseProcDeclAfterName(name_tok);
    }

    fn parseProcDeclAfterName(p: *Parser, name_tok: Token.Index) !NodeIndex {
        _ = try p.expect(.l_paren, "expected opening paren in procedure declaration", .{});
        _ = try p.expect(.r_paren, "Phase 1 only supports empty parameter lists", .{});
        const body = try p.parseBlock();
        return p.ast.addNode(.proc_decl, name_tok, .{ .lhs = body });
    }

    fn parseImport(p: *Parser, tok: Token.Index) !NodeIndex {
        const str_tok = try p.expect(.string_literal, "expected module string after #import", .{});
        _ = try p.expect(.semicolon, "expected semicolon after import", .{});
        return p.ast.addNode(.import_decl, tok, .{ .lhs = str_tok });
    }

    fn parseBlock(p: *Parser) !NodeIndex {
        const lbrace = try p.expect(.l_brace, "expected procedure body", .{});
        var stmts = std.ArrayList(u32).empty;
        defer stmts.deinit(p.allocator);
        while (!p.check(.r_brace)) {
            if (p.check(.eof)) return p.failCurrent("expected closing brace before end of file", .{});
            const stmt = try p.parseStmt();
            try stmts.append(p.allocator, stmt);
        }
        _ = try p.expect(.r_brace, "expected closing brace", .{});
        const extra = try p.ast.addExtraSlice(stmts.items);
        return p.ast.addNode(.block, lbrace, .{ .lhs = extra, .rhs = @intCast(stmts.items.len) });
    }

    fn parseStmt(p: *Parser) !NodeIndex {
        if (p.match(.keyword_return)) |tok| {
            _ = try p.expect(.semicolon, "Phase 1 only supports empty return statements", .{});
            return p.ast.addNode(.return_stmt, tok, .{});
        }
        if (p.check(.identifier)) {
            if (p.peekTag(1) == .colon) return p.parseLocalTypedDecl();
            if (p.peekTag(1) == .colon_equal) return p.parseLocalInferredDecl();
            if (p.peekTag(1) == .colon_colon) return p.parseLocalConstDecl();
            if (p.peekTag(1) == .equal) return p.parseAssignStmt();
        }
        const expr = try p.parseExpr();
        _ = try p.expect(.semicolon, "expected semicolon after expression statement", .{});
        return p.ast.addNode(.expr_stmt, p.ast.mainToken(expr), .{ .lhs = expr });
    }

    fn parseLocalTypedDecl(p: *Parser) !NodeIndex {
        const name_tok = try p.expect(.identifier, "expected local variable name", .{});
        _ = try p.expect(.colon, "expected ':' in local declaration", .{});
        const type_expr = try p.parseTypeExpr();
        const init = if (p.matchDiscard(.equal)) try p.parseExpr() else null_node;
        _ = try p.expect(.semicolon, "expected semicolon after local declaration", .{});
        return p.ast.addNode(.var_decl, name_tok, .{ .lhs = type_expr, .rhs = init });
    }

    fn parseLocalInferredDecl(p: *Parser) !NodeIndex {
        const name_tok = try p.expect(.identifier, "expected local variable name", .{});
        _ = try p.expect(.colon_equal, "expected ':=' in local declaration", .{});
        const init = try p.parseExpr();
        _ = try p.expect(.semicolon, "expected semicolon after local declaration", .{});
        return p.ast.addNode(.var_decl, name_tok, .{ .lhs = null_node, .rhs = init });
    }

    fn parseLocalConstDecl(p: *Parser) !NodeIndex {
        const name_tok = try p.expect(.identifier, "expected local constant name", .{});
        _ = try p.expect(.colon_colon, "expected '::' in local constant declaration", .{});
        const value = try p.parseTypeOrExpr();
        _ = try p.expect(.semicolon, "expected semicolon after local constant declaration", .{});
        return p.ast.addNode(.const_decl, name_tok, .{ .lhs = value });
    }

    fn parseAssignStmt(p: *Parser) !NodeIndex {
        const name_tok = try p.expect(.identifier, "expected assignment target", .{});
        const lhs = try p.ast.addNode(.identifier, name_tok, .{});
        _ = try p.expect(.equal, "expected '=' in assignment", .{});
        const rhs = try p.parseExpr();
        _ = try p.expect(.semicolon, "expected semicolon after assignment", .{});
        return p.ast.addNode(.assign_stmt, name_tok, .{ .lhs = lhs, .rhs = rhs });
    }

    fn parseTypeExpr(p: *Parser) !NodeIndex {
        const tok = p.index;
        if (p.match(.identifier) != null or p.match(.keyword_void) != null) return p.ast.addNode(.type_expr, tok, .{});
        return p.failCurrent("expected type expression", .{});
    }

    fn parseTypeOrExpr(p: *Parser) !NodeIndex {
        if ((p.check(.identifier) or p.check(.keyword_void)) and p.peekTag(1) == .semicolon) return p.parseTypeExpr();
        return p.parseExpr();
    }

    fn parseExpr(p: *Parser) anyerror!NodeIndex { return p.parseBinaryExpr(0); }

    fn parseBinaryExpr(p: *Parser, min_prec: u8) anyerror!NodeIndex {
        var lhs = try p.parseCall();
        while (binaryPrecedence(p.peekTag(0))) |prec| {
            if (prec < min_prec) break;
            const op_tok = p.index;
            p.index += 1;
            const rhs = try p.parseBinaryExpr(prec + 1);
            lhs = try p.ast.addNode(.binary_expr, op_tok, .{ .lhs = lhs, .rhs = rhs });
        }
        return lhs;
    }

    fn parseCall(p: *Parser) anyerror!NodeIndex {
        var expr = try p.parsePrimary();
        while (p.match(.l_paren)) |lparen| {
            var args = std.ArrayList(u32).empty;
            defer args.deinit(p.allocator);
            if (!p.check(.r_paren)) {
                while (true) {
                    try args.append(p.allocator, try p.parseExpr());
                    if (!p.matchDiscard(.comma)) break;
                }
            }
            _ = try p.expect(.r_paren, "expected closing paren after call arguments", .{});
            const extra = try p.ast.addExtraSlice(args.items);
            expr = try p.ast.addNode(.call_expr, lparen, .{ .lhs = expr, .rhs = extra });
        }
        return expr;
    }

    fn parsePrimary(p: *Parser) !NodeIndex {
        if (p.match(.directive_char)) |tok| {
            const str_tok = try p.expect(.string_literal, "expected string literal after #char", .{});
            return p.ast.addNode(.char_literal, tok, .{ .lhs = str_tok });
        }
        if (p.match(.keyword_type_of)) |tok| {
            _ = try p.expect(.l_paren, "expected '(' after type_of", .{});
            const operand = try p.parseExpr();
            _ = try p.expect(.r_paren, "expected ')' after type_of operand", .{});
            return p.ast.addNode(.type_of_expr, tok, .{ .lhs = operand });
        }
        if (p.match(.keyword_size_of)) |tok| {
            _ = try p.expect(.l_paren, "expected '(' after size_of", .{});
            const operand = try p.parseTypeOrExpr();
            _ = try p.expect(.r_paren, "expected ')' after size_of operand", .{});
            return p.ast.addNode(.size_of_expr, tok, .{ .lhs = operand });
        }
        if (p.match(.identifier)) |tok| return p.ast.addNode(.identifier, tok, .{});
        if (isTypeKeyword(p.peekTag(0))) {
            const tok = p.index;
            p.index += 1;
            return p.ast.addNode(.type_expr, tok, .{});
        }
        if (p.match(.string_literal)) |tok| return p.ast.addNode(.string_literal, tok, .{});
        if (p.match(.integer_literal)) |tok| return p.ast.addNode(.integer_literal, tok, .{});
        if (p.match(.float_literal)) |tok| return p.ast.addNode(.float_literal, tok, .{});
        if (p.match(.keyword_true)) |tok| return p.ast.addNode(.bool_literal, tok, .{ .lhs = 1 });
        if (p.match(.keyword_false)) |tok| return p.ast.addNode(.bool_literal, tok, .{ .lhs = 0 });
        return p.failCurrent("expected expression", .{});
    }

    fn expect(p: *Parser, tag: Tag, comptime fmt: []const u8, args: anytype) !Token.Index {
        if (p.match(tag)) |tok| return tok;
        return p.failCurrent(fmt, args);
    }

    fn match(p: *Parser, tag: Tag) ?Token.Index {
        if (p.check(tag)) {
            const tok = p.index;
            p.index += 1;
            return tok;
        }
        return null;
    }

    fn matchDiscard(p: *Parser, tag: Tag) bool { return p.match(tag) != null; }
    fn check(p: *const Parser, tag: Tag) bool { return p.tokens[p.index].tag == tag; }
    fn peekTag(p: *const Parser, offset: usize) Tag { return p.tokens[@min(p.index + offset, p.tokens.len - 1)].tag; }

    fn failCurrent(p: *const Parser, comptime fmt: []const u8, args: anytype) error{CompilationFailed} {
        const tok = p.tokens[@min(p.index, p.tokens.len - 1)];
        return p.diag.failAt(tok.start, fmt, args);
    }
};

fn isTypeKeyword(tag: Tag) bool {
    return switch (tag) {
        .keyword_void => true,
        else => false,
    };
}

fn binaryPrecedence(tag: Tag) ?u8 {
    return switch (tag) {
        .star, .slash, .percent => 20,
        .plus, .minus => 10,
        else => null,
    };
}

test "parser parses hello sailor" {
    const lexer = @import("lexer.zig");
    const source = "#import \"Basic\";\nmain :: () {\n print(\"Hello, Sailor from Jai!\\n\");\n}\n";
    const diag = Diagnostic.init(std.testing.allocator, "test.jai", source);
    var tokens = try lexer.tokenize(std.testing.allocator, source, diag);
    defer tokens.deinit(std.testing.allocator);
    const slice = tokens.slice();
    var ast = try parse(std.testing.allocator, source, slice.items(.tag), slice.items(.start), slice.items(.end), diag);
    defer {
        std.testing.allocator.free(ast.tokens);
        ast.deinit();
    }
    try std.testing.expectEqual(Node.Tag.root, ast.tag(ast.root));
}
