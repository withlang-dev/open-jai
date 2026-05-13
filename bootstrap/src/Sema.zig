const std = @import("std");
const Ast = @import("Ast.zig").Ast;
const NodeIndex = @import("Ast.zig").NodeIndex;
const Diagnostic = @import("diagnostics.zig").Diagnostic;
const InternPool = @import("InternPool.zig").InternPool;
const Type = @import("Type.zig").Type;
const Resolved = @import("resolve.zig").Resolved;
const Symbol = @import("resolve.zig").Symbol;
const using_param_sentinel: u32 = 0xfffffffe;

var active_ip: ?*InternPool = null;

pub fn activeInternPoolForTypeQueries() ?*InternPool {
    return active_ip;
}

pub const Typed = struct {
    allocator: std.mem.Allocator,
    node_types: []Type,
    type_aliases: std.StringHashMapUnmanaged(Type) = .empty,
    proc_type_aliases: std.StringHashMapUnmanaged(void) = .empty,
    inferred_param_types: std.AutoHashMapUnmanaged(NodeIndex, Type) = .empty,
    comptime_ints: std.AutoHashMapUnmanaged(NodeIndex, i64) = .empty,
    comptime_floats: std.AutoHashMapUnmanaged(NodeIndex, f64) = .empty,
    comptime_strings: std.AutoHashMapUnmanaged(NodeIndex, []const u8) = .empty,
    owned_comptime_strings: std.ArrayList([]const u8) = .empty,
    comptime_bytes: std.AutoHashMapUnmanaged(NodeIndex, []const u8) = .empty,
    owned_comptime_bytes: std.ArrayList([]const u8) = .empty,
    comptime_source_locations: std.AutoHashMapUnmanaged(NodeIndex, SourceLocationValue) = .empty,
    owned_source_location_paths: std.ArrayList([]const u8) = .empty,
    comptime_calendars: std.AutoHashMapUnmanaged(NodeIndex, CalendarValue) = .empty,
    main_proc: ?NodeIndex,

    pub fn deinit(t: *Typed) void {
        t.type_aliases.deinit(t.allocator);
        t.proc_type_aliases.deinit(t.allocator);
        t.inferred_param_types.deinit(t.allocator);
        t.comptime_ints.deinit(t.allocator);
        t.comptime_floats.deinit(t.allocator);
        t.comptime_strings.deinit(t.allocator);
        for (t.owned_comptime_strings.items) |value| t.allocator.free(value);
        t.owned_comptime_strings.deinit(t.allocator);
        t.comptime_bytes.deinit(t.allocator);
        for (t.owned_comptime_bytes.items) |value| t.allocator.free(value);
        t.owned_comptime_bytes.deinit(t.allocator);
        t.comptime_source_locations.deinit(t.allocator);
        for (t.owned_source_location_paths.items) |value| t.allocator.free(value);
        t.owned_source_location_paths.deinit(t.allocator);
        t.comptime_calendars.deinit(t.allocator);
        t.allocator.free(t.node_types);
    }

    pub fn typeOf(t: *const Typed, node: NodeIndex) Type {
        return t.node_types[node];
    }

    pub fn putComptimeString(t: *Typed, node: NodeIndex, value: []const u8) !void {
        const owned = try t.allocator.dupe(u8, value);
        errdefer t.allocator.free(owned);
        try t.owned_comptime_strings.append(t.allocator, owned);
        try t.comptime_strings.put(t.allocator, node, owned);
    }

    pub fn putComptimeBytes(t: *Typed, node: NodeIndex, value: []const u8) !void {
        const owned = try t.allocator.dupe(u8, value);
        errdefer t.allocator.free(owned);
        try t.owned_comptime_bytes.append(t.allocator, owned);
        try t.comptime_bytes.put(t.allocator, node, owned);
    }

    pub fn putComptimeSourceLocation(t: *Typed, node: NodeIndex, value: SourceLocationValue) !void {
        const owned_path = try t.allocator.dupe(u8, value.fully_pathed_filename);
        errdefer t.allocator.free(owned_path);
        try t.owned_source_location_paths.append(t.allocator, owned_path);
        try t.comptime_source_locations.put(t.allocator, node, .{
            .fully_pathed_filename = owned_path,
            .line_number = value.line_number,
        });
    }

    pub fn putComptimeCalendar(t: *Typed, node: NodeIndex, value: CalendarValue) !void {
        try t.comptime_calendars.put(t.allocator, node, value);
    }
};

pub const SourceLocationValue = struct {
    fully_pathed_filename: []const u8,
    line_number: i64,
};

pub const CalendarValue = struct {
    year: i64,
    month_starting_at_0: i64,
    day_of_month_starting_at_0: i64,
    day_of_week_starting_at_0: i64,
    hour: i64,
    minute: i64,
    second: i64,
    millisecond: i64,
    time_zone: i64,
};

pub fn analyze(allocator: std.mem.Allocator, ast: *const Ast, resolved: *const Resolved, ip: *InternPool, diag: Diagnostic) !Typed {
    active_ip = ip;
    defer active_ip = null;
    var typed = Typed{
        .allocator = allocator,
        .node_types = try allocator.alloc(Type, ast.node_tags.items.len),
        .main_proc = resolved.main_proc,
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
    if (resolved.require_main and main_count != 1) return diag.failAt(0, "expected exactly one main procedure", .{});
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
        } else if (ast.tag(stmt) == .const_decl and (ast.tag(ast.data(stmt).lhs) == .type_expr or ast.tag(ast.data(stmt).lhs) == .struct_type or ast.tag(ast.data(stmt).lhs) == .union_type or ast.tag(ast.data(stmt).lhs) == .enum_type or ast.tag(ast.data(stmt).lhs) == .array_type or ast.tag(ast.data(stmt).lhs) == .proc_type)) {
            const name = ast.tokenSlice(ast.mainToken(stmt));
            const ty = try typeFromTypeExprWithAliases(ast, typed, ast.data(stmt).lhs, diag);
            try typed.type_aliases.put(typed.allocator, name, ty);
            if (ty.isProcedure()) try typed.proc_type_aliases.put(typed.allocator, name, {});
            typed.node_types[stmt] = Type.init(InternPool.well_known.type_type);
            typed.node_types[ast.data(stmt).lhs] = Type.init(InternPool.well_known.type_type);
        }
    }
}

fn analyzeNode(ast: *const Ast, resolved: *const Resolved, typed: *Typed, node: NodeIndex, diag: Diagnostic) !Type {
    if (node == @import("Ast.zig").null_node or node >= ast.node_tags.items.len) return Type.voidType();
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
        .placeholder_decl => Type.init(InternPool.well_known.any_type),
        .assign_stmt => blk: {
            _ = try analyzeNode(ast, resolved, typed, ast.data(node).lhs, diag);
            _ = try analyzeNode(ast, resolved, typed, ast.data(node).rhs, diag);
            break :blk Type.voidType();
        },
        .type_expr => Type.init(InternPool.well_known.type_type),
        .import_decl, .load_decl => Type.init(InternPool.well_known.any_type),
        .struct_type, .union_type, .enum_type => Type.init(InternPool.well_known.type_type),
        .pointer_type => Type.init(try internPointerType(ast, try typeFromTypeExpr(ast, ast.data(node).lhs, diag), diag)),
        .array_type => Type.init(InternPool.well_known.any_type),
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
        .meta_expr => blk: {
            if (ast.data(node).lhs != @import("Ast.zig").null_node) {
                if (ast.tag(ast.data(node).lhs) == .block) {
                    try analyzeBlock(ast, resolved, typed, ast.data(node).lhs, diag);
                } else {
                    _ = try analyzeNode(ast, resolved, typed, ast.data(node).lhs, diag);
                }
            }
            if (ast.data(node).rhs != @import("Ast.zig").null_node) {
                break :blk try typeFromTypeExpr(ast, ast.data(node).rhs, diag);
            }
            break :blk Type.init(InternPool.well_known.any_type);
        },
        .meta_stmt => blk: {
            if (ast.data(node).lhs != @import("Ast.zig").null_node and ast.tag(ast.data(node).lhs) == .block) {
                try analyzeBlock(ast, resolved, typed, ast.data(node).lhs, diag);
            } else if (ast.data(node).lhs != @import("Ast.zig").null_node) {
                _ = try analyzeNode(ast, resolved, typed, ast.data(node).lhs, diag);
            }
            if (ast.data(node).rhs != @import("Ast.zig").null_node) {
                _ = try analyzeNode(ast, resolved, typed, ast.data(node).rhs, diag);
            }
            break :blk Type.voidType();
        },
        .run_expr => blk: {
            if (ast.tokens[ast.mainToken(node)].tag == .keyword_push_context) {
                _ = try analyzeNode(ast, resolved, typed, ast.data(node).rhs, diag);
                try analyzeBlock(ast, resolved, typed, ast.data(node).lhs, diag);
                break :blk Type.voidType();
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
                .shift_left, .dot_star => break :blk Type.init(InternPool.well_known.s64_type),
                .dot_dot => break :blk operand_ty,
                .minus => {
                    if (!(operand_ty.isInteger() or operand_ty.index == InternPool.well_known.float32_type or operand_ty.index == InternPool.well_known.float64_type)) {
                        return diag.failAt(ast.tokens[ast.mainToken(node)].start, "unary '-' requires a numeric operand", .{});
                    }
                    break :blk operand_ty;
                },
                .bang => {
                    // Allow ! on any bool-coercible type: bool, int, string, pointer.
                    if (!operand_ty.isBool() and !operand_ty.isInteger() and !operand_ty.isString() and !operand_ty.isPointer() and !operand_ty.isFloat() and !operand_ty.isAny()) {
                        return diag.failAt(ast.tokens[ast.mainToken(node)].start, "unary '!' requires a bool-coercible operand", .{});
                    }
                    break :blk Type.boolType();
                },
                .tilde => {
                    if (!operand_ty.isInteger() and operand_ty.index == InternPool.well_known.void_type) return diag.failAt(ast.tokens[ast.mainToken(node)].start, "unary '~' requires an integer operand", .{});
                    break :blk operand_ty;
                },
                .star => {
                    const operand = ast.data(node).lhs;
                    const pointee = try analyzeNode(ast, resolved, typed, operand, diag);
                    if (ast.tag(operand) == .identifier) {
                        const decl = resolved.local_values.get(operand) orelse @import("Ast.zig").null_node;
                        if (decl != @import("Ast.zig").null_node and ast.tag(decl) != .var_decl) return diag.failAt(ast.tokens[ast.mainToken(node)].start, "address-of '*' requires a mutable local variable", .{});
                    }
                    break :blk Type.init(try internPointerType(ast, pointee, diag));
                },
                .keyword_xx => {
                    if (operand_ty.isInteger() or operand_ty.isFloat() or operand_ty.isBool() or operand_ty.isString() or operand_ty.isPointer() or operand_ty.isAny()) break :blk operand_ty;
                    return diag.failAt(ast.tokens[ast.mainToken(node)].start, "xx autocast requires a cast-compatible operand", .{});
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
                    if (cast_ty.isInteger() and (operand_ty.isAny() or operand_ty.isPointer())) break :blk cast_ty;
                    if (cast_ty.isBool() and (operand_ty.isInteger() or operand_ty.isFloat() or operand_ty.isBool() or operand_ty.isString() or operand_ty.isPointer() or operand_ty.isAny())) break :blk cast_ty;
                    if (cast_ty.isAny()) break :blk cast_ty;
                    if (no_check and !cast_ty.isInteger()) return diag.failAt(ast.tokens[ast.mainToken(node)].start, "cast,no_check currently supports integer target types only", .{});
                    if (cast_ty.index == InternPool.well_known.float32_type or cast_ty.index == InternPool.well_known.float64_type) {
                        _ = try analyzeNode(ast, resolved, typed, operand, diag);
                        break :blk cast_ty;
                    }
                    if (ast.tag(target_ty) == .pointer_type and operand_ty.isInteger()) break :blk cast_ty;
                    if (ast.tag(target_ty) == .pointer_type and (operand_ty.isAny() or operand_ty.isPointer() or operand_ty.index == InternPool.well_known.type_type)) break :blk cast_ty;
                    if (ast.tag(target_ty) == .pointer_type and ast.tag(operand) == .identifier) {
                        const name = ast.tokenSlice(ast.mainToken(operand));
                        if (resolved.lookup(name)) |sym| switch (sym) {
                            .proc => break :blk Type.init(try internPointerType(ast, Type.voidType(), diag)),
                            else => {},
                        };
                    }
                    break :blk cast_ty;
                },
                else => return diag.failAt(ast.tokens[ast.mainToken(node)].start, "unsupported unary operator", .{}),
            }
        },
        .binary_expr => blk: {
            const lhs_ty = try analyzeNode(ast, resolved, typed, ast.data(node).lhs, diag);
            const rhs_ty = try analyzeNode(ast, resolved, typed, ast.data(node).rhs, diag);
            break :blk switch (ast.tokens[ast.mainToken(node)].tag) {
                .star, .plus, .minus, .slash, .plus_equal, .minus_equal, .star_equal, .slash_equal => {
                    if (ast.tokens[ast.mainToken(node)].tag == .minus and lhs_ty.index == InternPool.well_known.apollo_time_type and rhs_ty.index == InternPool.well_known.apollo_time_type) break :blk lhs_ty;
                    if (lhs_ty.isAny() or rhs_ty.isAny()) break :blk Type.init(InternPool.well_known.s64_type);
                    if (lhs_ty.isPointer() or rhs_ty.isPointer()) break :blk if (lhs_ty.isPointer()) lhs_ty else rhs_ty;
                    if (lhs_ty.index == InternPool.well_known.type_type or rhs_ty.index == InternPool.well_known.type_type or lhs_ty.index == InternPool.well_known.type_table_type or rhs_ty.index == InternPool.well_known.type_table_type) break :blk Type.init(InternPool.well_known.s64_type);
                    if (lhs_ty.isString() or rhs_ty.isString()) break :blk Type.init(InternPool.well_known.s64_type);
                    if (lhs_ty.isInteger() and rhs_ty.isInteger()) break :blk lhs_ty;
                    if ((lhs_ty.isInteger() or lhs_ty.isFloat()) and (rhs_ty.isInteger() or rhs_ty.isFloat())) break :blk if (lhs_ty.isFloat() or rhs_ty.isFloat()) Type.init(InternPool.well_known.float32_type) else lhs_ty;
                    break :blk Type.init(InternPool.well_known.any_type);
                },
                .percent => {
                    if ((lhs_ty.isInteger() and rhs_ty.isInteger()) or lhs_ty.isAny() or rhs_ty.isAny() or lhs_ty.isPointer() or rhs_ty.isPointer()) break :blk Type.init(InternPool.well_known.s64_type);
                    return diag.failAt(ast.tokens[ast.mainToken(node)].start, "'%' requires integer operands", .{});
                },
                .ampersand, .pipe, .caret, .shift_left, .shift_right, .shift_left_rotate, .shift_right_rotate, .ampersand_equal, .pipe_equal, .caret_equal => {
                    if ((lhs_ty.isInteger() and rhs_ty.isInteger()) or lhs_ty.isAny() or rhs_ty.isAny()) break :blk Type.init(InternPool.well_known.s64_type);
                    if (lhs_ty.index == rhs_ty.index and lhs_ty.index != InternPool.well_known.void_type) break :blk lhs_ty;
                    return diag.failAt(ast.tokens[ast.mainToken(node)].start, "bitwise operator requires integer operands", .{});
                },
                .equal_equal, .bang_equal, .keyword_case => {
                    break :blk Type.boolType();
                },
                .less_than, .less_equal, .greater_than, .greater_equal => {
                    if (lhs_ty.isAny() or rhs_ty.isAny() or lhs_ty.isPointer() or rhs_ty.isPointer() or lhs_ty.isString() or rhs_ty.isString()) break :blk Type.boolType();
                    if ((lhs_ty.isInteger() or lhs_ty.isFloat()) and (rhs_ty.isInteger() or rhs_ty.isFloat())) break :blk Type.boolType();
                    return diag.failAt(ast.tokens[ast.mainToken(node)].start, "comparison operator requires numeric operands", .{});
                },
                .ampersand_ampersand, .pipe_pipe, .pipe_pipe_equal => {
                    if ((lhs_ty.isBool() or lhs_ty.isInteger()) and (rhs_ty.isBool() or rhs_ty.isInteger())) break :blk Type.boolType();
                    break :blk Type.boolType();
                },
                else => return diag.failAt(ast.tokens[ast.mainToken(node)].start, "Phase 2 binary operator is not implemented yet", .{}),
            };
        },
        .proc_decl => Type.voidType(),
        .ifx_expr => blk: {
            const cond_ty = try analyzeNode(ast, resolved, typed, ast.data(node).lhs, diag);
            if (!cond_ty.isBool() and !cond_ty.isInteger() and !cond_ty.isFloat() and !cond_ty.isString() and !cond_ty.isPointer() and !cond_ty.isAny()) {
                return diag.failAt(ast.tokens[ast.mainToken(ast.data(node).lhs)].start, "ifx condition must be bool", .{});
            }
            const arms = ast.extraSlice(ast.data(node).rhs);
            if (arms.len != 2) return diag.failAt(ast.tokens[ast.mainToken(node)].start, "internal error: ifx requires then and else arms", .{});
            const then_ty = try analyzeNode(ast, resolved, typed, @intCast(arms[0]), diag);
            const else_ty = try analyzeNode(ast, resolved, typed, @intCast(arms[1]), diag);
            if (then_ty.index == else_ty.index) break :blk then_ty;
            if (then_ty.isAny() or else_ty.isAny()) break :blk Type.init(InternPool.well_known.any_type);
            if (then_ty.isInteger() and else_ty.isInteger()) break :blk Type.init(InternPool.well_known.s64_type);
            if ((then_ty.isBool() and (else_ty.isInteger() or else_ty.isFloat())) or
                (else_ty.isBool() and (then_ty.isInteger() or then_ty.isFloat())))
            {
                break :blk if (then_ty.isFloat() or else_ty.isFloat()) Type.init(InternPool.well_known.float32_type) else Type.init(InternPool.well_known.s64_type);
            }
            if ((then_ty.isInteger() or then_ty.isFloat()) and (else_ty.isInteger() or else_ty.isFloat())) break :blk if (then_ty.isFloat() or else_ty.isFloat()) Type.init(InternPool.well_known.float32_type) else Type.init(InternPool.well_known.s64_type);
            return diag.failAt(ast.tokens[ast.mainToken(node)].start, "ifx branch types are not compatible in this Phase 8 slice", .{});
        },
        .identifier => blk: {
            if (resolved.local_values.get(node)) |value_node| {
                if (value_node == @import("Ast.zig").null_node) break :blk Type.init(InternPool.well_known.any_type);
                if (resolved.loop_indexes.contains(value_node)) break :blk Type.init(InternPool.well_known.s64_type);
                if (resolved.loop_value_types.get(value_node)) |type_id| break :blk Type.init(type_id);
                break :blk switch (ast.tag(value_node)) {
                    .var_decl => if (ast.data(value_node).rhs == using_param_sentinel)
                        Type.init(InternPool.well_known.any_type)
                    else if (ast.data(value_node).lhs != @import("Ast.zig").null_node)
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
            if (std.mem.eql(u8, name, "OS")) break :blk Type.string();
            if (std.mem.eql(u8, name, "STDIN_FILENO") or std.mem.eql(u8, name, "STDOUT_FILENO") or std.mem.eql(u8, name, "STDERR_FILENO") or
                std.mem.eql(u8, name, "STD_INPUT_HANDLE") or std.mem.eql(u8, name, "STD_OUTPUT_HANDLE") or std.mem.eql(u8, name, "STD_ERROR_HANDLE"))
            {
                break :blk Type.init(InternPool.well_known.s64_type);
            }
            const sym = resolved.lookup(name) orelse blk_sym: {
                if (isBuiltinTypeName(name)) break :blk_sym Symbol{ .const_value = node };
                if (std.mem.indexOfScalar(u8, name, '_') != null) break :blk Type.init(InternPool.well_known.any_type);
                return diag.failAt(ast.tokens[ast.mainToken(node)].start, "unresolved identifier '{s}'", .{name});
            };
            break :blk switch (sym) {
                .placeholder => Type.init(InternPool.well_known.any_type),
                .builtin_print, .builtin_swap, .builtin_write_string, .builtin_write_strings, .builtin_write_number, .builtin_write_nonnegative_number, .builtin_new, .builtin_free, .builtin_exit, .builtin_memcpy, .builtin_memset, .builtin_assert, .builtin_sin, .builtin_random_seed, .builtin_to_calendar, .builtin_sleep_milliseconds, .builtin_file_close, .builtin_log, .builtin_init_string_builder, .builtin_free_buffers, .builtin_append, .builtin_print_to_builder, .builtin_reset_temporary_storage, .builtin_log_leak_report, .builtin_push_allocator => Type.voidType(),
                .builtin_new_array => Type.init(try internPointerType(ast, Type.init(InternPool.well_known.any_type), diag)),
                .builtin_calendar_to_string, .builtin_format_int, .builtin_format_float, .builtin_format_struct, .builtin_type_to_string, .builtin_compiler_arg, .builtin_compiler_read_file, .builtin_read_entire_file, .builtin_get_working_directory, .builtin_get_path_of_running_executable, .builtin_sprint, .builtin_tprint, .builtin_talloc_string, .builtin_to_string, .builtin_copy_string, .builtin_builder_to_string, .builtin_trim, .builtin_join, .builtin_replace, .builtin_slice, .builtin_path_strip_filename => Type.string(),
                .builtin_compiler_write_file, .builtin_write_entire_file, .builtin_make_directory_if_it_does_not_exist, .builtin_delete_directory, .builtin_file_exists, .builtin_set_working_directory, .builtin_visit_files, .builtin_file_set_position, .builtin_file_write, .builtin_file_read => Type.boolType(),
                .builtin_get_command_line_arguments, .builtin_get_cpu_info, .builtin_file_open, .builtin_string_builder_type, .builtin_split, .builtin_make_leak_report => Type.init(InternPool.well_known.any_type),
                .builtin_to_c_string => Type.init(try internPointerType(ast, Type.init(InternPool.well_known.u8_type), diag)),
                .builtin_check_feature, .builtin_contains, .builtin_begins_with => Type.boolType(),
                .builtin_file_length, .builtin_posix_read, .builtin_get_std_handle, .builtin_builder_string_length, .builtin_compare, .builtin_find_index_from_left, .builtin_find_index_from_right, .builtin_string_to_int, .builtin_parse_int, .builtin_to_integer, .builtin_c_style_strlen => Type.init(InternPool.well_known.s64_type),
                .builtin_string_to_float => Type.init(InternPool.well_known.float64_type),
                .builtin_compiler_arg_count => Type.init(InternPool.well_known.s64_type),
                .builtin_current_time_consensus, .builtin_current_time_monotonic => Type.apolloTime(),
                .builtin_get_time, .builtin_seconds_since_init, .builtin_to_float64_seconds => Type.init(InternPool.well_known.float64_type),
                .builtin_alloc => Type.init(InternPool.well_known.u64_type),
                .builtin_array_add, .builtin_array_free, .builtin_peek, .builtin_pop, .builtin_array_reset, .builtin_array_reserve, .builtin_array_ordered_remove_by_index, .builtin_array_copy => Type.init(InternPool.well_known.any_type),
                .builtin_array_find => Type.boolType(),
                .builtin_abs => Type.init(InternPool.well_known.float32_type),
                .builtin_to_upper, .builtin_to_lower => Type.init(InternPool.well_known.s64_type),
                .builtin_is_digit, .builtin_is_alpha, .builtin_is_alnum, .builtin_is_space, .builtin_is_any => Type.boolType(),
                .builtin_random_get => Type.init(InternPool.well_known.u64_type),
                .builtin_random_get_zero_to_one, .builtin_random_get_within_range => Type.init(InternPool.well_known.float64_type),
                .builtin_get_type_table => Type.init(InternPool.well_known.type_table_type),
                .builtin_get_field => Type.init(InternPool.well_known.any_type),
                .builtin_enum_range => Type.init(InternPool.well_known.any_type),
                .builtin_enum_values_as_s64, .builtin_enum_names => Type.init(InternPool.well_known.type_table_type),
                .proc => Type.voidType(),
                .const_value => |value_node| switch (ast.tag(value_node)) {
                    .import_decl, .load_decl => Type.init(InternPool.well_known.any_type),
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
            if (!cond_ty.isBool() and !cond_ty.isInteger() and !cond_ty.isString() and !cond_ty.isPointer() and !cond_ty.isFloat() and !cond_ty.isVoid() and !cond_ty.isAny()) {
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
            if (!cond_ty.isBool() and !cond_ty.isInteger() and !cond_ty.isString() and !cond_ty.isPointer() and !cond_ty.isFloat() and !cond_ty.isAny()) {
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
            if (operands.len == 4 and (operands[1] & 0x80000000) != 0) {
                const iterable = @as(NodeIndex, @intCast(operands[0]));
                _ = try analyzeNode(ast, resolved, typed, iterable, diag);
                try analyzeBlock(ast, resolved, typed, ast.data(node).rhs, diag);
            } else if (operands.len == 4 or (operands.len == 2 and (operands[1] & 0x80000000) == 0)) {
                // Range for: [start, end] or [start, end, iterator_tok, is_reverse]
                _ = try analyzeNode(ast, resolved, typed, @intCast(operands[0]), diag);
                _ = try analyzeNode(ast, resolved, typed, @intCast(operands[1]), diag);
                try analyzeBlock(ast, resolved, typed, ast.data(node).rhs, diag);
            } else if (operands.len == 1 or (operands.len == 2 and (operands[1] & 0x80000000) != 0) or operands.len == 3) {
                const iterable = @as(NodeIndex, @intCast(operands[0]));
                _ = try analyzeNode(ast, resolved, typed, iterable, diag);
                try analyzeBlock(ast, resolved, typed, ast.data(node).rhs, diag);
            } else return diag.failAt(ast.tokens[ast.mainToken(node)].start, "internal error: for statement has invalid operand count", .{});
            break :blk Type.voidType();
        },
        .aggregate_literal => blk: {
            for (ast.extraSlice(ast.data(node).lhs)) |elem_idx| {
                const elem: NodeIndex = @intCast(elem_idx);
                if (ast.tag(elem) == .assign_stmt)
                    _ = try analyzeNode(ast, resolved, typed, ast.data(elem).rhs, diag)
                else
                    _ = try analyzeNode(ast, resolved, typed, elem, diag);
            }
            break :blk Type.init(InternPool.well_known.any_type);
        },
        .typed_aggregate_literal => blk: {
            const payload = ast.extraSlice(ast.data(node).lhs);
            const type_node: NodeIndex = @intCast(payload[0]);
            const fields = ast.extraSlice(payload[1]);
            for (fields) |field_idx| {
                const field: NodeIndex = @intCast(field_idx);
                if (ast.tag(field) == .assign_stmt)
                    _ = try analyzeNode(ast, resolved, typed, ast.data(field).rhs, diag)
                else
                    _ = try analyzeNode(ast, resolved, typed, field, diag);
            }
            break :blk try typeFromTypeExprWithAliases(ast, typed, type_node, diag);
        },
        .typed_array_literal => blk: {
            const payload = ast.extraSlice(ast.data(node).lhs);
            const type_node: NodeIndex = @intCast(payload[0]);
            const elems = ast.extraSlice(payload[1]);
            for (elems) |elem| _ = try analyzeNode(ast, resolved, typed, @intCast(elem), diag);
            break :blk try typeFromTypeExprWithAliases(ast, typed, type_node, diag);
        },
        .field_access => blk: {
            if (ast.data(node).lhs == @import("Ast.zig").null_node) break :blk Type.init(InternPool.well_known.any_type);
            if (ast.data(node).lhs != @import("Ast.zig").null_node and ast.tag(ast.data(node).lhs) == .identifier and std.mem.eql(u8, ast.tokenSlice(ast.mainToken(ast.data(node).lhs)), "Type_Info_Tag")) break :blk Type.init(InternPool.well_known.s64_type);
            const lhs_ty = try analyzeNode(ast, resolved, typed, ast.data(node).lhs, diag);
            const field_name = ast.tokenSlice(ast.data(node).rhs);
            if (lhs_ty.isAny()) {
                if (std.mem.eql(u8, field_name, "value_pointer") or std.mem.eql(u8, field_name, "type")) break :blk Type.init(try internPointerType(ast, Type.voidType(), diag));
                if (std.mem.eql(u8, field_name, "members") or std.mem.eql(u8, field_name, "notes")) break :blk Type.init(InternPool.well_known.type_table_type);
                if (std.mem.eql(u8, field_name, "name")) break :blk Type.string();
                if (std.mem.eql(u8, field_name, "offset_in_bytes") or std.mem.eql(u8, field_name, "flags") or std.mem.eql(u8, field_name, "enum_type_flags") or std.mem.eql(u8, field_name, "runtime_size")) break :blk Type.init(InternPool.well_known.s64_type);
                break :blk Type.init(InternPool.well_known.any_type);
            }
            if (lhs_ty.isPointer()) {
                if (std.mem.eql(u8, field_name, "value_pointer")) break :blk Type.init(try internPointerType(ast, Type.voidType(), diag));
                if (std.mem.eql(u8, field_name, "type")) break :blk Type.init(InternPool.well_known.any_type);
                if (std.mem.eql(u8, field_name, "members") or std.mem.eql(u8, field_name, "notes")) break :blk Type.init(InternPool.well_known.type_table_type);
                if (std.mem.eql(u8, field_name, "name")) break :blk Type.string();
                if (std.mem.eql(u8, field_name, "offset_in_bytes") or std.mem.eql(u8, field_name, "flags") or std.mem.eql(u8, field_name, "enum_type_flags") or std.mem.eql(u8, field_name, "runtime_size")) break :blk Type.init(InternPool.well_known.s64_type);
                break :blk Type.init(InternPool.well_known.any_type);
            }
            if (lhs_ty.index == InternPool.well_known.type_type) {
                if (std.mem.eql(u8, field_name, "members") or std.mem.eql(u8, field_name, "notes")) break :blk Type.init(InternPool.well_known.type_table_type);
                if (std.mem.eql(u8, field_name, "name")) break :blk Type.string();
                if (std.mem.eql(u8, field_name, "type") or std.mem.eql(u8, field_name, "offset_in_bytes") or std.mem.eql(u8, field_name, "flags") or std.mem.eql(u8, field_name, "enum_type_flags") or std.mem.eql(u8, field_name, "runtime_size")) break :blk Type.init(InternPool.well_known.s64_type);
                break :blk Type.init(InternPool.well_known.s64_type);
            }
            if (lhs_ty.index == InternPool.well_known.apollo_time_type) {
                if (std.mem.eql(u8, field_name, "low")) break :blk Type.init(InternPool.well_known.u64_type);
                if (std.mem.eql(u8, field_name, "high")) break :blk Type.init(InternPool.well_known.s64_type);
                return diag.failAt(ast.tokens[ast.data(node).rhs].start, "unsupported Apollo_Time field '{s}'", .{field_name});
            }
            if (lhs_ty.index == InternPool.well_known.calendar_type) {
                if (isCalendarField(field_name)) break :blk Type.init(InternPool.well_known.s64_type);
                return diag.failAt(ast.tokens[ast.data(node).rhs].start, "unsupported Calendar field '{s}'", .{field_name});
            }
            if (std.mem.eql(u8, field_name, "count")) break :blk Type.init(InternPool.well_known.s64_type);
            if (std.mem.eql(u8, field_name, "data")) break :blk Type.init(try internPointerType(ast, Type.voidType(), diag));
            if (lhs_ty.index == InternPool.well_known.type_table_type) {
                if (std.mem.eql(u8, field_name, "count")) break :blk Type.init(InternPool.well_known.s64_type);
                break :blk Type.init(InternPool.well_known.any_type);
            }
            if (lhs_ty.index == InternPool.well_known.type_info_type) {
                if (std.mem.eql(u8, field_name, "type") or std.mem.eql(u8, field_name, "runtime_size")) break :blk Type.init(InternPool.well_known.s64_type);
                break :blk Type.init(InternPool.well_known.any_type);
            }
            break :blk lhs_ty;
        },
        .index_expr => blk: {
            _ = try analyzeNode(ast, resolved, typed, ast.data(node).rhs, diag);
            break :blk try analyzeNode(ast, resolved, typed, ast.data(node).lhs, diag);
        },
        .call_expr => blk: {
            const callee = ast.data(node).lhs;
            const args = ast.extraSlice(ast.data(node).rhs);
            if (ast.tag(callee) == .field_access) {
                const field_name = ast.tokenSlice(ast.data(callee).rhs);
                _ = try analyzeNode(ast, resolved, typed, ast.data(callee).lhs, diag);
                if (isImportAliasField(ast, resolved, callee)) {
                    if (try compilerIntrinsicReturnType(ast, field_name, diag)) |return_ty| {
                        for (args) |arg_idx| {
                            const arg: NodeIndex = @intCast(arg_idx);
                            if (ast.tag(arg) == .assign_stmt)
                                _ = try analyzeNode(ast, resolved, typed, ast.data(arg).rhs, diag)
                            else if (ast.tag(arg) == .binary_expr and ast.tokens[ast.mainToken(arg)].tag == .equal and ast.tag(ast.data(arg).lhs) == .identifier)
                                _ = try analyzeNode(ast, resolved, typed, ast.data(arg).rhs, diag)
                            else if (ast.tag(arg) == .unary_expr and ast.tokens[ast.mainToken(arg)].tag == .dot_dot)
                                _ = try analyzeNode(ast, resolved, typed, ast.data(arg).lhs, diag)
                            else
                                _ = try analyzeNode(ast, resolved, typed, arg, diag);
                        }
                        break :blk return_ty;
                    }
                    if (resolved.lookup(field_name)) |field_sym| switch (field_sym) {
                        .proc => |proc_node| return try analyzeProcCall(ast, resolved, typed, proc_node, args, diag, node),
                        .const_value => |value_node| {
                            if (isValidNode(ast, value_node) and ast.tag(value_node) == .proc_decl) return try analyzeProcCall(ast, resolved, typed, value_node, args, diag, node);
                        },
                        else => {},
                    };
                }
                for (args) |arg_idx| {
                    const arg: NodeIndex = @intCast(arg_idx);
                    if (ast.tag(arg) == .assign_stmt)
                        _ = try analyzeNode(ast, resolved, typed, ast.data(arg).rhs, diag)
                    else if (ast.tag(arg) == .unary_expr and ast.tokens[ast.mainToken(arg)].tag == .dot_dot)
                        _ = try analyzeNode(ast, resolved, typed, ast.data(arg).lhs, diag)
                    else
                        _ = try analyzeNode(ast, resolved, typed, arg, diag);
                }
                break :blk Type.init(InternPool.well_known.any_type);
            }
            if (ast.tag(callee) == .proc_decl) {
                for (args) |arg_idx| _ = try analyzeNode(ast, resolved, typed, @intCast(arg_idx), diag);
                const sig = ast.extraSlice(ast.data(callee).rhs);
                if (sig.len > 1 and sig[1] != @import("Ast.zig").null_node) {
                    break :blk try typeFromTypeExprWithAliases(ast, typed, @intCast(sig[1]), diag);
                }
                break :blk Type.voidType();
            }
            if (ast.tag(callee) != .identifier) return diag.failAt(ast.tokens[ast.mainToken(callee)].start, "Phase 1 only supports calls by identifier", .{});
            const name = ast.tokenSlice(ast.mainToken(callee));
            if (isOperatorIdentifierName(name)) {
                if (args.len != 1 and args.len != 2) return diag.failAt(ast.tokens[ast.mainToken(node)].start, "operator call expects one or two operands", .{});
                const lhs_ty = try analyzeNode(ast, resolved, typed, @intCast(args[0]), diag);
                if (args.len == 1) break :blk lhs_ty;
                const rhs_ty = try analyzeNode(ast, resolved, typed, @intCast(args[1]), diag);
                if (std.mem.eql(u8, name, "==") or std.mem.eql(u8, name, "!=") or std.mem.eql(u8, name, "<") or std.mem.eql(u8, name, "<=") or std.mem.eql(u8, name, ">") or std.mem.eql(u8, name, ">=")) break :blk Type.boolType();
                if (lhs_ty.isFloat() or rhs_ty.isFloat()) break :blk Type.init(InternPool.well_known.float32_type);
                if (lhs_ty.isInteger() and rhs_ty.isInteger()) break :blk lhs_ty;
                break :blk lhs_ty;
            }
            if (resolved.overloads(name)) |candidates| {
                const selected = try selectOverload(ast, candidates, args.len, diag, node);
                return try analyzeProcCall(ast, resolved, typed, selected, args, diag, node);
            }
            if (resolved.local_values.get(callee)) |decl| {
                if (decl == @import("Ast.zig").null_node) {
                    for (args) |arg| _ = try analyzeNode(ast, resolved, typed, callArgValueNode(ast, @intCast(arg)), diag);
                    break :blk Type.init(InternPool.well_known.any_type);
                }
                if (isValidNode(ast, decl) and ast.tag(decl) == .proc_decl) {
                    return try analyzeProcCall(ast, resolved, typed, decl, args, diag, node);
                }
                if (isValidNode(ast, decl) and ast.tag(decl) == .var_decl and ast.data(decl).rhs != @import("Ast.zig").null_node and isValidNode(ast, ast.data(decl).rhs) and ast.tag(ast.data(decl).rhs) == .proc_decl) {
                    return try analyzeProcCall(ast, resolved, typed, ast.data(decl).rhs, args, diag, node);
                }
                if (isValidNode(ast, decl) and ast.tag(decl) == .var_decl) {
                    const callee_ty = try analyzeNode(ast, resolved, typed, callee, diag);
                    if (callee_ty.isAny()) {
                        for (args) |arg| _ = try analyzeNode(ast, resolved, typed, callArgValueNode(ast, @intCast(arg)), diag);
                        break :blk Type.init(InternPool.well_known.any_type);
                    }
                    if (callee_ty.isProcedure()) {
                        for (args) |arg| _ = try analyzeNode(ast, resolved, typed, callArgValueNode(ast, @intCast(arg)), diag);
                        break :blk try procedureTypeReturnType(ast, typed, callee_ty, diag);
                    }
                }
            }
            const sym = resolved.lookup(name) orelse {
                if (resolved.local_values.get(callee)) |decl| {
                    if (decl == @import("Ast.zig").null_node) {
                        for (args) |arg| _ = try analyzeNode(ast, resolved, typed, callArgValueNode(ast, @intCast(arg)), diag);
                        break :blk Type.init(InternPool.well_known.any_type);
                    }
                    if (try varDeclHasProcedureType(ast, typed, decl, diag)) {
                        for (args) |arg| _ = try analyzeNode(ast, resolved, typed, callArgValueNode(ast, @intCast(arg)), diag);
                        const proc_ty = try typeFromTypeExprWithAliases(ast, typed, ast.data(decl).lhs, diag);
                        break :blk try procedureTypeReturnType(ast, typed, proc_ty, diag);
                    }
                }
                return diag.failAt(ast.tokens[ast.mainToken(callee)].start, "unresolved identifier '{s}'", .{name});
            };
            if (try compilerIntrinsicReturnType(ast, name, diag)) |return_ty| {
                for (args) |arg_idx| {
                    const arg_node: NodeIndex = @intCast(arg_idx);
                    if (ast.tag(arg_node) == .assign_stmt)
                        _ = try analyzeNode(ast, resolved, typed, ast.data(arg_node).rhs, diag)
                    else if (ast.tag(arg_node) == .binary_expr and ast.tokens[ast.mainToken(arg_node)].tag == .equal and ast.tag(ast.data(arg_node).lhs) == .identifier)
                        _ = try analyzeNode(ast, resolved, typed, ast.data(arg_node).rhs, diag)
                    else if (ast.tag(arg_node) == .unary_expr and ast.tokens[ast.mainToken(arg_node)].tag == .dot_dot)
                        _ = try analyzeNode(ast, resolved, typed, ast.data(arg_node).lhs, diag)
                    else
                        _ = try analyzeNode(ast, resolved, typed, arg_node, diag);
                }
                break :blk return_ty;
            }
            if (sym == .placeholder) {
                for (args) |arg| {
                    const arg_node: NodeIndex = @intCast(arg);
                    if (ast.tag(arg_node) == .assign_stmt)
                        _ = try analyzeNode(ast, resolved, typed, ast.data(arg_node).rhs, diag)
                    else if (ast.tag(arg_node) == .binary_expr and ast.tokens[ast.mainToken(arg_node)].tag == .equal and ast.tag(ast.data(arg_node).lhs) == .identifier)
                        _ = try analyzeNode(ast, resolved, typed, ast.data(arg_node).rhs, diag)
                    else if (ast.tag(arg_node) == .unary_expr and ast.tokens[ast.mainToken(arg_node)].tag == .dot_dot)
                        _ = try analyzeNode(ast, resolved, typed, ast.data(arg_node).lhs, diag)
                    else
                        _ = try analyzeNode(ast, resolved, typed, arg_node, diag);
                }
                break :blk Type.init(InternPool.well_known.any_type);
            }
            switch (sym) {
                .proc => |proc_node| {
                    const selected = if (resolved.overloads(name)) |candidates| try selectOverload(ast, candidates, args.len, diag, node) else proc_node;
                    return try analyzeProcCall(ast, resolved, typed, selected, args, diag, node);
                },
                else => {},
            }
            if (std.mem.eql(u8, name, "print") or std.mem.eql(u8, name, "log")) switch (sym) {
                .builtin_print, .builtin_log => {
                    if (args.len == 0) return diag.failAt(ast.tokens[ast.mainToken(node)].start, "print expects at least one argument", .{});
                    const first_arg: NodeIndex = @intCast(args[0]);
                    if (ast.tag(first_arg) == .unary_expr and ast.tokens[ast.mainToken(first_arg)].tag == .dot_dot)
                        _ = try analyzeNode(ast, resolved, typed, ast.data(first_arg).lhs, diag)
                    else
                        _ = try analyzeNode(ast, resolved, typed, first_arg, diag);
                    for (args[1..]) |arg| {
                        const arg_node: NodeIndex = @intCast(arg);
                        const arg_ty = if (ast.tag(arg_node) == .unary_expr and ast.tokens[ast.mainToken(arg_node)].tag == .dot_dot)
                            try analyzeNode(ast, resolved, typed, ast.data(arg_node).lhs, diag)
                        else
                            try analyzeNode(ast, resolved, typed, arg_node, diag);
                        if (!(arg_ty.isString() or arg_ty.isInteger() or arg_ty.index == InternPool.well_known.float32_type or arg_ty.index == InternPool.well_known.float64_type or arg_ty.isBool() or arg_ty.isVoid() or arg_ty.isPointer() or arg_ty.index == InternPool.well_known.type_type or arg_ty.index == InternPool.well_known.type_table_type or arg_ty.isAny() or arg_ty.index == InternPool.well_known.apollo_time_type or arg_ty.index == InternPool.well_known.calendar_type or arg_ty.index == InternPool.well_known.vector3_type or arg_ty.index == InternPool.well_known.vector4_type)) return diag.failAt(ast.tokens[ast.mainToken(@intCast(arg))].start, "Phase 3 print currently rejected this argument type", .{});
                    }
                    break :blk Type.voidType();
                },
                .placeholder => unreachable,
                .proc => return diag.failAt(ast.tokens[ast.mainToken(node)].start, "Phase 1 only supports calling Basic.print/log", .{}),
                .builtin_swap, .builtin_write_string, .builtin_write_strings, .builtin_write_number, .builtin_write_nonnegative_number, .builtin_new, .builtin_new_array, .builtin_free, .builtin_exit, .builtin_memcpy, .builtin_memset, .builtin_assert, .builtin_sin, .builtin_current_time_consensus, .builtin_current_time_monotonic, .builtin_to_calendar, .builtin_calendar_to_string, .builtin_random_seed, .builtin_random_get, .builtin_random_get_zero_to_one, .builtin_random_get_within_range, .builtin_compiler_arg_count, .builtin_compiler_arg, .builtin_compiler_read_file, .builtin_compiler_write_file, .builtin_get_command_line_arguments, .builtin_get_cpu_info, .builtin_check_feature, .builtin_make_directory_if_it_does_not_exist, .builtin_delete_directory, .builtin_file_exists, .builtin_set_working_directory, .builtin_get_working_directory, .builtin_visit_files, .builtin_get_path_of_running_executable, .builtin_read_entire_file, .builtin_write_entire_file, .builtin_file_open, .builtin_file_close, .builtin_file_length, .builtin_file_set_position, .builtin_file_write, .builtin_file_read, .builtin_posix_read, .builtin_get_std_handle, .builtin_reset_temporary_storage, .builtin_talloc_string, .builtin_make_leak_report, .builtin_log_leak_report, .builtin_push_allocator, .builtin_sprint, .builtin_tprint, .builtin_to_string, .builtin_to_c_string, .builtin_copy_string, .builtin_string_builder_type, .builtin_init_string_builder, .builtin_free_buffers, .builtin_append, .builtin_print_to_builder, .builtin_builder_string_length, .builtin_builder_to_string, .builtin_compare, .builtin_contains, .builtin_begins_with, .builtin_split, .builtin_trim, .builtin_join, .builtin_find_index_from_left, .builtin_find_index_from_right, .builtin_string_to_int, .builtin_string_to_float, .builtin_parse_int, .builtin_to_integer, .builtin_replace, .builtin_slice, .builtin_path_strip_filename, .builtin_c_style_strlen, .builtin_format_int, .builtin_format_float, .builtin_get_type_table, .builtin_alloc, .builtin_array_add, .builtin_array_free, .builtin_peek, .builtin_pop, .builtin_array_reset, .builtin_array_reserve, .builtin_array_ordered_remove_by_index, .builtin_array_find, .builtin_array_copy, .builtin_get_time, .builtin_seconds_since_init, .builtin_sleep_milliseconds, .builtin_to_float64_seconds, .builtin_format_struct, .builtin_to_upper, .builtin_to_lower, .builtin_is_digit, .builtin_is_alpha, .builtin_is_alnum, .builtin_is_space, .builtin_is_any, .builtin_get_field, .builtin_type_to_string, .builtin_enum_range, .builtin_enum_values_as_s64, .builtin_enum_names, .builtin_abs => return diag.failAt(ast.tokens[ast.mainToken(node)].start, "internal resolver mismatch for print", .{}),
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
                .placeholder => unreachable,
                .builtin_print, .builtin_write_string, .builtin_write_strings, .builtin_write_number, .builtin_write_nonnegative_number, .builtin_new, .builtin_new_array, .builtin_free, .builtin_exit, .builtin_memcpy, .builtin_memset, .builtin_assert, .builtin_sin, .builtin_current_time_consensus, .builtin_current_time_monotonic, .builtin_to_calendar, .builtin_calendar_to_string, .builtin_random_seed, .builtin_random_get, .builtin_random_get_zero_to_one, .builtin_random_get_within_range, .builtin_compiler_arg_count, .builtin_compiler_arg, .builtin_compiler_read_file, .builtin_compiler_write_file, .builtin_get_command_line_arguments, .builtin_get_cpu_info, .builtin_check_feature, .builtin_make_directory_if_it_does_not_exist, .builtin_delete_directory, .builtin_file_exists, .builtin_set_working_directory, .builtin_get_working_directory, .builtin_visit_files, .builtin_get_path_of_running_executable, .builtin_read_entire_file, .builtin_write_entire_file, .builtin_file_open, .builtin_file_close, .builtin_file_length, .builtin_file_set_position, .builtin_file_write, .builtin_file_read, .builtin_posix_read, .builtin_get_std_handle, .builtin_reset_temporary_storage, .builtin_talloc_string, .builtin_make_leak_report, .builtin_log_leak_report, .builtin_push_allocator, .builtin_sprint, .builtin_tprint, .builtin_to_string, .builtin_to_c_string, .builtin_copy_string, .builtin_string_builder_type, .builtin_init_string_builder, .builtin_free_buffers, .builtin_append, .builtin_print_to_builder, .builtin_builder_string_length, .builtin_builder_to_string, .builtin_compare, .builtin_contains, .builtin_begins_with, .builtin_split, .builtin_trim, .builtin_join, .builtin_find_index_from_left, .builtin_find_index_from_right, .builtin_string_to_int, .builtin_string_to_float, .builtin_parse_int, .builtin_to_integer, .builtin_replace, .builtin_slice, .builtin_path_strip_filename, .builtin_c_style_strlen, .builtin_format_int, .builtin_format_float, .builtin_get_type_table, .builtin_alloc, .builtin_array_add, .builtin_array_free, .builtin_peek, .builtin_pop, .builtin_array_reset, .builtin_array_reserve, .builtin_array_ordered_remove_by_index, .builtin_array_find, .builtin_array_copy, .builtin_get_time, .builtin_seconds_since_init, .builtin_sleep_milliseconds, .builtin_to_float64_seconds, .builtin_format_struct, .builtin_to_upper, .builtin_to_lower, .builtin_is_digit, .builtin_is_alpha, .builtin_is_alnum, .builtin_is_space, .builtin_is_any, .builtin_log, .builtin_get_field, .builtin_type_to_string, .builtin_enum_range, .builtin_enum_values_as_s64, .builtin_enum_names, .builtin_abs => return diag.failAt(ast.tokens[ast.mainToken(node)].start, "internal resolver mismatch for swap", .{}),
                .proc => return diag.failAt(ast.tokens[ast.mainToken(node)].start, "Phase 2 only supports builtin Basic.swap", .{}),
                .const_value => return diag.failAt(ast.tokens[ast.mainToken(callee)].start, "constant value is not callable", .{}),
            } else if (std.mem.eql(u8, name, "New")) switch (sym) {
                .builtin_new => {
                    if (args.len < 1) return diag.failAt(ast.tokens[ast.mainToken(node)].start, "New expects one type argument", .{});
                    const arg: NodeIndex = @intCast(args[0]);
                    for (args[1..]) |extra_arg| {
                        const extra_node: NodeIndex = @intCast(extra_arg);
                        if (ast.tag(extra_node) == .assign_stmt)
                            _ = try analyzeNode(ast, resolved, typed, ast.data(extra_node).rhs, diag)
                        else
                            _ = try analyzeNode(ast, resolved, typed, extra_node, diag);
                    }
                    const pointed = try typeFromTypeExpr(ast, arg, diag);
                    break :blk Type.init(try internPointerType(ast, pointed, diag));
                },
                else => return diag.failAt(ast.tokens[ast.mainToken(callee)].start, "internal resolver mismatch for New", .{}),
            } else if (std.mem.eql(u8, name, "NewArray")) switch (sym) {
                .builtin_new_array => {
                    if (args.len < 2) return diag.failAt(ast.tokens[ast.mainToken(node)].start, "NewArray expects a count and type argument", .{});
                    const count_ty = try analyzeNode(ast, resolved, typed, @intCast(args[0]), diag);
                    if (!(count_ty.isInteger() or count_ty.isAny())) return diag.failAt(ast.tokens[ast.mainToken(@intCast(args[0]))].start, "NewArray count must be an integer", .{});
                    _ = try typeFromTypeExpr(ast, @intCast(args[1]), diag);
                    for (args[2..]) |extra_arg| {
                        const extra_node: NodeIndex = @intCast(extra_arg);
                        if (ast.tag(extra_node) == .assign_stmt)
                            _ = try analyzeNode(ast, resolved, typed, ast.data(extra_node).rhs, diag)
                        else
                            _ = try analyzeNode(ast, resolved, typed, extra_node, diag);
                    }
                    break :blk Type.init(try internPointerType(ast, Type.init(InternPool.well_known.any_type), diag));
                },
                else => return diag.failAt(ast.tokens[ast.mainToken(callee)].start, "internal resolver mismatch for NewArray", .{}),
            } else if (std.mem.eql(u8, name, "free")) switch (sym) {
                .builtin_free => {
                    if (args.len != 1) return diag.failAt(ast.tokens[ast.mainToken(node)].start, "free expects one pointer argument", .{});
                    _ = try analyzeNode(ast, resolved, typed, @intCast(args[0]), diag);
                    break :blk Type.voidType();
                },
                else => return diag.failAt(ast.tokens[ast.mainToken(callee)].start, "internal resolver mismatch for free", .{}),
            } else if (std.mem.eql(u8, name, "alloc")) switch (sym) {
                .builtin_alloc => {
                    if (args.len < 1) return diag.failAt(ast.tokens[ast.mainToken(node)].start, "alloc expects one byte-count argument", .{});
                    const count_ty = try analyzeNode(ast, resolved, typed, @intCast(args[0]), diag);
                    for (args[1..]) |extra_arg| {
                        const extra_node: NodeIndex = @intCast(extra_arg);
                        if (ast.tag(extra_node) == .assign_stmt)
                            _ = try analyzeNode(ast, resolved, typed, ast.data(extra_node).rhs, diag)
                        else
                            _ = try analyzeNode(ast, resolved, typed, extra_node, diag);
                    }
                    if (!(count_ty.isInteger() or count_ty.isAny())) return diag.failAt(ast.tokens[ast.mainToken(@intCast(args[0]))].start, "alloc byte count must be an integer", .{});
                    break :blk Type.init(InternPool.well_known.u64_type);
                },
                else => return diag.failAt(ast.tokens[ast.mainToken(callee)].start, "internal resolver mismatch for alloc", .{}),
            } else if (std.mem.eql(u8, name, "compiler_arg_count")) switch (sym) {
                .builtin_compiler_arg_count => {
                    if (args.len != 0) return diag.failAt(ast.tokens[ast.mainToken(node)].start, "compiler_arg_count expects no arguments", .{});
                    break :blk Type.init(InternPool.well_known.s64_type);
                },
                else => return diag.failAt(ast.tokens[ast.mainToken(callee)].start, "internal resolver mismatch for compiler_arg_count", .{}),
            } else if (std.mem.eql(u8, name, "compiler_arg")) switch (sym) {
                .builtin_compiler_arg => {
                    if (args.len != 1) return diag.failAt(ast.tokens[ast.mainToken(node)].start, "compiler_arg expects one integer index", .{});
                    const index_ty = try analyzeNode(ast, resolved, typed, @intCast(args[0]), diag);
                    if (!(index_ty.isInteger() or index_ty.isAny())) return diag.failAt(ast.tokens[ast.mainToken(@intCast(args[0]))].start, "compiler_arg index must be an integer", .{});
                    break :blk Type.string();
                },
                else => return diag.failAt(ast.tokens[ast.mainToken(callee)].start, "internal resolver mismatch for compiler_arg", .{}),
            } else if (std.mem.eql(u8, name, "get_cpu_info")) {
                switch (sym) {
                    .builtin_get_cpu_info, .proc => {},
                    else => return diag.failAt(ast.tokens[ast.mainToken(callee)].start, "internal resolver mismatch for get_cpu_info", .{}),
                }
                if (args.len != 0) return diag.failAt(ast.tokens[ast.mainToken(node)].start, "get_cpu_info expects no arguments", .{});
                break :blk Type.init(InternPool.well_known.any_type);
            } else if (std.mem.eql(u8, name, "check_feature") or std.mem.eql(u8, name, "has_feature")) {
                switch (sym) {
                    .builtin_check_feature, .proc => {},
                    else => return diag.failAt(ast.tokens[ast.mainToken(callee)].start, "internal resolver mismatch for {s}", .{name}),
                }
                const expected_args: usize = if (std.mem.eql(u8, name, "has_feature")) 1 else 2;
                if (args.len != expected_args) return diag.failAt(ast.tokens[ast.mainToken(node)].start, "{s} expects {d} argument{s}", .{ name, expected_args, if (expected_args == 1) "" else "s" });
                for (args) |arg| _ = try analyzeNode(ast, resolved, typed, @intCast(arg), diag);
                break :blk Type.boolType();
            } else if (std.mem.eql(u8, name, "compiler_read_file")) switch (sym) {
                .builtin_compiler_read_file => {
                    if (args.len != 1) return diag.failAt(ast.tokens[ast.mainToken(node)].start, "compiler_read_file expects one path string", .{});
                    const path_ty = try analyzeNode(ast, resolved, typed, @intCast(args[0]), diag);
                    if (!(path_ty.isString() or path_ty.isAny())) return diag.failAt(ast.tokens[ast.mainToken(@intCast(args[0]))].start, "compiler_read_file path must be a string", .{});
                    break :blk Type.string();
                },
                else => return diag.failAt(ast.tokens[ast.mainToken(callee)].start, "internal resolver mismatch for compiler_read_file", .{}),
            } else if (std.mem.eql(u8, name, "read_entire_file")) switch (sym) {
                .builtin_read_entire_file => {
                    if (args.len != 1) return diag.failAt(ast.tokens[ast.mainToken(node)].start, "read_entire_file expects one path string", .{});
                    const path_ty = try analyzeNode(ast, resolved, typed, @intCast(args[0]), diag);
                    if (!(path_ty.isString() or path_ty.isAny())) return diag.failAt(ast.tokens[ast.mainToken(@intCast(args[0]))].start, "read_entire_file path must be a string", .{});
                    break :blk Type.string();
                },
                else => return diag.failAt(ast.tokens[ast.mainToken(callee)].start, "internal resolver mismatch for read_entire_file", .{}),
            } else if (std.mem.eql(u8, name, "compiler_write_file")) switch (sym) {
                .builtin_compiler_write_file => {
                    if (args.len != 2) return diag.failAt(ast.tokens[ast.mainToken(node)].start, "compiler_write_file expects a path string and contents string", .{});
                    const path_ty = try analyzeNode(ast, resolved, typed, @intCast(args[0]), diag);
                    if (!(path_ty.isString() or path_ty.isAny())) return diag.failAt(ast.tokens[ast.mainToken(@intCast(args[0]))].start, "compiler_write_file path must be a string", .{});
                    const contents_ty = try analyzeNode(ast, resolved, typed, @intCast(args[1]), diag);
                    if (!(contents_ty.isString() or contents_ty.isAny())) return diag.failAt(ast.tokens[ast.mainToken(@intCast(args[1]))].start, "compiler_write_file contents must be a string", .{});
                    break :blk Type.boolType();
                },
                else => return diag.failAt(ast.tokens[ast.mainToken(callee)].start, "internal resolver mismatch for compiler_write_file", .{}),
            } else if (std.mem.eql(u8, name, "write_entire_file")) switch (sym) {
                .builtin_write_entire_file => {
                    if (args.len != 2) return diag.failAt(ast.tokens[ast.mainToken(node)].start, "write_entire_file expects a path string and contents string", .{});
                    const path_ty = try analyzeNode(ast, resolved, typed, @intCast(args[0]), diag);
                    const contents_ty = try analyzeNode(ast, resolved, typed, @intCast(args[1]), diag);
                    if (!(path_ty.isString() or path_ty.isAny())) return diag.failAt(ast.tokens[ast.mainToken(@intCast(args[0]))].start, "write_entire_file path must be a string", .{});
                    if (!(contents_ty.isString() or contents_ty.isAny())) return diag.failAt(ast.tokens[ast.mainToken(@intCast(args[1]))].start, "write_entire_file contents must be a string", .{});
                    break :blk Type.boolType();
                },
                else => return diag.failAt(ast.tokens[ast.mainToken(callee)].start, "internal resolver mismatch for write_entire_file", .{}),
            } else if (std.mem.eql(u8, name, "make_directory_if_it_does_not_exist")) switch (sym) {
                .builtin_make_directory_if_it_does_not_exist => {
                    if (args.len < 1 or args.len > 2) return diag.failAt(ast.tokens[ast.mainToken(node)].start, "make_directory_if_it_does_not_exist expects a path string and optional recursive flag", .{});
                    _ = try analyzeNode(ast, resolved, typed, @intCast(args[0]), diag);
                    if (args.len == 2) _ = try analyzeNode(ast, resolved, typed, @intCast(args[1]), diag);
                    break :blk Type.boolType();
                },
                else => return diag.failAt(ast.tokens[ast.mainToken(callee)].start, "internal resolver mismatch for make_directory_if_it_does_not_exist", .{}),
            } else if (std.mem.eql(u8, name, "delete_directory")) switch (sym) {
                .builtin_delete_directory => {
                    if (args.len != 1) return diag.failAt(ast.tokens[ast.mainToken(node)].start, "delete_directory expects one path string", .{});
                    _ = try analyzeNode(ast, resolved, typed, @intCast(args[0]), diag);
                    break :blk Type.boolType();
                },
                else => return diag.failAt(ast.tokens[ast.mainToken(callee)].start, "internal resolver mismatch for delete_directory", .{}),
            } else if (std.mem.eql(u8, name, "file_exists")) switch (sym) {
                .builtin_file_exists => {
                    if (args.len != 1) return diag.failAt(ast.tokens[ast.mainToken(node)].start, "file_exists expects one path string", .{});
                    _ = try analyzeNode(ast, resolved, typed, @intCast(args[0]), diag);
                    break :blk Type.boolType();
                },
                else => return diag.failAt(ast.tokens[ast.mainToken(callee)].start, "internal resolver mismatch for file_exists", .{}),
            } else if (std.mem.eql(u8, name, "set_working_directory")) switch (sym) {
                .builtin_set_working_directory => {
                    if (args.len != 1) return diag.failAt(ast.tokens[ast.mainToken(node)].start, "set_working_directory expects one path string", .{});
                    _ = try analyzeNode(ast, resolved, typed, @intCast(args[0]), diag);
                    break :blk Type.boolType();
                },
                else => return diag.failAt(ast.tokens[ast.mainToken(callee)].start, "internal resolver mismatch for set_working_directory", .{}),
            } else if (std.mem.eql(u8, name, "get_working_directory")) switch (sym) {
                .builtin_get_working_directory => {
                    if (args.len != 0) return diag.failAt(ast.tokens[ast.mainToken(node)].start, "get_working_directory expects no arguments", .{});
                    break :blk Type.string();
                },
                else => return diag.failAt(ast.tokens[ast.mainToken(callee)].start, "internal resolver mismatch for get_working_directory", .{}),
            } else if (std.mem.eql(u8, name, "visit_files")) switch (sym) {
                .builtin_visit_files => {
                    if (args.len < 4) return diag.failAt(ast.tokens[ast.mainToken(node)].start, "visit_files expects start path, recursive flag, user data, visitor procedure, and optional named flags", .{});
                    for (args) |arg| {
                        const arg_node: NodeIndex = @intCast(arg);
                        _ = try analyzeNode(ast, resolved, typed, callArgValueNode(ast, arg_node), diag);
                    }
                    break :blk Type.boolType();
                },
                else => return diag.failAt(ast.tokens[ast.mainToken(callee)].start, "internal resolver mismatch for visit_files", .{}),
            } else if (std.mem.eql(u8, name, "file_open")) switch (sym) {
                .builtin_file_open => {
                    if (args.len < 1) return diag.failAt(ast.tokens[ast.mainToken(node)].start, "file_open expects a path string", .{});
                    for (args) |arg| {
                        const arg_node: NodeIndex = @intCast(arg);
                        _ = try analyzeNode(ast, resolved, typed, if (ast.tag(arg_node) == .assign_stmt) ast.data(arg_node).rhs else arg_node, diag);
                    }
                    break :blk Type.init(InternPool.well_known.any_type);
                },
                else => return diag.failAt(ast.tokens[ast.mainToken(callee)].start, "internal resolver mismatch for file_open", .{}),
            } else if (std.mem.eql(u8, name, "file_close")) switch (sym) {
                .builtin_file_close => {
                    if (args.len != 1) return diag.failAt(ast.tokens[ast.mainToken(node)].start, "file_close expects one file handle", .{});
                    _ = try analyzeNode(ast, resolved, typed, @intCast(args[0]), diag);
                    break :blk Type.voidType();
                },
                else => return diag.failAt(ast.tokens[ast.mainToken(callee)].start, "internal resolver mismatch for file_close", .{}),
            } else if (std.mem.eql(u8, name, "file_length")) switch (sym) {
                .builtin_file_length => {
                    if (args.len != 1) return diag.failAt(ast.tokens[ast.mainToken(node)].start, "file_length expects one file handle", .{});
                    _ = try analyzeNode(ast, resolved, typed, @intCast(args[0]), diag);
                    break :blk Type.init(InternPool.well_known.s64_type);
                },
                else => return diag.failAt(ast.tokens[ast.mainToken(callee)].start, "internal resolver mismatch for file_length", .{}),
            } else if (std.mem.eql(u8, name, "file_set_position")) switch (sym) {
                .builtin_file_set_position => {
                    if (args.len != 2) return diag.failAt(ast.tokens[ast.mainToken(node)].start, "file_set_position expects a file handle and position", .{});
                    _ = try analyzeNode(ast, resolved, typed, @intCast(args[0]), diag);
                    _ = try analyzeNode(ast, resolved, typed, @intCast(args[1]), diag);
                    break :blk Type.boolType();
                },
                else => return diag.failAt(ast.tokens[ast.mainToken(callee)].start, "internal resolver mismatch for file_set_position", .{}),
            } else if (std.mem.eql(u8, name, "file_write")) switch (sym) {
                .builtin_file_write => {
                    if (args.len < 2 or args.len > 3) return diag.failAt(ast.tokens[ast.mainToken(node)].start, "file_write expects a file handle, string or buffer, and optional byte count", .{});
                    for (args) |arg| _ = try analyzeNode(ast, resolved, typed, @intCast(arg), diag);
                    break :blk Type.boolType();
                },
                else => return diag.failAt(ast.tokens[ast.mainToken(callee)].start, "internal resolver mismatch for file_write", .{}),
            } else if (std.mem.eql(u8, name, "file_read")) switch (sym) {
                .builtin_file_read => {
                    if (args.len != 3) return diag.failAt(ast.tokens[ast.mainToken(node)].start, "file_read expects a file handle, buffer, and byte count", .{});
                    for (args) |arg| _ = try analyzeNode(ast, resolved, typed, @intCast(arg), diag);
                    break :blk Type.boolType();
                },
                else => return diag.failAt(ast.tokens[ast.mainToken(callee)].start, "internal resolver mismatch for {s}", .{name}),
            } else if (std.mem.eql(u8, name, "read")) switch (sym) {
                .builtin_posix_read => {
                    if (args.len != 3) return diag.failAt(ast.tokens[ast.mainToken(node)].start, "read expects a file descriptor, buffer, and byte count", .{});
                    for (args) |arg| _ = try analyzeNode(ast, resolved, typed, @intCast(arg), diag);
                    break :blk Type.init(InternPool.well_known.s64_type);
                },
                else => return diag.failAt(ast.tokens[ast.mainToken(callee)].start, "internal resolver mismatch for {s}", .{name}),
            } else if (std.mem.eql(u8, name, "GetStdHandle")) switch (sym) {
                .builtin_get_std_handle => {
                    if (args.len != 1) return diag.failAt(ast.tokens[ast.mainToken(node)].start, "GetStdHandle expects one standard-handle selector", .{});
                    _ = try analyzeNode(ast, resolved, typed, @intCast(args[0]), diag);
                    break :blk Type.init(InternPool.well_known.s64_type);
                },
                else => return diag.failAt(ast.tokens[ast.mainToken(callee)].start, "internal resolver mismatch for {s}", .{name}),
            } else if (std.mem.eql(u8, name, "reset_temporary_storage")) switch (sym) {
                .builtin_reset_temporary_storage => {
                    if (args.len != 0) return diag.failAt(ast.tokens[ast.mainToken(node)].start, "reset_temporary_storage expects no arguments", .{});
                    break :blk Type.voidType();
                },
                else => return diag.failAt(ast.tokens[ast.mainToken(callee)].start, "internal resolver mismatch for {s}", .{name}),
            } else if (std.mem.eql(u8, name, "talloc_string")) switch (sym) {
                .builtin_talloc_string => {
                    if (args.len != 1) return diag.failAt(ast.tokens[ast.mainToken(node)].start, "talloc_string expects one byte count", .{});
                    _ = try analyzeNode(ast, resolved, typed, @intCast(args[0]), diag);
                    break :blk Type.string();
                },
                else => return diag.failAt(ast.tokens[ast.mainToken(callee)].start, "internal resolver mismatch for {s}", .{name}),
            } else if (std.mem.eql(u8, name, "make_leak_report")) switch (sym) {
                .builtin_make_leak_report => {
                    if (args.len != 0) return diag.failAt(ast.tokens[ast.mainToken(node)].start, "make_leak_report expects no arguments", .{});
                    break :blk Type.init(InternPool.well_known.any_type);
                },
                else => return diag.failAt(ast.tokens[ast.mainToken(callee)].start, "internal resolver mismatch for {s}", .{name}),
            } else if (std.mem.eql(u8, name, "log_leak_report")) switch (sym) {
                .builtin_log_leak_report => {
                    if (args.len != 1) return diag.failAt(ast.tokens[ast.mainToken(node)].start, "log_leak_report expects one report", .{});
                    _ = try analyzeNode(ast, resolved, typed, @intCast(args[0]), diag);
                    break :blk Type.voidType();
                },
                else => return diag.failAt(ast.tokens[ast.mainToken(callee)].start, "internal resolver mismatch for {s}", .{name}),
            } else if (std.mem.eql(u8, name, "push_allocator")) switch (sym) {
                .builtin_push_allocator => {
                    if (args.len < 1 or args.len > 2) return diag.failAt(ast.tokens[ast.mainToken(node)].start, "push_allocator expects an allocator and optional data pointer", .{});
                    for (args) |arg| _ = try analyzeNode(ast, resolved, typed, @intCast(arg), diag);
                    break :blk Type.voidType();
                },
                else => return diag.failAt(ast.tokens[ast.mainToken(callee)].start, "internal resolver mismatch for {s}", .{name}),
            } else if (std.mem.eql(u8, name, "get_command_line_arguments")) switch (sym) {
                .builtin_get_command_line_arguments => {
                    if (args.len != 0) return diag.failAt(ast.tokens[ast.mainToken(node)].start, "get_command_line_arguments expects no arguments", .{});
                    break :blk Type.init(InternPool.well_known.any_type);
                },
                else => return diag.failAt(ast.tokens[ast.mainToken(callee)].start, "internal resolver mismatch for get_command_line_arguments", .{}),
            } else if (std.mem.eql(u8, name, "array_add")) switch (sym) {
                .builtin_array_add => {
                    for (args) |arg| {
                        const arg_node: NodeIndex = @intCast(arg);
                        if (ast.tag(arg_node) == .unary_expr and ast.tokens[ast.mainToken(arg_node)].tag == .dot_dot)
                            _ = try analyzeNode(ast, resolved, typed, ast.data(arg_node).lhs, diag)
                        else
                            _ = try analyzeNode(ast, resolved, typed, arg_node, diag);
                    }
                    break :blk Type.init(InternPool.well_known.any_type);
                },
                else => return diag.failAt(ast.tokens[ast.mainToken(callee)].start, "internal resolver mismatch for array_add", .{}),
            } else if (std.mem.eql(u8, name, "array_free")) switch (sym) {
                .builtin_array_free => {
                    if (args.len != 1) return diag.failAt(ast.tokens[ast.mainToken(node)].start, "array_free expects one array argument", .{});
                    _ = try analyzeNode(ast, resolved, typed, @intCast(args[0]), diag);
                    break :blk Type.voidType();
                },
                else => return diag.failAt(ast.tokens[ast.mainToken(callee)].start, "internal resolver mismatch for array_free", .{}),
            } else if (std.mem.eql(u8, name, "peek")) switch (sym) {
                .builtin_peek => {
                    if (args.len != 1) return diag.failAt(ast.tokens[ast.mainToken(node)].start, "peek expects one array argument", .{});
                    _ = try analyzeNode(ast, resolved, typed, @intCast(args[0]), diag);
                    break :blk Type.init(InternPool.well_known.any_type);
                },
                else => return diag.failAt(ast.tokens[ast.mainToken(callee)].start, "internal resolver mismatch for peek", .{}),
            } else if (std.mem.eql(u8, name, "pop")) switch (sym) {
                .builtin_pop => {
                    if (args.len != 1) return diag.failAt(ast.tokens[ast.mainToken(node)].start, "pop expects one array argument", .{});
                    _ = try analyzeNode(ast, resolved, typed, @intCast(args[0]), diag);
                    break :blk Type.init(InternPool.well_known.any_type);
                },
                else => return diag.failAt(ast.tokens[ast.mainToken(callee)].start, "internal resolver mismatch for pop", .{}),
            } else if (std.mem.eql(u8, name, "array_reset")) switch (sym) {
                .builtin_array_reset => {
                    if (args.len != 1) return diag.failAt(ast.tokens[ast.mainToken(node)].start, "array_reset expects one array argument", .{});
                    _ = try analyzeNode(ast, resolved, typed, @intCast(args[0]), diag);
                    break :blk Type.voidType();
                },
                else => return diag.failAt(ast.tokens[ast.mainToken(callee)].start, "internal resolver mismatch for array_reset", .{}),
            } else if (std.mem.eql(u8, name, "array_reserve")) switch (sym) {
                .builtin_array_reserve => {
                    if (args.len != 2) return diag.failAt(ast.tokens[ast.mainToken(node)].start, "array_reserve expects an array and capacity", .{});
                    _ = try analyzeNode(ast, resolved, typed, @intCast(args[0]), diag);
                    _ = try analyzeNode(ast, resolved, typed, @intCast(args[1]), diag);
                    break :blk Type.voidType();
                },
                else => return diag.failAt(ast.tokens[ast.mainToken(callee)].start, "internal resolver mismatch for array_reserve", .{}),
            } else if (std.mem.eql(u8, name, "array_ordered_remove_by_index")) switch (sym) {
                .builtin_array_ordered_remove_by_index => {
                    if (args.len != 2) return diag.failAt(ast.tokens[ast.mainToken(node)].start, "array_ordered_remove_by_index expects an array and index", .{});
                    _ = try analyzeNode(ast, resolved, typed, @intCast(args[0]), diag);
                    _ = try analyzeNode(ast, resolved, typed, @intCast(args[1]), diag);
                    break :blk Type.voidType();
                },
                else => return diag.failAt(ast.tokens[ast.mainToken(callee)].start, "internal resolver mismatch for array_ordered_remove_by_index", .{}),
            } else if (std.mem.eql(u8, name, "array_find")) switch (sym) {
                .builtin_array_find => {
                    if (args.len != 2) return diag.failAt(ast.tokens[ast.mainToken(node)].start, "array_find expects an array and value", .{});
                    _ = try analyzeNode(ast, resolved, typed, @intCast(args[0]), diag);
                    _ = try analyzeNode(ast, resolved, typed, @intCast(args[1]), diag);
                    break :blk Type.boolType();
                },
                else => return diag.failAt(ast.tokens[ast.mainToken(callee)].start, "internal resolver mismatch for array_find", .{}),
            } else if (std.mem.eql(u8, name, "array_copy")) switch (sym) {
                .builtin_array_copy => {
                    if (args.len != 1 and args.len != 2) return diag.failAt(ast.tokens[ast.mainToken(node)].start, "array_copy expects a source array or destination and source arrays", .{});
                    for (args) |arg| _ = try analyzeNode(ast, resolved, typed, @intCast(arg), diag);
                    break :blk Type.init(InternPool.well_known.any_type);
                },
                else => return diag.failAt(ast.tokens[ast.mainToken(callee)].start, "internal resolver mismatch for array_copy", .{}),
            } else if (std.mem.eql(u8, name, "write_string") or std.mem.eql(u8, name, "write_strings") or std.mem.eql(u8, name, "write_number") or std.mem.eql(u8, name, "write_nonnegative_number")) switch (sym) {
                .builtin_write_string, .builtin_write_strings, .builtin_write_number, .builtin_write_nonnegative_number => {
                    for (args) |arg| _ = try analyzeNode(ast, resolved, typed, @intCast(arg), diag);
                    break :blk Type.voidType();
                },
                .builtin_new, .builtin_new_array, .builtin_free => return diag.failAt(ast.tokens[ast.mainToken(callee)].start, "internal resolver mismatch for write builtin", .{}),
                else => return diag.failAt(ast.tokens[ast.mainToken(callee)].start, "internal resolver mismatch for write builtin", .{}),
            } else if (std.mem.eql(u8, name, "assert")) switch (sym) {
                .builtin_assert => {
                    if (args.len < 1) return diag.failAt(ast.tokens[ast.mainToken(node)].start, "assert expects a condition and optional message", .{});
                    const cond_ty = try analyzeNode(ast, resolved, typed, @intCast(args[0]), diag);
                    if (!(cond_ty.isBool() or cond_ty.isInteger() or cond_ty.isString() or cond_ty.isPointer() or cond_ty.isAny())) return diag.failAt(ast.tokens[ast.mainToken(@intCast(args[0]))].start, "assert condition must be truthy-coercible", .{});
                    if (args.len >= 2) {
                        const msg_ty = try analyzeNode(ast, resolved, typed, @intCast(args[1]), diag);
                        if (!msg_ty.isString()) return diag.failAt(ast.tokens[ast.mainToken(@intCast(args[1]))].start, "assert message must be a string", .{});
                        for (args[2..]) |arg| _ = try analyzeNode(ast, resolved, typed, @intCast(arg), diag);
                    }
                    break :blk Type.voidType();
                },
                else => return diag.failAt(ast.tokens[ast.mainToken(callee)].start, "internal resolver mismatch for assert", .{}),
            } else if (std.mem.eql(u8, name, "memcpy") or std.mem.eql(u8, name, "memset")) switch (sym) {
                .builtin_memcpy, .builtin_memset => {
                    if (args.len != 3) return diag.failAt(ast.tokens[ast.mainToken(node)].start, "{s} expects destination, source/value, and byte count", .{name});
                    const dst_ty = try analyzeNode(ast, resolved, typed, @intCast(args[0]), diag);
                    const src_ty = try analyzeNode(ast, resolved, typed, @intCast(args[1]), diag);
                    const count_ty = try analyzeNode(ast, resolved, typed, @intCast(args[2]), diag);
                    const dst_ok = dst_ty.isPointer() or dst_ty.isAny() or dst_ty.isString();
                    const src_ok = if (std.mem.eql(u8, name, "memset")) src_ty.isInteger() else src_ty.isPointer() or src_ty.isAny() or src_ty.isString();
                    if (!dst_ok or !src_ok) return diag.failAt(ast.tokens[ast.mainToken(node)].start, "{s} arguments have incompatible types", .{name});
                    if (!count_ty.isInteger()) return diag.failAt(ast.tokens[ast.mainToken(@intCast(args[2]))].start, "memcpy byte count must be an integer", .{});
                    break :blk Type.voidType();
                },
                else => return diag.failAt(ast.tokens[ast.mainToken(callee)].start, "internal resolver mismatch for memory builtin", .{}),
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
            } else if (std.mem.eql(u8, name, "abs")) switch (sym) {
                .builtin_abs => {
                    if (args.len != 1) return diag.failAt(ast.tokens[ast.mainToken(node)].start, "abs expects one argument", .{});
                    const arg_ty = try analyzeNode(ast, resolved, typed, @intCast(args[0]), diag);
                    if (!(arg_ty.isInteger() or arg_ty.isFloat() or arg_ty.isAny())) return diag.failAt(ast.tokens[ast.mainToken(@intCast(args[0]))].start, "abs argument must be numeric", .{});
                    break :blk arg_ty;
                },
                else => return diag.failAt(ast.tokens[ast.mainToken(callee)].start, "internal resolver mismatch for abs", .{}),
            } else if (std.mem.eql(u8, name, "formatInt")) switch (sym) {
                .builtin_format_int => {
                    if (args.len < 1) return diag.failAt(ast.tokens[ast.mainToken(node)].start, "formatInt expects an integer value", .{});
                    const value_ty = try analyzeNode(ast, resolved, typed, @intCast(args[0]), diag);
                    if (!(value_ty.isInteger() or value_ty.isAny() or value_ty.isPointer() or value_ty.index == InternPool.well_known.type_table_type or value_ty.index == InternPool.well_known.type_type)) return diag.failAt(ast.tokens[ast.mainToken(@intCast(args[0]))].start, "formatInt value must be an integer", .{});
                    for (args[1..]) |arg_idx| {
                        const arg: NodeIndex = @intCast(arg_idx);
                        if (ast.tag(arg) != .assign_stmt) {
                            const option_ty = try analyzeNode(ast, resolved, typed, arg, diag);
                            if (!(option_ty.isInteger() or option_ty.isAny())) return diag.failAt(ast.tokens[ast.mainToken(arg)].start, "formatInt option must be an integer", .{});
                            continue;
                        }
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
            } else if (std.mem.eql(u8, name, "get_time") or std.mem.eql(u8, name, "seconds_since_init")) switch (sym) {
                .builtin_get_time, .builtin_seconds_since_init => {
                    if (args.len != 0) return diag.failAt(ast.tokens[ast.mainToken(node)].start, "{s} expects no arguments", .{name});
                    break :blk Type.init(InternPool.well_known.float64_type);
                },
                else => return diag.failAt(ast.tokens[ast.mainToken(callee)].start, "internal resolver mismatch for {s}", .{name}),
            } else if (std.mem.eql(u8, name, "sleep_milliseconds")) switch (sym) {
                .builtin_sleep_milliseconds => {
                    if (args.len != 1) return diag.failAt(ast.tokens[ast.mainToken(node)].start, "sleep_milliseconds expects one argument", .{});
                    const arg_ty = try analyzeNode(ast, resolved, typed, @intCast(args[0]), diag);
                    if (!(arg_ty.isInteger() or arg_ty.isFloat())) return diag.failAt(ast.tokens[ast.mainToken(@intCast(args[0]))].start, "sleep_milliseconds argument must be numeric", .{});
                    break :blk Type.voidType();
                },
                else => return diag.failAt(ast.tokens[ast.mainToken(callee)].start, "internal resolver mismatch for sleep_milliseconds", .{}),
            } else if (std.mem.eql(u8, name, "to_float64_seconds")) switch (sym) {
                .builtin_to_float64_seconds => {
                    if (args.len != 1) return diag.failAt(ast.tokens[ast.mainToken(node)].start, "to_float64_seconds expects one argument", .{});
                    _ = try analyzeNode(ast, resolved, typed, @intCast(args[0]), diag);
                    break :blk Type.init(InternPool.well_known.float64_type);
                },
                else => return diag.failAt(ast.tokens[ast.mainToken(callee)].start, "internal resolver mismatch for to_float64_seconds", .{}),
            } else if (std.mem.eql(u8, name, "formatStruct")) switch (sym) {
                .builtin_format_struct => {
                    if (args.len < 1) return diag.failAt(ast.tokens[ast.mainToken(node)].start, "formatStruct expects a value", .{});
                    for (args) |arg_idx| {
                        const arg: NodeIndex = @intCast(arg_idx);
                        if (ast.tag(arg) == .assign_stmt) {
                            _ = try analyzeNode(ast, resolved, typed, ast.data(arg).rhs, diag);
                        } else {
                            _ = try analyzeNode(ast, resolved, typed, arg, diag);
                        }
                    }
                    break :blk Type.string();
                },
                else => return diag.failAt(ast.tokens[ast.mainToken(callee)].start, "internal resolver mismatch for formatStruct", .{}),
            } else if (std.mem.eql(u8, name, "to_upper") or std.mem.eql(u8, name, "to_lower")) switch (sym) {
                .builtin_to_upper, .builtin_to_lower => {
                    if (args.len != 1) return diag.failAt(ast.tokens[ast.mainToken(node)].start, "{s} expects one argument", .{name});
                    const arg_ty = try analyzeNode(ast, resolved, typed, @intCast(args[0]), diag);
                    if (!arg_ty.isInteger()) return diag.failAt(ast.tokens[ast.mainToken(@intCast(args[0]))].start, "{s} argument must be an integer character code", .{name});
                    break :blk Type.init(InternPool.well_known.s64_type);
                },
                else => return diag.failAt(ast.tokens[ast.mainToken(callee)].start, "internal resolver mismatch for {s}", .{name}),
            } else if (std.mem.eql(u8, name, "is_digit") or std.mem.eql(u8, name, "is_alpha") or std.mem.eql(u8, name, "is_alnum") or std.mem.eql(u8, name, "is_space")) switch (sym) {
                .builtin_is_digit, .builtin_is_alpha, .builtin_is_alnum, .builtin_is_space => {
                    if (args.len != 1) return diag.failAt(ast.tokens[ast.mainToken(node)].start, "{s} expects one argument", .{name});
                    const arg_ty = try analyzeNode(ast, resolved, typed, @intCast(args[0]), diag);
                    if (!arg_ty.isInteger()) return diag.failAt(ast.tokens[ast.mainToken(@intCast(args[0]))].start, "{s} argument must be an integer character code", .{name});
                    break :blk Type.boolType();
                },
                else => return diag.failAt(ast.tokens[ast.mainToken(callee)].start, "internal resolver mismatch for {s}", .{name}),
            } else if (std.mem.eql(u8, name, "is_any")) switch (sym) {
                .builtin_is_any => {
                    if (args.len != 2) return diag.failAt(ast.tokens[ast.mainToken(node)].start, "is_any expects two arguments", .{});
                    const lhs_ty = try analyzeNode(ast, resolved, typed, @intCast(args[0]), diag);
                    const rhs_ty = try analyzeNode(ast, resolved, typed, @intCast(args[1]), diag);
                    if (!lhs_ty.isInteger()) return diag.failAt(ast.tokens[ast.mainToken(@intCast(args[0]))].start, "is_any first argument must be an integer character code", .{});
                    if (!rhs_ty.isString()) return diag.failAt(ast.tokens[ast.mainToken(@intCast(args[1]))].start, "is_any second argument must be a string", .{});
                    break :blk Type.boolType();
                },
                else => return diag.failAt(ast.tokens[ast.mainToken(callee)].start, "internal resolver mismatch for is_any", .{}),
            } else if (std.mem.eql(u8, name, "to_calendar")) switch (sym) {
                .builtin_to_calendar => {
                    if (args.len < 1 or args.len > 2) return diag.failAt(ast.tokens[ast.mainToken(node)].start, "to_calendar expects Apollo_Time and optional timezone arguments", .{});
                    const time_ty = try analyzeNode(ast, resolved, typed, @intCast(args[0]), diag);
                    if (time_ty.index != InternPool.well_known.apollo_time_type) return diag.failAt(ast.tokens[ast.mainToken(@intCast(args[0]))].start, "to_calendar first argument must be Apollo_Time", .{});
                    if (args.len == 2) try validateTimezoneLiteral(ast, @intCast(args[1]), diag);
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
            } else if (std.mem.eql(u8, name, "get_field")) switch (sym) {
                .builtin_get_field => {
                    if (args.len != 2) return diag.failAt(ast.tokens[ast.mainToken(node)].start, "get_field expects two arguments", .{});
                    _ = try analyzeNode(ast, resolved, typed, @intCast(args[0]), diag);
                    _ = try analyzeNode(ast, resolved, typed, @intCast(args[1]), diag);
                    break :blk Type.init(InternPool.well_known.any_type);
                },
                else => return diag.failAt(ast.tokens[ast.mainToken(callee)].start, "internal resolver mismatch for get_field", .{}),
            } else if (std.mem.eql(u8, name, "type_to_string")) switch (sym) {
                .builtin_type_to_string => {
                    if (args.len != 1) return diag.failAt(ast.tokens[ast.mainToken(node)].start, "type_to_string expects one argument", .{});
                    _ = try analyzeNode(ast, resolved, typed, @intCast(args[0]), diag);
                    break :blk Type.string();
                },
                else => return diag.failAt(ast.tokens[ast.mainToken(callee)].start, "internal resolver mismatch for type_to_string", .{}),
            } else if (std.mem.eql(u8, name, "sprint") or std.mem.eql(u8, name, "tprint") or std.mem.eql(u8, name, "trim") or std.mem.eql(u8, name, "to_string")) {
                for (args) |arg| {
                    const arg_node: NodeIndex = @intCast(arg);
                    if (ast.tag(arg_node) == .assign_stmt)
                        _ = try analyzeNode(ast, resolved, typed, ast.data(arg_node).rhs, diag)
                    else if (ast.tag(arg_node) == .unary_expr and ast.tokens[ast.mainToken(arg_node)].tag == .dot_dot)
                        _ = try analyzeNode(ast, resolved, typed, ast.data(arg_node).lhs, diag)
                    else
                        _ = try analyzeNode(ast, resolved, typed, arg_node, diag);
                }
                break :blk Type.string();
            } else if (std.mem.eql(u8, name, "enum_range")) switch (sym) {
                .builtin_enum_range => {
                    if (args.len != 1) return diag.failAt(ast.tokens[ast.mainToken(node)].start, "enum_range expects one argument", .{});
                    _ = try analyzeNode(ast, resolved, typed, @intCast(args[0]), diag);
                    break :blk Type.init(InternPool.well_known.any_type);
                },
                else => return diag.failAt(ast.tokens[ast.mainToken(callee)].start, "internal resolver mismatch for enum_range", .{}),
            } else if (std.mem.eql(u8, name, "enum_values_as_s64") or std.mem.eql(u8, name, "enum_names")) switch (sym) {
                .builtin_enum_values_as_s64, .builtin_enum_names => {
                    if (args.len != 1) return diag.failAt(ast.tokens[ast.mainToken(node)].start, "{s} expects one argument", .{name});
                    _ = try analyzeNode(ast, resolved, typed, @intCast(args[0]), diag);
                    break :blk Type.init(InternPool.well_known.type_table_type);
                },
                else => return diag.failAt(ast.tokens[ast.mainToken(callee)].start, "internal resolver mismatch for {s}", .{name}),
            } else {
                for (args) |arg| {
                    const arg_node: NodeIndex = @intCast(arg);
                    if (ast.tag(arg_node) == .assign_stmt)
                        _ = try analyzeNode(ast, resolved, typed, ast.data(arg_node).rhs, diag)
                    else if (ast.tag(arg_node) == .unary_expr and ast.tokens[ast.mainToken(arg_node)].tag == .dot_dot)
                        _ = try analyzeNode(ast, resolved, typed, ast.data(arg_node).lhs, diag)
                    else
                        _ = try analyzeNode(ast, resolved, typed, arg_node, diag);
                }
                break :blk Type.init(InternPool.well_known.any_type);
            }
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
    if (ast.data(proc).rhs == @import("Ast.zig").null_node) return null;
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
        const variadic = lastParamIsVariadic(ast, params);
        const required = requiredParamCount(ast, params);
        if (!variadic and arg_count >= required and arg_count <= params.len) return candidate;
        if (variadic and arg_count >= required and variadic_match == null) variadic_match = candidate;
    }
    if (variadic_match) |candidate| return candidate;
    _ = diag;
    _ = call_node;
    return candidates[0];
}

fn lastParamIsVariadic(ast: *const Ast, params: []const u32) bool {
    if (params.len == 0) return false;
    const last: NodeIndex = @intCast(params[params.len - 1]);
    return ast.tag(last) == .var_decl and ast.data(last).rhs == 1;
}

fn paramDefaultInit(ast: *const Ast, param: NodeIndex) NodeIndex {
    if (ast.tag(param) != .var_decl) return @import("Ast.zig").null_node;
    if (ast.data(param).rhs == 1) return @import("Ast.zig").null_node;
    return ast.data(param).rhs;
}

fn requiredParamCount(ast: *const Ast, params: []const u32) usize {
    var required: usize = 0;
    for (params, 0..) |param_idx, i| {
        const param: NodeIndex = @intCast(param_idx);
        if (lastParamIsVariadic(ast, params) and i == params.len - 1) break;
        if (paramDefaultInit(ast, param) == @import("Ast.zig").null_node) required += 1;
    }
    return required;
}

fn analyzeProcCall(ast: *const Ast, resolved: *const Resolved, typed: *Typed, proc_node: NodeIndex, args: []const u32, diag: Diagnostic, call_node: NodeIndex) anyerror!Type {
    const sig = procSignature(ast, proc_node);
    const params = if (sig) |s| ast.extraSlice(s.params_extra) else &[_]u32{};
    const variadic = lastParamIsVariadic(ast, params);
    const required = requiredParamCount(ast, params);
    _ = required;
    _ = variadic;
    _ = call_node;
    var inferred = std.ArrayList(NodeIndex).empty;
    defer inferred.deinit(typed.allocator);
    var param_used = try typed.allocator.alloc(bool, params.len);
    defer typed.allocator.free(param_used);
    @memset(param_used, false);

    var positional_index: usize = 0;
    for (args) |arg| {
        const arg_node: NodeIndex = @intCast(arg);
        if (ast.tag(arg_node) == .assign_stmt or (ast.tag(arg_node) == .binary_expr and ast.tokens[ast.mainToken(arg_node)].tag == .equal and ast.tag(ast.data(arg_node).lhs) == .identifier)) {
            const arg_name = ast.tokenSlice(ast.mainToken(ast.data(arg_node).lhs));
            var matched = false;
            for (params, 0..) |param_idx, i| {
                const param: NodeIndex = @intCast(param_idx);
                if (!std.mem.eql(u8, ast.tokenSlice(ast.mainToken(param)), arg_name)) continue;
                const rhs_node = ast.data(arg_node).rhs;
                const arg_ty = if (ast.tag(rhs_node) == .unary_expr and ast.tokens[ast.mainToken(rhs_node)].tag == .dot_dot)
                    try analyzeNode(ast, resolved, typed, ast.data(rhs_node).lhs, diag)
                else
                    try analyzeNode(ast, resolved, typed, rhs_node, diag);
                param_used[i] = true;
                if (ast.data(param).lhs == @import("Ast.zig").null_node) {
                    try typed.inferred_param_types.put(typed.allocator, param, arg_ty);
                    try inferred.append(typed.allocator, param);
                }
                matched = true;
                break;
            }
            if (!matched) return diag.failAt(ast.tokens[ast.mainToken(arg_node)].start, "unknown named argument '{s}'", .{arg_name});
            continue;
        }
        while (positional_index < params.len and param_used[positional_index]) positional_index += 1;
        const arg_ty = if (ast.tag(arg_node) == .unary_expr and ast.tokens[ast.mainToken(arg_node)].tag == .dot_dot)
            try analyzeNode(ast, resolved, typed, ast.data(arg_node).lhs, diag)
        else
            try analyzeNode(ast, resolved, typed, arg_node, diag);
        if (positional_index < params.len) {
            const param: NodeIndex = @intCast(params[positional_index]);
            param_used[positional_index] = true;
            if (ast.data(param).lhs == @import("Ast.zig").null_node) {
                try typed.inferred_param_types.put(typed.allocator, param, arg_ty);
                try inferred.append(typed.allocator, param);
            }
            positional_index += 1;
        }
    }
    for (params, 0..) |param_idx, i| {
        if (param_used[i]) continue;
        const param: NodeIndex = @intCast(param_idx);
        if (lastParamIsVariadic(ast, params) and i == params.len - 1) continue;
        if (paramDefaultInit(ast, param) == @import("Ast.zig").null_node) continue;
    }
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

fn callArgValueNode(ast: *const Ast, arg: NodeIndex) NodeIndex {
    if (ast.tag(arg) == .assign_stmt) return ast.data(arg).rhs;
    if (ast.tag(arg) == .binary_expr and ast.tokens[ast.mainToken(arg)].tag == .equal and ast.tag(ast.data(arg).lhs) == .identifier) return ast.data(arg).rhs;
    if (ast.tag(arg) == .unary_expr and ast.tokens[ast.mainToken(arg)].tag == .dot_dot) return ast.data(arg).lhs;
    return arg;
}

fn isImportAliasField(ast: *const Ast, resolved: *const Resolved, field_access: NodeIndex) bool {
    if (!isValidNode(ast, field_access) or ast.tag(field_access) != .field_access) return false;
    const lhs = ast.data(field_access).lhs;
    if (!isValidNode(ast, lhs) or ast.tag(lhs) != .identifier) return false;
    const decl = resolved.local_values.get(lhs) orelse return false;
    return isValidNode(ast, decl) and ast.tag(decl) == .import_decl;
}

fn compilerIntrinsicReturnType(ast: *const Ast, name: []const u8, diag: Diagnostic) !?Type {
    if (std.mem.eql(u8, name, "compiler_create_workspace") or
        std.mem.eql(u8, name, "get_current_workspace") or
        std.mem.eql(u8, name, "compiler_wait_for_message") or
        std.mem.eql(u8, name, "add_global_data") or
        std.mem.eql(u8, name, "run_command"))
    {
        return Type.init(InternPool.well_known.s64_type);
    }
    if (std.mem.eql(u8, name, "get_build_options") or
        std.mem.eql(u8, name, "compiler_get_nodes") or
        std.mem.eql(u8, name, "compiler_get_code") or
        std.mem.eql(u8, name, "make_location") or
        std.mem.eql(u8, name, "get_completed_work"))
    {
        return Type.init(InternPool.well_known.any_type);
    }
    if (std.mem.eql(u8, name, "code_to_string") or
        std.mem.eql(u8, name, "builder_to_string") or
        std.mem.eql(u8, name, "sprint") or
        std.mem.eql(u8, name, "tprint") or
        std.mem.eql(u8, name, "trim") or
        std.mem.eql(u8, name, "to_string") or
        std.mem.eql(u8, name, "copy_string") or
        std.mem.eql(u8, name, "join") or
        std.mem.eql(u8, name, "replace") or
        std.mem.eql(u8, name, "slice") or
        std.mem.eql(u8, name, "path_strip_filename") or
        std.mem.eql(u8, name, "get_path_of_running_executable"))
    {
        return Type.string();
    }
    if (std.mem.eql(u8, name, "to_c_string")) return Type.init(try internPointerType(ast, Type.init(InternPool.well_known.u8_type), diag));
    if (std.mem.eql(u8, name, "compare") or
        std.mem.eql(u8, name, "builder_string_length") or
        std.mem.eql(u8, name, "find_index_from_left") or
        std.mem.eql(u8, name, "find_index_from_right") or
        std.mem.eql(u8, name, "string_to_int") or
        std.mem.eql(u8, name, "parse_int") or
        std.mem.eql(u8, name, "to_integer") or
        std.mem.eql(u8, name, "c_style_strlen") or
        std.mem.eql(u8, name, "get_number_of_processors") or
        std.mem.eql(u8, name, "min") or
        std.mem.eql(u8, name, "max") or
        std.mem.eql(u8, name, "clamp"))
    {
        return Type.init(InternPool.well_known.s64_type);
    }
    if (std.mem.eql(u8, name, "contains") or std.mem.eql(u8, name, "begins_with")) return Type.boolType();
    if (std.mem.eql(u8, name, "thread_is_done")) return Type.boolType();
    if (std.mem.eql(u8, name, "copy_file") or
        std.mem.eql(u8, name, "build_cpp") or
        std.mem.eql(u8, name, "build_cpp_dynamic_lib") or
        std.mem.eql(u8, name, "cpp_link_library") or
        std.mem.eql(u8, name, "generate_bindings") or
        std.mem.eql(u8, name, "init"))
    {
        return Type.boolType();
    }
    if (std.mem.eql(u8, name, "string_to_float")) return Type.init(InternPool.well_known.float64_type);
    if (std.mem.eql(u8, name, "sqrt") or std.mem.eql(u8, name, "cos")) return Type.init(InternPool.well_known.float64_type);
    if (std.mem.eql(u8, name, "split")) return Type.init(InternPool.well_known.any_type);
    if (std.mem.eql(u8, name, "set_build_options") or
        std.mem.eql(u8, name, "set_build_options_dc") or
        std.mem.eql(u8, name, "set_optimization") or
        std.mem.eql(u8, name, "compiler_begin_intercept") or
        std.mem.eql(u8, name, "compiler_end_intercept") or
        std.mem.eql(u8, name, "compiler_set_workspace_status") or
        std.mem.eql(u8, name, "compiler_custom_link_command_is_complete") or
        std.mem.eql(u8, name, "compiler_report") or
        std.mem.eql(u8, name, "do_error_checking") or
        std.mem.eql(u8, name, "log_error") or
        std.mem.eql(u8, name, "add_build_file") or
        std.mem.eql(u8, name, "add_build_string") or
        std.mem.eql(u8, name, "print_expression") or
        std.mem.eql(u8, name, "init_string_builder") or
        std.mem.eql(u8, name, "free_buffers") or
        std.mem.eql(u8, name, "append") or
        std.mem.eql(u8, name, "advance") or
        std.mem.eql(u8, name, "print_to_builder") or
        std.mem.eql(u8, name, "start") or
        std.mem.eql(u8, name, "add_work") or
        std.mem.eql(u8, name, "shutdown") or
        std.mem.eql(u8, name, "lock") or
        std.mem.eql(u8, name, "unlock") or
        std.mem.eql(u8, name, "thread_init") or
        std.mem.eql(u8, name, "thread_start") or
        std.mem.eql(u8, name, "thread_deinit") or
        std.mem.eql(u8, name, "thread_destroy"))
    {
        return Type.voidType();
    }
    return null;
}

fn isBuiltinTypeName(name: []const u8) bool {
    return std.mem.eql(u8, name, "void") or std.mem.eql(u8, name, "bool") or std.mem.eql(u8, name, "string") or std.mem.eql(u8, name, "int") or std.mem.eql(u8, name, "s64") or std.mem.eql(u8, name, "float") or std.mem.eql(u8, name, "float32") or std.mem.eql(u8, name, "float64") or std.mem.eql(u8, name, "s32") or std.mem.eql(u8, name, "u8") or std.mem.eql(u8, name, "u16") or std.mem.eql(u8, name, "u32") or std.mem.eql(u8, name, "u64") or std.mem.eql(u8, name, "Vector2") or std.mem.eql(u8, name, "Vector3") or std.mem.eql(u8, name, "Vector4") or std.mem.eql(u8, name, "Type") or std.mem.eql(u8, name, "Any") or std.mem.eql(u8, name, "String_Builder") or isCompilerMetaTypeName(name);
}

fn isOperatorIdentifierName(name: []const u8) bool {
    return std.mem.eql(u8, name, "+") or
        std.mem.eql(u8, name, "-") or
        std.mem.eql(u8, name, "*") or
        std.mem.eql(u8, name, "/") or
        std.mem.eql(u8, name, "%") or
        std.mem.eql(u8, name, "==") or
        std.mem.eql(u8, name, "!=") or
        std.mem.eql(u8, name, "<") or
        std.mem.eql(u8, name, "<=") or
        std.mem.eql(u8, name, ">") or
        std.mem.eql(u8, name, ">=");
}

fn isCompilerMetaTypeName(name: []const u8) bool {
    return std.mem.eql(u8, name, "Workspace") or
        std.mem.eql(u8, name, "Build_Options") or
        std.mem.eql(u8, name, "Generate_Bindings_Options") or
        std.mem.eql(u8, name, "Code") or
        std.mem.eql(u8, name, "Code_Node") or
        std.mem.eql(u8, name, "Code_Literal") or
        std.mem.eql(u8, name, "Code_Argument") or
        std.mem.eql(u8, name, "Code_Procedure_Call") or
        std.mem.eql(u8, name, "Code_Declaration") or
        std.mem.eql(u8, name, "Source_Code_Location") or
        std.mem.eql(u8, name, "Type_Info_Pointer") or
        std.mem.eql(u8, name, "Message") or
        std.mem.eql(u8, name, "Message_File") or
        std.mem.eql(u8, name, "Message_Import") or
        std.mem.eql(u8, name, "Message_Phase") or
        std.mem.eql(u8, name, "Message_Typechecked") or
        std.mem.eql(u8, name, "Message_Debug_Dump") or
        std.mem.eql(u8, name, "Message_Complete") or
        std.mem.eql(u8, name, "Version_Info") or
        std.mem.eql(u8, name, "Metaprogram_Plugin") or
        std.mem.eql(u8, name, "Intercept_Flags");
}

fn typeFromTypeExpr(ast: *const Ast, node: NodeIndex, diag: Diagnostic) !Type {
    return typeFromTypeExprWithAliases(ast, null, node, diag);
}

fn typeFromTypeExprWithAliases(ast: *const Ast, typed: ?*Typed, node: NodeIndex, diag: Diagnostic) !Type {
    if (node == @import("Ast.zig").null_node) return Type.voidType();
    if ((ast.tag(node) == .type_expr or ast.tag(node) == .identifier) and typed != null) {
        const name = ast.tokenSlice(ast.mainToken(node));
        if (typed.?.type_aliases.get(name)) |alias_ty| return alias_ty;
    }
    if (ast.tag(node) == .struct_type or ast.tag(node) == .union_type or ast.tag(node) == .enum_type or ast.tag(node) == .array_type) return Type.init(InternPool.well_known.any_type);
    if (ast.tag(node) == .pointer_type) return Type.init(try internPointerType(ast, try typeFromTypeExprWithAliases(ast, typed, ast.data(node).lhs, diag), diag));
    if (ast.tag(node) == .proc_type) return Type.init(try internProcType(ast, node, diag));
    if (ast.tag(node) == .type_of_expr) return Type.init(InternPool.well_known.s64_type);
    if (ast.tag(node) != .type_expr and ast.tag(node) != .identifier) return diag.failAt(ast.tokens[ast.mainToken(node)].start, "expected type expression", .{});
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
    if (std.mem.eql(u8, name, "String_Builder")) return Type.init(InternPool.well_known.s64_type);
    if (std.mem.eql(u8, name, "Vector2")) return Type.init(InternPool.well_known.any_type);
    if (std.mem.eql(u8, name, "Vector3")) return Type.init(InternPool.well_known.vector3_type);
    if (std.mem.eql(u8, name, "Vector4")) return Type.init(InternPool.well_known.vector4_type);
    if (std.mem.eql(u8, name, "Workspace")) return Type.init(InternPool.well_known.s64_type);
    if (isCompilerMetaTypeName(name)) return Type.init(InternPool.well_known.any_type);
    return Type.init(InternPool.well_known.any_type);
}

fn internPointerType(ast: *const Ast, child: Type, diag: Diagnostic) !@import("InternPool.zig").Index {
    const ip = active_ip orelse return diag.failAt(0, "internal error: pointer type interning without InternPool", .{});
    _ = ast;
    return ip.internPointerType(child.index);
}

fn isValidNode(ast: *const Ast, node: NodeIndex) bool {
    return node != @import("Ast.zig").null_node and node < ast.node_tags.items.len;
}

fn internProcType(ast: *const Ast, proc_type: NodeIndex, diag: Diagnostic) !@import("InternPool.zig").Index {
    const ip = active_ip orelse return diag.failAt(0, "internal error: procedure type interning without InternPool", .{});
    _ = ast;
    return ip.internProcType(proc_type);
}

fn varDeclHasProcedureType(ast: *const Ast, typed: *Typed, decl: NodeIndex, diag: Diagnostic) !bool {
    if (!isValidNode(ast, decl) or ast.tag(decl) != .var_decl) return false;
    const type_node = ast.data(decl).lhs;
    if (type_node == @import("Ast.zig").null_node or !isValidNode(ast, type_node)) return false;
    if (ast.tag(type_node) == .proc_type) return true;
    return (try typeFromTypeExprWithAliases(ast, typed, type_node, diag)).isProcedure();
}

fn procedureTypeReturnType(ast: *const Ast, typed: *Typed, proc_ty: Type, diag: Diagnostic) !Type {
    const ip = active_ip orelse return diag.failAt(0, "internal error: procedure type query without InternPool", .{});
    return switch (ip.key(proc_ty.index)) {
        .type_proc => |proc| blk: {
            const proc_type_node: NodeIndex = proc.sig_node;
            if (!isValidNode(ast, proc_type_node) or ast.tag(proc_type_node) != .proc_type) break :blk Type.init(InternPool.well_known.any_type);
            const ret = ast.data(proc_type_node).rhs;
            if (ret == @import("Ast.zig").null_node) break :blk Type.voidType();
            break :blk try typeFromTypeExprWithAliases(ast, typed, ret, diag);
        },
        else => Type.init(InternPool.well_known.any_type),
    };
}

test "sema allows calling local values inferred as Any" {
    const lexer = @import("lexer.zig");
    const parser = @import("parser.zig");
    const resolve_mod = @import("resolve.zig");

    const source =
        "funcs: [4] () -> int;\n" ++
        "setup :: (theme: int) #expand {\n" ++
        "  proc := funcs[theme];\n" ++
        "  x := proc();\n" ++
        "}\n" ++
        "main :: () {}\n";
    const diag = Diagnostic.init(std.testing.allocator, "local_any_call.jai", source);

    var tokens = try lexer.tokenize(std.testing.allocator, source, diag);
    defer tokens.deinit(std.testing.allocator);

    const slice = tokens.slice();
    var ast = try parser.parse(std.testing.allocator, source, slice.items(.tag), slice.items(.start), slice.items(.end), diag);
    defer {
        std.testing.allocator.free(ast.tokens);
        ast.deinit();
    }

    var resolved = try resolve_mod.resolve(std.testing.allocator, &ast, diag, true, &.{});
    defer resolved.deinit();
    try resolved.failIfImplicitPlaceholders(diag);

    var ip = try InternPool.init(std.testing.allocator);
    defer ip.deinit();
    var typed = try analyze(std.testing.allocator, &ast, &resolved, &ip, diag);
    defer typed.deinit();
}
