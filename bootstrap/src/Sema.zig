const std = @import("std");
const Ast = @import("Ast.zig").Ast;
const NodeIndex = @import("Ast.zig").NodeIndex;
const Diagnostic = @import("diagnostics.zig").Diagnostic;
const InternPool = @import("InternPool.zig").InternPool;
const Type = @import("Type.zig").Type;
const Resolved = @import("resolve.zig").Resolved;
const Symbol = @import("resolve.zig").Symbol;

var active_ip: ?*InternPool = null;

pub fn activeInternPoolForTypeQueries() ?*InternPool { return active_ip; }

pub const Typed = struct {
    allocator: std.mem.Allocator,
    node_types: []Type,
    type_aliases: std.StringHashMapUnmanaged(Type) = .empty,
    inferred_param_types: std.AutoHashMapUnmanaged(NodeIndex, Type) = .empty,
    comptime_ints: std.AutoHashMapUnmanaged(NodeIndex, i64) = .empty,
    comptime_floats: std.AutoHashMapUnmanaged(NodeIndex, f64) = .empty,
    main_proc: NodeIndex,

    pub fn deinit(t: *Typed) void {
        t.type_aliases.deinit(t.allocator);
        t.inferred_param_types.deinit(t.allocator);
        t.comptime_ints.deinit(t.allocator);
        t.comptime_floats.deinit(t.allocator);
        t.allocator.free(t.node_types);
    }

    pub fn typeOf(t: *const Typed, node: NodeIndex) Type { return t.node_types[node]; }
};

pub fn analyze(allocator: std.mem.Allocator, ast: *const Ast, resolved: *const Resolved, ip: *InternPool, diag: Diagnostic) !Typed {
    active_ip = ip;
    defer active_ip = null;
    var typed = Typed{
        .allocator = allocator,
        .node_types = try allocator.alloc(Type, ast.node_tags.items.len),
        .main_proc = resolved.main_proc.?,
    };
    errdefer typed.deinit();
    @memset(typed.node_types, Type.voidType());
    try collectTypeAliases(ast, &typed, ast.data(ast.root).lhs, diag);
    const root_decls = ast.extraSlice(ast.data(ast.root).lhs);
    var main_count: usize = 0;
    for (root_decls) |decl_idx| {
        const decl: NodeIndex = @intCast(decl_idx);
        if (ast.tag(decl) == .proc_decl) {
            const name = ast.tokenSlice(ast.mainToken(decl));
            if (std.mem.eql(u8, name, "main")) main_count += 1;
            const proc_sig = procSignature(ast, decl);
            if (proc_sig) |s| {
                const params = ast.extraSlice(s.params_extra);
                if (params.len > 0 and ast.data(@as(NodeIndex, @intCast(params[0]))).lhs == @import("Ast.zig").null_node) {
                    typed.node_types[decl] = Type.voidType();
                    continue;
                }
            }
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

fn analyzeBlock(ast: *const Ast, resolved: *const Resolved, typed: *Typed, block: NodeIndex, diag: Diagnostic) anyerror!void {
    try collectTypeAliases(ast, typed, ast.data(block).lhs, diag);
    for (ast.extraSlice(ast.data(block).lhs)) |stmt| _ = try analyzeNode(ast, resolved, typed, @intCast(stmt), diag);
}

fn collectTypeAliases(ast: *const Ast, typed: *Typed, stmts_extra: u32, diag: Diagnostic) !void {
    for (ast.extraSlice(stmts_extra)) |stmt_idx| {
        const stmt: NodeIndex = @intCast(stmt_idx);
        if (ast.tag(stmt) == .stmt_list) {
            try collectTypeAliases(ast, typed, ast.data(stmt).lhs, diag);
        } else if (ast.tag(stmt) == .const_decl and ast.tag(ast.data(stmt).lhs) == .type_expr) {
            const name = ast.tokenSlice(ast.mainToken(stmt));
            const ty = try typeFromTypeExprWithAliases(ast, typed, ast.data(stmt).lhs, diag);
            try typed.type_aliases.put(typed.allocator, name, ty);
            typed.node_types[stmt] = Type.init(InternPool.well_known.type_type);
            typed.node_types[ast.data(stmt).lhs] = Type.init(InternPool.well_known.type_type);
        }
    }
}

fn analyzeNode(ast: *const Ast, resolved: *const Resolved, typed: *Typed, node: NodeIndex, diag: Diagnostic) !Type {
    const ty = switch (ast.tag(node)) {
        .expr_stmt => try analyzeNode(ast, resolved, typed, ast.data(node).lhs, diag),
        .stmt_list => blk: {
            try collectTypeAliases(ast, typed, ast.data(node).lhs, diag);
            for (ast.extraSlice(ast.data(node).lhs)) |child| _ = try analyzeNode(ast, resolved, typed, @intCast(child), diag);
            break :blk Type.voidType();
        },
            .return_stmt => blk: {
                if (ast.data(node).lhs != @import("Ast.zig").null_node) _ = try analyzeNode(ast, resolved, typed, ast.data(node).lhs, diag);
                break :blk Type.voidType();
            },
        .var_decl => blk: {
            const explicit_ty = if (ast.data(node).lhs != @import("Ast.zig").null_node) try typeFromTypeExprWithAliases(ast, typed, ast.data(node).lhs, diag) else Type.voidType();
            if (ast.data(node).rhs != @import("Ast.zig").null_node) {
                const init_ty = try analyzeNode(ast, resolved, typed, ast.data(node).rhs, diag);
                if (ast.data(node).lhs == @import("Ast.zig").null_node) break :blk init_ty;
            }
            if (ast.data(node).lhs != @import("Ast.zig").null_node) break :blk explicit_ty;
            break :blk Type.voidType();
        },
        .const_decl => try analyzeNode(ast, resolved, typed, ast.data(node).lhs, diag),
        .assign_stmt => blk: {
            _ = try analyzeNode(ast, resolved, typed, ast.data(node).lhs, diag);
            _ = try analyzeNode(ast, resolved, typed, ast.data(node).rhs, diag);
            break :blk Type.voidType();
        },
        .type_expr => Type.init(InternPool.well_known.type_type),
        .pointer_type => Type.init(try internPointerType(ast, try typeFromTypeExpr(ast, ast.data(node).lhs, diag), diag)),
        .proc_type => Type.init(try internProcType(ast, node, diag)),
        .string_literal => Type.string(),
        .integer_literal, .char_literal => Type.init(InternPool.well_known.s64_type),
        .float_literal => Type.init(InternPool.well_known.float32_type),
        .bool_literal => Type.boolType(),
        .null_literal => Type.init(try internPointerType(ast, Type.voidType(), diag)),
        .undefined_literal => Type.voidType(),
        .type_of_expr => blk: {
            _ = try analyzeNode(ast, resolved, typed, ast.data(node).lhs, diag);
            break :blk Type.init(InternPool.well_known.type_type);
        },
        .is_constant_expr => blk: {
            _ = try analyzeNode(ast, resolved, typed, ast.data(node).lhs, diag);
            break :blk Type.boolType();
        },
        .run_expr => blk: {
            if (ast.tokens[ast.mainToken(node)].tag == .keyword_push_context) {
                _ = try analyzeNode(ast, resolved, typed, ast.data(node).rhs, diag);
                try analyzeBlock(ast, resolved, typed, ast.data(node).lhs, diag);
                return diag.failAt(ast.tokens[ast.mainToken(node)].start, "push_context semantic context switching is not implemented in this Phase 6 slice", .{});
            }
            if (ast.tag(ast.data(node).lhs) == .block) {
                if (ast.data(node).rhs != 0) break :blk try typeFromTypeExpr(ast, ast.data(node).rhs, diag);
                break :blk Type.voidType();
            }
            break :blk try analyzeNode(ast, resolved, typed, ast.data(node).lhs, diag);
        },
        .size_of_expr => blk: {
            _ = try analyzeNode(ast, resolved, typed, ast.data(node).lhs, diag);
            break :blk Type.init(InternPool.well_known.s64_type);
        },
        .unary_expr => blk: {
            const op = ast.tokens[ast.mainToken(node)].tag;
            const operand_ty = try analyzeNode(ast, resolved, typed, ast.data(node).lhs, diag);
            switch (op) {
                .shift_left => break :blk Type.init(InternPool.well_known.s64_type),
                .dot_dot => return diag.failAt(ast.tokens[ast.mainToken(node)].start, "spread '..' is only supported when expanding variadic procedure arguments", .{}),
                .minus => {
                    if (!(operand_ty.isInteger() or operand_ty.index == InternPool.well_known.float32_type or operand_ty.index == InternPool.well_known.float64_type)) {
                        return diag.failAt(ast.tokens[ast.mainToken(node)].start, "unary '-' requires a numeric operand", .{});
                    }
                    break :blk operand_ty;
                },
                .bang => {
                    // Allow ! on any bool-coercible type: bool, int, string, pointer.
                    if (!operand_ty.isBool() and !operand_ty.isInteger() and !operand_ty.isString() and !operand_ty.isPointer() and !operand_ty.isFloat()) {
                        return diag.failAt(ast.tokens[ast.mainToken(node)].start, "unary '!' requires a bool-coercible operand", .{});
                    }
                    break :blk Type.boolType();
                },
                .star => {
                    if (ast.tag(ast.data(node).lhs) != .identifier) return diag.failAt(ast.tokens[ast.mainToken(node)].start, "address-of '*' currently supports local identifiers only", .{});
                    const decl = resolved.local_values.get(ast.data(node).lhs) orelse return diag.failAt(ast.tokens[ast.mainToken(node)].start, "address-of '*' requires a local variable", .{});
                    if (ast.tag(decl) != .var_decl) return diag.failAt(ast.tokens[ast.mainToken(node)].start, "address-of '*' requires a mutable local variable", .{});
                    const pointee = try analyzeNode(ast, resolved, typed, ast.data(node).lhs, diag);
                    break :blk Type.init(try internPointerType(ast, pointee, diag));
                },
                .keyword_xx => {
                    if (operand_ty.isInteger() or operand_ty.isFloat() or operand_ty.isBool()) break :blk operand_ty;
                    return diag.failAt(ast.tokens[ast.mainToken(node)].start, "xx autocast requires a numeric or bool operand", .{});
                },
                .keyword_cast => {
                    const raw_target_ty = ast.data(node).rhs;
                    const target_ty: u32 = raw_target_ty & 0x7fffffff;
                    const no_check = (raw_target_ty & 0x80000000) != 0;
                    const cast_ty = try typeFromTypeExpr(ast, target_ty, diag);
                    const operand = ast.data(node).lhs;
                    if (cast_ty.isInteger() and operand_ty.isInteger()) break :blk cast_ty;
                    if (cast_ty.isInteger() and operand_ty.isFloat()) break :blk cast_ty;
                    if (cast_ty.isInteger() and operand_ty.isBool()) break :blk cast_ty;
                    if (cast_ty.isBool() and operand_ty.isInteger()) break :blk cast_ty;
                    if (cast_ty.isAny()) break :blk cast_ty;
                    if (no_check and !cast_ty.isInteger()) return diag.failAt(ast.tokens[ast.mainToken(node)].start, "cast,no_check currently supports integer target types only", .{});
                    if (cast_ty.index == InternPool.well_known.float32_type or cast_ty.index == InternPool.well_known.float64_type) {
                        _ = try analyzeNode(ast, resolved, typed, operand, diag);
                        break :blk cast_ty;
                    }
                    if (ast.tag(target_ty) == .pointer_type and ast.tag(operand) == .identifier) {
                        const name = ast.tokenSlice(ast.mainToken(operand));
                        if (resolved.lookup(name)) |sym| switch (sym) {
                            .proc => break :blk Type.init(try internPointerType(ast, Type.voidType(), diag)),
                            else => {},
                        };
                    }
                    return diag.failAt(ast.tokens[ast.mainToken(node)].start, "only numeric casts and cast(*void) procedure-name are implemented", .{});
                },
                else => return diag.failAt(ast.tokens[ast.mainToken(node)].start, "unsupported unary operator", .{}),
            }
        },
        .binary_expr => blk: {
            const lhs_ty = try analyzeNode(ast, resolved, typed, ast.data(node).lhs, diag);
            const rhs_ty = try analyzeNode(ast, resolved, typed, ast.data(node).rhs, diag);
            break :blk switch (ast.tokens[ast.mainToken(node)].tag) {
                .star, .plus, .minus, .slash, .plus_equal, .minus_equal, .star_equal, .slash_equal => {
                    if (lhs_ty.isInteger() and rhs_ty.isInteger()) break :blk lhs_ty;
                    if ((lhs_ty.isInteger() or lhs_ty.isFloat()) and (rhs_ty.isInteger() or rhs_ty.isFloat())) break :blk if (lhs_ty.isFloat() or rhs_ty.isFloat()) Type.init(InternPool.well_known.float32_type) else lhs_ty;
                    return diag.failAt(ast.tokens[ast.mainToken(node)].start, "binary operator requires numeric operands", .{});
                },
                .percent => {
                    if (lhs_ty.isInteger() and rhs_ty.isInteger()) break :blk Type.init(InternPool.well_known.s64_type);
                    return diag.failAt(ast.tokens[ast.mainToken(node)].start, "'%' requires integer operands", .{});
                },
                .ampersand, .pipe, .caret, .shift_left, .shift_right, .shift_left_rotate, .shift_right_rotate => {
                    if (lhs_ty.isInteger() and rhs_ty.isInteger()) break :blk Type.init(InternPool.well_known.s64_type);
                    return diag.failAt(ast.tokens[ast.mainToken(node)].start, "bitwise operator requires integer operands", .{});
                },
                .equal_equal, .bang_equal => {
                    if ((lhs_ty.index == InternPool.well_known.type_type and rhs_ty.index == InternPool.well_known.type_type) or ((lhs_ty.isInteger() or lhs_ty.isFloat() or lhs_ty.isString() or lhs_ty.isBool()) and (rhs_ty.isInteger() or rhs_ty.isFloat() or rhs_ty.isString() or rhs_ty.isBool()))) break :blk Type.boolType();
                    return diag.failAt(ast.tokens[ast.mainToken(node)].start, "equality operator requires comparable operands", .{});
                },
                .less_than, .less_equal, .greater_than, .greater_equal => {
                    if ((lhs_ty.isInteger() or lhs_ty.isFloat()) and (rhs_ty.isInteger() or rhs_ty.isFloat())) break :blk Type.boolType();
                    return diag.failAt(ast.tokens[ast.mainToken(node)].start, "comparison operator requires numeric operands", .{});
                },
                .ampersand_ampersand, .pipe_pipe => {
                    if ((lhs_ty.isBool() or lhs_ty.isInteger()) and (rhs_ty.isBool() or rhs_ty.isInteger())) break :blk Type.boolType();
                    return diag.failAt(ast.tokens[ast.mainToken(node)].start, "logical operator requires bool operands", .{});
                },
                else => return diag.failAt(ast.tokens[ast.mainToken(node)].start, "Phase 2 binary operator is not implemented yet", .{}),
            };
        },
        .proc_decl => Type.voidType(),
        .ifx_expr => blk: {
            const cond_ty = try analyzeNode(ast, resolved, typed, ast.data(node).lhs, diag);
            if (!cond_ty.isBool()) return diag.failAt(ast.tokens[ast.mainToken(ast.data(node).lhs)].start, "ifx condition must be bool", .{});
            const arms = ast.extraSlice(ast.data(node).rhs);
            if (arms.len != 2) return diag.failAt(ast.tokens[ast.mainToken(node)].start, "internal error: ifx requires then and else arms", .{});
            const then_ty = try analyzeNode(ast, resolved, typed, @intCast(arms[0]), diag);
            const else_ty = try analyzeNode(ast, resolved, typed, @intCast(arms[1]), diag);
            if (then_ty.index == else_ty.index) break :blk then_ty;
            if (then_ty.isInteger() and else_ty.isInteger()) break :blk Type.init(InternPool.well_known.s64_type);
            if ((then_ty.isInteger() or then_ty.isFloat()) and (else_ty.isInteger() or else_ty.isFloat())) break :blk if (then_ty.isFloat() or else_ty.isFloat()) Type.init(InternPool.well_known.float32_type) else Type.init(InternPool.well_known.s64_type);
            return diag.failAt(ast.tokens[ast.mainToken(node)].start, "ifx branch types are not compatible in this Phase 8 slice", .{});
        },
        .identifier => blk: {
            if (resolved.local_values.get(node)) |value_node| {
                break :blk switch (ast.tag(value_node)) {
                    .var_decl => if (ast.data(value_node).lhs != @import("Ast.zig").null_node)
                        try typeFromTypeExprWithAliases(ast, typed, ast.data(value_node).lhs, diag)
                    else if (typed.inferred_param_types.get(value_node)) |param_ty|
                        param_ty
                    else if (ast.data(value_node).rhs == @import("Ast.zig").null_node)
                        return diag.failAt(ast.tokens[ast.mainToken(node)].start, "inferred procedure parameter '{s}' used before call-site type inference", .{ast.tokenSlice(ast.mainToken(value_node))})
                    else if (ast.tag(ast.data(value_node).rhs) == .undefined_literal)
                        try typeFromTypeExprWithAliases(ast, typed, ast.data(value_node).lhs, diag)
                    else
                        try analyzeNode(ast, resolved, typed, ast.data(value_node).rhs, diag),
                    else => try analyzeNode(ast, resolved, typed, value_node, diag),
                };
            }
            if (resolved.loop_indexes.contains(node)) break :blk Type.init(InternPool.well_known.s64_type);
            if (resolved.loop_value_types.get(node)) |type_id| break :blk Type.init(type_id);
            const name = ast.tokenSlice(ast.mainToken(node));
            const sym = resolved.lookup(name) orelse blk_sym: {
                if (isBuiltinTypeName(name)) break :blk_sym Symbol{ .const_value = node };
                return diag.failAt(ast.tokens[ast.mainToken(node)].start, "unresolved identifier '{s}'", .{name});
            };
            break :blk switch (sym) {
                .builtin_print, .builtin_swap, .builtin_write_string, .builtin_write_strings, .builtin_write_number, .builtin_write_nonnegative_number, .builtin_new, .builtin_free, .builtin_exit, .builtin_memcpy, .builtin_assert, .builtin_sin, .builtin_random_seed, .builtin_to_calendar => Type.voidType(),
                .builtin_calendar_to_string => Type.string(),
                .builtin_current_time_consensus, .builtin_current_time_monotonic => Type.apolloTime(),
                .builtin_random_get => Type.init(InternPool.well_known.u64_type),
                .builtin_random_get_zero_to_one, .builtin_random_get_within_range => Type.init(InternPool.well_known.float64_type),
                .builtin_format_int => Type.string(),
                .builtin_format_float => Type.string(),
                .builtin_get_type_table => Type.init(InternPool.well_known.type_table_type),
                .proc => Type.voidType(),
                .const_value => |value_node| switch (ast.tag(value_node)) {
                    .var_decl => if (ast.data(value_node).lhs != @import("Ast.zig").null_node)
                        try typeFromTypeExpr(ast, ast.data(value_node).lhs, diag)
                    else if (typed.inferred_param_types.get(value_node)) |param_ty|
                        param_ty
                    else if (ast.data(value_node).rhs == @import("Ast.zig").null_node)
                        return diag.failAt(ast.tokens[ast.mainToken(node)].start, "inferred procedure parameter '{s}' used before call-site type inference", .{ast.tokenSlice(ast.mainToken(value_node))})
                    else if (ast.tag(ast.data(value_node).rhs) == .undefined_literal)
                        try typeFromTypeExpr(ast, ast.data(value_node).lhs, diag)
                    else
                        try analyzeNode(ast, resolved, typed, ast.data(value_node).rhs, diag),
                    .identifier => if (isBuiltinTypeName(ast.tokenSlice(ast.mainToken(value_node))))
                        Type.init(InternPool.well_known.type_type)
                    else
                        try analyzeNode(ast, resolved, typed, value_node, diag),
                    else => try analyzeNode(ast, resolved, typed, value_node, diag),
                },
            };
        },
        .if_stmt => blk: {
            const cond_ty = try analyzeNode(ast, resolved, typed, ast.data(node).lhs, diag);
            // Allow integer, string, and pointer as conditions (truthiness coercion).
            if (!cond_ty.isBool() and !cond_ty.isInteger() and !cond_ty.isString() and !cond_ty.isPointer() and !cond_ty.isFloat() and !cond_ty.isVoid()) {
                return diag.failAt(ast.tokens[ast.mainToken(ast.data(node).lhs)].start, "if condition must be bool-coercible", .{});
            }
            const blocks = ast.extraSlice(ast.data(node).rhs);
            try analyzeBlock(ast, resolved, typed, @intCast(blocks[0]), diag);
            if (blocks.len > 1 and blocks[1] != @import("Ast.zig").null_node) try analyzeBlock(ast, resolved, typed, @intCast(blocks[1]), diag);
            break :blk Type.voidType();
        },
        .while_stmt => blk: {
            const cond_node = ast.data(node).lhs;
            const real_cond = if (ast.tag(cond_node) == .var_decl) ast.data(cond_node).rhs else cond_node;
            const cond_ty = try analyzeNode(ast, resolved, typed, real_cond, diag);
            if (!cond_ty.isBool() and !cond_ty.isInteger() and !cond_ty.isString() and !cond_ty.isPointer() and !cond_ty.isFloat()) {
                return diag.failAt(ast.tokens[ast.mainToken(cond_node)].start, "while condition must be bool-coercible", .{});
            }
            try analyzeBlock(ast, resolved, typed, ast.data(node).rhs, diag);
            break :blk Type.voidType();
        },
        .defer_stmt => blk: {
            _ = try analyzeNode(ast, resolved, typed, ast.data(node).lhs, diag);
            break :blk Type.voidType();
        },
        .break_stmt, .continue_stmt => Type.voidType(),
        .for_stmt => blk: {
            const operands = ast.extraSlice(ast.data(node).lhs);
            if (operands.len == 4 or operands.len == 2) {
                // Range for: [start, end] or [start, end, iterator_tok, is_reverse]
                _ = try analyzeNode(ast, resolved, typed, @intCast(operands[0]), diag);
                _ = try analyzeNode(ast, resolved, typed, @intCast(operands[1]), diag);
                try analyzeBlock(ast, resolved, typed, ast.data(node).rhs, diag);
            } else if (operands.len == 1) {
                const iterable = @as(NodeIndex, @intCast(operands[0]));
                const iterable_ty = try analyzeNode(ast, resolved, typed, iterable, diag);
                if (iterable_ty.index != InternPool.well_known.type_table_type) return diag.failAt(ast.tokens[ast.mainToken(iterable)].start, "expression-for currently supports type table iterables; unsupported iterable type", .{});
                try analyzeBlock(ast, resolved, typed, ast.data(node).rhs, diag);
            } else return diag.failAt(ast.tokens[ast.mainToken(node)].start, "internal error: for statement has invalid operand count", .{});
            break :blk Type.voidType();
        },
        .aggregate_literal => blk: {
            for (ast.extraSlice(ast.data(node).lhs)) |elem| _ = try analyzeNode(ast, resolved, typed, @intCast(elem), diag);
            break :blk Type.voidType();
        },
        .typed_aggregate_literal => blk: {
            const payload = ast.extraSlice(ast.data(node).lhs);
            const type_node: NodeIndex = @intCast(payload[0]);
            const type_name = if (ast.tag(type_node) == .identifier or ast.tag(type_node) == .type_expr) ast.tokenSlice(ast.mainToken(type_node)) else "<expression>";
            const fields = ast.extraSlice(payload[1]);
            for (fields) |field_idx| {
                const field: NodeIndex = @intCast(field_idx);
                _ = try analyzeNode(ast, resolved, typed, ast.data(field).rhs, diag);
            }
            if (std.mem.eql(u8, type_name, "Version_Info")) break :blk Type.voidType();
            return diag.failAt(ast.tokens[ast.mainToken(node)].start, "typed aggregate literal for '{s}' requires struct type layout support", .{type_name});
        },
        .field_access => blk: {
            if (ast.data(node).lhs != @import("Ast.zig").null_node and ast.tag(ast.data(node).lhs) == .identifier and std.mem.eql(u8, ast.tokenSlice(ast.mainToken(ast.data(node).lhs)), "Type_Info_Tag")) break :blk Type.init(InternPool.well_known.s64_type);
            const lhs_ty = try analyzeNode(ast, resolved, typed, ast.data(node).lhs, diag);
            if (lhs_ty.index == InternPool.well_known.apollo_time_type) {
                const field_name = ast.tokenSlice(ast.data(node).rhs);
                if (std.mem.eql(u8, field_name, "low")) break :blk Type.init(InternPool.well_known.u64_type);
                if (std.mem.eql(u8, field_name, "high")) break :blk Type.init(InternPool.well_known.s64_type);
                return diag.failAt(ast.tokens[ast.data(node).rhs].start, "unsupported Apollo_Time field '{s}'", .{field_name});
            }
            if (lhs_ty.index == InternPool.well_known.calendar_type) {
                const field_name = ast.tokenSlice(ast.data(node).rhs);
                if (isCalendarField(field_name)) break :blk Type.init(InternPool.well_known.s64_type);
                return diag.failAt(ast.tokens[ast.data(node).rhs].start, "unsupported Calendar field '{s}'", .{field_name});
            }
            if (lhs_ty.index == InternPool.well_known.type_table_type) {
                const field_name = ast.tokenSlice(ast.data(node).rhs);
                if (std.mem.eql(u8, field_name, "count")) break :blk Type.init(InternPool.well_known.s64_type);
                return diag.failAt(ast.tokens[ast.data(node).rhs].start, "unsupported type table field '{s}'", .{field_name});
            }
            if (lhs_ty.index == InternPool.well_known.type_info_type) {
                const field_name = ast.tokenSlice(ast.data(node).rhs);
                if (std.mem.eql(u8, field_name, "type") or std.mem.eql(u8, field_name, "runtime_size")) break :blk Type.init(InternPool.well_known.s64_type);
                return diag.failAt(ast.tokens[ast.data(node).rhs].start, "unsupported type info field '{s}'", .{field_name});
            }
            break :blk lhs_ty;
        },
        .call_expr => blk: {
            const callee = ast.data(node).lhs;
            if (ast.tag(callee) != .identifier) return diag.failAt(ast.tokens[ast.mainToken(callee)].start, "Phase 1 only supports calls by identifier", .{});
            const name = ast.tokenSlice(ast.mainToken(callee));
            const args = ast.extraSlice(ast.data(node).rhs);
            if (resolved.overloads(name)) |candidates| {
                const selected = try selectOverload(ast, candidates, args.len, diag, node);
                return try analyzeProcCall(ast, resolved, typed, selected, args, diag, node);
            }
            if (resolved.local_values.get(callee)) |decl| {
                if (ast.tag(decl) == .proc_decl) {
                    return try analyzeProcCall(ast, resolved, typed, decl, args, diag, node);
                }
            }
            const sym = resolved.lookup(name) orelse {
                if (resolved.local_values.get(callee)) |decl| {
                    if (ast.tag(decl) == .var_decl and ast.data(decl).lhs != @import("Ast.zig").null_node and ast.tag(ast.data(decl).lhs) == .proc_type) {
                        for (args) |arg| _ = try analyzeNode(ast, resolved, typed, @intCast(arg), diag);
                        break :blk Type.init(InternPool.well_known.s64_type);
                    }
                }
                return diag.failAt(ast.tokens[ast.mainToken(callee)].start, "unresolved identifier '{s}'", .{name});
            };
            switch (sym) {
                .proc => |proc_node| {
                    const selected = if (resolved.overloads(name)) |candidates| try selectOverload(ast, candidates, args.len, diag, node) else proc_node;
                    return try analyzeProcCall(ast, resolved, typed, selected, args, diag, node);
                },
                else => {},
            }
            if (std.mem.eql(u8, name, "print")) switch (sym) {
                .builtin_print => {
                    if (args.len == 0) return diag.failAt(ast.tokens[ast.mainToken(node)].start, "print expects at least one argument", .{});
                    const fmt_ty = try analyzeNode(ast, resolved, typed, @intCast(args[0]), diag);
                    _ = fmt_ty;
                    for (args[1..]) |arg| {
                        const arg_ty = try analyzeNode(ast, resolved, typed, @intCast(arg), diag);
                        if (arg_ty.isAny() or !(arg_ty.isString() or arg_ty.isInteger() or arg_ty.index == InternPool.well_known.float32_type or arg_ty.index == InternPool.well_known.float64_type or arg_ty.isBool() or arg_ty.isVoid() or arg_ty.isPointer() or arg_ty.index == InternPool.well_known.type_type)) return diag.failAt(ast.tokens[ast.mainToken(@intCast(arg))].start, "Phase 3 print supports string, integer, float, bool, void, pointer, and type arguments", .{});
                    }
                    break :blk Type.voidType();
                },
                .proc => return diag.failAt(ast.tokens[ast.mainToken(node)].start, "Phase 1 only supports calling Basic.print", .{}),
                .builtin_swap, .builtin_write_string, .builtin_write_strings, .builtin_write_number, .builtin_write_nonnegative_number, .builtin_new, .builtin_free, .builtin_exit, .builtin_memcpy, .builtin_assert, .builtin_sin, .builtin_current_time_consensus, .builtin_current_time_monotonic, .builtin_to_calendar, .builtin_calendar_to_string, .builtin_random_seed, .builtin_random_get, .builtin_random_get_zero_to_one, .builtin_random_get_within_range, .builtin_format_int, .builtin_format_float, .builtin_get_type_table => return diag.failAt(ast.tokens[ast.mainToken(node)].start, "internal resolver mismatch for print", .{}),
                .const_value => return diag.failAt(ast.tokens[ast.mainToken(callee)].start, "constant value is not callable", .{}),
            } else if (std.mem.eql(u8, name, "swap")) switch (sym) {
                .builtin_swap => {
                    if (args.len != 2) return diag.failAt(ast.tokens[ast.mainToken(node)].start, "swap expects exactly two arguments", .{});
                    const lhs = @as(NodeIndex, @intCast(args[0]));
                    const rhs = @as(NodeIndex, @intCast(args[1]));
                    try validateSwapAddressArg(ast, resolved, lhs, diag);
                    try validateSwapAddressArg(ast, resolved, rhs, diag);
                    break :blk Type.voidType();
                },
                .builtin_print, .builtin_write_string, .builtin_write_strings, .builtin_write_number, .builtin_write_nonnegative_number, .builtin_new, .builtin_free, .builtin_exit, .builtin_memcpy, .builtin_assert, .builtin_sin, .builtin_current_time_consensus, .builtin_current_time_monotonic, .builtin_to_calendar, .builtin_calendar_to_string, .builtin_random_seed, .builtin_random_get, .builtin_random_get_zero_to_one, .builtin_random_get_within_range, .builtin_format_int, .builtin_format_float, .builtin_get_type_table => return diag.failAt(ast.tokens[ast.mainToken(node)].start, "internal resolver mismatch for swap", .{}),
                .proc => return diag.failAt(ast.tokens[ast.mainToken(node)].start, "Phase 2 only supports builtin Basic.swap", .{}),
                .const_value => return diag.failAt(ast.tokens[ast.mainToken(callee)].start, "constant value is not callable", .{}),
            } else if (std.mem.eql(u8, name, "New")) switch (sym) {
                .builtin_new => {
                    if (args.len != 1) return diag.failAt(ast.tokens[ast.mainToken(node)].start, "New expects one type argument", .{});
                    const arg: NodeIndex = @intCast(args[0]);
                    const pointed = try typeFromTypeExpr(ast, arg, diag);
                    break :blk Type.init(try internPointerType(ast, pointed, diag));
                },
                else => return diag.failAt(ast.tokens[ast.mainToken(callee)].start, "internal resolver mismatch for New", .{}),
            } else if (std.mem.eql(u8, name, "free")) switch (sym) {
                .builtin_free => {
                    if (args.len != 1) return diag.failAt(ast.tokens[ast.mainToken(node)].start, "free expects one pointer argument", .{});
                    _ = try analyzeNode(ast, resolved, typed, @intCast(args[0]), diag);
                    break :blk Type.voidType();
                },
                else => return diag.failAt(ast.tokens[ast.mainToken(callee)].start, "internal resolver mismatch for free", .{}),
            } else if (std.mem.eql(u8, name, "write_string") or std.mem.eql(u8, name, "write_strings") or std.mem.eql(u8, name, "write_number") or std.mem.eql(u8, name, "write_nonnegative_number")) switch (sym) {
                .builtin_write_string, .builtin_write_strings, .builtin_write_number, .builtin_write_nonnegative_number => {
                    for (args) |arg| _ = try analyzeNode(ast, resolved, typed, @intCast(arg), diag);
                    break :blk Type.voidType();
                },
                .builtin_new, .builtin_free => return diag.failAt(ast.tokens[ast.mainToken(callee)].start, "internal resolver mismatch for write builtin", .{}),
                else => return diag.failAt(ast.tokens[ast.mainToken(callee)].start, "internal resolver mismatch for write builtin", .{}),
            } else if (std.mem.eql(u8, name, "assert")) switch (sym) {
                .builtin_assert => {
                    if (args.len < 1 or args.len > 2) return diag.failAt(ast.tokens[ast.mainToken(node)].start, "assert expects a condition and optional message", .{});
                    const cond_ty = try analyzeNode(ast, resolved, typed, @intCast(args[0]), diag);
                    if (!cond_ty.isBool()) return diag.failAt(ast.tokens[ast.mainToken(@intCast(args[0]))].start, "assert condition must be bool", .{});
                    if (args.len == 2) {
                        const msg_ty = try analyzeNode(ast, resolved, typed, @intCast(args[1]), diag);
                        if (!msg_ty.isString()) return diag.failAt(ast.tokens[ast.mainToken(@intCast(args[1]))].start, "assert message must be a string", .{});
                    }
                    break :blk Type.voidType();
                },
                else => return diag.failAt(ast.tokens[ast.mainToken(callee)].start, "internal resolver mismatch for assert", .{}),
            } else if (std.mem.eql(u8, name, "memcpy")) switch (sym) {
                .builtin_memcpy => {
                    if (args.len != 3) return diag.failAt(ast.tokens[ast.mainToken(node)].start, "memcpy expects destination, source, and byte count", .{});
                    const dst_ty = try analyzeNode(ast, resolved, typed, @intCast(args[0]), diag);
                    const src_ty = try analyzeNode(ast, resolved, typed, @intCast(args[1]), diag);
                    const count_ty = try analyzeNode(ast, resolved, typed, @intCast(args[2]), diag);
                    if (!dst_ty.isPointer() or !src_ty.isPointer()) return diag.failAt(ast.tokens[ast.mainToken(node)].start, "memcpy destination and source must be pointers", .{});
                    if (!count_ty.isInteger()) return diag.failAt(ast.tokens[ast.mainToken(@intCast(args[2]))].start, "memcpy byte count must be an integer", .{});
                    break :blk Type.voidType();
                },
                else => return diag.failAt(ast.tokens[ast.mainToken(callee)].start, "internal resolver mismatch for memcpy", .{}),
            } else if (std.mem.eql(u8, name, "exit")) switch (sym) {
                .builtin_exit => {
                    if (args.len != 1) return diag.failAt(ast.tokens[ast.mainToken(node)].start, "exit expects one integer status argument", .{});
                    const arg_ty = try analyzeNode(ast, resolved, typed, @intCast(args[0]), diag);
                    if (!arg_ty.isInteger()) return diag.failAt(ast.tokens[ast.mainToken(@intCast(args[0]))].start, "exit status must be an integer", .{});
                    break :blk Type.voidType();
                },
                else => return diag.failAt(ast.tokens[ast.mainToken(callee)].start, "internal resolver mismatch for exit", .{}),
            } else if (std.mem.eql(u8, name, "sin")) switch (sym) {
                .builtin_sin => {
                    if (args.len != 1) return diag.failAt(ast.tokens[ast.mainToken(node)].start, "sin expects one argument", .{});
                    _ = try analyzeNode(ast, resolved, typed, @intCast(args[0]), diag);
                    break :blk Type.init(InternPool.well_known.float32_type);
                },
                else => return diag.failAt(ast.tokens[ast.mainToken(callee)].start, "internal resolver mismatch for sin", .{}),
            } else if (std.mem.eql(u8, name, "formatInt")) switch (sym) {
                .builtin_format_int => {
                    if (args.len < 1) return diag.failAt(ast.tokens[ast.mainToken(node)].start, "formatInt expects an integer value", .{});
                    const value_ty = try analyzeNode(ast, resolved, typed, @intCast(args[0]), diag);
                    if (!value_ty.isInteger()) return diag.failAt(ast.tokens[ast.mainToken(@intCast(args[0]))].start, "formatInt value must be an integer", .{});
                    for (args[1..]) |arg_idx| {
                        const arg: NodeIndex = @intCast(arg_idx);
                        if (ast.tag(arg) != .assign_stmt) return diag.failAt(ast.tokens[ast.mainToken(arg)].start, "formatInt options must be named arguments", .{});
                        const option_name = ast.tokenSlice(ast.mainToken(ast.data(arg).lhs));
                        if (!std.mem.eql(u8, option_name, "base") and !std.mem.eql(u8, option_name, "minimum_digits")) return diag.failAt(ast.tokens[ast.mainToken(ast.data(arg).lhs)].start, "unsupported formatInt option '{s}'", .{option_name});
                        const option_ty = try analyzeNode(ast, resolved, typed, ast.data(arg).rhs, diag);
                        if (!option_ty.isInteger()) return diag.failAt(ast.tokens[ast.mainToken(ast.data(arg).rhs)].start, "formatInt option '{s}' must be an integer", .{option_name});
                    }
                    break :blk Type.string();
                },
                else => return diag.failAt(ast.tokens[ast.mainToken(callee)].start, "internal resolver mismatch for formatInt", .{}),
            } else if (std.mem.eql(u8, name, "formatFloat")) switch (sym) {
                .builtin_format_float => {
                    if (args.len < 1) return diag.failAt(ast.tokens[ast.mainToken(node)].start, "formatFloat expects a numeric value", .{});
                    const value_ty = try analyzeNode(ast, resolved, typed, @intCast(args[0]), diag);
                    if (!(value_ty.isFloat() or value_ty.isInteger())) return diag.failAt(ast.tokens[ast.mainToken(@intCast(args[0]))].start, "formatFloat value must be numeric", .{});
                    for (args[1..]) |arg_idx| {
                        const arg: NodeIndex = @intCast(arg_idx);
                        if (ast.tag(arg) != .assign_stmt) return diag.failAt(ast.tokens[ast.mainToken(arg)].start, "formatFloat options must be named arguments", .{});
                        const option_name = ast.tokenSlice(ast.mainToken(ast.data(arg).lhs));
                        if (!std.mem.eql(u8, option_name, "width") and !std.mem.eql(u8, option_name, "trailing_width") and !std.mem.eql(u8, option_name, "zero_removal") and !std.mem.eql(u8, option_name, "mode")) return diag.failAt(ast.tokens[ast.mainToken(ast.data(arg).lhs)].start, "unsupported formatFloat option '{s}'", .{option_name});
                        if (std.mem.eql(u8, option_name, "width") or std.mem.eql(u8, option_name, "trailing_width")) {
                            const option_ty = try analyzeNode(ast, resolved, typed, ast.data(arg).rhs, diag);
                            if (!option_ty.isInteger()) return diag.failAt(ast.tokens[ast.mainToken(ast.data(arg).rhs)].start, "formatFloat option '{s}' must be an integer", .{option_name});
                        }
                    }
                    break :blk Type.string();
                },
                else => return diag.failAt(ast.tokens[ast.mainToken(callee)].start, "internal resolver mismatch for formatFloat", .{}),
            } else if (std.mem.eql(u8, name, "current_time_consensus")) switch (sym) {
                .builtin_current_time_consensus => {
                    if (args.len != 0) return diag.failAt(ast.tokens[ast.mainToken(node)].start, "current_time_consensus expects no arguments", .{});
                    break :blk Type.apolloTime();
                },
                else => return diag.failAt(ast.tokens[ast.mainToken(callee)].start, "internal resolver mismatch for current_time_consensus", .{}),
            } else if (std.mem.eql(u8, name, "current_time_monotonic")) switch (sym) {
                .builtin_current_time_monotonic => {
                    if (args.len != 0) return diag.failAt(ast.tokens[ast.mainToken(node)].start, "current_time_monotonic expects no arguments", .{});
                    break :blk Type.apolloTime();
                },
                else => return diag.failAt(ast.tokens[ast.mainToken(callee)].start, "internal resolver mismatch for current_time_monotonic", .{}),
            } else if (std.mem.eql(u8, name, "to_calendar")) switch (sym) {
                .builtin_to_calendar => {
                    if (args.len != 2) return diag.failAt(ast.tokens[ast.mainToken(node)].start, "to_calendar expects Apollo_Time and timezone arguments", .{});
                    const time_ty = try analyzeNode(ast, resolved, typed, @intCast(args[0]), diag);
                    if (time_ty.index != InternPool.well_known.apollo_time_type) return diag.failAt(ast.tokens[ast.mainToken(@intCast(args[0]))].start, "to_calendar first argument must be Apollo_Time", .{});
                    try validateTimezoneLiteral(ast, @intCast(args[1]), diag);
                    break :blk Type.calendar();
                },
                else => return diag.failAt(ast.tokens[ast.mainToken(callee)].start, "internal resolver mismatch for to_calendar", .{}),
            } else if (std.mem.eql(u8, name, "calendar_to_string")) switch (sym) {
                .builtin_calendar_to_string => {
                    if (args.len != 1) return diag.failAt(ast.tokens[ast.mainToken(node)].start, "calendar_to_string expects one Calendar argument", .{});
                    const calendar_ty = try analyzeNode(ast, resolved, typed, @intCast(args[0]), diag);
                    if (calendar_ty.index != InternPool.well_known.calendar_type) return diag.failAt(ast.tokens[ast.mainToken(@intCast(args[0]))].start, "calendar_to_string argument must be Calendar", .{});
                    break :blk Type.string();
                },
                else => return diag.failAt(ast.tokens[ast.mainToken(callee)].start, "internal resolver mismatch for calendar_to_string", .{}),
            } else if (std.mem.eql(u8, name, "random_seed")) switch (sym) {
                .builtin_random_seed => {
                    if (args.len != 1) return diag.failAt(ast.tokens[ast.mainToken(node)].start, "random_seed expects one integer seed", .{});
                    const seed_ty = try analyzeNode(ast, resolved, typed, @intCast(args[0]), diag);
                    if (!seed_ty.isInteger()) return diag.failAt(ast.tokens[ast.mainToken(@intCast(args[0]))].start, "random_seed seed must be an integer", .{});
                    break :blk Type.voidType();
                },
                else => return diag.failAt(ast.tokens[ast.mainToken(callee)].start, "internal resolver mismatch for random_seed", .{}),
            } else if (std.mem.eql(u8, name, "random_get")) switch (sym) {
                .builtin_random_get => {
                    if (args.len != 0) return diag.failAt(ast.tokens[ast.mainToken(node)].start, "random_get expects no arguments", .{});
                    break :blk Type.init(InternPool.well_known.u64_type);
                },
                else => return diag.failAt(ast.tokens[ast.mainToken(callee)].start, "internal resolver mismatch for random_get", .{}),
            } else if (std.mem.eql(u8, name, "random_get_zero_to_one")) switch (sym) {
                .builtin_random_get_zero_to_one => {
                    if (args.len != 0) return diag.failAt(ast.tokens[ast.mainToken(node)].start, "random_get_zero_to_one expects no arguments", .{});
                    break :blk Type.init(InternPool.well_known.float64_type);
                },
                else => return diag.failAt(ast.tokens[ast.mainToken(callee)].start, "internal resolver mismatch for random_get_zero_to_one", .{}),
            } else if (std.mem.eql(u8, name, "random_get_within_range")) switch (sym) {
                .builtin_random_get_within_range => {
                    if (args.len != 2) return diag.failAt(ast.tokens[ast.mainToken(node)].start, "random_get_within_range expects min and max", .{});
                    const min_ty = try analyzeNode(ast, resolved, typed, @intCast(args[0]), diag);
                    const max_ty = try analyzeNode(ast, resolved, typed, @intCast(args[1]), diag);
                    if (!(min_ty.isInteger() or min_ty.isFloat()) or !(max_ty.isInteger() or max_ty.isFloat())) return diag.failAt(ast.tokens[ast.mainToken(node)].start, "random_get_within_range bounds must be numeric", .{});
                    break :blk Type.init(InternPool.well_known.float64_type);
                },
                else => return diag.failAt(ast.tokens[ast.mainToken(callee)].start, "internal resolver mismatch for random_get_within_range", .{}),
            } else if (std.mem.eql(u8, name, "get_type_table")) switch (sym) {
                .builtin_get_type_table => {
                    if (args.len != 0) return diag.failAt(ast.tokens[ast.mainToken(node)].start, "get_type_table expects no arguments", .{});
                    break :blk Type.init(InternPool.well_known.type_table_type);
                },
                else => return diag.failAt(ast.tokens[ast.mainToken(callee)].start, "internal resolver mismatch for get_type_table", .{}),
            } else return diag.failAt(ast.tokens[ast.mainToken(callee)].start, "Phase 2 only supports builtin print, swap, and low-level write calls", .{});
        },
        // Bare block: anonymous scope.
        .block => blk: {
            try analyzeBlock(ast, resolved, typed, node, diag);
            break :blk Type.voidType();
        },
        else => return diag.failAt(ast.tokens[ast.mainToken(node)].start, "unsupported AST node in semantic analysis", .{}),
    };
    typed.node_types[node] = ty;
    return ty;
}

const ProcSig = struct { params_extra: u32, return_type: NodeIndex };
fn procSignature(ast: *const Ast, proc: NodeIndex) ?ProcSig {
    if (ast.data(proc).rhs == 0) return null;
    const sig = ast.extraSlice(ast.data(proc).rhs);
    if (sig.len < 2) return null;
    return .{ .params_extra = sig[0], .return_type = sig[1] };
}

fn selectOverload(ast: *const Ast, candidates: []const NodeIndex, arg_count: usize, diag: Diagnostic, call_node: NodeIndex) !NodeIndex {
    var variadic_match: ?NodeIndex = null;
    for (candidates) |candidate| {
        const sig = procSignature(ast, candidate) orelse {
            if (arg_count == 0) return candidate;
            continue;
        };
        const params = ast.extraSlice(sig.params_extra);
        if (params.len == arg_count and !lastParamIsVariadic(ast, params)) return candidate;
        if (lastParamIsVariadic(ast, params) and arg_count >= params.len - 1 and variadic_match == null) variadic_match = candidate;
    }
    if (variadic_match) |candidate| return candidate;
    return diag.failAt(ast.tokens[ast.mainToken(call_node)].start, "no overload accepts {d} arguments", .{arg_count});
}

fn lastParamIsVariadic(ast: *const Ast, params: []const u32) bool {
    if (params.len == 0) return false;
    const last: NodeIndex = @intCast(params[params.len - 1]);
    return ast.tag(last) == .var_decl and ast.data(last).rhs == 1;
}

fn analyzeProcCall(ast: *const Ast, resolved: *const Resolved, typed: *Typed, proc_node: NodeIndex, args: []const u32, diag: Diagnostic, call_node: NodeIndex) anyerror!Type {
    const sig = procSignature(ast, proc_node);
    const params = if (sig) |s| ast.extraSlice(s.params_extra) else &[_]u32{};
    const variadic = lastParamIsVariadic(ast, params);
    if ((!variadic and args.len != params.len) or (variadic and args.len < params.len - 1)) return diag.failAt(ast.tokens[ast.mainToken(call_node)].start, "procedure overload expects {d}{s} arguments, got {d}", .{ params.len, if (variadic) " or more" else "", args.len });
    var inferred = std.ArrayList(NodeIndex).empty;
    defer inferred.deinit(typed.allocator);
    for (args, 0..) |arg, i| {
        const arg_node: NodeIndex = @intCast(arg);
        if (ast.tag(arg_node) == .unary_expr and ast.tokens[ast.mainToken(arg_node)].tag == .dot_dot) return diag.failAt(ast.tokens[ast.mainToken(arg_node)].start, "spread '..' argument lowering is not implemented in this Phase 4 slice", .{});
        const arg_ty = if (ast.tag(arg_node) == .assign_stmt) try analyzeNode(ast, resolved, typed, ast.data(arg_node).rhs, diag) else try analyzeNode(ast, resolved, typed, arg_node, diag);
        if (i < params.len) {
            const param: NodeIndex = @intCast(params[i]);
            if (ast.data(param).lhs == @import("Ast.zig").null_node) {
                try typed.inferred_param_types.put(typed.allocator, param, arg_ty);
                try inferred.append(typed.allocator, param);
            }
        }
    }
    if (sig) |s| if (s.return_type == @import("Ast.zig").null_node) try analyzeBlock(ast, resolved, typed, ast.data(proc_node).lhs, diag);
    for (inferred.items) |param| _ = typed.inferred_param_types.remove(param);
    return if (sig) |s| if (s.return_type == @import("Ast.zig").null_node) Type.init(InternPool.well_known.s64_type) else try typeFromTypeExpr(ast, s.return_type, diag) else Type.voidType();
}

fn isCalendarField(name: []const u8) bool {
    return std.mem.eql(u8, name, "year") or
        std.mem.eql(u8, name, "month_starting_at_0") or
        std.mem.eql(u8, name, "day_of_month_starting_at_0") or
        std.mem.eql(u8, name, "day_of_week_starting_at_0") or
        std.mem.eql(u8, name, "hour") or
        std.mem.eql(u8, name, "minute") or
        std.mem.eql(u8, name, "second") or
        std.mem.eql(u8, name, "millisecond") or
        std.mem.eql(u8, name, "time_zone");
}

fn validateTimezoneLiteral(ast: *const Ast, node: NodeIndex, diag: Diagnostic) !void {
    if (ast.tag(node) != .field_access or ast.data(node).lhs != @import("Ast.zig").null_node) return diag.failAt(ast.tokens[ast.mainToken(node)].start, "timezone argument must be .UTC or .LOCAL", .{});
    const name = ast.tokenSlice(ast.data(node).rhs);
    if (!std.mem.eql(u8, name, "UTC") and !std.mem.eql(u8, name, "LOCAL")) return diag.failAt(ast.tokens[ast.data(node).rhs].start, "unsupported timezone literal '.{s}'", .{name});
}

fn validateSwapAddressArg(ast: *const Ast, resolved: *const Resolved, node: NodeIndex, diag: Diagnostic) !void {
    if (ast.tag(node) != .unary_expr or ast.tokens[ast.mainToken(node)].tag != .star) return diag.failAt(ast.tokens[ast.mainToken(node)].start, "swap arguments must be address-of local variables (*name)", .{});
    const operand = ast.data(node).lhs;
    if (ast.tag(operand) != .identifier) return diag.failAt(ast.tokens[ast.mainToken(operand)].start, "swap address argument must name a local variable", .{});
    const decl = resolved.local_values.get(operand) orelse return diag.failAt(ast.tokens[ast.mainToken(operand)].start, "swap address argument must refer to a local variable", .{});
    if (ast.tag(decl) != .var_decl) return diag.failAt(ast.tokens[ast.mainToken(operand)].start, "swap address argument must refer to a mutable local variable", .{});
}

fn isBuiltinTypeName(name: []const u8) bool {
    return std.mem.eql(u8, name, "void") or std.mem.eql(u8, name, "bool") or std.mem.eql(u8, name, "string") or std.mem.eql(u8, name, "int") or std.mem.eql(u8, name, "s64") or std.mem.eql(u8, name, "float") or std.mem.eql(u8, name, "float32") or std.mem.eql(u8, name, "float64") or std.mem.eql(u8, name, "s32") or std.mem.eql(u8, name, "u8") or std.mem.eql(u8, name, "u16") or std.mem.eql(u8, name, "u32") or std.mem.eql(u8, name, "u64") or std.mem.eql(u8, name, "Vector3") or std.mem.eql(u8, name, "Type") or std.mem.eql(u8, name, "Any");
}

fn typeFromTypeExpr(ast: *const Ast, node: NodeIndex, diag: Diagnostic) !Type {
    return typeFromTypeExprWithAliases(ast, null, node, diag);
}

fn typeFromTypeExprWithAliases(ast: *const Ast, typed: ?*Typed, node: NodeIndex, diag: Diagnostic) !Type {
    if (node == @import("Ast.zig").null_node) return Type.voidType();
    if (ast.tag(node) == .type_expr and typed != null) {
        const name = ast.tokenSlice(ast.mainToken(node));
        if (typed.?.type_aliases.get(name)) |alias_ty| return alias_ty;
    }
    if (ast.tag(node) == .pointer_type) return Type.init(try internPointerType(ast, try typeFromTypeExprWithAliases(ast, typed, ast.data(node).lhs, diag), diag));
    if (ast.tag(node) == .proc_type) return Type.init(try internProcType(ast, node, diag));
    if (ast.tag(node) == .type_of_expr) return Type.init(InternPool.well_known.s64_type);
    if (ast.tag(node) != .type_expr) return diag.failAt(ast.tokens[ast.mainToken(node)].start, "expected type expression", .{});
    const name = ast.tokenSlice(ast.mainToken(node));
    if (std.mem.eql(u8, name, "void")) return Type.voidType();
    if (std.mem.eql(u8, name, "bool")) return Type.boolType();
    if (std.mem.eql(u8, name, "string")) return Type.string();
    if (std.mem.eql(u8, name, "int") or std.mem.eql(u8, name, "s64")) return Type.init(InternPool.well_known.s64_type);
    if (std.mem.eql(u8, name, "float") or std.mem.eql(u8, name, "float32")) return Type.init(InternPool.well_known.float32_type);
    if (std.mem.eql(u8, name, "float64")) return Type.init(InternPool.well_known.float64_type);
    if (std.mem.eql(u8, name, "s32")) return Type.init(InternPool.well_known.s32_type);
    if (std.mem.eql(u8, name, "u8")) return Type.init(InternPool.well_known.u8_type);
    if (std.mem.eql(u8, name, "u16")) return Type.init(InternPool.well_known.u16_type);
    if (std.mem.eql(u8, name, "u32")) return Type.init(InternPool.well_known.u32_type);
    if (std.mem.eql(u8, name, "u64")) return Type.init(InternPool.well_known.u64_type);
    if (std.mem.eql(u8, name, "Type")) return Type.init(InternPool.well_known.type_type);
    if (std.mem.eql(u8, name, "Any")) return Type.init(InternPool.well_known.any_type);
    if (std.mem.eql(u8, name, "Vector3")) return Type.init(InternPool.well_known.vector3_type);
    return diag.failAt(ast.tokens[ast.mainToken(node)].start, "unknown Phase 2 type '{s}'", .{name});
}

fn internPointerType(ast: *const Ast, child: Type, diag: Diagnostic) !@import("InternPool.zig").Index {
    const ip = active_ip orelse return diag.failAt(0, "internal error: pointer type interning without InternPool", .{});
    if (child.index == InternPool.well_known.type_type) return diag.failAt(0, "pointer-to-Type is not supported in this Phase 3 slice", .{});
    _ = ast;
    return ip.internPointerType(child.index);
}

fn internProcType(ast: *const Ast, proc_type: NodeIndex, diag: Diagnostic) !@import("InternPool.zig").Index {
    const ip = active_ip orelse return diag.failAt(0, "internal error: procedure type interning without InternPool", .{});
    _ = ast;
    return ip.internProcType(proc_type);
}
