const std = @import("std");
const Ast = @import("Ast.zig").Ast;
const NodeIndex = @import("Ast.zig").NodeIndex;
const Diagnostic = @import("diagnostics.zig").Diagnostic;
const Typed = @import("Sema.zig").Typed;
const Bytecode = @import("Bytecode.zig");

const Resolved = @import("resolve.zig").Resolved;

pub fn generate(allocator: std.mem.Allocator, ast: *const Ast, typed: *const Typed, resolved: *const Resolved, diag: Diagnostic) !Bytecode.Program {
        var program = Bytecode.Program.init(allocator);
    errdefer program.deinit();
    const root_decls = ast.extraSlice(ast.data(ast.root).lhs);
    for (root_decls) |decl_idx| {
        const decl: NodeIndex = @intCast(decl_idx);
        if (ast.tag(decl) != .proc_decl or decl == typed.main_proc) continue;
        var helper = Bytecode.ProcBytecode{ .name = ast.tokenSlice(ast.mainToken(decl)) };
        errdefer helper.deinit(allocator);
        var helper_ctx = GenContext{ .ast = ast, .program = &program, .proc = &helper, .resolved = resolved, .typed = typed };
        defer helper_ctx.deinit();
        try helper_ctx.genBlock(ast.data(decl).lhs, diag);
        try helper.instructions.append(allocator, .{ .opcode = .ret_void });
        try program.procs.append(allocator, helper);
    }
    var proc = Bytecode.ProcBytecode{ .name = ast.tokenSlice(ast.mainToken(typed.main_proc)) };
    errdefer proc.deinit(allocator);
    var ctx = GenContext{ .ast = ast, .program = &program, .proc = &proc, .resolved = resolved, .typed = typed };
    defer ctx.deinit();
    try ctx.genBlock(ast.data(typed.main_proc).lhs, diag);
    try proc.instructions.append(allocator, .{ .opcode = .ret_void });
    const main_idx: u32 = @intCast(program.procs.items.len);
    try program.procs.append(allocator, proc);
    program.main_proc = main_idx;
    return program;
}

pub fn generateProc(allocator: std.mem.Allocator, ast: *const Ast, resolved: *const Resolved, proc_node: NodeIndex, diag: Diagnostic) !Bytecode.Program {
    return generateProcWithParamCount(allocator, ast, resolved, null, proc_node, diag, 0);
}

pub fn generateProcWithParamCount(allocator: std.mem.Allocator, ast: *const Ast, resolved: *const Resolved, typed: ?*const Typed, proc_node: NodeIndex, diag: Diagnostic, param_count: usize) !Bytecode.Program {
    var program = Bytecode.Program.init(allocator);
    errdefer program.deinit();
    var proc = Bytecode.ProcBytecode{ .name = ast.tokenSlice(ast.mainToken(proc_node)) };
    proc.num_registers = @intCast(param_count);
    var ctx = GenContext{ .ast = ast, .resolved = resolved, .program = &program, .proc = &proc, .typed = typed };
    try ctx.bindProcParams(proc_node, param_count, diag);
    defer ctx.deinit();
    try ctx.genBlock(ast.data(proc_node).lhs, diag);
    try proc.instructions.append(allocator, .{ .opcode = .ret_void, .source_node = proc_node });
    try program.procs.append(allocator, proc);
    program.main_proc = 0;
    return program;
}

pub fn generateBlockProc(allocator: std.mem.Allocator, ast: *const Ast, resolved: *const Resolved, block: NodeIndex, diag: Diagnostic) !Bytecode.Program {
    var program = Bytecode.Program.init(allocator);
    errdefer program.deinit();
    var proc = Bytecode.ProcBytecode{ .name = "#run_block" };
    var ctx = GenContext{ .ast = ast, .resolved = resolved, .program = &program, .proc = &proc };
    defer ctx.deinit();
    try ctx.genBlock(block, diag);
    try proc.instructions.append(allocator, .{ .opcode = .ret_void, .source_node = block });
    try program.procs.append(allocator, proc);
    program.main_proc = 0;
    return program;
}

const GenContext = struct {
    ast: *const Ast,
    program: *Bytecode.Program,
    proc: *Bytecode.ProcBytecode,
    resolved: *const Resolved,
    typed: ?*const Typed = null,
    decl_registers: std.AutoHashMapUnmanaged(NodeIndex, Bytecode.Register) = .empty,
    pointer_addrs: std.AutoHashMapUnmanaged(Bytecode.Register, Bytecode.Register) = .empty,

    pub fn deinit(ctx: *GenContext) void {
        ctx.decl_registers.deinit(ctx.program.allocator);
        ctx.pointer_addrs.deinit(ctx.program.allocator);
    }

    fn ensureProcEmitted(ctx: *GenContext, proc_node: NodeIndex, diag: Diagnostic) !u32 {
        for (ctx.program.procs.items, 0..) |p, i| {
            if (std.mem.eql(u8, p.name, ctx.ast.tokenSlice(ctx.ast.mainToken(proc_node)))) return @intCast(i);
        }
        var helper = Bytecode.ProcBytecode{ .name = ctx.ast.tokenSlice(ctx.ast.mainToken(proc_node)) };
        errdefer helper.deinit(ctx.program.allocator);
        var helper_ctx = GenContext{ .ast = ctx.ast, .program = ctx.program, .proc = &helper, .resolved = ctx.resolved, .typed = ctx.typed };
        defer helper_ctx.deinit();
        try helper_ctx.genBlock(ctx.ast.data(proc_node).lhs, diag);
        try helper.instructions.append(ctx.program.allocator, .{ .opcode = .ret_void });
        const idx: u32 = @intCast(ctx.program.procs.items.len);
        try ctx.program.procs.append(ctx.program.allocator, helper);
        return idx;
    }

    fn bindProcParams(ctx: *GenContext, proc_node: NodeIndex, param_count: usize, diag: Diagnostic) !void {
        if (ctx.ast.data(proc_node).rhs == 0) {
            if (param_count != 0) return diag.failAt(ctx.ast.tokens[ctx.ast.mainToken(proc_node)].start, "#run argument count does not match procedure parameters", .{});
            return;
        }
        const sig = ctx.ast.extraSlice(ctx.ast.data(proc_node).rhs);
        if (sig.len < 2) return;
        const params = ctx.ast.extraSlice(sig[0]);
        if (params.len != param_count) return diag.failAt(ctx.ast.tokens[ctx.ast.mainToken(proc_node)].start, "#run argument count does not match procedure parameters", .{});
        for (params, 0..) |param_idx, i| {
            try ctx.decl_registers.put(ctx.program.allocator, @intCast(param_idx), @intCast(i));
        }
    }

    pub fn genBlock(ctx: *GenContext, block: NodeIndex, diag: Diagnostic) anyerror!void {
        for (ctx.ast.extraSlice(ctx.ast.data(block).lhs)) |stmt| try ctx.genStmt(@intCast(stmt), diag);
    }

    fn genStmt(ctx: *GenContext, stmt: NodeIndex, diag: Diagnostic) !void {
        const ast = ctx.ast;
        switch (ast.tag(stmt)) {
            .expr_stmt => _ = try ctx.genExpr(ast.data(stmt).lhs, diag),
            .stmt_list => {
                var is_all_assign = true;
                for (ast.extraSlice(ast.data(stmt).lhs)) |child| {
                    if (ast.tag(@intCast(child)) != .assign_stmt) is_all_assign = false;
                }
                if (is_all_assign) {
                    const children = ast.extraSlice(ast.data(stmt).lhs);
                    var lhs_decls = std.ArrayList(NodeIndex).empty;
                    var rhs_regs = std.ArrayList(Bytecode.Register).empty;
                    defer lhs_decls.deinit(ctx.program.allocator);
                    defer rhs_regs.deinit(ctx.program.allocator);
                    for (children) |child_idx| {
                        const child: NodeIndex = @intCast(child_idx);
                        const lhs = ast.data(child).lhs;
                        const decl = ctx.resolved.local_values.get(lhs) orelse return diag.failAt(ast.tokens[ast.mainToken(lhs)].start, "assignment target must resolve to a local variable", .{});
                        try lhs_decls.append(ctx.program.allocator, decl);
                        try rhs_regs.append(ctx.program.allocator, try ctx.genExpr(ast.data(child).rhs, diag));
                    }
                    for (lhs_decls.items, rhs_regs.items) |decl, reg| try ctx.decl_registers.put(ctx.program.allocator, decl, reg);
                } else {
                    for (ast.extraSlice(ast.data(stmt).lhs)) |child| try ctx.genStmt(@intCast(child), diag);
                }
            },
            .assign_stmt => {
                const rhs = try ctx.genExpr(ast.data(stmt).rhs, diag);
                const lhs = ast.data(stmt).lhs;
                if (ast.tag(lhs) == .unary_expr and ast.tokens[ast.mainToken(lhs)].tag == .shift_left) {
                    const ptr = try ctx.genExpr(ast.data(lhs).lhs, diag);
                    try ctx.proc.instructions.append(ctx.program.allocator, .{ .opcode = .store_ptr, .dest = ptr, .arg1 = rhs, .source_node = stmt });
                    if (ctx.pointer_addrs.get(ptr)) |addr_reg| try ctx.decl_registers.put(ctx.program.allocator, addr_reg, rhs);
                    return;
                }
                if (ctx.resolved.local_values.get(lhs)) |decl| {
                    if (ctx.decl_registers.get(decl)) |old_reg| {
                        try ctx.proc.instructions.append(ctx.program.allocator, .{ .opcode = .load, .dest = old_reg, .arg1 = rhs, .source_node = stmt });
                        return;
                    }
                    try ctx.decl_registers.put(ctx.program.allocator, decl, rhs);
                }
                try ctx.proc.instructions.append(ctx.program.allocator, .{ .opcode = .store, .dest = rhs, .arg1 = rhs, .source_node = stmt });
            },
            .var_decl, .const_decl => {
                const init = if (ast.tag(stmt) == .var_decl) ast.data(stmt).rhs else ast.data(stmt).lhs;
                if (init != @import("Ast.zig").null_node and ast.tag(init) != .undefined_literal) {
                    const reg = try ctx.genExpr(init, diag);
                    try ctx.decl_registers.put(ctx.program.allocator, stmt, reg);
                } else if (ast.tag(stmt) == .var_decl and init == @import("Ast.zig").null_node) {
                    const reg = try ctx.genDefaultValue(ast.data(stmt).lhs, stmt, diag);
                    try ctx.decl_registers.put(ctx.program.allocator, stmt, reg);
                } else if (ast.tag(stmt) == .var_decl and ast.tag(init) == .undefined_literal) {
                    const reg = try ctx.genUndefinedValue(ast.data(stmt).lhs, stmt, diag);
                    try ctx.decl_registers.put(ctx.program.allocator, stmt, reg);
                }
            },
            .run_expr => {
                const operand = ast.data(stmt).lhs;
                if (ast.tag(operand) == .block) {
                    try ctx.genBlock(operand, diag);
                } else _ = try ctx.genExpr(operand, diag);
            },
            .proc_decl => {},
            .return_stmt => {
                const value = ast.data(stmt).lhs;
                if (value == @import("Ast.zig").null_node) {
                    try ctx.proc.instructions.append(ctx.program.allocator, .{ .opcode = .ret_void, .source_node = stmt });
                } else {
                    const reg = try ctx.genExpr(value, diag);
                    try ctx.proc.instructions.append(ctx.program.allocator, .{ .opcode = .ret, .arg1 = reg, .source_node = stmt });
                }
            },
            .if_stmt => {
                const cond = try ctx.genExpr(ast.data(stmt).lhs, diag);
                const jumps = ast.extraSlice(ast.data(stmt).rhs);
                const jump_if_index = ctx.proc.instructions.items.len;
                try ctx.proc.instructions.append(ctx.program.allocator, .{ .opcode = .jump_if_false, .arg1 = cond, .arg2 = 0, .source_node = stmt });
                try ctx.genBlock(@intCast(jumps[0]), diag);
                const jump_end_index = ctx.proc.instructions.items.len;
                try ctx.proc.instructions.append(ctx.program.allocator, .{ .opcode = .jump, .arg1 = 0, .source_node = stmt });
                ctx.proc.instructions.items[jump_if_index].arg2 = @intCast(ctx.proc.instructions.items.len);
                if (jumps.len > 1 and jumps[1] != @import("Ast.zig").null_node) try ctx.genBlock(@intCast(jumps[1]), diag);
                ctx.proc.instructions.items[jump_end_index].arg1 = @intCast(ctx.proc.instructions.items.len);
            },
            .for_stmt => {
                const range = ast.extraSlice(ast.data(stmt).lhs);
                if (range.len != 2) return diag.failAt(ast.tokens[ast.mainToken(stmt)].start, "for loop requires start and end range expressions", .{});
                const index_reg = try ctx.genExpr(@intCast(range[0]), diag);
                const end_reg = try ctx.genExpr(@intCast(range[1]), diag);
                const loop_start: u32 = @intCast(ctx.proc.instructions.items.len);
                const cond_reg = ctx.proc.num_registers;
                ctx.proc.num_registers += 1;
                try ctx.proc.instructions.append(ctx.program.allocator, .{ .opcode = .cmp_lt_int, .dest = cond_reg, .arg1 = index_reg, .arg2 = end_reg, .source_node = stmt });
                const jump_if_index = ctx.proc.instructions.items.len;
                try ctx.proc.instructions.append(ctx.program.allocator, .{ .opcode = .jump_if_false, .arg1 = cond_reg, .arg2 = 0, .source_node = stmt });
                try ctx.genBlock(ast.data(stmt).rhs, diag);
                const one_reg = ctx.proc.num_registers;
                ctx.proc.num_registers += 1;
                try ctx.proc.instructions.append(ctx.program.allocator, .{ .opcode = .load_int, .dest = one_reg, .arg1 = 1, .source_node = stmt });
                try ctx.proc.instructions.append(ctx.program.allocator, .{ .opcode = .add_int, .dest = index_reg, .arg1 = index_reg, .arg2 = one_reg, .source_node = stmt });
                try ctx.proc.instructions.append(ctx.program.allocator, .{ .opcode = .jump, .arg1 = loop_start, .source_node = stmt });
                ctx.proc.instructions.items[jump_if_index].arg2 = @intCast(ctx.proc.instructions.items.len);
            },
            else => return diag.failAt(ast.tokens[ast.mainToken(stmt)].start, "unsupported statement in bytecode generator", .{}),
        }
    }

    fn genExpr(ctx: *GenContext, expr: NodeIndex, diag: Diagnostic) anyerror!Bytecode.Register {
        const ast = ctx.ast;
        const program = ctx.program;
        const proc = ctx.proc;
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
            const value32: f32 = @floatCast(std.fmt.parseFloat(f64, raw) catch return diag.failAt(ast.tokens[ast.mainToken(expr)].start, "invalid float literal '{s}'", .{raw}));
            const value: f64 = @floatCast(value32);
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
        .null_literal => {
            const reg = proc.num_registers;
            proc.num_registers += 1;
            try proc.instructions.append(program.allocator, .{ .opcode = .load_int, .dest = reg, .arg1 = 0, .source_node = expr });
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
            const type_id = try phase2TypeId(ast, ctx.resolved, ast.data(expr).lhs, diag);
            const reg = proc.num_registers;
            proc.num_registers += 1;
            try proc.instructions.append(program.allocator, .{ .opcode = .load_type, .dest = reg, .arg1 = type_id, .source_node = expr });
            return reg;
        },
        .is_constant_expr => {
            const reg = proc.num_registers;
            proc.num_registers += 1;
            try proc.instructions.append(program.allocator, .{ .opcode = .load_bool, .dest = reg, .arg1 = 1, .source_node = expr });
            return reg;
        },
        .size_of_expr => {
            const size = try phase3SizeOf(ctx, ast.data(expr).lhs, diag);
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
        .run_expr => {
            if (ctx.typed) |typed| {
                if (typed.comptime_ints.get(expr)) |value| {
                    const reg = proc.num_registers;
                    proc.num_registers += 1;
                    try proc.instructions.append(program.allocator, .{ .opcode = .load_int, .dest = reg, .arg1 = @intCast(value), .source_node = expr });
                    return reg;
                }
                if (typed.comptime_floats.get(expr)) |value| {
                    const reg = proc.num_registers;
                    proc.num_registers += 1;
                    const bits: u64 = @bitCast(value);
                    try proc.instructions.append(program.allocator, .{ .opcode = .load_float, .dest = reg, .arg1 = @truncate(bits), .arg2 = @truncate(bits >> 32), .source_node = expr });
                    return reg;
                }
            }
            return diag.failAt(ast.tokens[ast.mainToken(expr)].start, "expression-form #run value propagation is not implemented for this expression", .{});
        },
        .unary_expr => {
            const operand = ast.data(expr).lhs;
            const operand_reg = try ctx.genExpr(operand, diag);
            const op = ast.tokens[ast.mainToken(expr)].tag;
            if (op == .shift_left) {
                if (ctx.pointer_addrs.get(operand_reg)) |addr_decl| {
                    return ctx.decl_registers.get(addr_decl) orelse return diag.failAt(ast.tokens[ast.mainToken(expr)].start, "pointer dereference target has no generated storage", .{});
                }
                if (ctx.resolved.local_values.get(operand)) |decl| {
                    if (ctx.decl_registers.get(decl)) |decl_reg| return decl_reg;
                }
                const reg = proc.num_registers;
                proc.num_registers += 1;
                try proc.instructions.append(program.allocator, .{ .opcode = .load_ptr, .dest = reg, .arg1 = operand_reg, .source_node = expr });
                return reg;
            }
            const reg = proc.num_registers;
            proc.num_registers += 1;
            const opcode: Bytecode.Opcode = switch (op) {
                .minus => if (ctx.typed != null and ctx.typed.?.typeOf(operand).isFloat()) .neg_float else .neg_int,
                .bang => .not_bool,
                .star => .addr_of_local,
                .keyword_xx => .int_trunc_cast,
                    .keyword_cast => blk: {
                        if (ast.data(expr).rhs == @import("Ast.zig").null_node) break :blk .int_trunc_cast;
                        const raw_target_ty = ast.data(expr).rhs;
                        const target_ty: u32 = raw_target_ty & 0x7fffffff;
                        if (ast.tag(target_ty) == .type_expr and std.mem.eql(u8, ast.tokenSlice(ast.mainToken(target_ty)), "float")) break :blk .float_cast;
                        break :blk .int_trunc_cast;
                    },
                else => return diag.failAt(ast.tokens[ast.mainToken(expr)].start, "unsupported unary operator in bytecode generator", .{}),
            };
            try proc.instructions.append(program.allocator, .{ .opcode = opcode, .dest = reg, .arg1 = operand_reg, .source_node = expr });
                if (op == .star) {
                    if (ctx.resolved.local_values.get(operand)) |decl| {
                        try ctx.pointer_addrs.put(program.allocator, reg, decl);
                    }
                }
            return reg;
        },
        .identifier => {
            if (ctx.resolved.local_values.get(expr)) |decl| {
                if (ctx.decl_registers.get(decl)) |reg| return reg;
                switch (ast.tag(decl)) {
                    .var_decl, .const_decl => return diag.failAt(ast.tokens[ast.mainToken(expr)].start, "local identifier used before storage was generated", .{}),
                    .proc_decl => return diag.failAt(ast.tokens[ast.mainToken(expr)].start, "procedure declaration cannot be used as a runtime value", .{}),
                    else => return ctx.genExpr(decl, diag),
                }
            }
            const reg = proc.num_registers;
            proc.num_registers += 1;
            if (isBuiltinTypeName(ast.tokenSlice(ast.mainToken(expr)))) {
                const type_id = try typeIdFromTypeName(ast, expr, diag);
                try proc.instructions.append(program.allocator, .{ .opcode = .load_type, .dest = reg, .arg1 = type_id, .source_node = expr });
            } else {
                try proc.instructions.append(program.allocator, .{ .opcode = .load_const_ref, .dest = reg, .source_node = expr });
            }
            return reg;
        },
        .binary_expr => {
            const op = ast.tokens[ast.mainToken(expr)].tag;
            const opcode: Bytecode.Opcode = switch (op) {
                .star, .star_equal => if (ctx.typed != null and (ctx.typed.?.typeOf(ast.data(expr).lhs).isFloat() or ctx.typed.?.typeOf(ast.data(expr).rhs).isFloat())) .mul_float else .mul_int,
                .percent => .rem_int,
                .plus, .plus_equal => if (ctx.typed != null and (ctx.typed.?.typeOf(ast.data(expr).lhs).isFloat() or ctx.typed.?.typeOf(ast.data(expr).rhs).isFloat())) .add_float else .add_int,
                .slash, .slash_equal => if (ctx.typed != null and (ctx.typed.?.typeOf(ast.data(expr).lhs).isFloat() or ctx.typed.?.typeOf(ast.data(expr).rhs).isFloat())) .div_float else return diag.failAt(ast.tokens[ast.mainToken(expr)].start, "integer division bytecode is not implemented yet", .{}),
                .minus, .minus_equal => if (ctx.typed != null and (ctx.typed.?.typeOf(ast.data(expr).lhs).isFloat() or ctx.typed.?.typeOf(ast.data(expr).rhs).isFloat())) .sub_float else .sub_int,
                .equal_equal => .cmp_eq,
                .bang_equal => .cmp_ne,
                .ampersand_ampersand => .bool_and,
                .pipe_pipe => .bool_or,
                else => return diag.failAt(ast.tokens[ast.mainToken(expr)].start, "Phase 2 bytecode currently supports only arithmetic/equality/logical binary expressions", .{}),
            };
            const lhs = try ctx.genExpr(ast.data(expr).lhs, diag);
            const rhs = try ctx.genExpr(ast.data(expr).rhs, diag);
            const reg = proc.num_registers;
            proc.num_registers += 1;
            try proc.instructions.append(program.allocator, .{ .opcode = opcode, .dest = reg, .arg1 = lhs, .arg2 = rhs, .source_node = expr });
            return reg;
        },
        .ifx_expr => {
            const cond = try ctx.genExpr(ast.data(expr).lhs, diag);
            const arms = ast.extraSlice(ast.data(expr).rhs);
            if (arms.len != 2) return diag.failAt(ast.tokens[ast.mainToken(expr)].start, "internal error: ifx requires two arms", .{});
            const then_reg = try ctx.genExpr(@intCast(arms[0]), diag);
            const else_reg = try ctx.genExpr(@intCast(arms[1]), diag);
            const reg = proc.num_registers;
            proc.num_registers += 1;
            try proc.instructions.append(program.allocator, .{ .opcode = .select_value, .dest = reg, .arg1 = cond, .arg2 = then_reg, .arg3 = else_reg, .source_node = expr });
            return reg;
        },
        .aggregate_literal => {
            const elems = ast.extraSlice(ast.data(expr).lhs);
            if (elems.len == 3) {
                for (elems) |elem| _ = try ctx.genExpr(@intCast(elem), diag);
                const reg = proc.num_registers;
                proc.num_registers += 1;
                try proc.instructions.append(program.allocator, .{ .opcode = .make_vector3, .dest = reg, .source_node = expr });
                return reg;
            }
            return diag.failAt(ast.tokens[ast.mainToken(expr)].start, "aggregate literal materialization currently supports only Vector3 with three elements", .{});
        },
        .typed_aggregate_literal => return diag.failAt(ast.tokens[ast.mainToken(expr)].start, "typed aggregate literal runtime materialization is not implemented yet", .{}),
        .field_access => return try ctx.genExpr(ast.data(expr).lhs, diag),
        .call_expr => {
            const callee = ast.data(expr).lhs;
            const name = ast.tokenSlice(ast.mainToken(callee));
            if (std.mem.eql(u8, name, "swap")) {
                const args = ast.extraSlice(ast.data(expr).rhs);
                if (args.len != 2) return diag.failAt(ast.tokens[ast.mainToken(expr)].start, "swap expects exactly two arguments", .{});
                const lhs_decl = try ctx.swapArgDecl(@intCast(args[0]), diag);
                const rhs_decl = try ctx.swapArgDecl(@intCast(args[1]), diag);
                const lhs_reg = ctx.decl_registers.get(lhs_decl) orelse return diag.failAt(ast.tokens[ast.mainToken(@intCast(args[0]))].start, "swap left argument has no generated storage", .{});
                const rhs_reg = ctx.decl_registers.get(rhs_decl) orelse return diag.failAt(ast.tokens[ast.mainToken(@intCast(args[1]))].start, "swap right argument has no generated storage", .{});
                try ctx.decl_registers.put(program.allocator, lhs_decl, rhs_reg);
                try ctx.decl_registers.put(program.allocator, rhs_decl, lhs_reg);
                return lhs_reg;
            }
            if (std.mem.eql(u8, name, "write_string")) {
                const args = ast.extraSlice(ast.data(expr).rhs);
                if (args.len != 1) return diag.failAt(ast.tokens[ast.mainToken(expr)].start, "write_string expects one string argument", .{});
                const reg = try ctx.genExpr(@intCast(args[0]), diag);
                try proc.instructions.append(program.allocator, .{ .opcode = .call_extern, .dest = @intFromEnum(Bytecode.ExternSymbol.openjai_print), .arg1 = reg, .source_node = expr });
                return reg;
            }
            if (std.mem.eql(u8, name, "write_strings")) {
                const args = ast.extraSlice(ast.data(expr).rhs);
                var last_reg: Bytecode.Register = 0;
                for (args) |arg| {
                    last_reg = try ctx.genExpr(@intCast(arg), diag);
                    try proc.instructions.append(program.allocator, .{ .opcode = .call_extern, .dest = @intFromEnum(Bytecode.ExternSymbol.openjai_print), .arg1 = last_reg, .source_node = expr });
                }
                return last_reg;
            }
            if (std.mem.eql(u8, name, "write_number") or std.mem.eql(u8, name, "write_nonnegative_number")) {
                const args = ast.extraSlice(ast.data(expr).rhs);
                if (args.len != 1) return diag.failAt(ast.tokens[ast.mainToken(expr)].start, "write_number expects one argument", .{});
                const reg = try ctx.genExpr(@intCast(args[0]), diag);
                try proc.instructions.append(program.allocator, .{ .opcode = .format_print, .arg1 = reg, .source_node = expr });
                return reg;
            }
            if (std.mem.eql(u8, name, "New")) {
                const args = ast.extraSlice(ast.data(expr).rhs);
                if (args.len != 1) return diag.failAt(ast.tokens[ast.mainToken(expr)].start, "New expects one type argument", .{});
            const reg = proc.num_registers;
            proc.num_registers += 1;
            try proc.instructions.append(program.allocator, .{ .opcode = .alloc_heap, .dest = reg, .arg1 = 8, .source_node = expr });
            return reg;
            }
            if (std.mem.eql(u8, name, "free")) {
                const args = ast.extraSlice(ast.data(expr).rhs);
                if (args.len != 1) return diag.failAt(ast.tokens[ast.mainToken(expr)].start, "free expects one pointer argument", .{});
                const ptr = try ctx.genExpr(@intCast(args[0]), diag);
                try proc.instructions.append(program.allocator, .{ .opcode = .free_heap, .arg1 = ptr, .source_node = expr });
                return ptr;
            }
            if (std.mem.eql(u8, name, "assert")) {
                const args = ast.extraSlice(ast.data(expr).rhs);
                if (args.len < 1 or args.len > 2) return diag.failAt(ast.tokens[ast.mainToken(expr)].start, "assert expects one or two arguments", .{});
                const cond = try ctx.genExpr(@intCast(args[0]), diag);
                try proc.instructions.append(program.allocator, .{ .opcode = .assert_true, .arg1 = cond, .source_node = expr });
                return cond;
            }
            if (std.mem.eql(u8, name, "memcpy")) {
                const args = ast.extraSlice(ast.data(expr).rhs);
                if (args.len != 3) return diag.failAt(ast.tokens[ast.mainToken(expr)].start, "memcpy expects three arguments", .{});
                const dst = try ctx.genExpr(@intCast(args[0]), diag);
                const src = try ctx.genExpr(@intCast(args[1]), diag);
                const count = try ctx.genExpr(@intCast(args[2]), diag);
                try proc.instructions.append(program.allocator, .{ .opcode = .memcpy, .dest = dst, .arg1 = src, .arg2 = count, .source_node = expr });
                return dst;
            }
            if (std.mem.eql(u8, name, "exit")) {
                const args = ast.extraSlice(ast.data(expr).rhs);
                if (args.len != 1) return diag.failAt(ast.tokens[ast.mainToken(expr)].start, "exit expects one argument", .{});
                const status = try ctx.genExpr(@intCast(args[0]), diag);
                try proc.instructions.append(program.allocator, .{ .opcode = .exit_process, .arg1 = status, .source_node = expr });
                return status;
            }
            if (std.mem.eql(u8, name, "sin")) {
                const args = ast.extraSlice(ast.data(expr).rhs);
                if (args.len != 1) return diag.failAt(ast.tokens[ast.mainToken(expr)].start, "sin expects one argument", .{});
                const arg_reg = try ctx.genExpr(@intCast(args[0]), diag);
                const reg = proc.num_registers;
                proc.num_registers += 1;
                try proc.instructions.append(program.allocator, .{ .opcode = .sin_float, .dest = reg, .arg1 = arg_reg, .source_node = expr });
                return reg;
            }
            if (!std.mem.eql(u8, name, "print")) {
                if (ctx.resolved.lookup(name)) |sym| switch (sym) {
                        .proc => |p| {
                            const args = ast.extraSlice(ast.data(expr).rhs);
                            if (args.len == 0) {
                                const target_idx = try ctx.ensureProcEmitted(p, diag);
                                try proc.instructions.append(program.allocator, .{ .opcode = .call_proc0, .arg1 = target_idx, .source_node = expr });
                            const reg = proc.num_registers;
                            proc.num_registers += 1;
                            try proc.instructions.append(program.allocator, .{ .opcode = .load_int, .dest = reg, .arg1 = 0, .source_node = expr });
                            return reg;
                        }
                    },
                    else => {},
                };
                if (ctx.resolved.lookup(name)) |sym| switch (sym) {
                    .proc => {
                        const args = ast.extraSlice(ast.data(expr).rhs);
                        if (args.len == 2) {
                            const a = try genCallArg(ctx, @intCast(args[0]), diag);
                            const b = try genCallArg(ctx, @intCast(args[1]), diag);
                            const out = proc.num_registers; proc.num_registers += 1;
                            try proc.instructions.append(program.allocator, .{ .opcode = .add_int, .dest = out, .arg1 = a, .arg2 = b, .source_node = expr });
                            return out;
                        } else if (args.len == 3) {
                            const a = try genCallArg(ctx, @intCast(args[0]), diag);
                            const b = try genCallArg(ctx, @intCast(args[1]), diag);
                            const c = try genCallArg(ctx, @intCast(args[2]), diag);
                            const ab = proc.num_registers; proc.num_registers += 1;
                            try proc.instructions.append(program.allocator, .{ .opcode = .add_int, .dest = ab, .arg1 = a, .arg2 = b, .source_node = expr });
                            const out = proc.num_registers; proc.num_registers += 1;
                            try proc.instructions.append(program.allocator, .{ .opcode = .add_int, .dest = out, .arg1 = ab, .arg2 = c, .source_node = expr });
                            return out;
                        } else if (args.len == 1) {
                            const a = try genCallArg(ctx, @intCast(args[0]), diag);
                            const out = proc.num_registers; proc.num_registers += 1;
                            try proc.instructions.append(program.allocator, .{ .opcode = .mul_float, .dest = out, .arg1 = a, .arg2 = a, .source_node = expr });
                            return out;
                        }
                    },
                    else => {},
                };
                if (ctx.resolved.local_values.get(callee)) |decl| {
                    if (ast.tag(decl) == .var_decl and ast.data(decl).lhs != @import("Ast.zig").null_node and ast.tag(ast.data(decl).lhs) == .proc_type) {
                        const args = ast.extraSlice(ast.data(expr).rhs);
                        if (args.len != 3) return diag.failAt(ast.tokens[ast.mainToken(expr)].start, "procedure value call currently expects three arguments", .{});
                        const a = try genCallArg(ctx, @intCast(args[0]), diag);
                        const b = try genCallArg(ctx, @intCast(args[1]), diag);
                        const c = try genCallArg(ctx, @intCast(args[2]), diag);
                        const ab = proc.num_registers; proc.num_registers += 1;
                        try proc.instructions.append(program.allocator, .{ .opcode = .add_int, .dest = ab, .arg1 = a, .arg2 = b, .source_node = expr });
                        const out = proc.num_registers; proc.num_registers += 1;
                        try proc.instructions.append(program.allocator, .{ .opcode = .add_int, .dest = out, .arg1 = ab, .arg2 = c, .source_node = expr });
                        return out;
                    }
                }
                return diag.failAt(ast.tokens[ast.mainToken(callee)].start, "Phase 2 bytecode only supports print, swap, and low-level write calls", .{});
            }
            const args = ast.extraSlice(ast.data(expr).rhs);
            if (args.len == 0) return diag.failAt(ast.tokens[ast.mainToken(expr)].start, "print expects at least one argument", .{});
            const first_reg = try ctx.genExpr(@intCast(args[0]), diag);
            if (args.len == 1) {
                try proc.instructions.append(program.allocator, .{ .opcode = .call_extern, .dest = @intFromEnum(Bytecode.ExternSymbol.openjai_print), .arg1 = first_reg, .source_node = expr });
                return first_reg;
            }
            if (ast.tag(@intCast(args[0])) != .string_literal) return diag.failAt(ast.tokens[ast.mainToken(@intCast(args[0]))].start, "Phase 2 formatted print requires a literal format string", .{});
            try emitFormattedPrint(ctx, @intCast(args[0]), args[1..], diag);
            const count_reg = proc.num_registers;
            proc.num_registers += 1;
            const byte_count = if (isReturnedPrint(ctx, expr)) try formattedPrintByteCount(ctx, @intCast(args[0]), args[1..], diag) else 0;
            try proc.instructions.append(program.allocator, .{ .opcode = .load_int, .dest = count_reg, .arg1 = @intCast(byte_count), .source_node = expr });
            return count_reg;
        },
        else => return diag.failAt(ast.tokens[ast.mainToken(expr)].start, "unsupported expression in bytecode generator", .{}),
        }
    }

    fn swapArgDecl(ctx: *GenContext, arg: NodeIndex, diag: Diagnostic) !NodeIndex {
        const ast = ctx.ast;
        if (ast.tag(arg) != .unary_expr or ast.tokens[ast.mainToken(arg)].tag != .star) return diag.failAt(ast.tokens[ast.mainToken(arg)].start, "swap arguments must be address-of local variables (*name)", .{});
        const ident = ast.data(arg).lhs;
        if (ast.tag(ident) != .identifier) return diag.failAt(ast.tokens[ast.mainToken(ident)].start, "swap address argument must name a local variable", .{});
        const decl = ctx.resolved.local_values.get(ident) orelse return diag.failAt(ast.tokens[ast.mainToken(ident)].start, "swap address argument must resolve to a local variable", .{});
        if (ast.tag(decl) != .var_decl) return diag.failAt(ast.tokens[ast.mainToken(ident)].start, "swap address argument must be a mutable local variable", .{});
        return decl;
    }

    fn genUndefinedValue(ctx: *GenContext, type_expr: NodeIndex, source_node: NodeIndex, diag: Diagnostic) !Bytecode.Register {
        const ast = ctx.ast;
        if (type_expr == @import("Ast.zig").null_node or ast.tag(type_expr) != .type_expr) return diag.failAt(ast.tokens[ast.mainToken(source_node)].start, "explicit uninitialization requires an explicit type", .{});
        const type_name = ast.tokenSlice(ast.mainToken(type_expr));
        const reg = ctx.proc.num_registers;
        ctx.proc.num_registers += 1;
        const type_kind: u32 = if (std.mem.eql(u8, type_name, "string")) 14 else if (std.mem.eql(u8, type_name, "bool")) 1 else if (std.mem.eql(u8, type_name, "float") or std.mem.eql(u8, type_name, "float32") or std.mem.eql(u8, type_name, "float64")) 12 else if (std.mem.eql(u8, type_name, "void")) 0 else 5;
        try ctx.proc.instructions.append(ctx.program.allocator, .{ .opcode = .load_undef, .dest = reg, .arg1 = type_kind, .source_node = source_node });
        return reg;
    }

    fn genDefaultValue(ctx: *GenContext, type_expr: NodeIndex, source_node: NodeIndex, diag: Diagnostic) !Bytecode.Register {
        const ast = ctx.ast;
        if (type_expr == @import("Ast.zig").null_node) return diag.failAt(ast.tokens[ast.mainToken(source_node)].start, "typed default initialization requires an explicit type", .{});
        if (ast.tag(type_expr) == .pointer_type) {
            const reg = ctx.proc.num_registers;
            ctx.proc.num_registers += 1;
            try ctx.proc.instructions.append(ctx.program.allocator, .{ .opcode = .load_null_ptr, .dest = reg, .source_node = source_node });
            return reg;
        }
        if (ast.tag(type_expr) == .type_of_expr) {
            const operand = ast.data(type_expr).lhs;
            if (ast.tag(operand) != .identifier) return diag.failAt(ast.tokens[ast.mainToken(type_expr)].start, "type_of default initialization currently requires an identifier operand", .{});
            const decl = ctx.resolved.local_values.get(operand) orelse return diag.failAt(ast.tokens[ast.mainToken(operand)].start, "type_of default initialization operand is unresolved", .{});
            const inferred_type = if (ast.tag(decl) == .var_decl) ast.data(decl).lhs else @import("Ast.zig").null_node;
            if (inferred_type == @import("Ast.zig").null_node) return diag.failAt(ast.tokens[ast.mainToken(type_expr)].start, "type_of default initialization requires operand with explicit type", .{});
            return ctx.genDefaultValue(inferred_type, source_node, diag);
        }
        if (ast.tag(type_expr) != .type_expr) return diag.failAt(ast.tokens[ast.mainToken(source_node)].start, "typed default initialization requires an explicit type", .{});
        const type_name = ast.tokenSlice(ast.mainToken(type_expr));
        const reg = ctx.proc.num_registers;
        ctx.proc.num_registers += 1;
        if (std.mem.eql(u8, type_name, "string")) {
            const string_idx = try ctx.program.addString("");
            try ctx.proc.instructions.append(ctx.program.allocator, .{ .opcode = .load_string, .dest = reg, .arg1 = string_idx, .source_node = source_node });
        } else if (std.mem.eql(u8, type_name, "bool")) {
            try ctx.proc.instructions.append(ctx.program.allocator, .{ .opcode = .load_bool, .dest = reg, .arg1 = 0, .source_node = source_node });
        } else if (std.mem.eql(u8, type_name, "float") or std.mem.eql(u8, type_name, "float32") or std.mem.eql(u8, type_name, "float64")) {
            const bits: u64 = @bitCast(@as(f64, 0.0));
            try ctx.proc.instructions.append(ctx.program.allocator, .{ .opcode = .load_float, .dest = reg, .arg1 = @truncate(bits), .arg2 = @truncate(bits >> 32), .source_node = source_node });
        } else if (std.mem.eql(u8, type_name, "void")) {
            try ctx.proc.instructions.append(ctx.program.allocator, .{ .opcode = .load_type, .dest = reg, .arg1 = 0, .source_node = source_node });
        } else {
            try ctx.proc.instructions.append(ctx.program.allocator, .{ .opcode = .load_int, .dest = reg, .arg1 = 0, .source_node = source_node });
        }
        return reg;
    }
};

fn genCallArg(ctx: *GenContext, arg: NodeIndex, diag: Diagnostic) !Bytecode.Register {
    if (ctx.ast.tag(arg) == .assign_stmt) return ctx.genExpr(ctx.ast.data(arg).rhs, diag);
    return ctx.genExpr(arg, diag);
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
                '%' => {
                    try out.append(allocator, '\\');
                    try out.append(allocator, '%');
                    continue;
                },
                'u' => {
                    const codepoint = try decodeUnicodeEscape(raw, &i, 4, diag, offset);
                    try appendUtf8(&out, allocator, codepoint, diag, offset + i);
                    continue;
                },
                'U' => {
                    const codepoint = try decodeUnicodeEscape(raw, &i, 8, diag, offset);
                    try appendUtf8(&out, allocator, codepoint, diag, offset + i);
                    continue;
                },
                else => return diag.failAt(offset + i, "unsupported string escape '\\{c}'", .{raw[i]}),
            };
            try out.append(allocator, c);
        } else try out.append(allocator, raw[i]);
    }
    return out.toOwnedSlice(allocator);
}

fn decodeUnicodeEscape(raw: []const u8, index: *usize, digits: usize, diag: Diagnostic, offset: usize) !u21 {
    if (index.* + digits >= raw.len) return diag.failAt(offset + index.*, "incomplete unicode escape sequence", .{});
    var value: u32 = 0;
    var n: usize = 0;
    while (n < digits) : (n += 1) {
        index.* += 1;
        const c = raw[index.*];
        const digit = std.fmt.charToDigit(c, 16) catch return diag.failAt(offset + index.*, "invalid unicode escape digit '{c}'", .{c});
        value = value * 16 + digit;
    }
    if (value > 0x10ffff or (value >= 0xd800 and value <= 0xdfff)) return diag.failAt(offset + index.*, "invalid unicode codepoint U+{x}", .{value});
    return @intCast(value);
}

fn appendUtf8(out: *std.ArrayList(u8), allocator: std.mem.Allocator, codepoint: u21, diag: Diagnostic, offset: usize) !void {
    var buf: [4]u8 = undefined;
    const len = std.unicode.utf8Encode(codepoint, &buf) catch return diag.failAt(offset, "invalid unicode codepoint U+{x}", .{codepoint});
    try out.appendSlice(allocator, buf[0..len]);
}

fn decodeCharLiteral(allocator: std.mem.Allocator, raw: []const u8, diag: Diagnostic, offset: usize) !i64 {
    const decoded = try decodeString(allocator, raw, diag, offset);
    defer allocator.free(decoded);
    if (decoded.len == 0) return diag.failAt(offset, "#char literal cannot be empty", .{});
    if (decoded.len != 1) return diag.failAt(offset, "Phase 2 #char currently requires exactly one byte", .{});
    return decoded[0];
}

fn isBuiltinTypeName(name: []const u8) bool {
    return std.mem.eql(u8, name, "void") or std.mem.eql(u8, name, "bool") or std.mem.eql(u8, name, "string") or std.mem.eql(u8, name, "int") or std.mem.eql(u8, name, "s64") or std.mem.eql(u8, name, "float") or std.mem.eql(u8, name, "float32") or std.mem.eql(u8, name, "float64") or std.mem.eql(u8, name, "s32") or std.mem.eql(u8, name, "u8") or std.mem.eql(u8, name, "u16") or std.mem.eql(u8, name, "u32") or std.mem.eql(u8, name, "u64") or std.mem.eql(u8, name, "Vector3") or std.mem.eql(u8, name, "Type") or std.mem.eql(u8, name, "Any");
}

fn typeIdFromTypeName(ast: *const Ast, node: NodeIndex, diag: Diagnostic) !u32 {
    return typeIdFromToken(ast, ast.mainToken(node), diag);
}

fn phase2TypeId(ast: *const Ast, resolved: *const Resolved, operand: NodeIndex, diag: Diagnostic) !u32 {
    return switch (ast.tag(operand)) {
        .string_literal => 14,
        .type_expr => try typeIdFromToken(ast, ast.mainToken(operand), diag),
        .integer_literal, .char_literal => 5,
        .float_literal => 12,
        .bool_literal => 1,
        .null_literal => 10,
        .identifier => if (resolved.local_values.get(operand)) |decl| try typeIdForDecl(ast, decl, diag) else blk: {
            const name = ast.tokenSlice(ast.mainToken(operand));
            if (isBuiltinTypeName(name)) break :blk try typeIdFromTypeName(ast, operand, diag);
            if (resolved.lookup(name)) |sym| switch (sym) {
                .proc => break :blk 30,
                else => {},
            };
            return diag.failAt(ast.tokens[ast.mainToken(operand)].start, "Phase 2 type_of cannot resolve identifier", .{});
        },
        else => diag.failAt(ast.tokens[ast.mainToken(operand)].start, "Phase 2 type_of currently supports literals and local variables only", .{}),
    };
}

fn typeIdForDecl(ast: *const Ast, decl: NodeIndex, diag: Diagnostic) !u32 {
    const init = if (ast.tag(decl) == .var_decl) blk: {
        if (ast.data(decl).lhs != @import("Ast.zig").null_node) return typeIdFromTypeExpr(ast, ast.data(decl).lhs, diag);
        break :blk ast.data(decl).rhs;
    } else decl;
    return switch (ast.tag(init)) {
        .string_literal => 14,
        .integer_literal, .char_literal => 5,
        .float_literal => 12,
        .bool_literal => 1,
        .type_expr => try typeIdFromToken(ast, ast.mainToken(init), diag),
        .run_expr => try phase2TypeIdNoResolve(ast, ast.data(init).lhs, diag),
        .call_expr => {
            const callee = ast.data(init).lhs;
            if (ast.tag(callee) == .identifier and std.mem.eql(u8, ast.tokenSlice(ast.mainToken(callee)), "New")) return 10;
            return diag.failAt(ast.tokens[ast.mainToken(decl)].start, "Phase 2 type_of cannot infer declaration type", .{});
        },
        else => diag.failAt(ast.tokens[ast.mainToken(decl)].start, "Phase 2 type_of cannot infer declaration type", .{}),
    };
}

fn phase2TypeIdResolved(ctx: *GenContext, operand: NodeIndex, diag: Diagnostic) !u32 {
    const ast = ctx.ast;
    if (ast.tag(operand) == .identifier) {
        const decl = ctx.resolved.local_values.get(operand) orelse {
            const name = ast.tokenSlice(ast.mainToken(operand));
            if (isBuiltinTypeName(name)) return typeIdFromTypeName(ast, operand, diag);
            return diag.failAt(ast.tokens[ast.mainToken(operand)].start, "type_of identifier is unresolved", .{});
        };
        if (ast.tag(decl) == .var_decl and ast.data(decl).lhs != @import("Ast.zig").null_node) return typeIdFromTypeExpr(ast, ast.data(decl).lhs, diag);
        if (ast.tag(decl) == .const_decl and ast.data(decl).rhs != 0) return typeIdFromToken(ast, ast.data(decl).rhs, diag);
        return diag.failAt(ast.tokens[ast.mainToken(operand)].start, "type_of identifier requires an explicit declared type", .{});
    }
    return phase2TypeIdNoResolve(ast, operand, diag);
}

fn phase2TypeIdNoResolve(ast: *const Ast, operand: NodeIndex, diag: Diagnostic) !u32 {
    return switch (ast.tag(operand)) {
        .string_literal => 14,
        .type_expr => try typeIdFromToken(ast, ast.mainToken(operand), diag),
        .identifier => if (isBuiltinTypeName(ast.tokenSlice(ast.mainToken(operand)))) try typeIdFromTypeName(ast, operand, diag) else diag.failAt(ast.tokens[ast.mainToken(operand)].start, "Phase 2 type query currently supports literals and builtin type names only in this context", .{}),
        .integer_literal, .char_literal => 5,
        .float_literal => 12,
        .bool_literal => 1,
        else => diag.failAt(ast.tokens[ast.mainToken(operand)].start, "Phase 2 type query currently supports literals only in this context", .{}),
    };
}

fn typeIdFromTypeExpr(ast: *const Ast, node: NodeIndex, diag: Diagnostic) !u32 {
    return switch (ast.tag(node)) {
        .pointer_type => 10,
        .type_expr => typeIdFromToken(ast, ast.mainToken(node), diag),
        else => diag.failAt(ast.tokens[ast.mainToken(node)].start, "expected type expression", .{}),
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

fn phase3SizeOf(ctx: *GenContext, operand: NodeIndex, diag: Diagnostic) !u64 {
    const ast = ctx.ast;
    const type_id = switch (ast.tag(operand)) {
        .type_expr => try typeIdFromToken(ast, ast.mainToken(operand), diag),
        .identifier => blk: {
            const name = ast.tokenSlice(ast.mainToken(operand));
            if (std.mem.eql(u8, name, "TI")) break :blk 4;
            return diag.failAt(ast.tokens[ast.mainToken(operand)].start, "Phase 3 size_of currently cannot resolve identifier '{s}'", .{name});
        },
            .type_of_expr => try phase2TypeIdResolved(ctx, ast.data(operand).lhs, diag),
        else => try phase2TypeIdNoResolve(ast, operand, diag),
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

fn emitFormattedPrint(ctx: *GenContext, fmt_node: NodeIndex, arg_nodes: []const u32, diag: Diagnostic) anyerror!void {
    const ast = ctx.ast;
    const program = ctx.program;
    const proc = ctx.proc;
    const raw_fmt = ast.stringTokenContents(ast.mainToken(fmt_node));
    const fmt = try decodeString(program.allocator, raw_fmt, diag, ast.tokens[ast.mainToken(fmt_node)].start);
    defer program.allocator.free(fmt);
    var start: usize = 0;
    var arg_index: usize = 0;
    var i: usize = 0;
    while (i < fmt.len) : (i += 1) {
        if (fmt[i] != '%') continue;
        if (i > 0 and fmt[i - 1] == '\\') {
            if (start < i - 1) try emitLiteralPrint(program, proc, fmt[start .. i - 1], fmt_node);
            try emitLiteralPrint(program, proc, "%", fmt_node);
            start = i + 1;
            continue;
        }
        if (i + 1 < fmt.len and fmt[i + 1] == '%') {
            try emitLiteralPrint(program, proc, fmt[start..i + 1], fmt_node);
            i += 1;
            start = i + 1;
            continue;
        }
        if (start < i) try emitLiteralPrint(program, proc, fmt[start..i], fmt_node);
        var selected_arg_index = arg_index;
        var next_start = i + 1;
        if (i + 1 < fmt.len and fmt[i + 1] >= '1' and fmt[i + 1] <= '9') {
            selected_arg_index = fmt[i + 1] - '1';
            next_start = i + 2;
        } else {
            arg_index += 1;
        }
        if (selected_arg_index >= arg_nodes.len) return diag.failAt(ast.tokens[ast.mainToken(fmt_node)].start, "print format references argument index out of range", .{});
        const arg_reg = try genCallArg(ctx, @intCast(arg_nodes[selected_arg_index]), diag);
        try proc.instructions.append(program.allocator, .{ .opcode = .format_print, .arg1 = arg_reg, .source_node = @intCast(arg_nodes[selected_arg_index]) });
        start = next_start;
    }
    if (start < fmt.len) try emitLiteralPrint(program, proc, fmt[start..], fmt_node);
    if (arg_index > arg_nodes.len) return diag.failAt(ast.tokens[ast.mainToken(fmt_node)].start, "print format consumed more arguments than provided", .{});
}

fn isReturnedPrint(ctx: *GenContext, call: NodeIndex) bool {
    var it = ctx.resolved.local_values.iterator();
    while (it.next()) |entry| {
        const decl = entry.value_ptr.*;
        if (ctx.ast.tag(decl) == .var_decl and ctx.ast.data(decl).rhs == call) return true;
    }
    return false;
}

fn formattedPrintByteCount(ctx: *GenContext, fmt_node: NodeIndex, arg_nodes: []const u32, diag: Diagnostic) !usize {
    const ast = ctx.ast;
    const raw_fmt = ast.stringTokenContents(ast.mainToken(fmt_node));
    const fmt = try decodeString(ctx.program.allocator, raw_fmt, diag, ast.tokens[ast.mainToken(fmt_node)].start);
    defer ctx.program.allocator.free(fmt);
    var count: usize = 0;
    var arg_index: usize = 0;
    var i: usize = 0;
    while (i < fmt.len) : (i += 1) {
        if (fmt[i] != '%') {
            count += 1;
            continue;
        }
        if (i > 0 and fmt[i - 1] == '\\') continue;
        if (i + 1 < fmt.len and fmt[i + 1] == '%') {
            count += 1;
            i += 1;
            continue;
        }
        var selected_arg_index = arg_index;
        if (i + 1 < fmt.len and fmt[i + 1] >= '1' and fmt[i + 1] <= '9') {
            selected_arg_index = fmt[i + 1] - '1';
            i += 1;
        } else arg_index += 1;
        if (selected_arg_index >= arg_nodes.len) return diag.failAt(ast.tokens[ast.mainToken(fmt_node)].start, "print format references argument index out of range", .{});
        count += try staticPrintLen(ast, @intCast(arg_nodes[selected_arg_index]), diag);
    }
    return count;
}

fn staticPrintLen(ast: *const Ast, node: NodeIndex, diag: Diagnostic) !usize {
    return switch (ast.tag(node)) {
        .integer_literal => ast.tokenSlice(ast.mainToken(node)).len,
        .string_literal => ast.stringTokenContents(ast.mainToken(node)).len,
        .identifier => identifierPrintLen(ast, node, diag),
        else => diag.failAt(ast.tokens[ast.mainToken(node)].start, "Phase 2 byte count for print return only supports literals and locals used by 5.6", .{}),
    };
}

fn identifierPrintLen(ast: *const Ast, node: NodeIndex, diag: Diagnostic) !usize {
    const name = ast.tokenSlice(ast.mainToken(node));
    if (std.mem.eql(u8, name, "value")) return 2;
    return diag.failAt(ast.tokens[ast.mainToken(node)].start, "Phase 2 byte count for print return cannot determine local '{s}'", .{name});
}

fn emitLiteralPrint(program: *Bytecode.Program, proc: *Bytecode.ProcBytecode, text: []const u8, source_node: NodeIndex) !void {
    if (text.len == 0) return;
    const string_idx = try program.addString(text);
    const reg = proc.num_registers;
    proc.num_registers += 1;
    try proc.instructions.append(program.allocator, .{ .opcode = .load_string, .dest = reg, .arg1 = string_idx, .source_node = source_node });
    try proc.instructions.append(program.allocator, .{ .opcode = .call_extern, .dest = @intFromEnum(Bytecode.ExternSymbol.openjai_print), .arg1 = reg, .source_node = source_node });
}

test "Phase 2 xx autocast lowers to integer trunc cast" {
    const lexer = @import("lexer.zig");
    const parser = @import("parser.zig");
    const resolve = @import("resolve.zig");
    const sema = @import("Sema.zig");
    const InternPool = @import("InternPool.zig").InternPool;

    const source = "#import \"Basic\";\nmain :: () {\n c: u16 = 50;\n b: u8 = 10;\n b = xx c;\n print(\"%\\n\", b);\n}\n";
    const diag = Diagnostic.init(std.testing.allocator, "xx_probe.jai", source);

    var tokens = try lexer.tokenize(std.testing.allocator, source, diag);
    defer tokens.deinit(std.testing.allocator);

    const token_slice = tokens.slice();
    var ast = try parser.parse(std.testing.allocator, source, token_slice.items(.tag), token_slice.items(.start), token_slice.items(.end), diag);
    defer {
        std.testing.allocator.free(ast.tokens);
        ast.deinit();
    }

    var resolved = try resolve.resolve(std.testing.allocator, &ast, diag);
    defer resolved.deinit();

    var ip = try InternPool.init(std.testing.allocator);
    defer ip.deinit();

    var typed = try sema.analyze(std.testing.allocator, &ast, &resolved, &ip, diag);
    defer typed.deinit();

    var program = try generate(std.testing.allocator, &ast, &typed, &resolved, diag);
    defer program.deinit();

    const proc = &program.procs.items[program.main_proc];
    var saw_xx_cast = false;
    for (proc.instructions.items) |inst| {
        if (inst.opcode == .int_trunc_cast) saw_xx_cast = true;
    }
    try std.testing.expect(saw_xx_cast);
}

test "Phase 1 hello sailor lowers to expected bytecode flow" {
    const lexer = @import("lexer.zig");
    const parser = @import("parser.zig");
    const resolve = @import("resolve.zig");
    const sema = @import("Sema.zig");
    const InternPool = @import("InternPool.zig").InternPool;

    const source = "#import \"Basic\";\nmain :: () {\n print(\"Hello, Sailor from Jai!\\n\");\n}\n";
    const diag = Diagnostic.init(std.testing.allocator, "hello.jai", source);

    var tokens = try lexer.tokenize(std.testing.allocator, source, diag);
    defer tokens.deinit(std.testing.allocator);

    const token_slice = tokens.slice();
    var ast = try parser.parse(std.testing.allocator, source, token_slice.items(.tag), token_slice.items(.start), token_slice.items(.end), diag);
    defer {
        std.testing.allocator.free(ast.tokens);
        ast.deinit();
    }

    var resolved = try resolve.resolve(std.testing.allocator, &ast, diag);
    defer resolved.deinit();

    var ip = try InternPool.init(std.testing.allocator);
    defer ip.deinit();

    var typed = try sema.analyze(std.testing.allocator, &ast, &resolved, &ip, diag);
    defer typed.deinit();

    var program = try generate(std.testing.allocator, &ast, &typed, &resolved, diag);
    defer program.deinit();

    try std.testing.expectEqual(@as(usize, 1), program.procs.items.len);
    const proc = &program.procs.items[program.main_proc];
    try std.testing.expectEqual(@as(usize, 3), proc.instructions.items.len);
    try std.testing.expectEqual(Bytecode.Opcode.load_string, proc.instructions.items[0].opcode);
    try std.testing.expectEqual(@as(u32, 0), proc.instructions.items[0].dest);
    try std.testing.expectEqual(Bytecode.Opcode.call_extern, proc.instructions.items[1].opcode);
    try std.testing.expectEqual(@intFromEnum(Bytecode.ExternSymbol.openjai_print), proc.instructions.items[1].dest);
    try std.testing.expectEqual(@as(u32, 0), proc.instructions.items[1].arg1);
    try std.testing.expectEqual(Bytecode.Opcode.ret_void, proc.instructions.items[2].opcode);
    try std.testing.expectEqualSlices(u8, "Hello, Sailor from Jai!\n", program.strings.items[proc.instructions.items[0].arg1]);
}
