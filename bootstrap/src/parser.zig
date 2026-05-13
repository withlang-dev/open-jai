const std = @import("std");
const builtin = @import("builtin");
const Token = @import("Token.zig").Token;
const Tag = @import("Token.zig").Tag;
const Ast = @import("Ast.zig").Ast;
const null_node = @import("Ast.zig").null_node;
const Node = @import("Ast.zig").Node;
const NodeIndex = @import("Ast.zig").NodeIndex;
const Diagnostic = @import("diagnostics.zig").Diagnostic;
const using_param_sentinel: u32 = 0xfffffffe;

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
            if (p.ast.tag(decl) == .stmt_list) {
                try decls.appendSlice(p.allocator, p.ast.extraSlice(p.ast.data(decl).lhs));
            } else {
                try decls.append(p.allocator, decl);
            }
            _ = p.matchDiscard(.semicolon);
        }
        const extra = try p.ast.addExtraSlice(decls.items);
        const root = try p.ast.addNode(.root, 0, .{ .lhs = extra, .rhs = @intCast(decls.items.len) });
        p.ast.root = root;
        return p.ast;
    }

    fn parseTopLevelDecl(p: *Parser) anyerror!NodeIndex {
        if (p.match(.directive_if)) |tok| return p.parseDirectiveIf(tok, true);
        if (p.match(.directive_import)) |tok| return p.parseImport(tok);
        if (p.match(.directive_load)) |tok| return p.parseLoad(tok);
        if (p.match(.directive_scope_file)) |tok| return p.parseScope(tok);
        if (p.match(.directive_scope_export)) |tok| return p.parseScope(tok);
        if (p.match(.directive_scope_module)) |tok| return p.parseScope(tok);
        if (p.match(.directive_program_export)) |_| return p.parseTopLevelDecl();
        if (p.match(.directive_no_reset)) |_| {
            const decl = try p.parseTopLevelDecl();
            try p.markNoResetDecl(decl);
            return decl;
        }
        if (p.match(.directive_poke_name)) |tok| return p.parseTopLevelMetaDirective(tok);
        if (p.match(.directive_add_context)) |tok| return p.parseAddContext(tok);
        if (p.match(.directive_assert)) |tok| return p.parseTopLevelAssert(tok);
        if (p.match(.directive_placeholder)) |tok| return p.parseTopLevelPlaceholder(tok);
        if (p.match(.directive_run)) |tok| return p.parseRunStatement(tok);
        if (p.match(.keyword_operator)) |_| return p.parseOperatorDecl();
        if (p.check(.identifier)) {
            if (p.peekTag(1) == .colon_colon or p.peekTag(1) == .colon or p.peekTag(1) == .colon_equal or p.peekTag(1) == .comma) return p.parseTopLevelIdentifierDecl();
        }
        return p.failCurrent("expected top-level import, constant, or procedure declaration", .{});
    }

    fn markNoResetDecl(p: *Parser, node: NodeIndex) !void {
        if (node == null_node) return;
        if (p.ast.tag(node) == .stmt_list) {
            for (p.ast.extraSlice(p.ast.data(node).lhs)) |child| try p.markNoResetDecl(@intCast(child));
            return;
        }
        try p.ast.markNoReset(node);
    }

    fn parseOperatorDecl(p: *Parser) !NodeIndex {
        const name_tok = p.index;
        while (!p.check(.colon_colon) and !p.check(.eof)) p.index += 1;
        _ = try p.expect(.colon_colon, "expected '::' after operator name", .{});
        return p.parseProcDeclAfterName(name_tok);
    }

    fn parseTopLevelIdentifierDecl(p: *Parser) !NodeIndex {
        const name_tok = try p.expect(.identifier, "expected top-level declaration name", .{});
        if (p.check(.comma)) return p.parseTopLevelMultiNameDeclAfterFirst(name_tok);
        if (p.matchDiscard(.colon_colon)) {
            if (p.check(.keyword_inline) or p.check(.keyword_no_inline)) return p.parseProcDeclAfterName(name_tok);
            if (p.check(.l_paren)) return p.parseProcDeclAfterName(name_tok);
            if (p.check(.directive_import) or p.check(.directive_library) or p.check(.directive_system_library) or p.check(.directive_foreign_library) or p.check(.directive_type) or p.check(.directive_bake_arguments) or p.check(.directive_bake_constants) or p.check(.directive_code)) {
                return p.parseTopLevelDirectiveConstAfterName(name_tok);
            }
            const value = try p.parseTypeOrExpr();
            if (nodeAllowsImplicitTerminator(&p.ast, value)) {
                _ = p.matchDiscard(.semicolon);
            } else {
                _ = try p.expect(.semicolon, "expected semicolon after constant declaration", .{});
            }
            return p.ast.addNode(.const_decl, name_tok, .{ .lhs = value });
        }
        if (p.matchDiscard(.colon_equal)) {
            const init = try p.parseExpr();
            if (nodeAllowsImplicitTerminator(&p.ast, init)) {
                _ = p.matchDiscard(.semicolon);
            } else {
                _ = try p.expect(.semicolon, "expected semicolon after top-level variable declaration", .{});
            }
            return p.ast.addNode(.var_decl, name_tok, .{ .lhs = null_node, .rhs = init });
        }
        _ = try p.expect(.colon, "expected ':', ':=', or '::' after declaration name", .{});
        const type_expr = try p.parseTypeExpr();
        try p.consumeDeclModifiers();
        if (p.matchDiscard(.colon)) {
            const value = try p.parseExpr();
            _ = try p.expect(.semicolon, "expected semicolon after typed constant declaration", .{});
            return p.ast.addNode(.const_decl, name_tok, .{ .lhs = value, .rhs = p.ast.mainToken(type_expr) });
        }
        const init = if (p.matchDiscard(.equal)) blk: {
            if (p.match(.triple_minus)) |tok| break :blk try p.ast.addNode(.undefined_literal, tok, .{});
            break :blk try p.parseExpr();
        } else null_node;
        if (init == null_node and nodeAllowsImplicitTerminator(&p.ast, type_expr)) {
            _ = p.matchDiscard(.semicolon);
        } else {
            _ = try p.expect(.semicolon, "expected semicolon after top-level variable declaration", .{});
        }
        return p.ast.addNode(.var_decl, name_tok, .{ .lhs = type_expr, .rhs = init });
    }

    fn parseTopLevelMultiNameDeclAfterFirst(p: *Parser, first_name_tok: Token.Index) !NodeIndex {
        var name_toks = std.ArrayList(Token.Index).empty;
        defer name_toks.deinit(p.allocator);
        try name_toks.append(p.allocator, first_name_tok);
        while (p.matchDiscard(.comma)) try name_toks.append(p.allocator, try p.expect(.identifier, "expected declaration name after ','", .{}));
        _ = try p.expect(.colon, "expected ':' after multi-name top-level declaration", .{});
        const type_expr = try p.parseTypeExpr();
        try p.consumeDeclModifiers();
        const init = if (p.matchDiscard(.equal)) blk: {
            if (p.match(.triple_minus)) |tok| break :blk try p.ast.addNode(.undefined_literal, tok, .{});
            break :blk try p.parseExpr();
        } else null_node;
        _ = try p.expect(.semicolon, "expected semicolon after top-level variable declaration", .{});
        var decls = std.ArrayList(u32).empty;
        defer decls.deinit(p.allocator);
        for (name_toks.items) |name_tok| {
            try decls.append(p.allocator, try p.ast.addNode(.var_decl, name_tok, .{ .lhs = type_expr, .rhs = init }));
        }
        const extra = try p.ast.addExtraSlice(decls.items);
        return p.ast.addNode(.stmt_list, first_name_tok, .{ .lhs = extra, .rhs = @intCast(decls.items.len) });
    }

    fn parseTopLevelDirectiveConstAfterName(p: *Parser, name_tok: Token.Index) !NodeIndex {
        if (p.match(.directive_import)) |tok| {
            const value = try p.parseImportLikeDirective(tok, "expected module string after #import");
            _ = try p.expect(.semicolon, "expected semicolon after import", .{});
            return p.ast.addNode(.const_decl, name_tok, .{ .lhs = value });
        }
        if (p.match(.directive_library)) |tok| {
            const value = try p.parseImportLikeDirective(tok, "expected library string after #library");
            _ = p.matchDiscard(.semicolon);
            return p.ast.addNode(.const_decl, name_tok, .{ .lhs = value });
        }
        if (p.match(.directive_system_library)) |tok| {
            const value = try p.parseImportLikeDirective(tok, "expected library string after #system_library");
            _ = p.matchDiscard(.semicolon);
            return p.ast.addNode(.const_decl, name_tok, .{ .lhs = value });
        }
        if (p.match(.directive_foreign_library)) |tok| {
            const value = try p.parseImportLikeDirective(tok, "expected library string after #foreign_library");
            _ = p.matchDiscard(.semicolon);
            return p.ast.addNode(.const_decl, name_tok, .{ .lhs = value });
        }
        if (p.match(.directive_type) != null) {
            while (p.matchDiscard(.comma)) _ = try p.expect(.identifier, "expected #type modifier after ','", .{});
            const value = try p.parseTypeExpr();
            try p.consumeProcModifiers();
            _ = p.matchDiscard(.semicolon);
            return p.ast.addNode(.const_decl, name_tok, .{ .lhs = value });
        }
        if (p.match(.directive_bake_arguments) != null) {
            const value = try p.parseTypeExpr();
            _ = p.matchDiscard(.semicolon);
            return p.ast.addNode(.const_decl, name_tok, .{ .lhs = value });
        }
        if (p.match(.directive_bake_constants)) |tok| {
            const value = try p.parseOpaqueDirectiveExpr(tok);
            _ = p.matchDiscard(.semicolon);
            return p.ast.addNode(.const_decl, name_tok, .{ .lhs = value });
        }
        if (p.match(.directive_code)) |tok| {
            const value = try p.parseOpaqueDirectiveExpr(tok);
            _ = p.matchDiscard(.semicolon);
            return p.ast.addNode(.const_decl, name_tok, .{ .lhs = value });
        }
        return p.failCurrent("expected supported directive after '::'", .{});
    }

    fn parseProcDecl(p: *Parser) !NodeIndex {
        const name_tok = try p.expect(.identifier, "expected procedure name", .{});
        _ = try p.expect(.colon_colon, "expected double colon after procedure name", .{});
        return p.parseProcDeclAfterName(name_tok);
    }

    fn parseProcDeclAfterName(p: *Parser, name_tok: Token.Index) !NodeIndex {
        _ = p.matchDiscard(.keyword_inline) or p.matchDiscard(.keyword_no_inline);
        _ = try p.expect(.l_paren, "expected opening paren in procedure declaration", .{});
        var params = std.ArrayList(u32).empty;
        defer params.deinit(p.allocator);
        if (!p.check(.r_paren)) {
            while (true) {
                const is_using_param = p.matchDiscard(.keyword_using);
                _ = p.matchDiscard(.dollar) or p.matchDiscard(.dollar_dollar);
                const param_name = try p.expect(.identifier, "expected parameter name", .{});
                var is_variadic_param = false;
                var param_type: NodeIndex = null_node;
                var param_init: NodeIndex = null_node;
                if (p.matchDiscard(.colon)) {
                    is_variadic_param = p.matchDiscard(.dot_dot);
                    param_type = try p.parseTypeExpr();
                    if (p.matchDiscard(.equal)) param_init = try p.parseExpr();
                } else if (p.matchDiscard(.colon_equal)) {
                    param_init = try p.parseExpr();
                }
                const rhs: u32 = if (is_variadic_param) 1 else if (is_using_param and param_init == null_node) using_param_sentinel else param_init;
                const param = try p.ast.addNode(.var_decl, param_name, .{ .lhs = param_type, .rhs = rhs });
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
        var named_returns = std.ArrayList(u32).empty;
        defer named_returns.deinit(p.allocator);
        const return_type = if (p.matchDiscard(.arrow)) try p.parseProcReturnSpec(&named_returns) else null_node;
        try p.consumeProcModifiers();
        var body = if (p.matchDiscard(.semicolon)) try p.emptyBlock(name_tok) else try p.parseBlock();
        _ = p.matchDiscard(.semicolon);
        var notes = std.ArrayList(Token.Index).empty;
        defer notes.deinit(p.allocator);
        while (p.matchDiscard(.at)) try notes.append(p.allocator, try p.expect(.identifier, "expected attribute name after '@'", .{}));
        if (named_returns.items.len != 0) body = try p.prependBlockDecls(body, named_returns.items);
        const params_extra = try p.ast.addExtraSlice(params.items);
        const sig_values = [_]u32{ params_extra, return_type };
        const sig_extra = try p.ast.addExtraSlice(&sig_values);
        const proc = try p.ast.addNode(.proc_decl, name_tok, .{ .lhs = body, .rhs = sig_extra });
        try p.ast.addNodeNotes(proc, notes.items);
        return proc;
    }

    fn parseProcReturnSpec(p: *Parser, named_returns: *std.ArrayList(u32)) !NodeIndex {
        if (p.matchDiscard(.l_paren)) {
            if (p.check(.identifier) and p.peekTag(1) == .colon) {
                const return_type = try p.parseProcReturnSpec(named_returns);
                _ = try p.expect(.r_paren, "expected ')' after procedure return types", .{});
                return return_type;
            }
            const first_type = try p.parseTypeExpr();
            while (p.matchDiscard(.comma)) _ = try p.parseTypeExpr();
            _ = try p.expect(.r_paren, "expected ')' after procedure return types", .{});
            return first_type;
        }
        if (p.check(.identifier) and p.peekTag(1) == .colon) {
            const name_tok = try p.expect(.identifier, "expected named return name", .{});
            _ = try p.expect(.colon, "expected ':' in named return declaration", .{});
            const return_type = try p.parseTypeExpr();
            const init = if (p.matchDiscard(.equal)) try p.parseExpr() else null_node;
            try named_returns.append(p.allocator, try p.ast.addNode(.var_decl, name_tok, .{ .lhs = return_type, .rhs = init }));
            while (p.matchDiscard(.comma)) {
                if (!(p.check(.identifier) and p.peekTag(1) == .colon)) {
                    _ = try p.parseTypeExpr();
                    continue;
                }
                const next_name_tok = try p.expect(.identifier, "expected named return name", .{});
                _ = try p.expect(.colon, "expected ':' in named return declaration", .{});
                const next_type = try p.parseTypeExpr();
                const next_init = if (p.matchDiscard(.equal)) try p.parseExpr() else null_node;
                try named_returns.append(p.allocator, try p.ast.addNode(.var_decl, next_name_tok, .{ .lhs = next_type, .rhs = next_init }));
            }
            return return_type;
        }
        const first_type = try p.parseTypeExpr();
        while (p.matchDiscard(.comma)) {
            if (p.check(.identifier) and p.peekTag(1) == .colon) {
                const name_tok = try p.expect(.identifier, "expected named return name", .{});
                _ = try p.expect(.colon, "expected ':' in named return declaration", .{});
                const ty = try p.parseTypeExpr();
                const init = if (p.matchDiscard(.equal)) try p.parseExpr() else null_node;
                try named_returns.append(p.allocator, try p.ast.addNode(.var_decl, name_tok, .{ .lhs = ty, .rhs = init }));
            } else {
                _ = try p.parseTypeExpr();
            }
        }
        return first_type;
    }

    fn prependBlockDecls(p: *Parser, block: NodeIndex, decls: []const u32) !NodeIndex {
        var stmts = std.ArrayList(u32).empty;
        defer stmts.deinit(p.allocator);
        try stmts.appendSlice(p.allocator, decls);
        try stmts.appendSlice(p.allocator, p.ast.extraSlice(p.ast.data(block).lhs));
        const extra = try p.ast.addExtraSlice(stmts.items);
        return p.ast.addNode(.block, p.ast.mainToken(block), .{ .lhs = extra, .rhs = @intCast(stmts.items.len) });
    }

    fn emptyBlock(p: *Parser, main_tok: Token.Index) !NodeIndex {
        const extra = try p.ast.addExtraSlice(&.{});
        return p.ast.addNode(.block, main_tok, .{ .lhs = extra, .rhs = 0 });
    }

    fn consumeProcModifiers(p: *Parser) !void {
        while (true) {
            switch (p.peekTag(0)) {
                .directive_must, .directive_expand, .directive_c_call, .directive_no_context, .directive_cpp_method, .directive_dump => p.index += 1,
                .directive_modify => {
                    p.index += 1;
                    if (p.check(.l_brace)) {
                        try p.skipBalancedBraces();
                    } else {
                        while (!p.check(.l_brace) and !p.check(.semicolon) and !p.check(.eof)) p.index += 1;
                    }
                },
                .directive_deprecated => {
                    p.index += 1;
                    if (p.check(.string_literal)) p.index += 1;
                },
                .directive_elsewhere => {
                    p.index += 1;
                    if (p.check(.identifier)) p.index += 1;
                },
                .directive_foreign, .directive_library, .directive_system_library, .directive_foreign_library => {
                    p.index += 1;
                    while (p.check(.identifier) or p.check(.string_literal) or p.check(.comma)) p.index += 1;
                },
                else => return,
            }
        }
    }

    fn consumeDeclModifiers(p: *Parser) !void {
        while (true) {
            switch (p.peekTag(0)) {
                .directive_align => {
                    p.index += 1;
                    _ = try p.parseExpr();
                },
                .directive_no_padding, .directive_specified => p.index += 1,
                else => return,
            }
        }
    }

    fn skipBalancedBraces(p: *Parser) !void {
        _ = try p.expect(.l_brace, "expected '{{'", .{});
        var depth: usize = 1;
        while (depth > 0) {
            if (p.check(.eof)) return p.failCurrent("expected closing brace before end of file", .{});
            const tag = p.peekTag(0);
            p.index += 1;
            switch (tag) {
                .l_brace => depth += 1,
                .r_brace => depth -= 1,
                else => {},
            }
        }
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

    fn parseTopLevelAssert(p: *Parser, tok: Token.Index) !NodeIndex {
        const cond = try p.parseExpr();
        if (p.check(.string_literal)) p.index += 1;
        _ = p.matchDiscard(.semicolon);
        return p.ast.addNode(.run_expr, tok, .{ .lhs = cond });
    }

    fn parseTopLevelPlaceholder(p: *Parser, tok: Token.Index) !NodeIndex {
        const name_tok = try p.expect(.identifier, "expected placeholder name after #placeholder", .{});
        _ = p.matchDiscard(.semicolon);
        return p.ast.addNode(.placeholder_decl, name_tok, .{ .lhs = tok });
    }

    fn parseScope(p: *Parser, tok: Token.Index) !NodeIndex {
        _ = p.matchDiscard(.semicolon);
        return p.ast.addNode(.scope_decl, tok, .{});
    }

    fn parseTopLevelMetaDirective(p: *Parser, tok: Token.Index) !NodeIndex {
        while (!p.check(.semicolon) and !p.check(.eof)) p.index += 1;
        _ = p.matchDiscard(.semicolon);
        return p.ast.addNode(.meta_stmt, tok, .{ .lhs = try p.emptyBlock(tok), .rhs = null_node });
    }

    fn parseLoad(p: *Parser, tok: Token.Index) !NodeIndex {
        const str_tok = try p.expect(.string_literal, "expected file string after #load", .{});
        _ = try p.expect(.semicolon, "expected semicolon after #load", .{});
        return p.ast.addNode(.load_decl, tok, .{ .lhs = str_tok });
    }

    fn parseImport(p: *Parser, tok: Token.Index) !NodeIndex {
        const import_node = try p.parseImportLikeDirective(tok, "expected module string after #import");
        _ = try p.expect(.semicolon, "expected semicolon after import", .{});
        return import_node;
    }

    fn parseImportLikeDirective(p: *Parser, tok: Token.Index, comptime msg: []const u8) !NodeIndex {
        var has_dir: u32 = 0;
        while (p.matchDiscard(.comma)) {
            const modifier_tok = try p.expect(.identifier, "expected directive modifier after ','", .{});
            const modifier = p.ast.tokenSlice(modifier_tok);
            if (std.mem.eql(u8, modifier, "dir")) has_dir = 1;
        }
        const str_tok = try p.expect(.string_literal, msg, .{});
        if (p.matchDiscard(.l_paren)) {
            while (!p.check(.r_paren)) p.index += 1;
            _ = try p.expect(.r_paren, "expected ')' after import module parameters", .{});
        }
        return p.ast.addNode(.import_decl, tok, .{ .lhs = str_tok, .rhs = has_dir });
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

    fn parseStmt(p: *Parser) anyerror!NodeIndex {
        if (p.match(.directive_if)) |tok| return p.parseDirectiveIf(tok, false);
        if (p.match(.directive_asm)) |tok| return p.parseAsmStmt(tok);
        if (p.match(.directive_import)) |tok| return p.parseImport(tok);
        if (p.match(.directive_insert)) |tok| {
            const value = try p.parseOpaqueDirectiveExpr(tok);
            _ = p.matchDiscard(.semicolon);
            return p.ast.addNode(.meta_stmt, tok, .{ .lhs = value, .rhs = null_node });
        }
        if (p.match(.directive_load)) |tok| return p.parseLoad(tok);
        if (p.match(.directive_assert)) |tok| return p.parseTopLevelAssert(tok);
        if (p.match(.directive_placeholder)) |tok| return p.parseTopLevelPlaceholder(tok);
        if (p.matchDiscard(.keyword_inline) or p.matchDiscard(.keyword_no_inline)) {
            const expr = try p.parseExpr();
            _ = try p.expect(.semicolon, "expected semicolon after expression statement", .{});
            return p.ast.addNode(.expr_stmt, p.ast.mainToken(expr), .{ .lhs = expr });
        }
        if (p.match(.directive_run)) |tok| return p.parseRunStatement(tok);
        if (p.match(.keyword_push_context)) |tok| {
            const ctx_expr = try p.parseExpr();
            const body = try p.parseBlock();
            return p.ast.addNode(.run_expr, tok, .{ .lhs = body, .rhs = ctx_expr });
        }
        if (p.match(.keyword_return)) |tok| {
            if (p.check(.identifier) and p.peekTag(1) == .equal) {
                var stmts = std.ArrayList(u32).empty;
                defer stmts.deinit(p.allocator);
                while (true) {
                    const name_tok = try p.expect(.identifier, "expected named return value", .{});
                    _ = try p.expect(.equal, "expected '=' in named return assignment", .{});
                    const lhs = try p.ast.addNode(.identifier, name_tok, .{});
                    const rhs = try p.parseExpr();
                    try stmts.append(p.allocator, try p.ast.addNode(.assign_stmt, name_tok, .{ .lhs = lhs, .rhs = rhs }));
                    if (!p.matchDiscard(.comma)) break;
                }
                _ = try p.expect(.semicolon, "expected semicolon after return statement", .{});
                try stmts.append(p.allocator, try p.ast.addNode(.return_stmt, tok, .{ .lhs = null_node }));
                const extra = try p.ast.addExtraSlice(stmts.items);
                return p.ast.addNode(.stmt_list, tok, .{ .lhs = extra, .rhs = @intCast(stmts.items.len) });
            }
            const expr = if (p.check(.semicolon)) null_node else blk: {
                var values = std.ArrayList(NodeIndex).empty;
                defer values.deinit(p.allocator);
                try values.append(p.allocator, try p.parseExpr());
                while (p.matchDiscard(.comma)) try values.append(p.allocator, try p.parseExpr());
                if (values.items.len == 1) break :blk values.items[0];
                const extra = try p.ast.addExtraSlice(values.items);
                break :blk try p.ast.addNode(.stmt_list, tok, .{ .lhs = extra, .rhs = @intCast(values.items.len) });
            };
            _ = try p.expect(.semicolon, "expected semicolon after return statement", .{});
            return p.ast.addNode(.return_stmt, tok, .{ .lhs = expr });
        }
        if (p.match(.keyword_using)) |tok| {
            if (p.checkIdentifierLike() and p.peekTag(1) == .colon) {
                const name_tok = p.index;
                p.index += 2;
                const type_expr = try p.parseTypeExpr();
                _ = try p.expect(.semicolon, "expected semicolon after using declaration", .{});
                return p.ast.addNode(.var_decl, name_tok, .{ .lhs = type_expr, .rhs = null_node });
            }
            const expr = try p.parseExpr();
            _ = try p.expect(.semicolon, "expected semicolon after using statement", .{});
            return p.ast.addNode(.expr_stmt, tok, .{ .lhs = expr });
        }
        if (p.check(.keyword_if)) return p.parseIfStmt();
        if (p.check(.keyword_for)) return p.parseForStmt();
        if (p.check(.keyword_while)) return p.parseWhileStmt();
        if (p.check(.l_brace)) {
            // Bare block: anonymous scope.
            const block = try p.parseBlock();
            return block;
        }
        if (p.match(.keyword_defer)) |tok| {
            const deferred = try p.parseStmt();
            _ = p.matchDiscard(.semicolon);
            return p.ast.addNode(.defer_stmt, tok, .{ .lhs = deferred });
        }
        if (p.match(.keyword_break)) |tok| {
            const label: u32 = if (p.check(.identifier)) blk: {
                const t = p.index;
                p.index += 1;
                break :blk t;
            } else 0;
            _ = try p.expect(.semicolon, "expected semicolon after break", .{});
            return p.ast.addNode(.break_stmt, tok, .{ .lhs = label });
        }
        if (p.match(.keyword_continue)) |tok| {
            const label: u32 = if (p.check(.identifier)) blk: {
                const t = p.index;
                p.index += 1;
                break :blk t;
            } else 0;
            _ = try p.expect(.semicolon, "expected semicolon after continue", .{});
            return p.ast.addNode(.continue_stmt, tok, .{ .lhs = label });
        }
        if (p.check(.identifier) or p.check(.keyword_it) or p.check(.keyword_it_index)) {
            if (p.check(.identifier) and std.mem.eql(u8, p.ast.tokenSlice(p.index), "remove")) {
                const tok = p.index;
                p.index += 1;
                const operand = try p.parseExpr();
                _ = try p.expect(.semicolon, "expected semicolon after remove statement", .{});
                return p.ast.addNode(.meta_stmt, tok, .{ .lhs = operand, .rhs = null_node });
            }
            if (p.peekTag(1) == .comma or (p.peekTag(1) == .colon and p.peekTag(2) == .comma)) return p.parseMultiNameStmt();
            if (p.peekTag(1) == .colon) return p.parseLocalTypedDecl();
            if (p.peekTag(1) == .colon_equal) return p.parseLocalInferredDecl();
            if (p.peekTag(1) == .plus_equal or p.peekTag(1) == .minus_equal or p.peekTag(1) == .star_equal or p.peekTag(1) == .slash_equal or p.peekTag(1) == .ampersand_equal or p.peekTag(1) == .pipe_equal or p.peekTag(1) == .caret_equal) return p.parseAssignStmt();
            if (p.peekTag(1) == .colon_colon and p.peekTag(2) == .l_paren) return p.parseProcDecl();
            if (p.peekTag(1) == .colon_colon) return p.parseLocalConstDecl();
            if (p.peekTag(1) == .equal or p.peekTag(1) == .plus_equal or p.peekTag(1) == .minus_equal or p.peekTag(1) == .star_equal or p.peekTag(1) == .slash_equal or p.peekTag(1) == .ampersand_equal or p.peekTag(1) == .pipe_equal or p.peekTag(1) == .pipe_pipe_equal or p.peekTag(1) == .caret_equal) return p.parseAssignStmt();
        }
        if (p.check(.identifier) or p.check(.keyword_it) or p.check(.keyword_it_index)) return p.parseExprOrAssignStmt();
        if (p.check(.shift_left)) return p.parseDerefAssignOrExprStmt();
        return p.parseExprOrAssignStmt();
    }

    fn parseDirectiveIf(p: *Parser, tok: Token.Index, comptime top_level: bool) anyerror!NodeIndex {
        const selected = try p.parseDirectiveIfCondition();
        const has_block = p.check(.l_brace);
        if (selected) {
            const chosen = if (has_block)
                (if (top_level) try p.parseDirectiveIfBlock(tok, true) else try p.parseDirectiveIfBlock(tok, false))
            else
                (if (top_level) try p.parseDirectiveIfInlineBranch(tok, true) else try p.parseDirectiveIfInlineBranch(tok, false));
            try p.skipElseChainFlexible(top_level);
            return chosen;
        }
        if (has_block) {
            _ = try p.expect(.l_brace, "expected '{{' after #if condition", .{});
            try p.skipBraceBlock();
        } else {
            try p.skipInlineDirectiveBranch(top_level);
        }
        if (p.matchDiscard(.keyword_else) or p.matchDiscard(.directive_else)) {
            if (p.match(.directive_if)) |else_if_tok| return p.parseDirectiveIf(else_if_tok, top_level);
            if (p.check(.l_brace)) {
                return if (top_level) try p.parseDirectiveIfBlock(tok, true) else try p.parseDirectiveIfBlock(tok, false);
            }
            return if (top_level) try p.parseDirectiveIfInlineBranch(tok, true) else try p.parseDirectiveIfInlineBranch(tok, false);
        }
        return if (top_level) try p.emptyStmtList(tok) else try p.emptyStmtList(tok);
    }

    fn parseDirectiveIfCondition(p: *Parser) anyerror!bool {
        return try p.parseDirectiveIfOr();
    }

    fn parseDirectiveIfOr(p: *Parser) anyerror!bool {
        var value = try p.parseDirectiveIfPrimary();
        while (p.matchDiscard(.pipe_pipe)) {
            const rhs = try p.parseDirectiveIfPrimary();
            value = value or rhs;
        }
        return value;
    }

    fn parseDirectiveIfPrimary(p: *Parser) anyerror!bool {
        if (p.matchDiscard(.l_paren)) {
            const value = try p.parseDirectiveIfOr();
            _ = try p.expect(.r_paren, "expected ')' after #if condition", .{});
            return value;
        }
        if (p.match(.bang)) |_| return !(try p.parseDirectiveIfPrimary());
        if (p.match(.keyword_is_constant)) |_| {
            _ = try p.expect(.l_paren, "expected '(' after is_constant in #if condition", .{});
            _ = try p.parseExpr();
            _ = try p.expect(.r_paren, "expected ')' after is_constant operand", .{});
            return false;
        }
        const name_tok = try p.expect(.identifier, "expected identifier in #if condition", .{});
        const name = p.ast.tokenSlice(name_tok);
        if (std.mem.eql(u8, name, "OS")) {
            _ = try p.expect(.equal_equal, "expected '==' after OS in #if condition", .{});
            _ = try p.expect(.dot, "expected '.' before OS enum literal in #if condition", .{});
            const os_tok = try p.expect(.identifier, "expected OS enum literal in #if condition", .{});
            return parserHostMatchesOs(p.ast.tokenSlice(os_tok));
        }
        return false;
    }

    fn parseTopLevelDeclListUntilRBrace(p: *Parser, tok: Token.Index) anyerror!NodeIndex {
        var decls = std.ArrayList(u32).empty;
        defer decls.deinit(p.allocator);
        while (!p.check(.r_brace)) {
            if (p.check(.eof)) return p.failCurrent("expected '}}' after #if block", .{});
            const decl = try p.parseTopLevelDecl();
            if (p.ast.tag(decl) == .stmt_list) {
                try decls.appendSlice(p.allocator, p.ast.extraSlice(p.ast.data(decl).lhs));
            } else {
                try decls.append(p.allocator, decl);
            }
            _ = p.matchDiscard(.semicolon);
        }
        _ = try p.expect(.r_brace, "expected '}}' after #if block", .{});
        const extra = try p.ast.addExtraSlice(decls.items);
        return p.ast.addNode(.stmt_list, tok, .{ .lhs = extra, .rhs = @intCast(decls.items.len) });
    }

    fn parseDirectiveIfBlock(p: *Parser, tok: Token.Index, comptime top_level: bool) anyerror!NodeIndex {
        _ = try p.expect(.l_brace, "expected '{{' after #if condition", .{});
        return if (top_level) try p.parseTopLevelDeclListUntilRBrace(tok) else try p.parseStmtListUntilRBrace(tok);
    }

    fn parseDirectiveIfInlineBranch(p: *Parser, tok: Token.Index, comptime top_level: bool) anyerror!NodeIndex {
        if (top_level) {
            const decl = try p.parseTopLevelDecl();
            const values = [_]u32{decl};
            const extra = try p.ast.addExtraSlice(&values);
            return p.ast.addNode(.stmt_list, tok, .{ .lhs = extra, .rhs = 1 });
        }
        const stmt = try p.parseStmt();
        const values = [_]u32{stmt};
        const extra = try p.ast.addExtraSlice(&values);
        return p.ast.addNode(.stmt_list, tok, .{ .lhs = extra, .rhs = 1 });
    }

    fn parseStmtListUntilRBrace(p: *Parser, tok: Token.Index) anyerror!NodeIndex {
        var stmts = std.ArrayList(u32).empty;
        defer stmts.deinit(p.allocator);
        while (!p.check(.r_brace)) {
            if (p.check(.eof)) return p.failCurrent("expected '}}' after #if block", .{});
            try stmts.append(p.allocator, try p.parseStmt());
        }
        _ = try p.expect(.r_brace, "expected '}}' after #if block", .{});
        const extra = try p.ast.addExtraSlice(stmts.items);
        return p.ast.addNode(.stmt_list, tok, .{ .lhs = extra, .rhs = @intCast(stmts.items.len) });
    }

    fn emptyStmtList(p: *Parser, tok: Token.Index) !NodeIndex {
        const extra = try p.ast.addExtraSlice(&[_]u32{});
        return p.ast.addNode(.stmt_list, tok, .{ .lhs = extra, .rhs = 0 });
    }

    fn skipBraceBlock(p: *Parser) !void {
        var depth: usize = 1;
        while (depth > 0) {
            if (p.check(.eof)) return p.failCurrent("expected '}}' after #if block", .{});
            if (p.matchDiscard(.l_brace)) {
                depth += 1;
            } else if (p.matchDiscard(.r_brace)) {
                depth -= 1;
            } else {
                p.index += 1;
            }
        }
    }

    fn skipElseChainFlexible(p: *Parser, comptime top_level: bool) !void {
        if (!(p.matchDiscard(.keyword_else) or p.matchDiscard(.directive_else))) return;
        if (p.matchDiscard(.directive_if)) {
            _ = try p.parseDirectiveIfCondition();
            if (p.check(.l_brace)) {
                _ = try p.expect(.l_brace, "expected '{{' after #if condition", .{});
                try p.skipBraceBlock();
            } else {
                try p.skipInlineDirectiveBranch(top_level);
            }
            try p.skipElseChainFlexible(top_level);
            return;
        }
        if (p.check(.l_brace)) {
            _ = try p.expect(.l_brace, "expected '{{' after else", .{});
            try p.skipBraceBlock();
        } else {
            try p.skipInlineDirectiveBranch(top_level);
        }
    }

    fn skipInlineDirectiveBranch(p: *Parser, comptime top_level: bool) !void {
        _ = top_level;
        var paren_depth: usize = 0;
        while (!p.check(.eof)) {
            const tag = p.peekTag(0);
            if (paren_depth == 0 and (tag == .keyword_else or tag == .directive_else)) break;
            p.index += 1;
            switch (tag) {
                .l_paren => paren_depth += 1,
                .r_paren => {
                    if (paren_depth != 0) paren_depth -= 1;
                },
                .semicolon => if (paren_depth == 0) break,
                else => {},
            }
        }
    }

    fn parseWhileStmt(p: *Parser) !NodeIndex {
        const while_tok = try p.expect(.keyword_while, "expected while", .{});
        // Named condition: "while name := expr { }" — bind name as loop label.
        var cond_node: NodeIndex = undefined;
        if (p.check(.identifier) and p.peekTag(1) == .colon_equal) {
            const name_tok = p.index;
            p.index += 2; // consume name and :=
            const init_expr = try p.parseBinaryExpr(3);
            // Encode as var_decl so the name token is accessible.
            cond_node = try p.ast.addNode(.var_decl, name_tok, .{ .lhs = null_node, .rhs = init_expr });
        } else {
            cond_node = try p.parseBinaryExpr(3);
        }
        // Optional 'then' before single-statement body.
        _ = p.matchDiscard(.keyword_then);
        const body = try p.parseStmtAsBlock();
        return p.ast.addNode(.while_stmt, while_tok, .{ .lhs = cond_node, .rhs = body });
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
        _ = p.matchDiscard(.directive_complete);
        const cond = if (p.nextIfCaseEqualsBrace()) {
            const lhs = try p.parseBinaryExpr(6);
            _ = try p.expect(.equal_equal, "expected '==' before if-case block", .{});
            _ = try p.expect(.l_brace, "expected '{{' after if-case '=='", .{});
            return p.parseIfCaseStmt(if_tok, lhs);
        } else try p.parseExpr();
        // Optional 'then' keyword before single-statement body.
        _ = p.matchDiscard(.keyword_then);
        const then_block = try p.parseStmtAsBlock();
        const else_block = if (p.matchDiscard(.keyword_else)) try p.parseStmtAsBlock() else null_node;
        const blocks = [_]u32{ then_block, else_block };
        const blocks_extra = try p.ast.addExtraSlice(&blocks);
        return p.ast.addNode(.if_stmt, if_tok, .{ .lhs = cond, .rhs = blocks_extra });
    }

    fn nextIfCaseEqualsBrace(p: *Parser) bool {
        var i = p.index;
        var parens: i32 = 0;
        var brackets: i32 = 0;
        while (i < p.tokens.len) : (i += 1) {
            const tag = p.tokens[i].tag;
            if (parens == 0 and brackets == 0) {
                if (tag == .equal_equal and i + 1 < p.tokens.len and p.tokens[i + 1].tag == .l_brace) return true;
                if (tag == .keyword_then or tag == .l_brace or tag == .semicolon or tag == .eof) return false;
            }
            switch (tag) {
                .l_paren => parens += 1,
                .r_paren => {
                    if (parens > 0) parens -= 1;
                },
                .l_bracket => brackets += 1,
                .r_bracket => {
                    if (brackets > 0) brackets -= 1;
                },
                else => {},
            }
        }
        return false;
    }

    fn parseIfCaseStmt(p: *Parser, if_tok: Token.Index, cond: NodeIndex) !NodeIndex {
        const IfCase = struct {
            value: NodeIndex,
            block: NodeIndex,
            through: bool,
            token: Token.Index,
        };
        var cases = std.ArrayList(IfCase).empty;
        defer cases.deinit(p.allocator);
        while (!p.check(.r_brace) and !p.check(.eof)) {
            // Handle optional #complete before case
            _ = p.matchDiscard(.directive_complete);
            const case_tok = try p.expect(.keyword_case, "expected 'case' in if-case block", .{});
            // Default case: "case;" has no value
            const is_default = p.check(.semicolon);
            var case_value: NodeIndex = null_node;
            if (!is_default) {
                case_value = try p.parseExpr();
            }
            _ = try p.expect(.semicolon, "expected ';' after case value", .{});
            // Collect all statements for this case until next 'case', '}', or #through
            var case_stmts = std.ArrayList(u32).empty;
            defer case_stmts.deinit(p.allocator);
            var has_through = false;
            while (!p.check(.r_brace) and !p.check(.keyword_case) and !p.check(.eof)) {
                if (p.check(.directive_through)) {
                    p.index += 1;
                    _ = p.matchDiscard(.semicolon);
                    has_through = true;
                    break;
                }
                try case_stmts.append(p.allocator, try p.parseStmt());
            }
            const case_block_extra = try p.ast.addExtraSlice(case_stmts.items);
            const case_block = try p.ast.addNode(.block, case_tok, .{ .lhs = case_block_extra, .rhs = @intCast(case_stmts.items.len) });
            try cases.append(p.allocator, .{
                .value = if (is_default) null_node else case_value,
                .block = case_block,
                .through = has_through,
                .token = case_tok,
            });
        }
        _ = try p.expect(.r_brace, "expected '}}' after if-case block", .{});

        var next: NodeIndex = null_node;
        var i = cases.items.len;
        while (i > 0) {
            i -= 1;
            const case = cases.items[i];
            var branch_stmts = std.ArrayList(u32).empty;
            defer branch_stmts.deinit(p.allocator);
            var j = i;
            while (j < cases.items.len) : (j += 1) {
                const block_stmts = p.ast.extraSlice(p.ast.data(cases.items[j].block).lhs);
                try branch_stmts.appendSlice(p.allocator, block_stmts);
                if (!cases.items[j].through) break;
            }
            const branch_extra = try p.ast.addExtraSlice(branch_stmts.items);
            const branch_block = try p.ast.addNode(.block, case.token, .{ .lhs = branch_extra, .rhs = @intCast(branch_stmts.items.len) });
            if (case.value == null_node) {
                next = branch_block;
            } else {
                const cmp = try p.ast.addNode(.binary_expr, case.token, .{ .lhs = cond, .rhs = case.value });
                const else_block = if (next == null_node or p.ast.tag(next) == .block) next else blk: {
                    const nested = [_]u32{next};
                    const nested_extra = try p.ast.addExtraSlice(&nested);
                    break :blk try p.ast.addNode(.block, case.token, .{ .lhs = nested_extra, .rhs = 1 });
                };
                const if_blocks = [_]u32{ branch_block, else_block };
                const if_blocks_extra = try p.ast.addExtraSlice(&if_blocks);
                next = try p.ast.addNode(.if_stmt, case.token, .{ .lhs = cmp, .rhs = if_blocks_extra });
            }
        }
        if (next == null_node) {
            const empty = [_]u32{};
            const extra = try p.ast.addExtraSlice(&empty);
            next = try p.ast.addNode(.block, if_tok, .{ .lhs = extra, .rhs = 0 });
        }
        const stmts = [_]u32{next};
        const extra = try p.ast.addExtraSlice(&stmts);
        return p.ast.addNode(.stmt_list, if_tok, .{ .lhs = extra });
    }

    fn parseForStmt(p: *Parser) !NodeIndex {
        const for_tok = try p.expect(.keyword_for, "expected for", .{});
        // Reverse for: "for < i: 5..0 { }"
        const is_reverse: u32 = if (p.matchDiscard(.less_than)) 1 else 0;
        _ = p.matchDiscard(.star);
        // Named iterator: "for i: 0..5 { }" or "for number: 1..5 print(...)"
        var expansion_tok: u32 = 0;
        var iterator_tok: u32 = 0;
        var index_tok: u32 = 0;
        if (p.matchDiscard(.colon)) expansion_tok = try p.expect(.identifier, "expected for-expansion name after ':'", .{});
        if (p.checkIdentifierLike() and p.peekTag(1) == .comma and (p.peekTag(2) == .identifier or p.peekTag(2) == .keyword_it or p.peekTag(2) == .keyword_it_index) and p.peekTag(3) == .colon) {
            iterator_tok = p.index;
            index_tok = p.index + 2;
            p.index += 4;
        } else if (p.checkIdentifierLike() and p.peekTag(1) == .colon) {
            iterator_tok = p.index;
            p.index += 2; // consume name and ':'
        }
        const start_expr = try p.parseExpr();
        if (!p.matchDiscard(.dot_dot)) {
            // Iterable-form: "for collection { }"
            const iterable_extra = if (expansion_tok != 0) blk: {
                const iterable_values = [_]u32{ start_expr, expansion_tok | 0x80000000, if (iterator_tok != 0) iterator_tok | 0x80000000 else 0, index_tok };
                break :blk try p.ast.addExtraSlice(&iterable_values);
            } else if (index_tok != 0) blk: {
                const iterable_values = [_]u32{ start_expr, iterator_tok | 0x80000000, index_tok };
                break :blk try p.ast.addExtraSlice(&iterable_values);
            } else if (iterator_tok != 0) blk: {
                const iterable_values = [_]u32{ start_expr, iterator_tok | 0x80000000 };
                break :blk try p.ast.addExtraSlice(&iterable_values);
            } else blk: {
                const iterable_values = [_]u32{start_expr};
                break :blk try p.ast.addExtraSlice(&iterable_values);
            };
            const iterable_body = try p.parseStmtAsBlock();
            return p.ast.addNode(.for_stmt, for_tok, .{ .lhs = iterable_extra, .rhs = iterable_body });
        }
        const end_expr = try p.parseExpr();
        // Single-statement or block body.
        const body = try p.parseStmtAsBlock();
        // Encode: [start, end, iterator_tok, is_reverse]
        const range_values = [_]u32{ start_expr, end_expr, iterator_tok, is_reverse };
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
        if (p.peekTag(0) == .plus_equal or p.peekTag(0) == .minus_equal or p.peekTag(0) == .star_equal or p.peekTag(0) == .slash_equal or p.peekTag(0) == .ampersand_equal or p.peekTag(0) == .pipe_equal or p.peekTag(0) == .pipe_pipe_equal or p.peekTag(0) == .caret_equal) {
            const op_tok = p.index;
            p.index += 1;
            const rhs_expr = try p.parseExpr();
            const rhs = try p.ast.addNode(.binary_expr, op_tok, .{ .lhs = lhs, .rhs = rhs_expr });
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
        if (p.peekTag(0) == .colon and (p.peekTag(1) == .comma or p.peekTag(1) == .equal)) {
            _ = p.matchDiscard(.colon);
            name_modes.items[0] = .declare_typed;
        }
        while (p.matchDiscard(.comma)) {
            const name_tok = try p.expect(.identifier, "expected name after comma", .{});
            try name_toks.append(p.allocator, name_tok);
            if (p.peekTag(0) == .equal and p.peekTag(1) == .comma) {
                _ = p.matchDiscard(.equal);
                try name_modes.append(p.allocator, .assign);
            } else if (p.peekTag(0) == .colon and (p.peekTag(1) == .comma or p.peekTag(1) == .equal)) {
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
        } else if (p.peekTag(0) == .plus_equal or p.peekTag(0) == .minus_equal or p.peekTag(0) == .star_equal or p.peekTag(0) == .slash_equal or p.peekTag(0) == .ampersand_equal or p.peekTag(0) == .pipe_equal or p.peekTag(0) == .pipe_pipe_equal or p.peekTag(0) == .caret_equal) {
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
        const name_tok = try p.expectIdentifierLike("expected local variable name", .{});
        _ = try p.expect(.colon, "expected ':' in local declaration", .{});
        if (p.matchDiscard(.equal)) {
            const init = try p.parseExpr();
            _ = try p.expect(.semicolon, "expected semicolon after local declaration", .{});
            return p.ast.addNode(.var_decl, name_tok, .{ .lhs = null_node, .rhs = init });
        }
        const type_expr = try p.parseTypeExpr();
        try p.consumeDeclModifiers();
        const init = if (p.matchDiscard(.equal)) blk: {
            if (p.match(.triple_minus)) |tok| break :blk try p.ast.addNode(.undefined_literal, tok, .{});
            break :blk try p.parseExpr();
        } else null_node;
        if (init == null_node and nodeAllowsImplicitTerminator(&p.ast, type_expr)) {
            _ = p.matchDiscard(.semicolon);
        } else {
            _ = try p.expect(.semicolon, "expected semicolon after local declaration", .{});
        }
        return p.ast.addNode(.var_decl, name_tok, .{ .lhs = type_expr, .rhs = init });
    }

    fn parseLocalInferredDecl(p: *Parser) !NodeIndex {
        const name_tok = try p.expectIdentifierLike("expected local variable name", .{});
        _ = try p.expect(.colon_equal, "expected ':=' in local declaration", .{});
        const init = try p.parseExpr();
        if (nodeAllowsImplicitTerminator(&p.ast, init)) {
            _ = p.matchDiscard(.semicolon);
        } else {
            _ = try p.expect(.semicolon, "expected semicolon after local declaration", .{});
        }
        return p.ast.addNode(.var_decl, name_tok, .{ .lhs = null_node, .rhs = init });
    }

    fn parseLocalConstDecl(p: *Parser) !NodeIndex {
        const name_tok = try p.expectIdentifierLike("expected local constant name", .{});
        _ = try p.expect(.colon_colon, "expected '::' in local constant declaration", .{});
        if (p.check(.keyword_inline) or p.check(.keyword_no_inline) or p.check(.l_paren)) {
            return p.parseProcDeclAfterName(name_tok);
        }
        if (p.match(.directive_import)) |tok| {
            const value = try p.parseImportLikeDirective(tok, "expected module string after #import");
            _ = try p.expect(.semicolon, "expected semicolon after import", .{});
            return p.ast.addNode(.const_decl, name_tok, .{ .lhs = value });
        }
        if (p.match(.directive_library)) |tok| {
            const value = try p.parseImportLikeDirective(tok, "expected library string after #library");
            _ = p.matchDiscard(.semicolon);
            return p.ast.addNode(.const_decl, name_tok, .{ .lhs = value });
        }
        if (p.match(.directive_system_library)) |tok| {
            const value = try p.parseImportLikeDirective(tok, "expected library string after #system_library");
            _ = p.matchDiscard(.semicolon);
            return p.ast.addNode(.const_decl, name_tok, .{ .lhs = value });
        }
        if (p.match(.directive_foreign_library)) |tok| {
            const value = try p.parseImportLikeDirective(tok, "expected library string after #foreign_library");
            _ = p.matchDiscard(.semicolon);
            return p.ast.addNode(.const_decl, name_tok, .{ .lhs = value });
        }
        if (p.match(.directive_type) != null) {
            while (p.matchDiscard(.comma)) _ = try p.expect(.identifier, "expected #type modifier after ','", .{});
            const value = try p.parseTypeExpr();
            try p.consumeProcModifiers();
            _ = p.matchDiscard(.semicolon);
            return p.ast.addNode(.const_decl, name_tok, .{ .lhs = value });
        }
        if (p.check(.directive_code)) {
            const tok = p.index;
            p.index += 1;
            const value = try p.parseOpaqueDirectiveExpr(tok);
            _ = p.matchDiscard(.semicolon);
            return p.ast.addNode(.const_decl, name_tok, .{ .lhs = value });
        }
        const value = try p.parseTypeOrExpr();
        if (nodeAllowsImplicitTerminator(&p.ast, value)) {
            _ = p.matchDiscard(.semicolon);
        } else {
            _ = try p.expect(.semicolon, "expected semicolon after local constant declaration", .{});
        }
        return p.ast.addNode(.const_decl, name_tok, .{ .lhs = value });
    }

    fn parseExprOrAssignStmt(p: *Parser) !NodeIndex {
        const lhs = try p.parseExpr();
        if (p.matchDiscard(.comma)) {
            var lhs_nodes = std.ArrayList(NodeIndex).empty;
            var rhs_nodes = std.ArrayList(NodeIndex).empty;
            defer lhs_nodes.deinit(p.allocator);
            defer rhs_nodes.deinit(p.allocator);

            try lhs_nodes.append(p.allocator, lhs);
            try lhs_nodes.append(p.allocator, try p.parseExpr());
            while (p.matchDiscard(.comma)) try lhs_nodes.append(p.allocator, try p.parseExpr());

            _ = try p.expect(.equal, "expected '=' after multi-target assignment", .{});
            try rhs_nodes.append(p.allocator, try p.parseExpr());
            while (p.matchDiscard(.comma)) try rhs_nodes.append(p.allocator, try p.parseExpr());
            _ = try p.expect(.semicolon, "expected semicolon after assignment", .{});

            var stmts = std.ArrayList(u32).empty;
            defer stmts.deinit(p.allocator);
            for (lhs_nodes.items, 0..) |lhs_node, i| {
                const rhs_node = rhs_nodes.items[if (rhs_nodes.items.len == 1) 0 else i];
                try stmts.append(p.allocator, try p.ast.addNode(.assign_stmt, p.ast.mainToken(lhs_node), .{ .lhs = lhs_node, .rhs = rhs_node }));
            }
            const extra = try p.ast.addExtraSlice(stmts.items);
            return p.ast.addNode(.stmt_list, p.ast.mainToken(lhs), .{ .lhs = extra, .rhs = @intCast(stmts.items.len) });
        }
        const op = p.peekTag(0);
        if (op == .equal or op == .plus_equal or op == .minus_equal or op == .star_equal or op == .slash_equal or op == .ampersand_equal or op == .pipe_equal or op == .caret_equal) {
            const op_tok = p.index;
            p.index += 1;
            const rhs_expr = try p.parseExpr();
            const rhs = if (op == .equal) rhs_expr else try p.ast.addNode(.binary_expr, op_tok, .{ .lhs = lhs, .rhs = rhs_expr });
            if (nodeAllowsImplicitTerminator(&p.ast, rhs)) {
                _ = p.matchDiscard(.semicolon);
            } else {
                _ = try p.expect(.semicolon, "expected semicolon after assignment", .{});
            }
            return p.ast.addNode(.assign_stmt, p.ast.mainToken(lhs), .{ .lhs = lhs, .rhs = rhs });
        }
        _ = try p.expect(.semicolon, "expected semicolon after expression statement", .{});
        return p.ast.addNode(.expr_stmt, p.ast.mainToken(lhs), .{ .lhs = lhs });
    }

    fn looksLikeAnonymousProc(p: *Parser) bool {
        if (!p.check(.l_paren)) return false;
        switch (p.peekTag(1)) {
            .r_paren, .identifier, .keyword_using, .dollar, .dollar_dollar => {},
            else => return false,
        }
        var idx = p.index + 1;
        var depth: usize = 1;
        while (idx < p.tokens.len) : (idx += 1) {
            switch (p.tokens[idx].tag) {
                .l_paren => depth += 1,
                .r_paren => {
                    depth -= 1;
                    if (depth == 0) {
                        const next = if (idx + 1 < p.tokens.len) p.tokens[idx + 1].tag else .eof;
                        return next == .l_brace or next == .arrow or next == .fat_arrow;
                    }
                },
                .dot, .l_bracket, .equal_equal, .bang_equal, .less_than, .less_equal, .greater_than, .greater_equal, .ampersand_ampersand, .pipe_pipe, .plus, .minus, .star, .slash, .percent => if (depth == 1) return false,
                else => {},
            }
        }
        return false;
    }

    fn parseAnonymousProcExpr(p: *Parser) anyerror!NodeIndex {
        const name_tok: Token.Index = 0;
        _ = try p.expect(.l_paren, "expected opening paren in anonymous procedure", .{});
        var params = std.ArrayList(u32).empty;
        defer params.deinit(p.allocator);
        if (!p.check(.r_paren)) {
            while (true) {
                const is_using_param = p.matchDiscard(.keyword_using);
                _ = p.matchDiscard(.dollar) or p.matchDiscard(.dollar_dollar);
                const param_name = if (p.check(.identifier)) blk: {
                    const tok = p.index;
                    p.index += 1;
                    break :blk tok;
                } else 0;
                var is_variadic_param = false;
                var param_type: NodeIndex = null_node;
                var param_init: NodeIndex = null_node;
                if (p.matchDiscard(.colon)) {
                    is_variadic_param = p.matchDiscard(.dot_dot);
                    param_type = try p.parseTypeExpr();
                    if (p.matchDiscard(.equal)) param_init = try p.parseExpr();
                } else if (p.matchDiscard(.colon_equal)) {
                    param_init = try p.parseExpr();
                } else if (param_name != 0) {
                    p.index -= 1;
                    const synth = p.index;
                    p.index += 1;
                    const param = try p.ast.addNode(.var_decl, synth, .{ .lhs = try p.ast.addNode(.type_expr, synth, .{}), .rhs = null_node });
                    try params.append(p.allocator, param);
                    if (!p.matchDiscard(.comma)) break;
                    continue;
                } else return p.failCurrent("expected parameter name", .{});
                const rhs: u32 = if (is_variadic_param) 1 else if (is_using_param and param_init == null_node) using_param_sentinel else param_init;
                const param = try p.ast.addNode(.var_decl, param_name, .{ .lhs = param_type, .rhs = rhs });
                try params.append(p.allocator, param);
                if (!p.matchDiscard(.comma)) break;
            }
        }
        _ = try p.expect(.r_paren, "expected ')' after parameter list", .{});
        if (p.matchDiscard(.fat_arrow)) {
            const expr = try p.parseExpr();
            const ret = try p.ast.addNode(.return_stmt, p.ast.mainToken(expr), .{ .lhs = expr });
            const stmts = [_]u32{ret};
            const stmts_extra = try p.ast.addExtraSlice(&stmts);
            const body = try p.ast.addNode(.block, name_tok, .{ .lhs = stmts_extra, .rhs = 1 });
            const params_extra = try p.ast.addExtraSlice(params.items);
            const sig_values = [_]u32{ params_extra, null_node };
            const sig_extra = try p.ast.addExtraSlice(&sig_values);
            return p.ast.addNode(.proc_decl, name_tok, .{ .lhs = body, .rhs = sig_extra });
        }
        var named_returns = std.ArrayList(u32).empty;
        defer named_returns.deinit(p.allocator);
        const return_type = if (p.matchDiscard(.arrow)) try p.parseProcReturnSpec(&named_returns) else null_node;
        var body = try p.parseBlock();
        if (named_returns.items.len != 0) body = try p.prependBlockDecls(body, named_returns.items);
        const params_extra = try p.ast.addExtraSlice(params.items);
        const sig_values = [_]u32{ params_extra, return_type };
        const sig_extra = try p.ast.addExtraSlice(&sig_values);
        return p.ast.addNode(.proc_decl, name_tok, .{ .lhs = body, .rhs = sig_extra });
    }

    fn parseAssignStmt(p: *Parser) !NodeIndex {
        const name_tok = try p.expectIdentifierLike("expected assignment target", .{});
        const lhs = try p.ast.addNode(.identifier, name_tok, .{});
        const op = p.peekTag(0);
        if (!(op == .equal or op == .plus_equal or op == .minus_equal or op == .star_equal or op == .slash_equal or op == .ampersand_equal or op == .pipe_equal or op == .pipe_pipe_equal or op == .caret_equal)) return p.failCurrent("expected assignment operator", .{});
        p.index += 1;
        const op_tok = p.index - 1;
        const rhs_expr = try p.parseExpr();
        const rhs = if (op == .equal) rhs_expr else blk: {
            const lhs_copy = try p.ast.addNode(.identifier, name_tok, .{});
            break :blk try p.ast.addNode(.binary_expr, op_tok, .{ .lhs = lhs_copy, .rhs = rhs_expr });
        };
        if (nodeAllowsImplicitTerminator(&p.ast, rhs)) {
            _ = p.matchDiscard(.semicolon);
        } else {
            _ = try p.expect(.semicolon, "expected semicolon after assignment", .{});
        }
        return p.ast.addNode(.assign_stmt, name_tok, .{ .lhs = lhs, .rhs = rhs });
    }

    fn parseTypeExpr(p: *Parser) !NodeIndex {
        if (p.match(.l_bracket)) |tok| {
            const len_expr = if (p.check(.r_bracket) or p.check(.dot_dot)) blk: {
                _ = p.matchDiscard(.dot_dot);
                break :blk null_node;
            } else try p.parseExpr();
            _ = try p.expect(.r_bracket, "expected ']' after array type length", .{});
            const child = try p.parseTypeExpr();
            return p.ast.addNode(.array_type, tok, .{ .lhs = len_expr, .rhs = child });
        }
        if (p.match(.star)) |tok| {
            const child = try p.parseTypeExpr();
            return p.ast.addNode(.pointer_type, tok, .{ .lhs = child });
        }
        if (p.match(.keyword_struct)) |tok| return p.parseContainerType(.struct_type, tok);
        if (p.match(.keyword_union)) |tok| return p.parseContainerType(.union_type, tok);
        if (p.match(.keyword_enum) != null) {
            const tok = p.index - 1;
            return p.parseContainerType(.enum_type, tok);
        }
        if (p.match(.keyword_enum_flags) != null) {
            const tok = p.index - 1;
            return p.parseContainerType(.enum_type, tok);
        }
        if (p.match(.l_paren)) |tok| {
            var params = std.ArrayList(u32).empty;
            defer params.deinit(p.allocator);
            if (!p.check(.r_paren)) {
                while (true) {
                    _ = p.matchDiscard(.keyword_using);
                    _ = p.matchDiscard(.dollar) or p.matchDiscard(.dollar_dollar);
                    _ = p.matchDiscard(.dot_dot);
                    if (p.check(.identifier) and p.peekTag(1) == .colon) {
                        p.index += 2;
                        _ = p.matchDiscard(.dot_dot);
                    }
                    try params.append(p.allocator, try p.parseTypeExpr());
                    if (!p.matchDiscard(.comma)) break;
                }
            }
            _ = try p.expect(.r_paren, "expected ')' after procedure type parameters", .{});
            const ret = if (p.matchDiscard(.arrow)) try p.parseTypeExpr() else try p.ast.addNode(.type_expr, tok, .{});
            try p.consumeProcModifiers();
            const extra = try p.ast.addExtraSlice(params.items);
            return p.ast.addNode(.proc_type, tok, .{ .lhs = extra, .rhs = ret });
        }
        if (p.match(.keyword_type_of)) |tok| {
            _ = try p.expect(.l_paren, "expected '(' after type_of", .{});
            const operand = try p.parseExpr();
            _ = try p.expect(.r_paren, "expected ')' after type_of operand", .{});
            return p.ast.addNode(.type_of_expr, tok, .{ .lhs = operand });
        }
        if (p.match(.keyword_type_info)) |tok| {
            _ = try p.expect(.l_paren, "expected '(' after type_info", .{});
            const operand = try p.parseTypeOrExpr();
            _ = try p.expect(.r_paren, "expected ')' after type_info operand", .{});
            return p.ast.addNode(.type_of_expr, tok, .{ .lhs = operand });
        }
        const has_dollar = p.matchDiscard(.dollar) or p.matchDiscard(.dollar_dollar);
        const tok = p.index;
        if ((has_dollar and p.match(.identifier) != null) or p.match(.identifier) != null or p.match(.keyword_void) != null) {
            while (true) {
                if (p.matchDiscard(.dot)) {
                    if (p.matchDiscard(.l_bracket)) {
                        var depth: usize = 1;
                        while (depth > 0) {
                            if (p.check(.eof)) return p.failCurrent("expected ']' after type-index expression", .{});
                            const tag = p.peekTag(0);
                            p.index += 1;
                            switch (tag) {
                                .l_bracket => depth += 1,
                                .r_bracket => depth -= 1,
                                else => {},
                            }
                        }
                        continue;
                    }
                    _ = try p.expect(.identifier, "expected identifier after '.' in type expression", .{});
                    continue;
                }
                if (p.matchDiscard(.slash)) {
                    if (p.matchDiscard(.keyword_interface)) _ = try p.expect(.identifier, "expected interface name after /interface", .{}) else _ = try p.expect(.identifier, "expected identifier after '/' in type expression", .{});
                    continue;
                }
                if (p.matchDiscard(.l_paren)) {
                    var depth: usize = 1;
                    while (depth > 0) {
                        if (p.check(.eof)) return p.failCurrent("expected ')' after type parameters", .{});
                        const tag = p.peekTag(0);
                        p.index += 1;
                        switch (tag) {
                            .l_paren => depth += 1,
                            .r_paren => depth -= 1,
                            else => {},
                        }
                    }
                    continue;
                }
                break;
            }
            return p.ast.addNode(.type_expr, tok, .{});
        }
        return p.failCurrent("expected type expression", .{});
    }

    fn parseTypeOrExpr(p: *Parser) !NodeIndex {
        if (p.check(.keyword_struct) or p.check(.keyword_union) or p.check(.keyword_enum) or p.check(.keyword_enum_flags)) return p.parseTypeExpr();
        if ((p.check(.identifier) or p.check(.keyword_void)) and p.peekTag(1) == .semicolon) return p.parseTypeExpr();
        return p.parseExpr();
    }

    fn lparenTypeIsFollowedByArrow(p: *const Parser) bool {
        if (!p.check(.l_paren)) return false;
        var idx = p.index;
        var depth: usize = 0;
        while (idx < p.tokens.len) : (idx += 1) {
            switch (p.tokens[idx].tag) {
                .l_paren => depth += 1,
                .r_paren => {
                    depth -= 1;
                    if (depth == 0) return idx + 1 < p.tokens.len and p.tokens[idx + 1].tag == .arrow;
                },
                else => {},
            }
        }
        return false;
    }

    fn parseOpaqueProcTypeExpr(p: *Parser) !NodeIndex {
        const tok = try p.expect(.l_paren, "expected '(' in procedure type", .{});
        try p.skipBalancedParensAfterOpen();
        if (p.matchDiscard(.arrow)) {
            if (p.matchDiscard(.l_paren)) {
                try p.skipBalancedParensAfterOpen();
            } else {
                _ = try p.parseTypeExpr();
            }
        }
        try p.consumeProcModifiers();
        const empty = try p.ast.addExtraSlice(&[_]u32{});
        const ret = try p.ast.addNode(.type_expr, tok, .{});
        return p.ast.addNode(.proc_type, tok, .{ .lhs = empty, .rhs = ret });
    }

    fn skipBalancedParensAfterOpen(p: *Parser) !void {
        var depth: usize = 1;
        while (depth > 0) {
            if (p.check(.eof)) return p.failCurrent("expected ')' in procedure type", .{});
            const tag = p.peekTag(0);
            p.index += 1;
            switch (tag) {
                .l_paren => depth += 1,
                .r_paren => depth -= 1,
                else => {},
            }
        }
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

    fn parseExpr(p: *Parser) anyerror!NodeIndex {
        return p.parseBinaryExpr(0);
    }

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
            .minus, .bang, .star, .dot_dot, .tilde => {
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
                if (p.check(.l_bracket)) {
                    expr = try p.parseTypedArrayLiteral(expr, dot_tok);
                    continue;
                }
                if (p.check(.l_brace)) {
                    expr = try p.parseTypedAggregateLiteral(expr, dot_tok);
                    continue;
                }
                const field_tok = try p.expect(.identifier, "expected field name after '.'", .{});
                expr = try p.ast.addNode(.field_access, dot_tok, .{ .lhs = expr, .rhs = field_tok });
                continue;
            }
            if (p.match(.dot_star)) |dot_tok| {
                expr = try p.ast.addNode(.unary_expr, dot_tok, .{ .lhs = expr });
                continue;
            }
            if (p.match(.l_bracket)) |tok| {
                const index_expr = try p.parseExpr();
                _ = try p.expect(.r_bracket, "expected ']' after subscript expression", .{});
                expr = try p.ast.addNode(.index_expr, tok, .{ .lhs = expr, .rhs = index_expr });
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
                        } else if (p.match(.dot_dot)) |spread_tok| {
                            const operand = try p.parseExpr();
                            try args.append(p.allocator, try p.ast.addNode(.unary_expr, spread_tok, .{ .lhs = operand }));
                        } else if (astNodeIsIdentifierName(&p.ast, expr, "New")) try args.append(p.allocator, try p.parseTypeExpr()) else try args.append(p.allocator, try p.parseExpr());
                        if (!p.matchDiscard(.comma)) break;
                        if (p.check(.r_paren)) break;
                    }
                }
                _ = try p.expect(.r_paren, "expected closing paren after call arguments", .{});
                const extra = try p.ast.addExtraSlice(args.items);
                expr = try p.ast.addNode(.call_expr, lparen, .{ .lhs = expr, .rhs = extra });
                continue;
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
            const is_named = p.check(.identifier) and p.peekTag(1) == .equal;
            while (true) {
                if (is_named) {
                    const field_tok = try p.expect(.identifier, "expected field name in typed aggregate literal", .{});
                    _ = try p.expect(.equal, "expected '=' after typed aggregate field name", .{});
                    const value = try p.parseExpr();
                    const lhs = try p.ast.addNode(.identifier, field_tok, .{});
                    try fields.append(p.allocator, try p.ast.addNode(.assign_stmt, field_tok, .{ .lhs = lhs, .rhs = value }));
                } else {
                    try fields.append(p.allocator, try p.parseExpr());
                }
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

    fn parseTypedArrayLiteral(p: *Parser, type_node: NodeIndex, dot_tok: Token.Index) !NodeIndex {
        _ = try p.expect(.l_bracket, "expected '[' after typed array literal '.'", .{});
        var values = std.ArrayList(u32).empty;
        defer values.deinit(p.allocator);
        if (!p.check(.r_bracket)) {
            try values.append(p.allocator, try p.parseExpr());
            while (p.matchDiscard(.comma)) {
                if (p.check(.r_bracket)) break;
                try values.append(p.allocator, try p.parseExpr());
            }
        }
        _ = try p.expect(.r_bracket, "expected ']' after typed array literal", .{});
        const extra = try p.ast.addExtraSlice(values.items);
        const payload = [_]u32{ type_node, extra, @intCast(values.items.len) };
        const payload_extra = try p.ast.addExtraSlice(&payload);
        return p.ast.addNode(.typed_array_literal, dot_tok, .{ .lhs = payload_extra, .rhs = 3 });
    }

    fn parseContainerType(p: *Parser, node_tag: Node.Tag, tok: Token.Index) !NodeIndex {
        while (!p.check(.l_brace) and !p.check(.eof)) {
            if (p.matchDiscard(.directive_modify)) {
                if (p.check(.l_brace)) {
                    try p.skipBalancedBraces();
                } else {
                    while (!p.check(.l_brace) and !p.check(.eof)) p.index += 1;
                }
                continue;
            }
            p.index += 1;
        }
        _ = try p.expect(.l_brace, "expected '{{' after container type", .{});
        var depth: usize = 1;
        while (depth > 0) {
            if (p.check(.eof)) return p.failCurrent("expected closing brace before end of file", .{});
            const tag = p.peekTag(0);
            p.index += 1;
            switch (tag) {
                .l_brace => depth += 1,
                .r_brace => depth -= 1,
                else => {},
            }
        }
        while (isContainerPostfixDirective(p.peekTag(0))) p.index += 1;
        return p.ast.addNode(node_tag, tok, .{});
    }

    fn parsePrimary(p: *Parser) !NodeIndex {
        if (p.check(.l_paren) and p.looksLikeAnonymousProc()) {
            return p.parseAnonymousProcExpr();
        }
        if (p.check(.identifier) and p.peekTag(1) == .fat_arrow) {
            const param_name = try p.expect(.identifier, "expected lambda parameter name", .{});
            _ = try p.expect(.fat_arrow, "expected '=>' after lambda parameter", .{});
            const param = try p.ast.addNode(.var_decl, param_name, .{ .lhs = null_node, .rhs = null_node });
            const body = if (p.check(.l_brace)) try p.parseBlock() else blk: {
                const expr = try p.parseExpr();
                const ret = try p.ast.addNode(.return_stmt, p.ast.mainToken(expr), .{ .lhs = expr });
                const stmts = [_]u32{ret};
                const stmts_extra = try p.ast.addExtraSlice(&stmts);
                break :blk try p.ast.addNode(.block, param_name, .{ .lhs = stmts_extra, .rhs = 1 });
            };
            const params_extra = try p.ast.addExtraSlice(&[_]u32{param});
            const sig_values = [_]u32{ params_extra, null_node };
            const sig_extra = try p.ast.addExtraSlice(&sig_values);
            return p.ast.addNode(.proc_decl, param_name, .{ .lhs = body, .rhs = sig_extra });
        }
        if (p.check(.l_bracket)) return p.parseTypeExpr();
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
        if (p.match(.directive_procedure_name)) |tok| {
            if (p.matchDiscard(.l_paren)) _ = try p.expect(.r_paren, "expected ')' after #procedure_name", .{});
            return p.ast.addNode(.string_literal, tok, .{ .lhs = tok });
        }
        if (p.match(.directive_file)) |tok| return p.ast.addNode(.string_literal, tok, .{ .lhs = tok });
        if (p.match(.directive_filepath)) |tok| return p.ast.addNode(.string_literal, tok, .{ .lhs = tok });
        if (p.match(.directive_line)) |tok| return p.ast.addNode(.integer_literal, tok, .{ .lhs = tok });
        if (p.match(.directive_caller_code)) |tok| return try p.parseOpaqueDirectiveExpr(tok);
        if (p.match(.directive_caller_location)) |tok| return try p.parseOpaqueDirectiveExpr(tok);
        if (p.match(.directive_location)) |tok| return try p.parseOpaqueDirectiveExpr(tok);
        if (p.match(.directive_type) != null) return p.parseTypeExpr();
        if (p.match(.directive_code)) |tok| return try p.parseOpaqueDirectiveExpr(tok);
        if (p.match(.directive_insert)) |tok| return try p.parseOpaqueDirectiveExpr(tok);
        if (p.match(.directive_this)) |tok| {
            if (p.matchDiscard(.l_paren)) {
                const operand = try p.parseExpr();
                _ = try p.expect(.r_paren, "expected ')' after #this", .{});
                return operand;
            }
            return try p.ast.addNode(.identifier, tok, .{});
        }
        if (p.match(.directive_procedure_of_call)) |_| {
            const operand = try p.parseExpr();
            if (p.ast.tag(operand) == .call_expr) return p.ast.data(operand).lhs;
            return operand;
        }
        if (p.match(.directive_compile_time)) |tok| {
            return p.ast.addNode(.bool_literal, tok, .{ .lhs = 2 });
        }
        if (p.match(.keyword_operator)) |_| {
            const tok = p.index;
            if (!p.check(.eof)) p.index += 1;
            return p.ast.addNode(.identifier, tok, .{});
        }
        if (p.match(.directive_char)) |tok| {
            const str_tok = try p.expect(.string_literal, "expected string literal after #char", .{});
            return p.ast.addNode(.char_literal, tok, .{ .lhs = str_tok });
        }
        if (p.match(.keyword_xx)) |tok| {
            const operand = try p.parseUnary();
            return p.ast.addNode(.unary_expr, tok, .{ .lhs = operand });
        }
        if (p.match(.keyword_ifx) orelse p.match(.directive_ifx)) |tok| {
            const cond = try p.parseExpr();
            var then_expr = cond;
            var else_expr: NodeIndex = null_node;
            if (p.matchDiscard(.keyword_then)) {
                then_expr = try p.parseExpr();
                _ = p.matchDiscard(.semicolon);
                _ = try p.expect(.keyword_else, "expected 'else' in ifx expression", .{});
                else_expr = try p.parseExpr();
            } else if (p.matchDiscard(.keyword_else)) {
                else_expr = try p.parseExpr();
            } else if (!p.check(.semicolon) and !p.check(.comma) and !p.check(.r_paren) and !p.check(.r_brace)) {
                then_expr = try p.parseExpr();
                _ = try p.expect(.keyword_else, "expected 'else' in ifx expression", .{});
                else_expr = try p.parseExpr();
            }
            if (else_expr == null_node) {
                else_expr = try p.ast.addNode(.bool_literal, tok, .{ .lhs = 0 });
            }
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
            const target_ty = if (p.check(.l_paren))
                try p.parseOpaqueProcTypeExpr()
            else
                try p.parseTypeExpr();
            if (p.matchDiscard(.dot)) _ = try p.expect(.identifier, "expected cast mode after '.'", .{});
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
        if (p.match(.keyword_type_info)) |tok| {
            _ = try p.expect(.l_paren, "expected '(' after type_info", .{});
            const operand = try p.parseTypeOrExpr();
            _ = try p.expect(.r_paren, "expected ')' after type_info operand", .{});
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
            if (p.check(.identifier)) {
                const name_tok = p.index;
                p.index += 1;
                return p.ast.addNode(.field_access, tok, .{ .lhs = null_node, .rhs = name_tok });
            }
            if (p.matchDiscard(.l_bracket)) {
                var values = std.ArrayList(u32).empty;
                defer values.deinit(p.allocator);
                if (!p.check(.r_bracket)) {
                    try values.append(p.allocator, try p.parseExpr());
                    while (p.matchDiscard(.comma)) {
                        if (p.check(.r_bracket)) break;
                        try values.append(p.allocator, try p.parseExpr());
                    }
                }
                _ = try p.expect(.r_bracket, "expected ']' after aggregate literal", .{});
                const extra = try p.ast.addExtraSlice(values.items);
                return p.ast.addNode(.aggregate_literal, tok, .{ .lhs = extra, .rhs = @intCast(values.items.len) });
            }
            _ = try p.expect(.l_brace, "expected '{{' after '.' aggregate literal", .{});
            var values = std.ArrayList(u32).empty;
            defer values.deinit(p.allocator);
            if (!p.check(.r_brace)) {
                const is_named = p.check(.identifier) and p.peekTag(1) == .equal;
                if (is_named) {
                    while (true) {
                        const field_tok = try p.expect(.identifier, "expected field name in aggregate literal", .{});
                        _ = try p.expect(.equal, "expected '=' after aggregate field name", .{});
                        const value = try p.parseExpr();
                        const lhs = try p.ast.addNode(.identifier, field_tok, .{});
                        try values.append(p.allocator, try p.ast.addNode(.assign_stmt, field_tok, .{ .lhs = lhs, .rhs = value }));
                        if (!p.matchDiscard(.comma) or p.check(.r_brace)) break;
                    }
                } else {
                    try values.append(p.allocator, try p.parseExpr());
                    while (p.matchDiscard(.comma)) {
                        if (p.check(.r_brace)) break;
                        try values.append(p.allocator, try p.parseExpr());
                    }
                }
            }
            _ = try p.expect(.r_brace, "expected '}}' after aggregate literal", .{});
            const extra = try p.ast.addExtraSlice(values.items);
            return p.ast.addNode(.aggregate_literal, tok, .{ .lhs = extra, .rhs = @intCast(values.items.len) });
        }
        if (p.match(.keyword_struct)) |tok| return p.parseContainerType(.struct_type, tok);
        if (p.match(.keyword_union)) |tok| return p.parseContainerType(.union_type, tok);
        if (p.match(.keyword_enum) != null) {
            const tok = p.index - 1;
            return p.parseContainerType(.enum_type, tok);
        }
        if (p.match(.keyword_enum_flags) != null) {
            const tok = p.index - 1;
            return p.parseContainerType(.enum_type, tok);
        }
        if (p.match(.l_paren)) |_| {
            const expr = try p.parseExpr();
            _ = try p.expect(.r_paren, "expected ')' after parenthesized expression", .{});
            return expr;
        }
        if (p.matchDiscard(.dollar) or p.matchDiscard(.dollar_dollar)) {
            const ident = try p.expect(.identifier, "expected identifier after '$'", .{});
            return p.ast.addNode(.identifier, ident, .{});
        }
        if (p.match(.identifier)) |tok| return p.ast.addNode(.identifier, tok, .{});
        if (p.match(.keyword_it)) |tok| return p.ast.addNode(.identifier, tok, .{});
        if (p.match(.keyword_it_index)) |tok| return p.ast.addNode(.identifier, tok, .{});
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

    fn parseAsmStmt(p: *Parser, tok: Token.Index) !NodeIndex {
        while (p.matchDiscard(.comma)) _ = try p.expect(.identifier, "expected #asm modifier after ','", .{});
        while (p.check(.identifier)) {
            p.index += 1;
            _ = p.matchDiscard(.comma);
        }
        try p.skipBalancedBraces();
        const block = try p.emptyBlock(tok);
        return p.ast.addNode(.meta_stmt, tok, .{ .lhs = block, .rhs = null_node });
    }

    fn parseOpaqueDirectiveExpr(p: *Parser, tok: Token.Index) !NodeIndex {
        while (p.matchDiscard(.comma)) {
            const modifier_tok = try p.expect(.identifier, "expected directive modifier after ','", .{});
            if (std.mem.eql(u8, p.ast.tokenSlice(modifier_tok), "scope") and p.matchDiscard(.l_paren)) {
                _ = try p.expect(.r_paren, "expected ')' after scope modifier", .{});
            }
        }
        if (p.matchDiscard(.arrow)) {
            const return_type = try p.parseTypeExpr();
            const block = try p.parseBlock();
            return p.ast.addNode(.meta_expr, tok, .{ .lhs = block, .rhs = return_type });
        }
        if (p.matchDiscard(.l_paren)) {
            const operand = if (p.check(.r_paren)) null_node else try p.parseExpr();
            _ = try p.expect(.r_paren, "expected ')' after directive expression", .{});
            return p.ast.addNode(.meta_expr, tok, .{ .lhs = operand, .rhs = null_node });
        }
        if (p.check(.l_brace)) {
            const block = try p.parseBlock();
            return p.ast.addNode(.meta_expr, tok, .{ .lhs = block, .rhs = null_node });
        }
        if (p.tokens[tok].tag == .directive_code) {
            while (!p.check(.semicolon) and !p.check(.eof)) p.index += 1;
            return p.ast.addNode(.meta_expr, tok, .{ .lhs = null_node, .rhs = null_node });
        }
        if (p.check(.semicolon) or p.check(.comma) or p.check(.r_paren) or p.check(.r_brace)) {
            return p.ast.addNode(.meta_expr, tok, .{ .lhs = null_node, .rhs = null_node });
        }
        const operand = try p.parseExpr();
        return p.ast.addNode(.meta_expr, tok, .{ .lhs = operand, .rhs = null_node });
    }

    fn expect(p: *Parser, tag: Tag, comptime fmt: []const u8, args: anytype) !Token.Index {
        if (p.match(tag)) |tok| return tok;
        return p.failCurrent(fmt, args);
    }

    fn expectIdentifierLike(p: *Parser, comptime fmt: []const u8, args: anytype) !Token.Index {
        if (p.match(.identifier) orelse p.match(.keyword_it) orelse p.match(.keyword_it_index)) |tok| return tok;
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

    fn matchDiscard(p: *Parser, tag: Tag) bool {
        return p.match(tag) != null;
    }
    fn check(p: *const Parser, tag: Tag) bool {
        return p.tokens[p.index].tag == tag;
    }
    fn checkIdentifierLike(p: *const Parser) bool {
        return p.check(.identifier) or p.check(.keyword_it) or p.check(.keyword_it_index);
    }
    fn peekTag(p: *const Parser, offset: usize) Tag {
        return p.tokens[@min(p.index + offset, p.tokens.len - 1)].tag;
    }

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

fn astValueIsMultilineDirectiveString(ast: *const Ast, node: NodeIndex) bool {
    return ast.tag(node) == .string_literal and ast.data(node).lhs != 0 and ast.tokens[ast.data(node).lhs].tag == .directive_string;
}

fn nodeAllowsImplicitTerminator(ast: *const Ast, node: NodeIndex) bool {
    if (astValueIsRunBlock(ast, node) or astValueIsMultilineDirectiveString(ast, node)) return true;
    return switch (ast.tag(node)) {
        .struct_type, .union_type, .enum_type, .proc_decl => true,
        else => false,
    };
}

fn isContainerPostfixDirective(tag: Tag) bool {
    return switch (tag) {
        .directive_no_padding, .directive_specified => true,
        else => false,
    };
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
        .less_than, .less_equal, .greater_than, .greater_equal => 6,
        .pipe => 7,
        .caret => 8,
        .ampersand => 9,
        .shift_left, .shift_right, .shift_left_rotate, .shift_right_rotate => 15,
        .star, .slash, .percent => 20,
        .plus, .minus => 10,
        else => null,
    };
}

fn parserHostMatchesOs(name: []const u8) bool {
    return switch (builtin.target.os.tag) {
        .windows => std.mem.eql(u8, name, "WINDOWS"),
        .linux => std.mem.eql(u8, name, "LINUX"),
        .macos => std.mem.eql(u8, name, "MACOS") or std.mem.eql(u8, name, "DARWIN"),
        else => false,
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

test "parser preserves procedure notes" {
    const lexer = @import("lexer.zig");
    const source = "sample :: () {} @TestProcedure @Slow\nmain :: () {}\n";
    const diag = Diagnostic.init(std.testing.allocator, "notes.jai", source);
    var tokens = try lexer.tokenize(std.testing.allocator, source, diag);
    defer tokens.deinit(std.testing.allocator);
    const slice = tokens.slice();
    var ast = try parse(std.testing.allocator, source, slice.items(.tag), slice.items(.start), slice.items(.end), diag);
    defer {
        std.testing.allocator.free(ast.tokens);
        ast.deinit();
    }
    const decls = ast.extraSlice(ast.data(ast.root).lhs);
    const proc: NodeIndex = @intCast(decls[0]);
    try std.testing.expect(ast.hasNote(proc, "TestProcedure"));
    try std.testing.expect(ast.hasNote(proc, "Slow"));
    try std.testing.expect(!ast.hasNote(proc, "Missing"));
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

test "parser accepts opaque container and array syntax" {
    const lexer = @import("lexer.zig");
    const source =
        "#import \"Basic\";\n" ++
        "Vec :: struct { values: [4]int; }\n" ++
        "main :: () {\n" ++
        " items := int.[1, 2, 3];\n" ++
        " v: Vec;\n" ++
        " _ := items[0];\n" ++
        "}\n";
    const diag = Diagnostic.init(std.testing.allocator, "opaque_aggregate.jai", source);
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
    const vec_decl: NodeIndex = @intCast(decls[1]);
    try std.testing.expectEqual(Node.Tag.const_decl, ast.tag(vec_decl));
    try std.testing.expectEqual(Node.Tag.struct_type, ast.tag(ast.data(vec_decl).lhs));
}

test "parser accepts top-level vars and consts with container syntax" {
    const lexer = @import("lexer.zig");
    const source =
        "State :: struct {\n" ++
        "  value: int;\n" ++
        "}\n" ++
        "global: struct {\n" ++
        "  a, b: int;\n" ++
        "};\n" ++
        "value := struct {\n" ++
        "  x: int;\n" ++
        "}\n" ++
        "main :: () {}\n";
    const diag = Diagnostic.init(std.testing.allocator, "top_level_containers.jai", source);
    var tokens = try lexer.tokenize(std.testing.allocator, source, diag);
    defer tokens.deinit(std.testing.allocator);
    const slice = tokens.slice();
    var ast = try parse(std.testing.allocator, source, slice.items(.tag), slice.items(.start), slice.items(.end), diag);
    defer {
        std.testing.allocator.free(ast.tokens);
        ast.deinit();
    }

    const root = ast.extraSlice(ast.data(ast.root).lhs);
    try std.testing.expectEqual(@as(usize, 4), root.len);
    try std.testing.expectEqual(Node.Tag.const_decl, ast.tag(@intCast(root[0])));
    try std.testing.expectEqual(Node.Tag.struct_type, ast.tag(ast.data(@intCast(root[0])).lhs));
    try std.testing.expectEqual(Node.Tag.var_decl, ast.tag(@intCast(root[1])));
    try std.testing.expectEqual(Node.Tag.struct_type, ast.tag(ast.data(@intCast(root[1])).lhs));
    try std.testing.expectEqual(Node.Tag.var_decl, ast.tag(@intCast(root[2])));
    try std.testing.expectEqual(Node.Tag.struct_type, ast.tag(ast.data(@intCast(root[2])).rhs));
}

test "parser accepts top-level struct-typed variable without semicolon" {
    const lexer = @import("lexer.zig");
    const source =
        "settings_info: struct {\n" ++
        "    name: string;\n" ++
        "    Version_Lookup :: struct { version: int; }\n" ++
        "}\n" ++
        "plugins: [..] *Metaprogram_Plugin;\n";
    const diag = Diagnostic.init(std.testing.allocator, "struct_typed_var.jai", source);
    var tokens = try lexer.tokenize(std.testing.allocator, source, diag);
    defer tokens.deinit(std.testing.allocator);
    const slice = tokens.slice();
    var ast = try parse(std.testing.allocator, source, slice.items(.tag), slice.items(.start), slice.items(.end), diag);
    defer {
        std.testing.allocator.free(ast.tokens);
        ast.deinit();
    }
    try std.testing.expectEqual(@as(usize, 2), ast.extraSlice(ast.data(ast.root).lhs).len);
}

test "parser accepts old style typed top-level constant" {
    const lexer = @import("lexer.zig");
    const source =
        "MASS_EARTH0 : float : 5.97219e24;\n" ++
        "main :: () {}\n";
    const diag = Diagnostic.init(std.testing.allocator, "typed_const.jai", source);
    var tokens = try lexer.tokenize(std.testing.allocator, source, diag);
    defer tokens.deinit(std.testing.allocator);
    const slice = tokens.slice();
    var ast = try parse(std.testing.allocator, source, slice.items(.tag), slice.items(.start), slice.items(.end), diag);
    defer {
        std.testing.allocator.free(ast.tokens);
        ast.deinit();
    }
    const root = ast.extraSlice(ast.data(ast.root).lhs);
    const decl: NodeIndex = @intCast(root[0]);
    try std.testing.expectEqual(Node.Tag.const_decl, ast.tag(decl));
    try std.testing.expectEqual(Node.Tag.float_literal, ast.tag(ast.data(decl).lhs));
    try std.testing.expectEqualStrings("float", ast.tokenSlice(ast.data(decl).rhs));
}

test "parser accepts default args, named returns, and using statements" {
    const lexer = @import("lexer.zig");
    const source =
        "hello :: (a := 9, b: int = 3, v: ..string) -> x: int = 1, y: int = 2 #must {\n" ++
        "  using a;\n" ++
        "  return x, y;\n" ++
        "}\n";
    const diag = Diagnostic.init(std.testing.allocator, "proc_surface.jai", source);
    var tokens = try lexer.tokenize(std.testing.allocator, source, diag);
    defer tokens.deinit(std.testing.allocator);
    const slice = tokens.slice();
    var ast = try parse(std.testing.allocator, source, slice.items(.tag), slice.items(.start), slice.items(.end), diag);
    defer {
        std.testing.allocator.free(ast.tokens);
        ast.deinit();
    }
    const root = ast.extraSlice(ast.data(ast.root).lhs);
    const proc_decl: NodeIndex = @intCast(root[0]);
    const sig = ast.extraSlice(ast.data(proc_decl).rhs);
    const params = ast.extraSlice(sig[0]);
    try std.testing.expectEqual(@as(usize, 3), params.len);
    try std.testing.expectEqual(Node.Tag.type_expr, ast.tag(sig[1]));
    const body_stmts = ast.extraSlice(ast.data(ast.data(proc_decl).lhs).lhs);
    try std.testing.expectEqual(Node.Tag.var_decl, ast.tag(@intCast(body_stmts[0])));
    try std.testing.expectEqual(Node.Tag.var_decl, ast.tag(@intCast(body_stmts[1])));
}

test "parser accepts ifx shorthand forms from examples" {
    const lexer = @import("lexer.zig");
    const source =
        "#import \"Basic\";\n" ++
        "main :: () {\n" ++
        " a := 0;\n" ++
        " b := 100;\n" ++
        " c := ifx a > b 10 else 1000;\n" ++
        " y2 := ifx a else 1;\n" ++
        " y3 := ifx a > 5 else 0;\n" ++
        " y4 := ifx a;\n" ++
        "}\n";
    const diag = Diagnostic.init(std.testing.allocator, "ifx_examples.jai", source);
    var tokens = try lexer.tokenize(std.testing.allocator, source, diag);
    defer tokens.deinit(std.testing.allocator);
    const slice = tokens.slice();
    var ast = try parse(std.testing.allocator, source, slice.items(.tag), slice.items(.start), slice.items(.end), diag);
    defer {
        std.testing.allocator.free(ast.tokens);
        ast.deinit();
    }
    const decls = ast.extraSlice(ast.data(ast.root).lhs);
    try std.testing.expectEqual(@as(usize, 2), decls.len);
    const main_decl: NodeIndex = @intCast(decls[1]);
    const block = ast.data(main_decl).lhs;
    const stmts = ast.extraSlice(ast.data(block).lhs);
    try std.testing.expectEqual(@as(usize, 6), stmts.len);
    const c_stmt: NodeIndex = @intCast(stmts[2]);
    const y2_stmt: NodeIndex = @intCast(stmts[3]);
    const y3_stmt: NodeIndex = @intCast(stmts[4]);
    const y4_stmt: NodeIndex = @intCast(stmts[5]);
    try std.testing.expectEqual(Node.Tag.var_decl, ast.tag(c_stmt));
    try std.testing.expectEqual(Node.Tag.var_decl, ast.tag(y2_stmt));
    try std.testing.expectEqual(Node.Tag.var_decl, ast.tag(y3_stmt));
    try std.testing.expectEqual(Node.Tag.var_decl, ast.tag(y4_stmt));
    const c_decl = ast.data(c_stmt).rhs;
    const y2_decl = ast.data(y2_stmt).rhs;
    const y3_decl = ast.data(y3_stmt).rhs;
    const y4_decl = ast.data(y4_stmt).rhs;
    try std.testing.expectEqual(Node.Tag.ifx_expr, ast.tag(c_decl));
    try std.testing.expectEqual(Node.Tag.ifx_expr, ast.tag(y2_decl));
    try std.testing.expectEqual(Node.Tag.ifx_expr, ast.tag(y3_decl));
    try std.testing.expectEqual(Node.Tag.ifx_expr, ast.tag(y4_decl));
}

test "parser accepts top-level assert and placeholder directives" {
    const lexer = @import("lexer.zig");
    const source =
        "#assert true \"ok\";\n" ++
        "#placeholder TRUTH;\n" ++
        "main :: () {}\n";
    const diag = Diagnostic.init(std.testing.allocator, "top_level_directives.jai", source);
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
    try std.testing.expectEqual(Node.Tag.run_expr, ast.tag(@intCast(decls[0])));
    try std.testing.expectEqual(Node.Tag.placeholder_decl, ast.tag(@intCast(decls[1])));
    try std.testing.expectEqualStrings("TRUTH", ast.tokenSlice(ast.mainToken(@intCast(decls[1]))));
}

test "parser accepts spaced directives and inline directive if branches" {
    const lexer = @import("lexer.zig");
    const source =
        "# import \"Basic\";\n" ++
        "# if OS == .MACOS value :: #string END\n" ++
        "hello\n" ++
        "END\n" ++
        "else value :: \"nope\";\n" ++
        "main :: () {\n" ++
        " #if OS == .MACOS return;\n" ++
        " #asm AVX { add x, y; }\n" ++
        "}\n";
    const diag = Diagnostic.init(std.testing.allocator, "inline_directive_if.jai", source);
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
    try std.testing.expectEqual(Node.Tag.const_decl, ast.tag(@intCast(decls[1])));
    const main_decl: NodeIndex = @intCast(decls[2]);
    const stmts = ast.extraSlice(ast.data(ast.data(main_decl).lhs).lhs);
    try std.testing.expectEqual(@as(usize, 2), stmts.len);
    try std.testing.expectEqual(Node.Tag.stmt_list, ast.tag(@intCast(stmts[0])));
    try std.testing.expectEqual(Node.Tag.meta_stmt, ast.tag(@intCast(stmts[1])));
}

test "parser separates opaque meta directives from executable run" {
    const lexer = @import("lexer.zig");
    const source =
        "code :: #code x := 1;\n" ++
        "main :: () {\n" ++
        " #asm { mov rax, rax }\n" ++
        " a := #caller_code;\n" ++
        " #run print(\"x\");\n" ++
        "}\n";
    const diag = Diagnostic.init(std.testing.allocator, "meta_split.jai", source);
    var tokens = try lexer.tokenize(std.testing.allocator, source, diag);
    defer tokens.deinit(std.testing.allocator);
    const slice = tokens.slice();
    var ast = try parse(std.testing.allocator, source, slice.items(.tag), slice.items(.start), slice.items(.end), diag);
    defer {
        std.testing.allocator.free(ast.tokens);
        ast.deinit();
    }
    const decls = ast.extraSlice(ast.data(ast.root).lhs);
    try std.testing.expectEqual(Node.Tag.const_decl, ast.tag(@intCast(decls[0])));
    try std.testing.expectEqual(Node.Tag.meta_expr, ast.tag(ast.data(@intCast(decls[0])).lhs));
    const main_decl: NodeIndex = @intCast(decls[1]);
    const stmts = ast.extraSlice(ast.data(ast.data(main_decl).lhs).lhs);
    try std.testing.expectEqual(Node.Tag.meta_stmt, ast.tag(@intCast(stmts[0])));
    try std.testing.expectEqual(Node.Tag.var_decl, ast.tag(@intCast(stmts[1])));
    try std.testing.expectEqual(Node.Tag.meta_expr, ast.tag(ast.data(@intCast(stmts[1])).rhs));
    try std.testing.expectEqual(Node.Tag.run_expr, ast.tag(@intCast(stmts[2])));
}

test "parser accepts starred iterable for syntax" {
    const lexer = @import("lexer.zig");
    const source =
        "#import \"Basic\";\n" ++
        "main :: () {\n" ++
        " for * player: players {\n" ++
        "  player;\n" ++
        " }\n" ++
        "}\n";
    const diag = Diagnostic.init(std.testing.allocator, "starred_for.jai", source);
    var tokens = try lexer.tokenize(std.testing.allocator, source, diag);
    defer tokens.deinit(std.testing.allocator);
    const slice = tokens.slice();
    var ast = try parse(std.testing.allocator, source, slice.items(.tag), slice.items(.start), slice.items(.end), diag);
    defer {
        std.testing.allocator.free(ast.tokens);
        ast.deinit();
    }
    const decls = ast.extraSlice(ast.data(ast.root).lhs);
    const main_decl: NodeIndex = @intCast(decls[1]);
    const block = ast.data(main_decl).lhs;
    const stmts = ast.extraSlice(ast.data(block).lhs);
    try std.testing.expectEqual(@as(usize, 1), stmts.len);
    try std.testing.expectEqual(Node.Tag.for_stmt, ast.tag(@intCast(stmts[0])));
}

test "parser keeps full disjunction in if condition" {
    const lexer = @import("lexer.zig");
    const source =
        "#import \"Basic\";\n" ++
        "main :: () {\n" ++
        " input_path := compiler_arg(1);\n" ++
        " if input_path == \"-h\" || input_path == \"--help\" {\n" ++
        "  return;\n" ++
        " }\n" ++
        "}\n";
    const diag = Diagnostic.init(std.testing.allocator, "if_disjunction.jai", source);
    var tokens = try lexer.tokenize(std.testing.allocator, source, diag);
    defer tokens.deinit(std.testing.allocator);
    const slice = tokens.slice();
    var ast = try parse(std.testing.allocator, source, slice.items(.tag), slice.items(.start), slice.items(.end), diag);
    defer {
        std.testing.allocator.free(ast.tokens);
        ast.deinit();
    }
    const decls = ast.extraSlice(ast.data(ast.root).lhs);
    const main_decl: NodeIndex = @intCast(decls[1]);
    const block = ast.data(main_decl).lhs;
    const stmts = ast.extraSlice(ast.data(block).lhs);
    try std.testing.expectEqual(Node.Tag.if_stmt, ast.tag(@intCast(stmts[1])));
    const cond = ast.data(@intCast(stmts[1])).lhs;
    try std.testing.expectEqual(Node.Tag.binary_expr, ast.tag(cond));
    try std.testing.expectEqual(Tag.pipe_pipe, ast.tokens[ast.mainToken(cond)].tag);
}

test "parser selects top-level #if branch for host OS" {
    const lexer = @import("lexer.zig");
    const source =
        "#if OS == .WINDOWS {\n" ++
        " WindowsThing :: 1;\n" ++
        "} else {\n" ++
        " OtherThing :: 2;\n" ++
        "}\n";
    const diag = Diagnostic.init(std.testing.allocator, "top_level_if.jai", source);
    var tokens = try lexer.tokenize(std.testing.allocator, source, diag);
    defer tokens.deinit(std.testing.allocator);
    const slice = tokens.slice();
    var ast = try parse(std.testing.allocator, source, slice.items(.tag), slice.items(.start), slice.items(.end), diag);
    defer {
        std.testing.allocator.free(ast.tokens);
        ast.deinit();
    }
    const decls = ast.extraSlice(ast.data(ast.root).lhs);
    try std.testing.expectEqual(@as(usize, 1), decls.len);
    const decl: NodeIndex = @intCast(decls[0]);
    try std.testing.expectEqual(Node.Tag.const_decl, ast.tag(decl));
    const expected_name = if (builtin.target.os.tag == .windows) "WindowsThing" else "OtherThing";
    try std.testing.expectEqualStrings(expected_name, ast.tokenSlice(ast.mainToken(decl)));
}

test "parser accepts selected top-level directive if branch with multiline string before else if" {
    const lexer = @import("lexer.zig");
    const source =
        "#if OS == .WINDOWS {\n" ++
        "    value :: 1;\n" ++
        "} else #if OS == .MACOS {\n" ++
        "    DATA :: #string STRING\n" ++
        "<plist>\n" ++
        "    <string>Focus</string>\n" ++
        "</plist>\n" ++
        "STRING\n" ++
        "} else #if OS == .LINUX {\n" ++
        "    value :: 2;\n" ++
        "}\n";
    var tokens = try lexer.tokenize(std.testing.allocator, source, Diagnostic.init(std.testing.allocator, "test.jai", source));
    defer tokens.deinit(std.testing.allocator);
    const slice = tokens.slice();
    var ast = try parse(std.testing.allocator, source, slice.items(.tag), slice.items(.start), slice.items(.end), Diagnostic.init(std.testing.allocator, "test.jai", source));
    defer {
        std.testing.allocator.free(ast.tokens);
        ast.deinit();
    }
    try std.testing.expect(ast.extraSlice(ast.data(ast.root).lhs).len >= 1);
}

test "parser selects statement #if branch for host OS" {
    const lexer = @import("lexer.zig");
    const source =
        "#import \"Basic\";\n" ++
        "main :: () {\n" ++
        " x := 1;\n" ++
        " #if OS == .WINDOWS {\n" ++
        "  x = 2;\n" ++
        " } else {\n" ++
        "  x = 3;\n" ++
        " }\n" ++
        "}\n";
    const diag = Diagnostic.init(std.testing.allocator, "stmt_if.jai", source);
    var tokens = try lexer.tokenize(std.testing.allocator, source, diag);
    defer tokens.deinit(std.testing.allocator);
    const slice = tokens.slice();
    var ast = try parse(std.testing.allocator, source, slice.items(.tag), slice.items(.start), slice.items(.end), diag);
    defer {
        std.testing.allocator.free(ast.tokens);
        ast.deinit();
    }
    const decls = ast.extraSlice(ast.data(ast.root).lhs);
    const main_decl: NodeIndex = @intCast(decls[1]);
    const block = ast.data(main_decl).lhs;
    const stmts = ast.extraSlice(ast.data(block).lhs);
    try std.testing.expectEqual(@as(usize, 2), stmts.len);
    try std.testing.expectEqual(Node.Tag.var_decl, ast.tag(@intCast(stmts[0])));
    try std.testing.expectEqual(Node.Tag.stmt_list, ast.tag(@intCast(stmts[1])));
}

test "parser accepts procedure_name anonymous procs and inline call statements" {
    const lexer = @import("lexer.zig");
    const source =
        "#import \"Basic\";\n" ++
        "main :: () {\n" ++
        " print(\"%\", #procedure_name());\n" ++
        " inline test_local(1);\n" ++
        " f := () -> int { return 1; };\n" ++
        " g := () { };\n" ++
        " x := () -> int { return 2; }();\n" ++
        "}\n";
    const diag = Diagnostic.init(std.testing.allocator, "anon_proc_surface.jai", source);
    var tokens = try lexer.tokenize(std.testing.allocator, source, diag);
    defer tokens.deinit(std.testing.allocator);
    const slice = tokens.slice();
    var ast = try parse(std.testing.allocator, source, slice.items(.tag), slice.items(.start), slice.items(.end), diag);
    defer {
        std.testing.allocator.free(ast.tokens);
        ast.deinit();
    }
    const decls = ast.extraSlice(ast.data(ast.root).lhs);
    const main_decl: NodeIndex = @intCast(decls[1]);
    const block = ast.data(main_decl).lhs;
    const stmts = ast.extraSlice(ast.data(block).lhs);
    try std.testing.expectEqual(Node.Tag.expr_stmt, ast.tag(@intCast(stmts[0])));
    try std.testing.expectEqual(Node.Tag.expr_stmt, ast.tag(@intCast(stmts[1])));
    try std.testing.expectEqual(Node.Tag.var_decl, ast.tag(@intCast(stmts[2])));
    try std.testing.expectEqual(Node.Tag.var_decl, ast.tag(@intCast(stmts[3])));
    try std.testing.expectEqual(Node.Tag.var_decl, ast.tag(@intCast(stmts[4])));
}

test "parser accepts polymorph and using parameter forms" {
    const lexer = @import("lexer.zig");
    const source =
        "convert :: (arg: $T) {}\n" ++
        "arr_sum :: (a: [] $T) -> T { return result; }\n" ++
        "channel_write :: (using c: *Channel($T, $n), data: T) {}\n";
    const diag = Diagnostic.init(std.testing.allocator, "poly_proc_surface.jai", source);
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
    for (decls) |decl| try std.testing.expectEqual(Node.Tag.proc_decl, ast.tag(@intCast(decl)));
}
