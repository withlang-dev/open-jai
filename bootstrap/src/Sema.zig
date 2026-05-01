const std = @import("std");
const Ast = @import("Ast.zig").Ast;
const NodeIndex = @import("Ast.zig").NodeIndex;
const Diagnostic = @import("diagnostics.zig").Diagnostic;
const InternPool = @import("InternPool.zig").InternPool;
const Type = @import("Type.zig").Type;
const Resolved = @import("resolve.zig").Resolved;
const Symbol = @import("resolve.zig").Symbol;

pub const Typed = struct {
    allocator: std.mem.Allocator,
    node_types: []Type,
    main_proc: NodeIndex,

    pub fn deinit(t: *Typed) void { t.allocator.free(t.node_types); }

    pub fn typeOf(t: *const Typed, node: NodeIndex) Type { return t.node_types[node]; }
};

pub fn analyze(allocator: std.mem.Allocator, ast: *const Ast, resolved: *const Resolved, ip: *InternPool, diag: Diagnostic) !Typed {
    _ = ip;
    var typed = Typed{
        .allocator = allocator,
        .node_types = try allocator.alloc(Type, ast.node_tags.items.len),
        .main_proc = resolved.main_proc.?,
    };
    errdefer typed.deinit();
    @memset(typed.node_types, Type.voidType());
    const root_decls = ast.extraSlice(ast.data(ast.root).lhs);
    var main_count: usize = 0;
    for (root_decls) |decl_idx| {
        const decl: NodeIndex = @intCast(decl_idx);
        if (ast.tag(decl) == .proc_decl) {
            const name = ast.tokenSlice(ast.mainToken(decl));
            if (std.mem.eql(u8, name, "main")) main_count += 1;
            try analyzeProc(ast, resolved, &typed, decl, diag);
        }
    }
    if (main_count != 1) return diag.failAt(0, "expected exactly one main procedure", .{});
    return typed;
}

fn analyzeProc(ast: *const Ast, resolved: *const Resolved, typed: *Typed, proc: NodeIndex, diag: Diagnostic) !void {
    const name = ast.tokenSlice(ast.mainToken(proc));
    if (std.mem.eql(u8, name, "main")) {
        // Parser only accepts an empty parameter list and no return type in Phase 1.
    }
    try analyzeBlock(ast, resolved, typed, ast.data(proc).lhs, diag);
}

fn analyzeBlock(ast: *const Ast, resolved: *const Resolved, typed: *Typed, block: NodeIndex, diag: Diagnostic) !void {
    for (ast.extraSlice(ast.data(block).lhs)) |stmt| _ = try analyzeNode(ast, resolved, typed, @intCast(stmt), diag);
}

fn analyzeNode(ast: *const Ast, resolved: *const Resolved, typed: *Typed, node: NodeIndex, diag: Diagnostic) !Type {
    const ty = switch (ast.tag(node)) {
        .expr_stmt => try analyzeNode(ast, resolved, typed, ast.data(node).lhs, diag),
        .return_stmt => Type.voidType(),
        .var_decl => blk: {
            if (ast.data(node).rhs != @import("Ast.zig").null_node) _ = try analyzeNode(ast, resolved, typed, ast.data(node).rhs, diag);
            break :blk Type.voidType();
        },
        .const_decl => try analyzeNode(ast, resolved, typed, ast.data(node).lhs, diag),
        .assign_stmt => blk: {
            _ = try analyzeNode(ast, resolved, typed, ast.data(node).lhs, diag);
            _ = try analyzeNode(ast, resolved, typed, ast.data(node).rhs, diag);
            break :blk Type.voidType();
        },
        .type_expr => Type.init(InternPool.well_known.type_type),
        .string_literal => Type.string(),
        .integer_literal, .char_literal => Type.init(InternPool.well_known.s64_type),
        .float_literal => Type.init(InternPool.well_known.float32_type),
        .bool_literal => Type.boolType(),
        .type_of_expr => blk: {
            _ = try analyzeNode(ast, resolved, typed, ast.data(node).lhs, diag);
            break :blk Type.init(InternPool.well_known.type_type);
        },
        .size_of_expr => blk: {
            _ = try analyzeNode(ast, resolved, typed, ast.data(node).lhs, diag);
            break :blk Type.init(InternPool.well_known.s64_type);
        },
        .binary_expr => blk: {
            const lhs_ty = try analyzeNode(ast, resolved, typed, ast.data(node).lhs, diag);
            const rhs_ty = try analyzeNode(ast, resolved, typed, ast.data(node).rhs, diag);
            if (!(lhs_ty.isInteger() and rhs_ty.isInteger())) return diag.failAt(ast.tokens[ast.mainToken(node)].start, "Phase 3 binary operators currently require integer operands", .{});
            break :blk Type.init(InternPool.well_known.s64_type);
        },
        .proc_decl => Type.voidType(),
        .identifier => blk: {
            const name = ast.tokenSlice(ast.mainToken(node));
            const sym = resolved.lookup(name) orelse return diag.failAt(ast.tokens[ast.mainToken(node)].start, "unresolved identifier '{s}'", .{name});
            break :blk switch (sym) {
                .builtin_print => Type.voidType(),
                .proc => Type.voidType(),
                .const_value => |value_node| try analyzeNode(ast, resolved, typed, value_node, diag),
            };
        },
        .call_expr => blk: {
            const callee = ast.data(node).lhs;
            if (ast.tag(callee) != .identifier) return diag.failAt(ast.tokens[ast.mainToken(callee)].start, "Phase 1 only supports calls by identifier", .{});
            const name = ast.tokenSlice(ast.mainToken(callee));
            const sym = resolved.lookup(name) orelse return diag.failAt(ast.tokens[ast.mainToken(callee)].start, "unresolved identifier '{s}'", .{name});
            const args = ast.extraSlice(ast.data(node).rhs);
            switch (sym) {
                .builtin_print => {
                    if (args.len == 0) return diag.failAt(ast.tokens[ast.mainToken(node)].start, "print expects at least one argument", .{});
                    const fmt_ty = try analyzeNode(ast, resolved, typed, @intCast(args[0]), diag);
                    _ = fmt_ty;
                    for (args[1..]) |arg| {
                        const arg_ty = try analyzeNode(ast, resolved, typed, @intCast(arg), diag);
                        if (!(arg_ty.isString() or arg_ty.isInteger() or arg_ty.index == InternPool.well_known.float32_type or arg_ty.index == InternPool.well_known.float64_type or arg_ty.isBool() or arg_ty.index == InternPool.well_known.type_type)) return diag.failAt(ast.tokens[ast.mainToken(@intCast(arg))].start, "Phase 2 print supports string, integer, float, bool, and type arguments", .{});
                    }
                    break :blk Type.voidType();
                },
                .proc => return diag.failAt(ast.tokens[ast.mainToken(node)].start, "Phase 1 only supports calling Basic.print", .{}),
                .const_value => return diag.failAt(ast.tokens[ast.mainToken(callee)].start, "constant value is not callable", .{}),
            }
        },
        else => return diag.failAt(ast.tokens[ast.mainToken(node)].start, "unsupported AST node in semantic analysis", .{}),
    };
    typed.node_types[node] = ty;
    return ty;
}
