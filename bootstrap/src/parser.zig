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
            _ = p.matchDiscard(.semicolon);
        }
        const extra = try p.ast.addExtraSlice(decls.items);
        const root = try p.ast.addNode(.root, 0, .{ .lhs = extra, .rhs = @intCast(decls.items.len) });
        p.ast.root = root;
        return p.ast;
    }

    fn parseTopLevelDecl(p: *Parser) !NodeIndex {
        if (p.match(.directive_import)) |tok| return p.parseImport(tok);
        if (p.match(.directive_load)) |tok| return p.parseLoad(tok);
        if (p.match(.directive_scope_file)) |tok| return p.parseScope(tok);
        if (p.match(.directive_scope_export)) |tok| return p.parseScope(tok);
        if (p.match(.directive_scope_module)) |tok| return p.parseScope(tok);
        if (p.match(.directive_add_context)) |tok| return p.parseAddContext(tok);
        if (p.match(.directive_run)) |tok| return p.parseRunStatement(tok);
        if (p.check(.identifier)) {
            if (p.peekTag(1) == .colon_colon or p.peekTag(1) == .colon or p.peekTag(1) == .colon_equal) return p.parseTopLevelIdentifierDecl();
        }
        return p.failCurrent("expected top-level import, constant, or procedure declaration", .{});
    }

    fn parseTopLevelIdentifierDecl(p: *Parser) !NodeIndex {
        const name_tok = try p.expect(.identifier, "expected top-level declaration name", .{});
        if (p.matchDiscard(.colon_colon)) {
            if (p.check(.l_paren)) return p.parseProcDeclAfterName(name_tok);
            const value = try p.parseExpr();
            if (astValueIsRunBlock(&p.ast, value)) {
                _ = p.matchDiscard(.semicolon);
            } else {
                _ = try p.expect(.semicolon, "expected semicolon after constant declaration", .{});
            }
            return p.ast.addNode(.const_decl, name_tok, .{ .lhs = value });
        }
        if (p.matchDiscard(.colon_equal)) {
            const init = try p.parseExpr();
            _ = try p.expect(.semicolon, "expected semicolon after top-level variable declaration", .{});
            return p.ast.addNode(.var_decl, name_tok, .{ .lhs = null_node, .rhs = init });
        }
        _ = try p.expect(.colon, "expected ':', ':=', or '::' after declaration name", .{});
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
        var params = std.ArrayList(u32).empty;
        defer params.deinit(p.allocator);
        if (!p.check(.r_paren)) {
            while (true) {
                const param_name = try p.expect(.identifier, "expected parameter name", .{});
                const param_type = if (p.matchDiscard(.colon)) try p.parseTypeExpr() else null_node;
                const param = try p.ast.addNode(.var_decl, param_name, .{ .lhs = param_type, .rhs = null_node });
                try params.append(p.allocator, param);
                if (!p.matchDiscard(.comma)) break;
            }
        }
        _ = try p.expect(.r_paren, "expected ')' after parameter list", .{});
        if (p.matchDiscard(.fat_arrow)) {
            const expr = try p.parseExpr();
            _ = try p.expect(.semicolon, "expected semicolon after => procedure", .{});
            const ret = try p.ast.addNode(.return_stmt, p.ast.mainToken(expr), .{ .lhs = expr });
            const stmts = [_]u32{ret};
            const stmts_extra = try p.ast.addExtraSlice(&stmts);
            const body = try p.ast.addNode(.block, name_tok, .{ .lhs = stmts_extra, .rhs = 1 });
            const params_extra = try p.ast.addExtraSlice(params.items);
            const sig_values = [_]u32{ params_extra, null_node };
            const sig_extra = try p.ast.addExtraSlice(&sig_values);
            return p.ast.addNode(.proc_decl, name_tok, .{ .lhs = body, .rhs = sig_extra });
        }
        const return_type = if (p.matchDiscard(.arrow)) try p.parseTypeExpr() else null_node;
        const body = try p.parseBlock();
        const params_extra = try p.ast.addExtraSlice(params.items);
        const sig_values = [_]u32{ params_extra, return_type };
        const sig_extra = try p.ast.addExtraSlice(&sig_values);
        return p.ast.addNode(.proc_decl, name_tok, .{ .lhs = body, .rhs = sig_extra });
    }

    fn parseAddContext(p: *Parser, tok: Token.Index) !NodeIndex {
        const name_tok = try p.expect(.identifier, "expected context field name after #add_context", .{});
        if (p.matchDiscard(.colon_equal)) {
            const init = try p.parseExpr();
            _ = try p.expect(.semicolon, "expected semicolon after #add_context declaration", .{});
            const field = try p.ast.addNode(.var_decl, name_tok, .{ .lhs = null_node, .rhs = init });
            return p.ast.addNode(.add_context_decl, tok, .{ .lhs = field });
        }
        if (p.matchDiscard(.colon)) {
            const ty = try p.parseTypeExpr();
            _ = try p.expect(.semicolon, "expected semicolon after #add_context declaration", .{});
            const field = try p.ast.addNode(.var_decl, name_tok, .{ .lhs = ty, .rhs = null_node });
            return p.ast.addNode(.add_context_decl, tok, .{ .lhs = field });
        }
        return p.failCurrent("expected ':' or ':=' in #add_context declaration", .{});
    }

    fn parseScope(p: *Parser, tok: Token.Index) !NodeIndex {
        _ = try p.expect(.semicolon, "expected semicolon after scope directive", .{});
        return p.ast.addNode(.scope_decl, tok, .{});
    }

    fn parseLoad(p: *Parser, tok: Token.Index) !NodeIndex {
        const str_tok = try p.expect(.string_literal, "expected file string after #load", .{});
        _ = try p.expect(.semicolon, "expected semicolon after #load", .{});
        return p.ast.addNode(.load_decl, tok, .{ .lhs = str_tok });
    }

    fn parseImport(p: *Parser, tok: Token.Index) !NodeIndex {
        const str_tok = try p.expect(.string_literal, "expected module string after #import", .{});
        if (p.matchDiscard(.l_paren)) {
            while (!p.check(.r_paren)) p.index += 1;
            _ = try p.expect(.r_paren, "expected ')' after import module parameters", .{});
        }
        _ = try p.expect(.semicolon, "expected semicolon after import", .{});
        return p.ast.addNode(.import_decl, tok, .{ .lhs = str_tok });
    }

    fn parseBlock(p: *Parser) anyerror!NodeIndex {
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
        if (p.match(.directive_run)) |tok| return p.parseRunStatement(tok);
        if (p.match(.keyword_return)) |tok| {
            const expr = if (p.check(.semicolon)) null_node else try p.parseExpr();
            _ = try p.expect(.semicolon, "expected semicolon after return statement", .{});
            return p.ast.addNode(.return_stmt, tok, .{ .lhs = expr });
        }
        if (p.check(.keyword_if)) return p.parseIfStmt();
        if (p.check(.keyword_for)) return p.parseForStmt();
        if (p.check(.identifier)) {
            if (p.peekTag(1) == .comma) return p.parseMultiNameStmt();
            if (p.peekTag(1) == .colon) return p.parseLocalTypedDecl();
            if (p.peekTag(1) == .colon_equal) return p.parseLocalInferredDecl();
            if (p.peekTag(1) == .plus_equal or p.peekTag(1) == .minus_equal or p.peekTag(1) == .star_equal or p.peekTag(1) == .slash_equal) return p.parseAssignStmt();
            if (p.peekTag(1) == .colon_colon and p.peekTag(2) == .l_paren) return p.parseProcDecl();
            if (p.peekTag(1) == .colon_colon) return p.parseLocalConstDecl();
            if (p.peekTag(1) == .equal or p.peekTag(1) == .plus_equal or p.peekTag(1) == .minus_equal or p.peekTag(1) == .star_equal or p.peekTag(1) == .slash_equal) return p.parseAssignStmt();
        }
        if (p.check(.identifier)) return p.parseExprOrAssignStmt();
        if (p.check(.shift_left)) return p.parseDerefAssignOrExprStmt();
        const expr = try p.parseExpr();
        _ = try p.expect(.semicolon, "expected semicolon after expression statement", .{});
        return p.ast.addNode(.expr_stmt, p.ast.mainToken(expr), .{ .lhs = expr });
    }

    fn parseStmtAsBlock(p: *Parser) !NodeIndex {
        if (p.check(.l_brace)) return p.parseBlock();
        const stmt = try p.parseStmt();
        const stmts = [_]u32{stmt};
        const extra = try p.ast.addExtraSlice(&stmts);
        return p.ast.addNode(.block, p.ast.mainToken(stmt), .{ .lhs = extra, .rhs = 1 });
    }

    fn parseIfStmt(p: *Parser) !NodeIndex {
        const if_tok = try p.expect(.keyword_if, "expected if", .{});
        const cond = try p.parseExpr();
        const then_block = try p.parseStmtAsBlock();
        const else_block = if (p.matchDiscard(.keyword_else)) try p.parseStmtAsBlock() else null_node;
        const blocks = [_]u32{ then_block, else_block };
        const blocks_extra = try p.ast.addExtraSlice(&blocks);
        return p.ast.addNode(.if_stmt, if_tok, .{ .lhs = cond, .rhs = blocks_extra });
    }

    fn parseForStmt(p: *Parser) !NodeIndex {
        const for_tok = try p.expect(.keyword_for, "expected for", .{});
        const start_expr = try p.parseExpr();
        _ = try p.expect(.dot_dot, "expected '..' in range for statement", .{});
        const end_expr = try p.parseExpr();
        const body = try p.parseBlock();
        const range_values = [_]u32{ start_expr, end_expr };
        const range_extra = try p.ast.addExtraSlice(&range_values);
        return p.ast.addNode(.for_stmt, for_tok, .{ .lhs = range_extra, .rhs = body });
    }

    fn parseDerefAssignOrExprStmt(p: *Parser) !NodeIndex {
        const lhs = try p.parseUnary();
        if (p.matchDiscard(.equal)) {
            const rhs = try p.parseExpr();
            _ = try p.expect(.semicolon, "expected semicolon after dereference assignment", .{});
            return p.ast.addNode(.assign_stmt, p.ast.mainToken(lhs), .{ .lhs = lhs, .rhs = rhs });
        }
        _ = try p.expect(.semicolon, "expected semicolon after expression statement", .{});
        return p.ast.addNode(.expr_stmt, p.ast.mainToken(lhs), .{ .lhs = lhs });
    }

    fn parseMultiNameStmt(p: *Parser) !NodeIndex {
        var name_toks = std.ArrayList(Token.Index).empty;
        var name_modes = std.ArrayList(enum { declare, assign, declare_typed }).empty;
        defer name_toks.deinit(p.allocator);
        defer name_modes.deinit(p.allocator);
        try name_toks.append(p.allocator, try p.expect(.identifier, "expected name", .{}));
        try name_modes.append(p.allocator, .declare);
        while (p.matchDiscard(.comma)) {
            const name_tok = try p.expect(.identifier, "expected name after comma", .{});
            try name_toks.append(p.allocator, name_tok);
            if (p.peekTag(0) == .equal and p.peekTag(1) == .comma) {
                _ = p.matchDiscard(.equal);
                try name_modes.append(p.allocator, .assign);
            } else if (p.peekTag(0) == .colon and p.peekTag(1) == .comma) {
                _ = p.matchDiscard(.colon);
                try name_modes.append(p.allocator, .declare_typed);
            } else try name_modes.append(p.allocator, .declare);
        }

        var stmts = std.ArrayList(u32).empty;
        defer stmts.deinit(p.allocator);
        var shared_type_expr: NodeIndex = null_node;

        if (p.matchDiscard(.colon_equal)) {
            var values = std.ArrayList(NodeIndex).empty;
            defer values.deinit(p.allocator);
            try values.append(p.allocator, try p.parseExpr());
            while (p.matchDiscard(.comma)) try values.append(p.allocator, try p.parseExpr());
            _ = try p.expect(.semicolon, "expected semicolon after multi-name inferred declaration", .{});
            for (name_toks.items, 0..) |name_tok, i| {
                const init = values.items[if (values.items.len == 1) 0 else i];
                if (name_modes.items[i] == .assign) {
                    const lhs = try p.ast.addNode(.identifier, name_tok, .{});
                    try stmts.append(p.allocator, try p.ast.addNode(.assign_stmt, name_tok, .{ .lhs = lhs, .rhs = init }));
                } else {
                    try stmts.append(p.allocator, try p.ast.addNode(.var_decl, name_tok, .{ .lhs = null_node, .rhs = init }));
                }
            }
        } else if (p.matchDiscard(.colon) or (name_toks.items.len > 1 and name_modes.items[name_modes.items.len - 1] == .declare_typed)) {
            shared_type_expr = try p.parseTypeExpr();
            var values = std.ArrayList(NodeIndex).empty;
            defer values.deinit(p.allocator);
            if (p.matchDiscard(.equal)) {
                try values.append(p.allocator, try p.parseExpr());
                while (p.matchDiscard(.comma)) try values.append(p.allocator, try p.parseExpr());
            }
            _ = try p.expect(.semicolon, "expected semicolon after multi-name typed declaration", .{});
            for (name_toks.items, 0..) |name_tok, i| {
                const init = if (values.items.len == 0) null_node else values.items[if (values.items.len == 1) 0 else i];
                try stmts.append(p.allocator, try p.ast.addNode(.var_decl, name_tok, .{ .lhs = shared_type_expr, .rhs = init }));
            }
        } else if (p.matchDiscard(.equal)) {
            var values = std.ArrayList(NodeIndex).empty;
            defer values.deinit(p.allocator);
            try values.append(p.allocator, try p.parseExpr());
            while (p.matchDiscard(.comma)) try values.append(p.allocator, try p.parseExpr());
            _ = try p.expect(.semicolon, "expected semicolon after multi-name assignment", .{});
            for (name_toks.items, 0..) |name_tok, i| {
                const init = values.items[if (values.items.len == 1) 0 else i];
                if (name_modes.items[i] == .declare_typed) {
                    try stmts.append(p.allocator, try p.ast.addNode(.var_decl, name_tok, .{ .lhs = null_node, .rhs = init }));
                } else {
                    const lhs = try p.ast.addNode(.identifier, name_tok, .{});
                    try stmts.append(p.allocator, try p.ast.addNode(.assign_stmt, name_tok, .{ .lhs = lhs, .rhs = init }));
                }
            }
        } else if (p.peekTag(0) == .plus_equal or p.peekTag(0) == .minus_equal or p.peekTag(0) == .star_equal or p.peekTag(0) == .slash_equal) {
            const op_tok = p.index;
            p.index += 1;
            const rhs_expr = try p.parseExpr();
            _ = try p.expect(.semicolon, "expected semicolon after multi-name compound assignment", .{});
            if (name_modes.items.len != name_toks.items.len) return p.diag.failAt(p.tokens[op_tok].start, "internal parser error in multi-name compound assignment", .{});
            for (name_modes.items) |mode| if (mode != .declare) return p.diag.failAt(p.tokens[op_tok].start, "multi-name compound assignment targets must be existing mutable names", .{});
            for (name_toks.items) |name_tok| {
                const lhs = try p.ast.addNode(.identifier, name_tok, .{});
                const rhs_ident = try p.ast.addNode(.identifier, name_tok, .{});
                const rhs = try p.ast.addNode(.binary_expr, op_tok, .{ .lhs = rhs_ident, .rhs = rhs_expr });
                try stmts.append(p.allocator, try p.ast.addNode(.assign_stmt, name_tok, .{ .lhs = lhs, .rhs = rhs }));
            }
        } else return p.failCurrent("expected ':', ':=', '=', or compound assignment after multi-name statement", .{});

        const extra = try p.ast.addExtraSlice(stmts.items);
        return p.ast.addNode(.stmt_list, name_toks.items[0], .{ .lhs = extra, .rhs = @intCast(stmts.items.len) });
    }

    fn parseLocalTypedDecl(p: *Parser) !NodeIndex {
        const name_tok = try p.expect(.identifier, "expected local variable name", .{});
        _ = try p.expect(.colon, "expected ':' in local declaration", .{});
        const type_expr = try p.parseTypeExpr();
        const init = if (p.matchDiscard(.equal)) blk: {
            if (p.match(.triple_minus)) |tok| break :blk try p.ast.addNode(.undefined_literal, tok, .{});
            break :blk try p.parseExpr();
        } else null_node;
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

    fn parseExprOrAssignStmt(p: *Parser) !NodeIndex {
        const lhs = try p.parseExpr();
        const op = p.peekTag(0);
        if (op == .equal or op == .plus_equal or op == .minus_equal or op == .star_equal or op == .slash_equal) {
            const op_tok = p.index;
            p.index += 1;
            const rhs_expr = try p.parseExpr();
            const rhs = if (op == .equal) rhs_expr else try p.ast.addNode(.binary_expr, op_tok, .{ .lhs = lhs, .rhs = rhs_expr });
            _ = try p.expect(.semicolon, "expected semicolon after assignment", .{});
            return p.ast.addNode(.assign_stmt, p.ast.mainToken(lhs), .{ .lhs = lhs, .rhs = rhs });
        }
        _ = try p.expect(.semicolon, "expected semicolon after expression statement", .{});
        return p.ast.addNode(.expr_stmt, p.ast.mainToken(lhs), .{ .lhs = lhs });
    }

    fn parseAssignStmt(p: *Parser) !NodeIndex {
        const name_tok = try p.expect(.identifier, "expected assignment target", .{});
        const lhs = try p.ast.addNode(.identifier, name_tok, .{});
        const op = p.peekTag(0);
        if (!(op == .equal or op == .plus_equal or op == .minus_equal or op == .star_equal or op == .slash_equal)) return p.failCurrent("expected assignment operator", .{});
        p.index += 1;
            const op_tok = p.index - 1;
            const rhs_expr = try p.parseExpr();
            const rhs = if (op == .equal) rhs_expr else blk: {
            const lhs_copy = try p.ast.addNode(.identifier, name_tok, .{});
            break :blk try p.ast.addNode(.binary_expr, op_tok, .{ .lhs = lhs_copy, .rhs = rhs_expr });
        };
        _ = try p.expect(.semicolon, "expected semicolon after assignment", .{});
        return p.ast.addNode(.assign_stmt, name_tok, .{ .lhs = lhs, .rhs = rhs });
    }

    fn parseTypeExpr(p: *Parser) !NodeIndex {
        if (p.match(.star)) |tok| {
            const child = try p.parseTypeExpr();
            return p.ast.addNode(.pointer_type, tok, .{ .lhs = child });
        }
        if (p.match(.l_paren)) |tok| {
            var params = std.ArrayList(u32).empty;
            defer params.deinit(p.allocator);
            if (!p.check(.r_paren)) {
                while (true) {
                    try params.append(p.allocator, try p.parseTypeExpr());
                    if (!p.matchDiscard(.comma)) break;
                }
            }
            _ = try p.expect(.r_paren, "expected ')' after procedure type parameters", .{});
            _ = try p.expect(.arrow, "expected '->' in procedure type", .{});
            const ret = try p.parseTypeExpr();
            const extra = try p.ast.addExtraSlice(params.items);
            return p.ast.addNode(.proc_type, tok, .{ .lhs = extra, .rhs = ret });
        }
        if (p.match(.keyword_type_of)) |tok| {
            _ = try p.expect(.l_paren, "expected '(' after type_of", .{});
            const operand = try p.parseExpr();
            _ = try p.expect(.r_paren, "expected ')' after type_of operand", .{});
            return p.ast.addNode(.type_of_expr, tok, .{ .lhs = operand });
        }
        const tok = p.index;
        if (p.match(.identifier) != null or p.match(.keyword_void) != null) return p.ast.addNode(.type_expr, tok, .{});
        return p.failCurrent("expected type expression", .{});
    }

    fn parseTypeOrExpr(p: *Parser) !NodeIndex {
        if ((p.check(.identifier) or p.check(.keyword_void)) and p.peekTag(1) == .semicolon) return p.parseTypeExpr();
        return p.parseExpr();
    }

    fn parseRunArrowBlock(p: *Parser, tok: Token.Index) !NodeIndex {
        while (p.matchDiscard(.comma)) {
            _ = try p.expect(.identifier, "expected #run modifier after ','", .{});
        }
        _ = try p.expect(.arrow, "expected '->' in expression-form #run block", .{});
        const return_type = try p.parseTypeExpr();
        const block = try p.parseBlock();
        return p.ast.addNode(.run_expr, tok, .{ .lhs = block, .rhs = return_type });
    }

    fn parseRunStatement(p: *Parser, tok: Token.Index) !NodeIndex {
        if (p.check(.arrow)) return p.parseRunArrowBlock(tok);
        while (p.matchDiscard(.comma)) {
            const modifier_tok = try p.expect(.identifier, "expected #run modifier after ','", .{});
            const modifier = p.ast.tokenSlice(modifier_tok);
            if (!std.mem.eql(u8, modifier, "stallable")) {
                return p.diag.failAt(p.tokens[modifier_tok].start, "unsupported statement-form #run modifier '{s}'", .{modifier});
            }
        }
        const operand = if (p.check(.l_brace)) try p.parseBlock() else try p.parseExpr();
        _ = p.matchDiscard(.semicolon);
        if (p.ast.tag(operand) == .run_expr) return operand;
        return p.ast.addNode(.run_expr, tok, .{ .lhs = operand });
    }

    fn parseExpr(p: *Parser) anyerror!NodeIndex { return p.parseBinaryExpr(0); }

    fn parseBinaryExpr(p: *Parser, min_prec: u8) anyerror!NodeIndex {
        var lhs = try p.parseUnary();
        while (binaryPrecedence(p.peekTag(0))) |prec| {
            if (prec < min_prec) break;
            const op_tok = p.index;
            p.index += 1;
            const rhs = try p.parseBinaryExpr(prec + 1);
            lhs = try p.ast.addNode(.binary_expr, op_tok, .{ .lhs = lhs, .rhs = rhs });
        }
        return lhs;
    }

    fn parseUnary(p: *Parser) anyerror!NodeIndex {
        switch (p.peekTag(0)) {
            .minus, .bang, .star => {
                const op_tok = p.index;
                p.index += 1;
                const operand = try p.parseUnary();
                return p.ast.addNode(.unary_expr, op_tok, .{ .lhs = operand });
            },
            .shift_left => {
                const op_tok = p.index;
                p.index += 1;
                const operand = try p.parseUnary();
                return p.ast.addNode(.unary_expr, op_tok, .{ .lhs = operand });
            },
            else => return p.parseCall(),
        }
    }

    fn parseCall(p: *Parser) anyerror!NodeIndex {
        var expr = try p.parsePrimary();
        while (true) {
            if (p.match(.dot)) |dot_tok| {
                if (p.check(.l_brace)) {
                    expr = try p.parseTypedAggregateLiteral(expr, dot_tok);
                    continue;
                }
                const field_tok = try p.expect(.identifier, "expected field name after '.'", .{});
                expr = try p.ast.addNode(.field_access, dot_tok, .{ .lhs = expr, .rhs = field_tok });
                continue;
            }
            if (p.match(.l_paren)) |lparen| {
            var args = std.ArrayList(u32).empty;
            defer args.deinit(p.allocator);
            if (!p.check(.r_paren)) {
                while (true) {
                    if (p.check(.identifier) and p.peekTag(1) == .equal) {
                        const name_tok = p.index;
                        p.index += 2;
                        const value = try p.parseExpr();
                        try args.append(p.allocator, try p.ast.addNode(.assign_stmt, name_tok, .{ .lhs = try p.ast.addNode(.identifier, name_tok, .{}), .rhs = value }));
                    } else if (astNodeIsIdentifierName(&p.ast, expr, "New")) try args.append(p.allocator, try p.parseTypeExpr()) else try args.append(p.allocator, try p.parseExpr());
                    if (!p.matchDiscard(.comma)) break;
                }
            }
            _ = try p.expect(.r_paren, "expected closing paren after call arguments", .{});
            const extra = try p.ast.addExtraSlice(args.items);
            expr = try p.ast.addNode(.call_expr, lparen, .{ .lhs = expr, .rhs = extra });
            }
            break;
        }
        return expr;
    }

    fn parseTypedAggregateLiteral(p: *Parser, type_node: NodeIndex, dot_tok: Token.Index) !NodeIndex {
        _ = try p.expect(.l_brace, "expected '{{' after typed aggregate literal '.'", .{});
        var fields = std.ArrayList(u32).empty;
        defer fields.deinit(p.allocator);
        if (!p.check(.r_brace)) {
            while (true) {
                const field_tok = try p.expect(.identifier, "expected field name in typed aggregate literal", .{});
                _ = try p.expect(.equal, "expected '=' after typed aggregate field name", .{});
                const value = try p.parseExpr();
                const lhs = try p.ast.addNode(.identifier, field_tok, .{});
                try fields.append(p.allocator, try p.ast.addNode(.assign_stmt, field_tok, .{ .lhs = lhs, .rhs = value }));
                if (!p.matchDiscard(.comma)) break;
                if (p.check(.r_brace)) break;
            }
        }
        _ = try p.expect(.r_brace, "expected '}}' after typed aggregate literal", .{});
        const extra = try p.ast.addExtraSlice(fields.items);
        const payload = [_]u32{ type_node, extra, @intCast(fields.items.len) };
        const payload_extra = try p.ast.addExtraSlice(&payload);
        return p.ast.addNode(.typed_aggregate_literal, dot_tok, .{ .lhs = payload_extra, .rhs = 3 });
    }

    fn parsePrimary(p: *Parser) !NodeIndex {
        if (p.match(.directive_run)) |tok| {
            if (p.check(.comma) or p.check(.arrow)) return p.parseRunArrowBlock(tok);
            if (p.check(.l_brace)) return p.ast.addNode(.run_expr, tok, .{ .lhs = try p.parseBlock() });
            if (p.matchDiscard(.l_paren)) {
                const operand = try p.parseExpr();
                _ = try p.expect(.r_paren, "expected ')' after #run expression", .{});
                return p.ast.addNode(.run_expr, tok, .{ .lhs = operand });
            }
            const operand = try p.parseExpr();
            return p.ast.addNode(.run_expr, tok, .{ .lhs = operand });
        }
        if (p.match(.directive_char)) |tok| {
            const str_tok = try p.expect(.string_literal, "expected string literal after #char", .{});
            return p.ast.addNode(.char_literal, tok, .{ .lhs = str_tok });
        }
        if (p.match(.keyword_xx)) |tok| {
            const operand = try p.parseUnary();
            return p.ast.addNode(.unary_expr, tok, .{ .lhs = operand });
        }
        if (p.match(.keyword_ifx)) |tok| {
            const cond = try p.parseExpr();
            _ = try p.expect(.keyword_then, "expected 'then' in ifx expression", .{});
            const then_expr = try p.parseExpr();
            _ = try p.expect(.keyword_else, "expected 'else' in ifx expression", .{});
            const else_expr = try p.parseExpr();
            const arms = [_]u32{ then_expr, else_expr };
            const extra = try p.ast.addExtraSlice(&arms);
            return p.ast.addNode(.ifx_expr, tok, .{ .lhs = cond, .rhs = extra });
        }
        if (p.match(.directive_string)) |tok| {
            const payload_tok = try p.expect(.string_literal, "expected #string payload", .{});
            return p.ast.addNode(.string_literal, payload_tok, .{ .lhs = tok });
        }
        if (p.match(.keyword_cast)) |tok| {
            var no_check: u32 = 0;
            if (p.matchDiscard(.comma)) {
                const modifier_tok = try p.expect(.identifier, "expected cast modifier after ','", .{});
                const modifier = p.ast.tokenSlice(modifier_tok);
                if (std.mem.eql(u8, modifier, "no_check")) {
                    no_check = 1;
                } else {
                    return p.diag.failAt(p.tokens[modifier_tok].start, "unsupported cast modifier '{s}'", .{modifier});
                }
            }
            _ = try p.expect(.l_paren, "expected '(' after cast", .{});
            const target_ty = try p.parseTypeExpr();
            _ = try p.expect(.r_paren, "expected ')' after cast type", .{});
            const operand = try p.parseUnary();
            return p.ast.addNode(.unary_expr, tok, .{ .lhs = operand, .rhs = target_ty + no_check * 0x80000000 });
        }
        if (p.match(.keyword_type_of)) |tok| {
            _ = try p.expect(.l_paren, "expected '(' after type_of", .{});
            const operand = try p.parseExpr();
            _ = try p.expect(.r_paren, "expected ')' after type_of operand", .{});
            return p.ast.addNode(.type_of_expr, tok, .{ .lhs = operand });
        }
        if (p.match(.keyword_is_constant)) |tok| {
            _ = try p.expect(.l_paren, "expected '(' after is_constant", .{});
            const operand = try p.parseExpr();
            _ = try p.expect(.r_paren, "expected ')' after is_constant operand", .{});
            return p.ast.addNode(.is_constant_expr, tok, .{ .lhs = operand });
        }
        if (p.match(.keyword_size_of)) |tok| {
            _ = try p.expect(.l_paren, "expected '(' after size_of", .{});
            const operand = try p.parseTypeOrExpr();
            _ = try p.expect(.r_paren, "expected ')' after size_of operand", .{});
            return p.ast.addNode(.size_of_expr, tok, .{ .lhs = operand });
        }
        if (p.match(.dot)) |tok| {
            _ = try p.expect(.l_brace, "expected '{{' after '.' aggregate literal", .{});
            var values = std.ArrayList(u32).empty;
            defer values.deinit(p.allocator);
            if (!p.check(.r_brace)) {
                try values.append(p.allocator, try p.parseExpr());
                while (p.matchDiscard(.comma)) {
                    if (p.check(.r_brace)) break;
                    try values.append(p.allocator, try p.parseExpr());
                }
            }
            _ = try p.expect(.r_brace, "expected '}}' after aggregate literal", .{});
            const extra = try p.ast.addExtraSlice(values.items);
            return p.ast.addNode(.aggregate_literal, tok, .{ .lhs = extra, .rhs = @intCast(values.items.len) });
        }
        if (p.match(.l_paren)) |_| {
            const expr = try p.parseExpr();
            _ = try p.expect(.r_paren, "expected ')' after parenthesized expression", .{});
            return expr;
        }
        if (p.match(.identifier)) |tok| return p.ast.addNode(.identifier, tok, .{});
        if (isTypeKeyword(p.peekTag(0))) {
            const type_tok = p.index;
            p.index += 1;
            return p.ast.addNode(.type_expr, type_tok, .{});
        }
        if (p.match(.string_literal)) |tok| return p.ast.addNode(.string_literal, tok, .{});
        if (p.match(.integer_literal)) |tok| return p.ast.addNode(.integer_literal, tok, .{});
        if (p.match(.float_literal)) |tok| return p.ast.addNode(.float_literal, tok, .{});
        if (p.match(.keyword_null)) |tok| return p.ast.addNode(.null_literal, tok, .{});
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

fn astNodeIsIdentifierName(ast: *const Ast, node: NodeIndex, name: []const u8) bool {
    if (ast.tag(node) != .identifier) return false;
    return std.mem.eql(u8, ast.tokenSlice(ast.mainToken(node)), name);
}

fn astValueIsRunBlock(ast: *const Ast, node: NodeIndex) bool {
    return ast.tag(node) == .run_expr and ast.data(node).lhs != null_node and ast.tag(ast.data(node).lhs) == .block;
}

fn isTypeKeyword(tag: Tag) bool {
    return switch (tag) {
        .keyword_void => true,
        else => false,
    };
}

fn binaryPrecedence(tag: Tag) ?u8 {
    return switch (tag) {
        .pipe_pipe => 3,
        .ampersand_ampersand => 4,
        .equal_equal, .bang_equal => 5,
        .star, .slash, .percent => 20,
        .plus, .minus => 10,
        else => null,
    };
}

test "parser parses statement-form run with stallable modifier" {
    const lexer = @import("lexer.zig");
    const source = "#import \"Basic\";\nbuild :: () {}\n#run,stallable build();\nmain :: () {}\n";
    const diag = Diagnostic.init(std.testing.allocator, "run_stallable.jai", source);
    var tokens = try lexer.tokenize(std.testing.allocator, source, diag);
    defer tokens.deinit(std.testing.allocator);
    const slice = tokens.slice();
    var ast = try parse(std.testing.allocator, source, slice.items(.tag), slice.items(.start), slice.items(.end), diag);
    defer {
        std.testing.allocator.free(ast.tokens);
        ast.deinit();
    }
    const decls = ast.extraSlice(ast.data(ast.root).lhs);
    try std.testing.expectEqual(@as(usize, 4), decls.len);
    const run_decl: NodeIndex = @intCast(decls[2]);
    try std.testing.expectEqual(Node.Tag.run_expr, ast.tag(run_decl));
    const call = ast.data(run_decl).lhs;
    try std.testing.expectEqual(Node.Tag.call_expr, ast.tag(call));
    const callee = ast.data(call).lhs;
    try std.testing.expectEqual(Node.Tag.identifier, ast.tag(callee));
    try std.testing.expectEqualStrings("build", ast.tokenSlice(ast.mainToken(callee)));
    try std.testing.expectEqual(@as(usize, 0), ast.extraSlice(ast.data(call).rhs).len);
}

test "parser preserves expression-form run arrow block" {
    const lexer = @import("lexer.zig");
    const source = "#import \"Basic\";\nVERSION :: #run -> string { return \"dev\"; }\nmain :: () {}\n";
    const diag = Diagnostic.init(std.testing.allocator, "run_arrow.jai", source);
    var tokens = try lexer.tokenize(std.testing.allocator, source, diag);
    defer tokens.deinit(std.testing.allocator);
    const slice = tokens.slice();
    var ast = try parse(std.testing.allocator, source, slice.items(.tag), slice.items(.start), slice.items(.end), diag);
    defer {
        std.testing.allocator.free(ast.tokens);
        ast.deinit();
    }
    const decls = ast.extraSlice(ast.data(ast.root).lhs);
    try std.testing.expectEqual(@as(usize, 3), decls.len);
    const version_decl: NodeIndex = @intCast(decls[1]);
    try std.testing.expectEqual(Node.Tag.const_decl, ast.tag(version_decl));
    const run_expr = ast.data(version_decl).lhs;
    try std.testing.expectEqual(Node.Tag.run_expr, ast.tag(run_expr));
    try std.testing.expectEqual(Node.Tag.block, ast.tag(ast.data(run_expr).lhs));
    try std.testing.expectEqual(Node.Tag.type_expr, ast.tag(ast.data(run_expr).rhs));
    try std.testing.expectEqualStrings("string", ast.tokenSlice(ast.mainToken(ast.data(run_expr).rhs)));
}
test "parser parses hello sailor AST shape" {
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
    const decls = ast.extraSlice(ast.data(ast.root).lhs);
    try std.testing.expectEqual(@as(usize, 2), decls.len);
    const import_decl: NodeIndex = @intCast(decls[0]);
    const main_decl: NodeIndex = @intCast(decls[1]);
    try std.testing.expectEqual(Node.Tag.import_decl, ast.tag(import_decl));
    try std.testing.expectEqualStrings("Basic", ast.stringTokenContents(ast.data(import_decl).lhs));
    try std.testing.expectEqual(Node.Tag.proc_decl, ast.tag(main_decl));
    try std.testing.expectEqualStrings("main", ast.tokenSlice(ast.mainToken(main_decl)));
    const block = ast.data(main_decl).lhs;
    try std.testing.expectEqual(Node.Tag.block, ast.tag(block));
    const stmts = ast.extraSlice(ast.data(block).lhs);
    try std.testing.expectEqual(@as(usize, 1), stmts.len);
    const expr_stmt: NodeIndex = @intCast(stmts[0]);
    try std.testing.expectEqual(Node.Tag.expr_stmt, ast.tag(expr_stmt));
    const call = ast.data(expr_stmt).lhs;
    try std.testing.expectEqual(Node.Tag.call_expr, ast.tag(call));
    const callee = ast.data(call).lhs;
    try std.testing.expectEqual(Node.Tag.identifier, ast.tag(callee));
    try std.testing.expectEqualStrings("print", ast.tokenSlice(ast.mainToken(callee)));
    const args = ast.extraSlice(ast.data(call).rhs);
    try std.testing.expectEqual(@as(usize, 1), args.len);
    const arg: NodeIndex = @intCast(args[0]);
    try std.testing.expectEqual(Node.Tag.string_literal, ast.tag(arg));
    try std.testing.expectEqualStrings("Hello, Sailor from Jai!\\n", ast.stringTokenContents(ast.mainToken(arg)));
}
