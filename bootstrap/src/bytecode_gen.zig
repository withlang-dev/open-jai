const std = @import("std");
const Ast = @import("Ast.zig").Ast;
const NodeIndex = @import("Ast.zig").NodeIndex;
const Diagnostic = @import("diagnostics.zig").Diagnostic;
const Typed = @import("Sema.zig").Typed;
const Bytecode = @import("Bytecode.zig");

pub fn generate(allocator: std.mem.Allocator, ast: *const Ast, typed: *const Typed, diag: Diagnostic) !Bytecode.Program {
    var program = Bytecode.Program.init(allocator);
    errdefer program.deinit();
    var proc = Bytecode.ProcBytecode{ .name = ast.tokenSlice(ast.mainToken(typed.main_proc)) };
    errdefer proc.deinit(allocator);
    try genBlock(ast, &program, &proc, ast.data(typed.main_proc).lhs, diag);
    try proc.instructions.append(allocator, .{ .opcode = .ret_void });
    const main_idx: u32 = @intCast(program.procs.items.len);
    try program.procs.append(allocator, proc);
    program.main_proc = main_idx;
    return program;
}

fn genBlock(ast: *const Ast, program: *Bytecode.Program, proc: *Bytecode.ProcBytecode, block: NodeIndex, diag: Diagnostic) !void {
    for (ast.extraSlice(ast.data(block).lhs)) |stmt| try genStmt(ast, program, proc, @intCast(stmt), diag);
}

fn genStmt(ast: *const Ast, program: *Bytecode.Program, proc: *Bytecode.ProcBytecode, stmt: NodeIndex, diag: Diagnostic) !void {
    switch (ast.tag(stmt)) {
        .expr_stmt => _ = try genExpr(ast, program, proc, ast.data(stmt).lhs, diag),
        .assign_stmt => {
            const rhs = try genExpr(ast, program, proc, ast.data(stmt).rhs, diag);
            try proc.instructions.append(program.allocator, .{ .opcode = .store, .dest = ast.mainToken(ast.data(stmt).lhs), .arg1 = rhs, .source_node = stmt });
        },
        .return_stmt => try proc.instructions.append(program.allocator, .{ .opcode = .ret_void, .source_node = stmt }),
        else => return diag.failAt(ast.tokens[ast.mainToken(stmt)].start, "unsupported statement in bytecode generator", .{}),
    }
}

fn genExpr(ast: *const Ast, program: *Bytecode.Program, proc: *Bytecode.ProcBytecode, expr: NodeIndex, diag: Diagnostic) anyerror!Bytecode.Register {
    switch (ast.tag(expr)) {
        .string_literal => {
            const decoded = try decodeString(program.allocator, ast.stringTokenContents(ast.mainToken(expr)), diag, ast.tokens[ast.mainToken(expr)].start);
            defer program.allocator.free(decoded);
            const string_idx = try program.addString(decoded);
            const reg = proc.num_registers;
            proc.num_registers += 1;
            try proc.instructions.append(program.allocator, .{ .opcode = .load_string, .dest = reg, .arg1 = string_idx, .source_node = expr });
            return reg;
        },
        .integer_literal => {
            const raw = ast.tokenSlice(ast.mainToken(expr));
            const value = std.fmt.parseInt(i64, raw, 10) catch return diag.failAt(ast.tokens[ast.mainToken(expr)].start, "invalid integer literal '{s}'", .{raw});
            const reg = proc.num_registers;
            proc.num_registers += 1;
            try proc.instructions.append(program.allocator, .{ .opcode = .load_int, .dest = reg, .arg1 = @intCast(value), .source_node = expr });
            return reg;
        },
        .float_literal => {
            const raw = ast.tokenSlice(ast.mainToken(expr));
            const value = std.fmt.parseFloat(f64, raw) catch return diag.failAt(ast.tokens[ast.mainToken(expr)].start, "invalid float literal '{s}'", .{raw});
            const bits: u64 = @bitCast(value);
            const reg = proc.num_registers;
            proc.num_registers += 1;
            try proc.instructions.append(program.allocator, .{ .opcode = .load_float, .dest = reg, .arg1 = @truncate(bits), .arg2 = @truncate(bits >> 32), .source_node = expr });
            return reg;
        },
        .bool_literal => {
            const reg = proc.num_registers;
            proc.num_registers += 1;
            try proc.instructions.append(program.allocator, .{ .opcode = .load_bool, .dest = reg, .arg1 = ast.data(expr).lhs, .source_node = expr });
            return reg;
        },
        .char_literal => {
            const value = try decodeCharLiteral(program.allocator, ast.stringTokenContents(ast.data(expr).lhs), diag, ast.tokens[ast.data(expr).lhs].start);
            const reg = proc.num_registers;
            proc.num_registers += 1;
            try proc.instructions.append(program.allocator, .{ .opcode = .load_int, .dest = reg, .arg1 = @intCast(value), .source_node = expr });
            return reg;
        },
        .type_of_expr => {
            const type_id = try phase2TypeId(ast, ast.data(expr).lhs, diag);
            const reg = proc.num_registers;
            proc.num_registers += 1;
            try proc.instructions.append(program.allocator, .{ .opcode = .load_type, .dest = reg, .arg1 = type_id, .source_node = expr });
            return reg;
        },
        .size_of_expr => {
            const size = try phase3SizeOf(ast, ast.data(expr).lhs, diag);
            const reg = proc.num_registers;
            proc.num_registers += 1;
            try proc.instructions.append(program.allocator, .{ .opcode = .load_int, .dest = reg, .arg1 = @intCast(size), .source_node = expr });
            return reg;
        },
        .type_expr => {
            const type_id = try typeIdFromToken(ast, ast.mainToken(expr), diag);
            const reg = proc.num_registers;
            proc.num_registers += 1;
            try proc.instructions.append(program.allocator, .{ .opcode = .load_type, .dest = reg, .arg1 = type_id, .source_node = expr });
            return reg;
        },
        .identifier => {
            const reg = proc.num_registers;
            proc.num_registers += 1;
            try proc.instructions.append(program.allocator, .{ .opcode = .load_const_ref, .dest = reg, .source_node = expr });
            return reg;
        },
        .binary_expr => {
            const op = ast.tokens[ast.mainToken(expr)].tag;
            if (op != .star) return diag.failAt(ast.tokens[ast.mainToken(expr)].start, "Phase 3 bytecode currently supports only '*' binary expressions", .{});
            const lhs = try genExpr(ast, program, proc, ast.data(expr).lhs, diag);
            const rhs = try genExpr(ast, program, proc, ast.data(expr).rhs, diag);
            const reg = proc.num_registers;
            proc.num_registers += 1;
            try proc.instructions.append(program.allocator, .{ .opcode = .mul_int, .dest = reg, .arg1 = lhs, .arg2 = rhs, .source_node = expr });
            return reg;
        },
        .call_expr => {
            const callee = ast.data(expr).lhs;
            const name = ast.tokenSlice(ast.mainToken(callee));
            if (!std.mem.eql(u8, name, "print")) return diag.failAt(ast.tokens[ast.mainToken(callee)].start, "Phase 1 bytecode only supports print", .{});
            const args = ast.extraSlice(ast.data(expr).rhs);
            if (args.len == 0) return diag.failAt(ast.tokens[ast.mainToken(expr)].start, "print expects at least one argument", .{});
            const first_reg = try genExpr(ast, program, proc, @intCast(args[0]), diag);
            if (args.len == 1) {
                try proc.instructions.append(program.allocator, .{ .opcode = .call_extern, .dest = @intFromEnum(Bytecode.ExternSymbol.openjai_print), .arg1 = first_reg, .source_node = expr });
                return first_reg;
            }
            if (ast.tag(@intCast(args[0])) != .string_literal) return diag.failAt(ast.tokens[ast.mainToken(@intCast(args[0]))].start, "Phase 2 formatted print requires a literal format string", .{});
            try emitFormattedPrint(ast, program, proc, @intCast(args[0]), args[1..], diag);
            return first_reg;
        },
        else => return diag.failAt(ast.tokens[ast.mainToken(expr)].start, "unsupported expression in bytecode generator", .{}),
    }
}

fn decodeString(allocator: std.mem.Allocator, raw: []const u8, diag: Diagnostic, offset: usize) ![]u8 {
    var out = std.ArrayList(u8).empty;
    errdefer out.deinit(allocator);
    var i: usize = 0;
    while (i < raw.len) : (i += 1) {
        if (raw[i] == '\\') {
            i += 1;
            if (i >= raw.len) return diag.failAt(offset, "unterminated escape sequence", .{});
            const c: u8 = switch (raw[i]) {
                'n' => '\n',
                'r' => '\r',
                't' => '\t',
                '\\' => '\\',
                '"' => '"',
                '0' => 0,
                else => return diag.failAt(offset + i, "unsupported string escape '\\{c}'", .{raw[i]}),
            };
            try out.append(allocator, c);
        } else try out.append(allocator, raw[i]);
    }
    return out.toOwnedSlice(allocator);
}

fn decodeCharLiteral(allocator: std.mem.Allocator, raw: []const u8, diag: Diagnostic, offset: usize) !i64 {
    const decoded = try decodeString(allocator, raw, diag, offset);
    defer allocator.free(decoded);
    if (decoded.len == 0) return diag.failAt(offset, "#char literal cannot be empty", .{});
    if (decoded.len != 1) return diag.failAt(offset, "Phase 2 #char currently requires exactly one byte", .{});
    return decoded[0];
}

fn phase2TypeId(ast: *const Ast, operand: NodeIndex, diag: Diagnostic) !u32 {
    return switch (ast.tag(operand)) {
        .string_literal => 14,
        .type_expr => try typeIdFromToken(ast, ast.mainToken(operand), diag),
        .integer_literal, .char_literal => 5,
        .float_literal => 12,
        .bool_literal => 1,
        else => diag.failAt(ast.tokens[ast.mainToken(operand)].start, "Phase 2 type_of currently supports literals only", .{}),
    };
}

fn typeIdFromToken(ast: *const Ast, token: u32, diag: Diagnostic) !u32 {
    const name = ast.tokenSlice(token);
    if (std.mem.eql(u8, name, "int") or std.mem.eql(u8, name, "s64")) return 5;
    if (std.mem.eql(u8, name, "s32")) return 4;
    if (std.mem.eql(u8, name, "u16")) return 8;
    if (std.mem.eql(u8, name, "float") or std.mem.eql(u8, name, "float32")) return 12;
    if (std.mem.eql(u8, name, "float64")) return 13;
    if (std.mem.eql(u8, name, "string")) return 14;
    if (std.mem.eql(u8, name, "bool")) return 1;
    if (std.mem.eql(u8, name, "Type")) return 15;
    if (std.mem.eql(u8, name, "Any")) return 16;
    return diag.failAt(ast.tokens[token].start, "unknown Phase 3 type '{s}'", .{name});
}

fn phase3SizeOf(ast: *const Ast, operand: NodeIndex, diag: Diagnostic) !u64 {
    const type_id = switch (ast.tag(operand)) {
        .type_expr => try typeIdFromToken(ast, ast.mainToken(operand), diag),
        .identifier => blk: {
            const name = ast.tokenSlice(ast.mainToken(operand));
            if (std.mem.eql(u8, name, "TI")) break :blk 4;
            return diag.failAt(ast.tokens[ast.mainToken(operand)].start, "Phase 3 size_of currently cannot resolve identifier '{s}'", .{name});
        },
        .type_of_expr => try phase2TypeId(ast, ast.data(operand).lhs, diag),
        else => try phase2TypeId(ast, operand, diag),
    };
    return switch (type_id) {
        0 => 0,
        1 => 1,
        4, 12 => 4,
        5, 10, 13, 15 => 8,
        8 => 2,
        14, 16 => 16,
        else => diag.failAt(ast.tokens[ast.mainToken(operand)].start, "Phase 3 size_of has no size for type id {d}", .{type_id}),
    };
}

fn emitFormattedPrint(ast: *const Ast, program: *Bytecode.Program, proc: *Bytecode.ProcBytecode, fmt_node: NodeIndex, arg_nodes: []const u32, diag: Diagnostic) anyerror!void {
    const raw_fmt = ast.stringTokenContents(ast.mainToken(fmt_node));
    const fmt = try decodeString(program.allocator, raw_fmt, diag, ast.tokens[ast.mainToken(fmt_node)].start);
    defer program.allocator.free(fmt);
    var start: usize = 0;
    var arg_index: usize = 0;
    var i: usize = 0;
    while (i < fmt.len) : (i += 1) {
        if (fmt[i] != '%') continue;
        if (i + 1 < fmt.len and fmt[i + 1] == '%') {
            try emitLiteralPrint(program, proc, fmt[start..i + 1], fmt_node);
            i += 1;
            start = i + 1;
            continue;
        }
        if (start < i) try emitLiteralPrint(program, proc, fmt[start..i], fmt_node);
        if (arg_index >= arg_nodes.len) return diag.failAt(ast.tokens[ast.mainToken(fmt_node)].start, "print format has more placeholders than arguments", .{});
        const arg_reg = try genExpr(ast, program, proc, @intCast(arg_nodes[arg_index]), diag);
        try proc.instructions.append(program.allocator, .{ .opcode = .format_print, .arg1 = arg_reg, .source_node = @intCast(arg_nodes[arg_index]) });
        arg_index += 1;
        start = i + 1;
    }
    if (start < fmt.len) try emitLiteralPrint(program, proc, fmt[start..], fmt_node);
    if (arg_index != arg_nodes.len) return diag.failAt(ast.tokens[ast.mainToken(fmt_node)].start, "print format has fewer placeholders than arguments", .{});
}

fn emitLiteralPrint(program: *Bytecode.Program, proc: *Bytecode.ProcBytecode, text: []const u8, source_node: NodeIndex) !void {
    if (text.len == 0) return;
    const string_idx = try program.addString(text);
    const reg = proc.num_registers;
    proc.num_registers += 1;
    try proc.instructions.append(program.allocator, .{ .opcode = .load_string, .dest = reg, .arg1 = string_idx, .source_node = source_node });
    try proc.instructions.append(program.allocator, .{ .opcode = .call_extern, .dest = @intFromEnum(Bytecode.ExternSymbol.openjai_print), .arg1 = reg, .source_node = source_node });
}
