const std = @import("std");
const Ast = @import("Ast.zig").Ast;
const Node = @import("Ast.zig").Node;
const NodeIndex = @import("Ast.zig").NodeIndex;
const Diagnostic = @import("diagnostics.zig").Diagnostic;

pub const Symbol = union(enum) {
    proc: NodeIndex,
    builtin_print,
    const_value: NodeIndex,
};

pub const Resolved = struct {
    allocator: std.mem.Allocator,
    symbols: std.StringHashMapUnmanaged(Symbol) = .empty,
    imports_basic: bool = false,
    main_proc: ?NodeIndex = null,

    pub fn deinit(r: *Resolved) void {
        r.symbols.deinit(r.allocator);
    }

    pub fn lookup(r: *const Resolved, name: []const u8) ?Symbol {
        return r.symbols.get(name);
    }
};

pub fn resolve(allocator: std.mem.Allocator, ast: *const Ast, diag: Diagnostic) !Resolved {
    var r = Resolved{ .allocator = allocator };
    errdefer r.deinit();
    const root_decls = ast.extraSlice(ast.data(ast.root).lhs);
    for (root_decls) |decl_idx| {
        const decl: NodeIndex = @intCast(decl_idx);
        switch (ast.tag(decl)) {
            .import_decl => {
                const module_name = ast.stringTokenContents(ast.data(decl).lhs);
                if (std.mem.eql(u8, module_name, "Basic")) {
                    r.imports_basic = true;
                    try r.symbols.put(allocator, "print", .builtin_print);
                } else return diag.failAt(ast.tokens[ast.data(decl).lhs].start, "unknown Phase 1 import '{s}'", .{module_name});
            },
            .proc_decl => {
                const name = ast.tokenSlice(ast.mainToken(decl));
                if (r.symbols.contains(name)) return diag.failAt(ast.tokens[ast.mainToken(decl)].start, "duplicate top-level declaration '{s}'", .{name});
                try r.symbols.put(allocator, name, .{ .proc = decl });
                if (std.mem.eql(u8, name, "main")) r.main_proc = decl;
            },
            .const_decl => {
                const name = ast.tokenSlice(ast.mainToken(decl));
                if (r.symbols.contains(name)) return diag.failAt(ast.tokens[ast.mainToken(decl)].start, "duplicate top-level declaration '{s}'", .{name});
                try r.symbols.put(allocator, name, .{ .const_value = ast.data(decl).lhs });
            },
            else => return diag.failAt(ast.tokens[ast.mainToken(decl)].start, "unsupported top-level AST node in resolver", .{}),
        }
    }
    for (root_decls) |decl_idx| {
        const decl: NodeIndex = @intCast(decl_idx);
        if (ast.tag(decl) == .proc_decl) try resolveProc(ast, &r, decl, diag);
    }
    if (r.main_proc == null) return diag.failAt(0, "No program entry point was found. (The designated entry point name is 'main'.)", .{});
    return r;
}

fn resolveProc(ast: *const Ast, r: *const Resolved, proc: NodeIndex, diag: Diagnostic) !void {
    try resolveBlock(ast, r, ast.data(proc).lhs, diag);
}

fn resolveBlock(ast: *const Ast, r: *const Resolved, block: NodeIndex, diag: Diagnostic) !void {
    const stmts = ast.extraSlice(ast.data(block).lhs);
    for (stmts) |stmt_idx| try resolveNode(ast, r, @intCast(stmt_idx), diag);
}

fn resolveNode(ast: *const Ast, r: *const Resolved, node: NodeIndex, diag: Diagnostic) !void {
    switch (ast.tag(node)) {
        .expr_stmt => try resolveNode(ast, r, ast.data(node).lhs, diag),
        .var_decl => {
            if (ast.data(node).lhs != @import("Ast.zig").null_node) try resolveNode(ast, r, ast.data(node).lhs, diag);
            if (ast.data(node).rhs != @import("Ast.zig").null_node) try resolveNode(ast, r, ast.data(node).rhs, diag);
        },
        .const_decl => try resolveNode(ast, r, ast.data(node).lhs, diag),
        .assign_stmt => {
            try resolveNode(ast, r, ast.data(node).lhs, diag);
            try resolveNode(ast, r, ast.data(node).rhs, diag);
        },
        .return_stmt, .string_literal, .integer_literal, .float_literal, .bool_literal, .char_literal, .type_expr => {},
        .type_of_expr => try resolveNode(ast, r, ast.data(node).lhs, diag),
        .size_of_expr => try resolveNode(ast, r, ast.data(node).lhs, diag),
        .binary_expr => {
            try resolveNode(ast, r, ast.data(node).lhs, diag);
            try resolveNode(ast, r, ast.data(node).rhs, diag);
        },
        .call_expr => {
            try resolveNode(ast, r, ast.data(node).lhs, diag);
            for (ast.extraSlice(ast.data(node).rhs)) |arg| try resolveNode(ast, r, @intCast(arg), diag);
        },
        .identifier => {
            const name = ast.tokenSlice(ast.mainToken(node));
            if (r.lookup(name) == null) return diag.failAt(ast.tokens[ast.mainToken(node)].start, "unresolved identifier '{s}'", .{name});
        },
        else => return diag.failAt(ast.tokens[ast.mainToken(node)].start, "unsupported AST node in resolver", .{}),
    }
}
