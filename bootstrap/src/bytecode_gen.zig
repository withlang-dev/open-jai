const std = @import("std");
const Ast = @import("Ast.zig").Ast;
const NodeIndex = @import("Ast.zig").NodeIndex;
const Diagnostic = @import("diagnostics.zig").Diagnostic;
const Typed = @import("Sema.zig").Typed;
const Type = @import("Type.zig").Type;
const TokenTag = @import("Token.zig").Token.Tag;
const using_param_sentinel: u32 = 0xfffffffe;
const InternPool = @import("InternPool.zig").InternPool;
const Bytecode = @import("Bytecode.zig");

const Resolved = @import("resolve.zig").Resolved;

pub fn generate(allocator: std.mem.Allocator, ast: *const Ast, typed: *const Typed, resolved: *const Resolved, diag: Diagnostic) !Bytecode.Program {
    var program = Bytecode.Program.init(allocator);
    errdefer program.deinit();
    const root_decls = ast.extraSlice(ast.data(ast.root).lhs);
    for (root_decls) |decl_idx| {
        const decl: NodeIndex = @intCast(decl_idx);
        if (ast.tag(decl) != .proc_decl) continue;
        if (typed.main_proc != null and decl == typed.main_proc.?) continue;
        var helper = Bytecode.ProcBytecode{ .name = ast.tokenSlice(ast.mainToken(decl)) };
        errdefer helper.deinit(allocator);
        var helper_ctx = GenContext{ .ast = ast, .program = &program, .proc = &helper, .resolved = resolved, .typed = typed };
        defer helper_ctx.deinit();
        try helper_ctx.genBlock(ast.data(decl).lhs, diag);
        try helper.instructions.append(allocator, .{ .opcode = .ret_void });
        try program.procs.append(allocator, helper);
    }
    if (typed.main_proc) |main_proc| {
        var proc = Bytecode.ProcBytecode{ .name = ast.tokenSlice(ast.mainToken(main_proc)) };
        errdefer proc.deinit(allocator);
        var ctx = GenContext{ .ast = ast, .program = &program, .proc = &proc, .resolved = resolved, .typed = typed };
        defer ctx.deinit();
        try ctx.genBlock(ast.data(main_proc).lhs, diag);
        try proc.instructions.append(allocator, .{ .opcode = .ret_void });
        const main_idx: u32 = @intCast(program.procs.items.len);
        try program.procs.append(allocator, proc);
        program.main_proc = main_idx;
    }
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
    field_values: std.AutoHashMapUnmanaged(u64, Bytecode.Register) = .empty,
    array_last_items: std.AutoHashMapUnmanaged(NodeIndex, Bytecode.Register) = .empty,
    loop_index_registers: std.AutoHashMapUnmanaged(NodeIndex, Bytecode.Register) = .empty,
    // Loop control: tracks break/continue patch targets for each active loop.
    loop_stack: std.ArrayList(LoopFrame) = .empty,
    // Deferred statements: LIFO stack, emitted at scope exit.
    defer_stmts: std.ArrayList(NodeIndex) = .empty,
    // Procedure bodies currently inline simple calls for runtime codegen. This
    // stack prevents recursive inlining from turning recursion into compiler recursion.
    inline_stack: std.ArrayList(NodeIndex) = .empty,
    inline_return: ?*InlineReturnFrame = null,

    const LoopFrame = struct {
        label: []const u8, // empty = anonymous
        continue_target: u32, // instruction index to jump to on 'continue'
        break_patches: std.ArrayList(usize), // instruction indices to patch on 'break'
        defer_depth: usize, // defer_stmts.items.len at loop entry
    };

    const InlineReturnFrame = struct {
        result_reg: Bytecode.Register,
        result_type: NodeIndex = @import("Ast.zig").null_node,
        patches: std.ArrayList(usize) = .empty,
    };

    pub fn deinit(ctx: *GenContext) void {
        ctx.decl_registers.deinit(ctx.program.allocator);
        ctx.pointer_addrs.deinit(ctx.program.allocator);
        ctx.field_values.deinit(ctx.program.allocator);
        ctx.array_last_items.deinit(ctx.program.allocator);
        ctx.loop_index_registers.deinit(ctx.program.allocator);
        for (ctx.loop_stack.items) |*frame| frame.break_patches.deinit(ctx.program.allocator);
        ctx.loop_stack.deinit(ctx.program.allocator);
        ctx.defer_stmts.deinit(ctx.program.allocator);
        ctx.inline_stack.deinit(ctx.program.allocator);
    }

    /// Emit all deferred statements from `from_depth` to current depth (in reverse/LIFO order).
    fn emitDeferred(ctx: *GenContext, from_depth: usize, diag: Diagnostic) anyerror!void {
        var i = ctx.defer_stmts.items.len;
        while (i > from_depth) {
            i -= 1;
            try ctx.genStmt(ctx.defer_stmts.items[i], diag);
        }
    }

    /// Coerce a register value to bool if the node's type is not already bool.
    fn coerceToBool(ctx: *GenContext, reg: Bytecode.Register, node: NodeIndex) !Bytecode.Register {
        if (ctx.typed) |typed| {
            const ty = typed.typeOf(node);
            if (!ty.isBool()) {
                const bool_reg = ctx.proc.num_registers;
                ctx.proc.num_registers += 1;
                try ctx.proc.instructions.append(ctx.program.allocator, .{ .opcode = .int_to_bool_cast, .dest = bool_reg, .arg1 = reg, .source_node = node });
                return bool_reg;
            }
        }
        return reg;
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

    const ParamBindingRestore = struct {
        decl: NodeIndex,
        had_old: bool,
        old: Bytecode.Register = 0,
    };

    fn restoreParamBindings(ctx: *GenContext, restores: []const ParamBindingRestore) !void {
        for (restores) |restore| {
            if (restore.had_old) {
                try ctx.decl_registers.put(ctx.program.allocator, restore.decl, restore.old);
            } else {
                _ = ctx.decl_registers.remove(restore.decl);
            }
        }
    }

    fn resolveProcCallTarget(ctx: *GenContext, callee: NodeIndex, name: []const u8, arg_count: usize) ?NodeIndex {
        const ast = ctx.ast;
        if (ast.tag(callee) == .proc_decl) return callee;
        if (ctx.resolved.local_values.get(callee)) |decl| {
            if (decl != @import("Ast.zig").null_node) {
                if (ast.tag(decl) == .proc_decl) return decl;
                if (ast.tag(decl) == .var_decl and ast.data(decl).rhs != @import("Ast.zig").null_node) {
                    const init = ast.data(decl).rhs;
                    if (ast.tag(init) == .proc_decl) return init;
                    if (ast.tag(init) == .identifier) {
                        if (ctx.resolved.local_values.get(init)) |init_decl| if (ast.tag(init_decl) == .proc_decl) return init_decl;
                        if (ctx.resolved.lookup(ast.tokenSlice(ast.mainToken(init)))) |sym| switch (sym) {
                            .proc => |proc_node| return proc_node,
                            else => {},
                        };
                    }
                }
            }
        }
        if (ctx.resolved.overloads(name)) |candidates| {
            for (candidates) |candidate| {
                const sig = procSignature(ast, candidate) orelse {
                    if (arg_count == 0) return candidate;
                    continue;
                };
                const params = ast.extraSlice(sig.params_extra);
                if (arg_count <= params.len) return candidate;
            }
        }
        if (ctx.resolved.lookup(name)) |sym| switch (sym) {
            .proc => |proc_node| return proc_node,
            else => {},
        };
        return null;
    }

    fn stmtContainsNestedReturn(ctx: *GenContext, stmt: NodeIndex) bool {
        const ast = ctx.ast;
        return switch (ast.tag(stmt)) {
            .return_stmt => false,
            .block => blk: {
                for (ast.extraSlice(ast.data(stmt).lhs)) |child| if (ctx.stmtContainsAnyReturn(@intCast(child))) break :blk true;
                break :blk false;
            },
            .if_stmt => blk: {
                const arms = ast.extraSlice(ast.data(stmt).rhs);
                for (arms) |arm| if (arm != @import("Ast.zig").null_node and ctx.stmtContainsAnyReturn(@intCast(arm))) break :blk true;
                break :blk false;
            },
            .while_stmt, .for_stmt => ctx.stmtContainsAnyReturn(ast.data(stmt).rhs),
            else => false,
        };
    }

    fn stmtContainsAnyReturn(ctx: *GenContext, stmt: NodeIndex) bool {
        const ast = ctx.ast;
        return switch (ast.tag(stmt)) {
            .return_stmt => true,
            .block => blk: {
                for (ast.extraSlice(ast.data(stmt).lhs)) |child| if (ctx.stmtContainsAnyReturn(@intCast(child))) break :blk true;
                break :blk false;
            },
            .if_stmt => blk: {
                const arms = ast.extraSlice(ast.data(stmt).rhs);
                for (arms) |arm| if (arm != @import("Ast.zig").null_node and ctx.stmtContainsAnyReturn(@intCast(arm))) break :blk true;
                break :blk false;
            },
            .while_stmt, .for_stmt => ctx.stmtContainsAnyReturn(ast.data(stmt).rhs),
            else => false,
        };
    }

    fn tryEmitAssignCompound(ctx: *GenContext, lhs: NodeIndex, rhs_node: NodeIndex, source_node: NodeIndex, diag: Diagnostic) !?Bytecode.Register {
        const ast = ctx.ast;
        if (ast.tag(rhs_node) != .binary_expr) return null;
        const op = ast.tokens[ast.mainToken(rhs_node)].tag;
        if (!isCompoundAssignmentOp(op)) return null;
        return try ctx.emitCompoundAssignment(lhs, ast.data(rhs_node).rhs, op, source_node, diag);
    }

    fn emitCompoundAssignment(ctx: *GenContext, lhs: NodeIndex, rhs: NodeIndex, op: TokenTag, source_node: NodeIndex, diag: Diagnostic) !Bytecode.Register {
        const ast = ctx.ast;
        const current = try ctx.genExpr(lhs, diag);
        const operand = try ctx.genExpr(rhs, diag);
        const result = ctx.proc.num_registers;
        ctx.proc.num_registers += 1;
        try ctx.proc.instructions.append(ctx.program.allocator, .{
            .opcode = compoundAssignmentOpcode(ctx, lhs, rhs, op),
            .dest = result,
            .arg1 = current,
            .arg2 = operand,
            .source_node = source_node,
        });

        switch (ast.tag(lhs)) {
            .field_access, .index_expr => {
                const addr = try genAddressOfLvalue(ctx, lhs, diag);
                try ctx.proc.instructions.append(ctx.program.allocator, .{ .opcode = .store_ptr, .dest = addr, .arg1 = result, .source_node = source_node });
            },
            .unary_expr => {
                const tok = ast.tokens[ast.mainToken(lhs)].tag;
                if (tok == .shift_left or tok == .dot_star) {
                    const ptr = try ctx.genExpr(ast.data(lhs).lhs, diag);
                    try ctx.proc.instructions.append(ctx.program.allocator, .{ .opcode = .store_ptr, .dest = ptr, .arg1 = result, .source_node = source_node });
                }
            },
            .identifier => {
                if (ctx.resolved.local_values.get(lhs)) |decl| {
                    if (ctx.decl_registers.get(decl)) |old_reg| {
                        try ctx.proc.instructions.append(ctx.program.allocator, .{ .opcode = .load, .dest = old_reg, .arg1 = result, .source_node = source_node });
                        return old_reg;
                    }
                    try ctx.decl_registers.put(ctx.program.allocator, decl, result);
                }
            },
            else => {},
        }
        return result;
    }

    fn isLoopIndexIdentifier(ctx: *GenContext, ident: NodeIndex, for_node: NodeIndex) bool {
        const ast = ctx.ast;
        const name = ast.tokenSlice(ast.mainToken(ident));
        if (std.mem.eql(u8, name, "it_index")) return true;
        const range = ast.extraSlice(ast.data(for_node).lhs);
        return range.len == 3 and std.mem.eql(u8, name, ast.tokenSlice(range[2]));
    }

    fn emitAggregateToStruct(ctx: *GenContext, aggregate: NodeIndex, dest: Bytecode.Register, type_text: []const u8, source_node: NodeIndex, diag: Diagnostic) !void {
        const ast = ctx.ast;
        const type_name = firstTypeWord(stripPointerText(type_text));
        const type_node = try structTypeNodeByName(ctx, type_name) orelse return;
        const elems = ast.extraSlice(ast.data(aggregate).lhs);
        for (elems, 0..) |elem_idx, position| {
            const elem: NodeIndex = @intCast(elem_idx);
            const value_node = if (ast.tag(elem) == .assign_stmt) ast.data(elem).rhs else elem;
            const field_info = if (ast.tag(elem) == .assign_stmt)
                try fieldInfoFromTypeText(ctx, type_text, ast.tokenSlice(ast.mainToken(ast.data(elem).lhs)), diag)
            else
                try containerFieldInfoAtIndex(ctx, type_node, position, diag);
            const info = field_info orelse continue;
            const addr = if (info.offset == 0) dest else blk: {
                const tmp = ctx.proc.num_registers;
                ctx.proc.num_registers += 1;
                try ctx.proc.instructions.append(ctx.program.allocator, .{ .opcode = .ptr_offset, .dest = tmp, .arg1 = dest, .arg2 = @intCast(info.offset), .source_node = source_node });
                break :blk tmp;
            };
            const value_reg = try ctx.genExpr(value_node, diag);
            const clean_field_type = std.mem.trim(u8, info.type_text, " \t\r\n");
            if (try typeTextIsStruct(ctx, clean_field_type, diag)) {
                const size_reg = try ctx.emitInt(source_node, @intCast(try typeTextSize(ctx, clean_field_type, diag)));
                try ctx.proc.instructions.append(ctx.program.allocator, .{ .opcode = .memcpy, .dest = addr, .arg1 = value_reg, .arg2 = size_reg, .source_node = source_node });
            } else {
                try ctx.proc.instructions.append(ctx.program.allocator, .{ .opcode = .store_ptr, .dest = addr, .arg1 = value_reg, .source_node = source_node });
            }
        }
    }

    fn tryInlineProcCall(ctx: *GenContext, proc_node: NodeIndex, args: []const u32, call_expr: NodeIndex, diag: Diagnostic) !?Bytecode.Register {
        const ast = ctx.ast;
        for (ctx.inline_stack.items) |active_proc| if (active_proc == proc_node) return null;
        try ctx.inline_stack.append(ctx.program.allocator, proc_node);
        defer _ = ctx.inline_stack.pop();
        const sig = procSignature(ast, proc_node) orelse {
            if (args.len != 0) return null;
            const result = try ctx.genInlineResultSlot(call_expr, diag);
            var frame = InlineReturnFrame{ .result_reg = result };
            defer frame.patches.deinit(ctx.program.allocator);
            const previous_return = ctx.inline_return;
            ctx.inline_return = &frame;
            defer ctx.inline_return = previous_return;
            const stmts = ast.extraSlice(ast.data(ast.data(proc_node).lhs).lhs);
            for (stmts) |stmt_idx| try ctx.genStmt(@intCast(stmt_idx), diag);
            const end_index: u32 = @intCast(ctx.proc.instructions.items.len);
            for (frame.patches.items) |patch| ctx.proc.instructions.items[patch].arg1 = end_index;
            return result;
        };
        const params = ast.extraSlice(sig.params_extra);
        if (args.len > params.len) return null;
        const allocator = ctx.program.allocator;
        var param_args = try allocator.alloc(NodeIndex, params.len);
        defer allocator.free(param_args);
        @memset(param_args, @import("Ast.zig").null_node);

        var positional_index: usize = 0;
        for (args) |arg_idx| {
            const arg: NodeIndex = @intCast(arg_idx);
            if (ast.tag(arg) == .assign_stmt and ast.tag(ast.data(arg).lhs) == .identifier) {
                const arg_name = ast.tokenSlice(ast.mainToken(ast.data(arg).lhs));
                var matched = false;
                for (params, 0..) |param_idx, i| {
                    const param: NodeIndex = @intCast(param_idx);
                    if (!std.mem.eql(u8, ast.tokenSlice(ast.mainToken(param)), arg_name)) continue;
                    param_args[i] = ast.data(arg).rhs;
                    matched = true;
                    break;
                }
                if (!matched) return null;
            } else {
                while (positional_index < params.len and param_args[positional_index] != @import("Ast.zig").null_node) positional_index += 1;
                if (positional_index >= params.len) return null;
                param_args[positional_index] = arg;
                positional_index += 1;
            }
        }

        var restores = std.ArrayList(ParamBindingRestore).empty;
        defer restores.deinit(allocator);
        for (params, 0..) |param_idx, i| {
            const param: NodeIndex = @intCast(param_idx);
            const source = if (param_args[i] != @import("Ast.zig").null_node)
                param_args[i]
            else if (ast.data(param).rhs != @import("Ast.zig").null_node)
                ast.data(param).rhs
            else
                return null;
            const arg_reg = try genCallArg(ctx, source, diag);
            const old = ctx.decl_registers.get(param);
            try restores.append(allocator, .{ .decl = param, .had_old = old != null, .old = old orelse 0 });
            try ctx.decl_registers.put(allocator, param, arg_reg);
        }

        const result = try ctx.genInlineResultSlotForReturn(sig.return_type, call_expr, diag);
        var frame = InlineReturnFrame{ .result_reg = result, .result_type = sig.return_type };
        defer frame.patches.deinit(allocator);
        const previous_return = ctx.inline_return;
        ctx.inline_return = &frame;
        defer ctx.inline_return = previous_return;
        const stmts = ast.extraSlice(ast.data(ast.data(proc_node).lhs).lhs);
        for (stmts) |stmt_idx| try ctx.genStmt(@intCast(stmt_idx), diag);
        const end_index: u32 = @intCast(ctx.proc.instructions.items.len);
        for (frame.patches.items) |patch| ctx.proc.instructions.items[patch].arg1 = end_index;
        try ctx.restoreParamBindings(restores.items);
        return result;
    }

    pub fn genBlock(ctx: *GenContext, block: NodeIndex, diag: Diagnostic) anyerror!void {
        const defer_base = ctx.defer_stmts.items.len;
        for (ctx.ast.extraSlice(ctx.ast.data(block).lhs)) |stmt| try ctx.genStmt(@intCast(stmt), diag);
        // Emit deferred statements added in this block (LIFO), then pop them.
        try ctx.emitDeferred(defer_base, diag);
        ctx.defer_stmts.shrinkRetainingCapacity(defer_base);
    }

    fn genStmt(ctx: *GenContext, stmt: NodeIndex, diag: Diagnostic) !void {
        const ast = ctx.ast;
        switch (ast.tag(stmt)) {
            .import_decl, .load_decl, .scope_decl => {},
            .expr_stmt => _ = try ctx.genExpr(ast.data(stmt).lhs, diag),
            .stmt_list => {
                var is_all_assign = true;
                var all_assign_targets_are_locals = true;
                for (ast.extraSlice(ast.data(stmt).lhs)) |child| {
                    if (ast.tag(@intCast(child)) != .assign_stmt) {
                        is_all_assign = false;
                    } else if (ctx.resolved.local_values.get(ast.data(@as(NodeIndex, @intCast(child))).lhs) == null) {
                        all_assign_targets_are_locals = false;
                    }
                }
                if (is_all_assign and all_assign_targets_are_locals) {
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
                const lhs = ast.data(stmt).lhs;
                const rhs_node = ast.data(stmt).rhs;
                if (try ctx.tryEmitAssignCompound(lhs, rhs_node, stmt, diag)) |_| return;
                const rhs = try ctx.genExpr(rhs_node, diag);
                if (ast.tag(lhs) == .field_access) {
                    const field_info = blk: {
                        const base_text = typeTextForExpr(ctx, ast.data(lhs).lhs, diag) orelse break :blk null;
                        break :blk try fieldInfoFromTypeText(ctx, base_text, ast.tokenSlice(ast.data(lhs).rhs), diag);
                    };
                    if (field_info) |info| {
                        const addr = try genAddressOfLvalue(ctx, lhs, diag);
                        const clean_field_type = std.mem.trim(u8, info.type_text, " \t\r\n");
                        if (try typeTextIsStruct(ctx, clean_field_type, diag)) {
                            const size_reg = try ctx.emitInt(stmt, @intCast(try typeTextSize(ctx, clean_field_type, diag)));
                            try ctx.proc.instructions.append(ctx.program.allocator, .{ .opcode = .memcpy, .dest = addr, .arg1 = rhs, .arg2 = size_reg, .source_node = stmt });
                        } else {
                            try ctx.proc.instructions.append(ctx.program.allocator, .{ .opcode = .store_ptr, .dest = addr, .arg1 = rhs, .source_node = stmt });
                        }
                    } else {
                        const base = try ctx.genExpr(ast.data(lhs).lhs, diag);
                        try ctx.field_values.put(ctx.program.allocator, fieldValueKey(base, ast.tokenSlice(ast.data(lhs).rhs)), rhs);
                    }
                    return;
                }
                if (ast.tag(lhs) == .unary_expr and (ast.tokens[ast.mainToken(lhs)].tag == .shift_left or ast.tokens[ast.mainToken(lhs)].tag == .dot_star)) {
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
                if (init == using_param_sentinel) {
                    const reg = try ctx.genTypedPlaceholderValue(stmt, diag);
                    try ctx.decl_registers.put(ctx.program.allocator, stmt, reg);
                } else if (init != @import("Ast.zig").null_node and ast.tag(init) != .undefined_literal) {
                    const reg = try ctx.genExpr(init, diag);
                    const ty = if (ctx.typed) |typed| typed.typeOf(stmt) else Type.init(InternPool.well_known.any_type);
                    if (ty.isInteger() or ty.isBool()) {
                        const addr_reg = ctx.proc.num_registers;
                        ctx.proc.num_registers += 1;
                        try ctx.proc.instructions.append(ctx.program.allocator, .{ .opcode = .addr_of_local, .dest = addr_reg, .arg1 = reg, .source_node = stmt });
                    }
                    try ctx.decl_registers.put(ctx.program.allocator, stmt, reg);
                } else if (ast.tag(stmt) == .var_decl and init == @import("Ast.zig").null_node) {
                    const reg = try ctx.genDefaultValue(ast.data(stmt).lhs, stmt, diag);
                    try ctx.decl_registers.put(ctx.program.allocator, stmt, reg);
                } else if (ast.tag(stmt) == .var_decl and ast.tag(init) == .undefined_literal) {
                    const reg = try ctx.genUndefinedValue(ast.data(stmt).lhs, stmt, diag);
                    try ctx.decl_registers.put(ctx.program.allocator, stmt, reg);
                }
            },
            .meta_stmt => return,
            .run_expr => {
                if (ast.tokens[ast.mainToken(stmt)].tag == .keyword_push_context) {
                    _ = try ctx.genExpr(ast.data(stmt).rhs, diag);
                    try ctx.genBlock(ast.data(stmt).lhs, diag);
                    return;
                }
                const operand = ast.data(stmt).lhs;
                if (ast.tag(operand) == .block) {
                    return;
                } else _ = try ctx.genExpr(operand, diag);
            },
            .proc_decl => {},
            .return_stmt => {
                // Emit all active deferred statements (entire stack, reversed) before returning.
                try ctx.emitDeferred(0, diag);
                const value = ast.data(stmt).lhs;
                if (ctx.inline_return) |frame| {
                    if (value != @import("Ast.zig").null_node) {
                        if (frame.result_type != @import("Ast.zig").null_node) {
                            const result_type_text = std.mem.trim(u8, ctx.nodeSource(frame.result_type), " \t\r\n");
                            if (try typeTextIsStruct(ctx, result_type_text, diag)) {
                                if (ast.tag(value) == .aggregate_literal) {
                                    try ctx.emitAggregateToStruct(value, frame.result_reg, result_type_text, stmt, diag);
                                } else {
                                    const reg = try ctx.genExpr(value, diag);
                                    const size_reg = try ctx.emitInt(stmt, @intCast(try typeTextSize(ctx, result_type_text, diag)));
                                    try ctx.proc.instructions.append(ctx.program.allocator, .{ .opcode = .memcpy, .dest = frame.result_reg, .arg1 = reg, .arg2 = size_reg, .source_node = stmt });
                                }
                            } else {
                                const reg = try ctx.genExpr(value, diag);
                                try ctx.proc.instructions.append(ctx.program.allocator, .{ .opcode = .load, .dest = frame.result_reg, .arg1 = reg, .source_node = stmt });
                            }
                        } else {
                            const reg = try ctx.genExpr(value, diag);
                            try ctx.proc.instructions.append(ctx.program.allocator, .{ .opcode = .load, .dest = frame.result_reg, .arg1 = reg, .source_node = stmt });
                        }
                    }
                    const patch_idx = ctx.proc.instructions.items.len;
                    try ctx.proc.instructions.append(ctx.program.allocator, .{ .opcode = .jump, .arg1 = 0, .source_node = stmt });
                    try frame.patches.append(ctx.program.allocator, patch_idx);
                    return;
                }
                if (value == @import("Ast.zig").null_node) {
                    try ctx.proc.instructions.append(ctx.program.allocator, .{ .opcode = .ret_void, .source_node = stmt });
                } else {
                    const reg = try ctx.genExpr(value, diag);
                    try ctx.proc.instructions.append(ctx.program.allocator, .{ .opcode = .ret, .arg1 = reg, .source_node = stmt });
                }
            },
            .if_stmt => {
                const cond_raw = try ctx.genExpr(ast.data(stmt).lhs, diag);
                const cond = try ctx.coerceToBool(cond_raw, ast.data(stmt).lhs);
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
            .while_stmt => {
                const cond_node = ast.data(stmt).lhs;
                const real_cond = if (ast.tag(cond_node) == .var_decl) ast.data(cond_node).rhs else cond_node;
                // Get label name for named while.
                const label: []const u8 = if (ast.tag(cond_node) == .var_decl)
                    ast.tokenSlice(ast.mainToken(cond_node))
                else
                    "";
                const loop_start: u32 = @intCast(ctx.proc.instructions.items.len);
                const cond_raw = try ctx.genExpr(real_cond, diag);
                const cond = try ctx.coerceToBool(cond_raw, real_cond);
                const jump_if_index = ctx.proc.instructions.items.len;
                try ctx.proc.instructions.append(ctx.program.allocator, .{ .opcode = .jump_if_false, .arg1 = cond, .arg2 = 0, .source_node = stmt });
                // Push loop frame.
                var frame = LoopFrame{
                    .label = label,
                    .continue_target = loop_start,
                    .break_patches = std.ArrayList(usize).empty,
                    .defer_depth = ctx.defer_stmts.items.len,
                };
                try ctx.loop_stack.append(ctx.program.allocator, frame);
                try ctx.genBlock(ast.data(stmt).rhs, diag);
                // Emit loop-back jump.
                try ctx.proc.instructions.append(ctx.program.allocator, .{ .opcode = .jump, .arg1 = loop_start, .source_node = stmt });
                const loop_exit: u32 = @intCast(ctx.proc.instructions.items.len);
                ctx.proc.instructions.items[jump_if_index].arg2 = loop_exit;
                // Patch all break jumps.
                frame = ctx.loop_stack.pop().?;
                for (frame.break_patches.items) |patch_idx| {
                    ctx.proc.instructions.items[patch_idx].arg1 = loop_exit;
                }
                frame.break_patches.deinit(ctx.program.allocator);
            },
            .defer_stmt => {
                // Record deferred statement for LIFO emission at scope exit.
                try ctx.defer_stmts.append(ctx.program.allocator, ast.data(stmt).lhs);
            },
            .break_stmt => {
                const label_tok = ast.data(stmt).lhs;
                const label_name: []const u8 = if (label_tok != 0) ast.tokenSlice(label_tok) else "";
                // Find target loop frame.
                var frame_idx: usize = ctx.loop_stack.items.len;
                while (frame_idx > 0) {
                    frame_idx -= 1;
                    const f = &ctx.loop_stack.items[frame_idx];
                    if (label_name.len == 0 or std.mem.eql(u8, f.label, label_name)) {
                        // Emit deferred stmts down to loop entry depth.
                        try ctx.emitDeferred(f.defer_depth, diag);
                        const patch_idx = ctx.proc.instructions.items.len;
                        try ctx.proc.instructions.append(ctx.program.allocator, .{ .opcode = .jump, .arg1 = 0, .source_node = stmt });
                        try f.break_patches.append(ctx.program.allocator, patch_idx);
                        return;
                    }
                }
                return diag.failAt(ast.tokens[ast.mainToken(stmt)].start, "break outside of loop", .{});
            },
            .continue_stmt => {
                const label_tok = ast.data(stmt).lhs;
                const label_name: []const u8 = if (label_tok != 0) ast.tokenSlice(label_tok) else "";
                // Find target loop frame.
                var frame_idx: usize = ctx.loop_stack.items.len;
                while (frame_idx > 0) {
                    frame_idx -= 1;
                    const f = &ctx.loop_stack.items[frame_idx];
                    if (label_name.len == 0 or std.mem.eql(u8, f.label, label_name)) {
                        try ctx.emitDeferred(f.defer_depth, diag);
                        try ctx.proc.instructions.append(ctx.program.allocator, .{ .opcode = .jump, .arg1 = f.continue_target, .source_node = stmt });
                        return;
                    }
                }
                return diag.failAt(ast.tokens[ast.mainToken(stmt)].start, "continue outside of loop", .{});
            },
            .for_stmt => {
                const range = ast.extraSlice(ast.data(stmt).lhs);
                if (range.len == 1 or (range.len == 2 and (range[1] & 0x80000000) != 0) or range.len == 3) {
                    const iterated: NodeIndex = @intCast(range[0]);
                    const array_slot = try ctx.genExpr(iterated, diag);
                    const elem_text = if (typeTextForExpr(ctx, iterated, diag)) |iterated_text|
                        dynamicArrayElementText(iterated_text)
                    else
                        null;
                    const elem_size = if (elem_text) |text| try typeTextSize(ctx, text, diag) else 8;
                    const elem_is_struct = if (elem_text) |text| try typeTextIsStruct(ctx, text, diag) else false;
                    const elem_is_string = if (elem_text) |text| std.mem.eql(u8, firstTypeWord(text), "string") else false;

                    const count_reg = ctx.proc.num_registers;
                    ctx.proc.num_registers += 1;
                    try ctx.proc.instructions.append(ctx.program.allocator, .{ .opcode = .array_count, .dest = count_reg, .arg1 = array_slot, .source_node = stmt });

                    const index_reg = ctx.proc.num_registers;
                    ctx.proc.num_registers += 1;
                    try ctx.proc.instructions.append(ctx.program.allocator, .{ .opcode = .load_int, .dest = index_reg, .arg1 = 0, .source_node = stmt });
                    try ctx.loop_index_registers.put(ctx.program.allocator, stmt, index_reg);

                    const loop_start: u32 = @intCast(ctx.proc.instructions.items.len);
                    const cond_reg = ctx.proc.num_registers;
                    ctx.proc.num_registers += 1;
                    try ctx.proc.instructions.append(ctx.program.allocator, .{ .opcode = .cmp_lt_int, .dest = cond_reg, .arg1 = index_reg, .arg2 = count_reg, .source_node = stmt });
                    const jump_if_index = ctx.proc.instructions.items.len;
                    try ctx.proc.instructions.append(ctx.program.allocator, .{ .opcode = .jump_if_false, .arg1 = cond_reg, .arg2 = 0, .source_node = stmt });

                    const it_reg = ctx.proc.num_registers;
                    ctx.proc.num_registers += 1;
                    try ctx.proc.instructions.append(ctx.program.allocator, .{
                        .opcode = .array_index,
                        .dest = it_reg,
                        .arg1 = array_slot,
                        .arg2 = index_reg,
                        .arg3 = @intCast(elem_size),
                        .arg4 = if (elem_is_struct) 1 else if (elem_is_string) 2 else 0,
                        .source_node = stmt,
                    });
                    try ctx.decl_registers.put(ctx.program.allocator, stmt, it_reg);

                    var frame = LoopFrame{
                        .label = if (range.len >= 2 and (range[1] & 0x80000000) != 0) ast.tokenSlice(range[1] & 0x7fffffff) else "",
                        .continue_target = loop_start,
                        .break_patches = std.ArrayList(usize).empty,
                        .defer_depth = ctx.defer_stmts.items.len,
                    };
                    try ctx.loop_stack.append(ctx.program.allocator, frame);
                    try ctx.genBlock(ast.data(stmt).rhs, diag);
                    const one_reg = ctx.proc.num_registers;
                    ctx.proc.num_registers += 1;
                    try ctx.proc.instructions.append(ctx.program.allocator, .{ .opcode = .load_int, .dest = one_reg, .arg1 = 1, .source_node = stmt });
                    try ctx.proc.instructions.append(ctx.program.allocator, .{ .opcode = .add_int, .dest = index_reg, .arg1 = index_reg, .arg2 = one_reg, .source_node = stmt });
                    try ctx.proc.instructions.append(ctx.program.allocator, .{ .opcode = .jump, .arg1 = loop_start, .source_node = stmt });
                    const end_index: u32 = @intCast(ctx.proc.instructions.items.len);
                    ctx.proc.instructions.items[jump_if_index].arg2 = end_index;
                    frame = ctx.loop_stack.pop().?;
                    var popped = frame;
                    for (popped.break_patches.items) |patch_idx| ctx.proc.instructions.items[patch_idx].arg1 = end_index;
                    popped.break_patches.deinit(ctx.program.allocator);
                } else if (range.len == 4 or (range.len == 2 and (range[1] & 0x80000000) == 0)) {
                    const is_reverse = range.len == 4 and range[3] != 0;
                    const iterator_tok: u32 = if (range.len == 4) range[2] else 0;
                    const index_reg = try ctx.genExpr(@intCast(range[0]), diag);
                    const end_reg = try ctx.genExpr(@intCast(range[1]), diag);
                    const index_addr = ctx.proc.num_registers;
                    ctx.proc.num_registers += 1;
                    try ctx.proc.instructions.append(ctx.program.allocator, .{ .opcode = .addr_of_local, .dest = index_addr, .arg1 = index_reg, .source_node = stmt });
                    try ctx.decl_registers.put(ctx.program.allocator, stmt, index_reg);
                    const loop_start: u32 = @intCast(ctx.proc.instructions.items.len);
                    const cond_reg = ctx.proc.num_registers;
                    ctx.proc.num_registers += 1;
                    if (is_reverse) {
                        // Reverse: condition is index >= end, i.e. end < index+1 i.e. NOT (index < end)
                        // Use: cmp_lt_int(end, index) → end < index → true when index > end
                        // But we want index >= end, i.e. NOT (index < end)
                        // Simplest: cmp_lt_int(end-1, index) or use a different comparison
                        // Actually for reverse "for < i: 5..0": start=5, end=0
                        // condition: index > end  →  NOT (index <= end)  →  end < index
                        try ctx.proc.instructions.append(ctx.program.allocator, .{ .opcode = .cmp_lt_int, .dest = cond_reg, .arg1 = end_reg, .arg2 = index_reg, .source_node = stmt });
                    } else {
                        try ctx.proc.instructions.append(ctx.program.allocator, .{ .opcode = .cmp_lt_int, .dest = cond_reg, .arg1 = index_reg, .arg2 = end_reg, .source_node = stmt });
                    }
                    const jump_if_index = ctx.proc.instructions.items.len;
                    try ctx.proc.instructions.append(ctx.program.allocator, .{ .opcode = .jump_if_false, .arg1 = cond_reg, .arg2 = 0, .source_node = stmt });
                    // Push loop frame with iterator name as label.
                    const iter_label: []const u8 = if (iterator_tok != 0) ast.tokenSlice(iterator_tok) else "";
                    var frame = LoopFrame{
                        .label = iter_label,
                        .continue_target = loop_start,
                        .break_patches = std.ArrayList(usize).empty,
                        .defer_depth = ctx.defer_stmts.items.len,
                    };
                    try ctx.loop_stack.append(ctx.program.allocator, frame);
                    try ctx.genBlock(ast.data(stmt).rhs, diag);
                    // Increment/decrement.
                    const one_reg = ctx.proc.num_registers;
                    ctx.proc.num_registers += 1;
                    try ctx.proc.instructions.append(ctx.program.allocator, .{ .opcode = .load_int, .dest = one_reg, .arg1 = 1, .source_node = stmt });
                    if (is_reverse) {
                        try ctx.proc.instructions.append(ctx.program.allocator, .{ .opcode = .sub_int, .dest = index_reg, .arg1 = index_reg, .arg2 = one_reg, .source_node = stmt });
                    } else {
                        try ctx.proc.instructions.append(ctx.program.allocator, .{ .opcode = .add_int, .dest = index_reg, .arg1 = index_reg, .arg2 = one_reg, .source_node = stmt });
                    }
                    try ctx.proc.instructions.append(ctx.program.allocator, .{ .opcode = .jump, .arg1 = loop_start, .source_node = stmt });
                    const loop_exit: u32 = @intCast(ctx.proc.instructions.items.len);
                    ctx.proc.instructions.items[jump_if_index].arg2 = loop_exit;
                    frame = ctx.loop_stack.pop().?;
                    for (frame.break_patches.items) |patch_idx| {
                        ctx.proc.instructions.items[patch_idx].arg1 = loop_exit;
                    }
                    frame.break_patches.deinit(ctx.program.allocator);
                } else {
                    return diag.failAt(ast.tokens[ast.mainToken(stmt)].start, "for loop requires start and end range expressions", .{});
                }
            },
            // Bare block: anonymous scope — gen all statements inside.
            .block => try ctx.genBlock(stmt, diag),
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
                const value = try parseIntLiteral(ast, expr, diag);
                const reg = proc.num_registers;
                proc.num_registers += 1;
                try proc.instructions.append(program.allocator, .{ .opcode = .load_int, .dest = reg, .arg1 = intLiteralArg(value), .source_node = expr });
                return reg;
            },
            .float_literal => {
                const raw = ast.tokenSlice(ast.mainToken(expr));
                const value: f64 = std.fmt.parseFloat(f64, raw) catch return diag.failAt(ast.tokens[ast.mainToken(expr)].start, "invalid float literal '{s}'", .{raw});
                const bits: u64 = @bitCast(value);
                const reg = proc.num_registers;
                proc.num_registers += 1;
                try proc.instructions.append(program.allocator, .{ .opcode = .load_float, .dest = reg, .arg1 = @truncate(bits), .arg2 = @truncate(bits >> 32), .source_node = expr });
                return reg;
            },
            .bool_literal => {
                const reg = proc.num_registers;
                proc.num_registers += 1;
                const value: u32 = if (ast.data(expr).lhs == 2) 0 else ast.data(expr).lhs;
                try proc.instructions.append(program.allocator, .{ .opcode = .load_bool, .dest = reg, .arg1 = value, .source_node = expr });
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
                const type_id = try ctx.phase2TypeId(ast.data(expr).lhs, diag);
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
            .import_decl, .load_decl => {
                const reg = proc.num_registers;
                proc.num_registers += 1;
                try proc.instructions.append(program.allocator, .{ .opcode = .load_const_ref, .dest = reg, .source_node = expr });
                return reg;
            },
            .struct_type, .union_type, .enum_type, .array_type, .proc_type => {
                const reg = proc.num_registers;
                proc.num_registers += 1;
                try proc.instructions.append(program.allocator, .{ .opcode = .load_type, .dest = reg, .arg1 = 0, .source_node = expr });
                return reg;
            },
            .meta_expr => {
                if (ast.data(expr).lhs != @import("Ast.zig").null_node and ast.tag(ast.data(expr).lhs) == .block) return try ctx.genTypedPlaceholderValue(expr, diag);
                return try ctx.genTypedPlaceholderValue(expr, diag);
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
                    if (typed.comptime_strings.get(expr)) |value| {
                        return try ctx.emitString(expr, value);
                    }
                }
                return diag.failAt(ast.tokens[ast.mainToken(expr)].start, "expression-form #run value propagation is not implemented for this expression", .{});
            },
            .unary_expr => {
                const operand = ast.data(expr).lhs;
                const op = ast.tokens[ast.mainToken(expr)].tag;
                if (op == .star and (ast.tag(operand) == .identifier or ast.tag(operand) == .field_access or ast.tag(operand) == .index_expr)) return try genAddressOfLvalue(ctx, operand, diag);
                const operand_reg = try ctx.genExpr(operand, diag);
                if (op == .dot_dot) return operand_reg;
                if (op == .keyword_cast and ast.data(expr).rhs != @import("Ast.zig").null_node) {
                    const raw_target_ty = ast.data(expr).rhs;
                    const target_ty: u32 = raw_target_ty & 0x7fffffff;
                    if (ast.tag(target_ty) == .pointer_type) return operand_reg;
                    if (ast.tag(target_ty) == .type_expr) {
                        const target_name = ast.tokenSlice(ast.mainToken(target_ty));
                        if (!std.mem.eql(u8, target_name, "bool") and
                            !std.mem.eql(u8, target_name, "float") and
                            !std.mem.eql(u8, target_name, "float32") and
                            !std.mem.eql(u8, target_name, "float64") and
                            !std.mem.eql(u8, target_name, "int") and
                            !std.mem.eql(u8, target_name, "s64") and
                            !std.mem.eql(u8, target_name, "s32") and
                            !std.mem.eql(u8, target_name, "u8") and
                            !std.mem.eql(u8, target_name, "u16") and
                            !std.mem.eql(u8, target_name, "u32") and
                            !std.mem.eql(u8, target_name, "u64"))
                        {
                            return operand_reg;
                        }
                    }
                }
                if (op == .shift_left or op == .dot_star) {
                    if (ctx.typed != null and !ctx.typed.?.typeOf(operand).isPointer()) return operand_reg;
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
                if (op == .star and ast.tag(operand) != .identifier) {
                    return try ctx.genTypedPlaceholderValue(expr, diag);
                }
                if (op == .bang and (ctx.typed == null or !ctx.typed.?.typeOf(operand).isBool())) {
                    const bool_reg = proc.num_registers;
                    proc.num_registers += 1;
                    try proc.instructions.append(program.allocator, .{ .opcode = .int_to_bool_cast, .dest = bool_reg, .arg1 = operand_reg, .source_node = expr });
                    try proc.instructions.append(program.allocator, .{ .opcode = .not_bool, .dest = reg, .arg1 = bool_reg, .source_node = expr });
                    return reg;
                }
                if (op == .tilde) {
                    try proc.instructions.append(program.allocator, .{ .opcode = .bit_not, .dest = reg, .arg1 = operand_reg, .source_node = expr });
                    return reg;
                }
                const opcode: Bytecode.Opcode = switch (op) {
                    .minus => if (ctx.typed != null and ctx.typed.?.typeOf(operand).isFloat()) .neg_float else .neg_int,
                    .bang => .not_bool,
                    .star => .addr_of_local,
                    .keyword_xx => if (ctx.typed != null and ctx.typed.?.typeOf(operand).isBool()) .bool_to_int_cast else .int_trunc_cast,
                    .keyword_cast => blk: {
                        if (ast.data(expr).rhs == @import("Ast.zig").null_node) break :blk .int_trunc_cast;
                        const raw_target_ty = ast.data(expr).rhs;
                        const target_ty: u32 = raw_target_ty & 0x7fffffff;
                        if (ast.tag(target_ty) == .type_expr and std.mem.eql(u8, ast.tokenSlice(ast.mainToken(target_ty)), "bool")) break :blk .int_to_bool_cast;
                        if (ast.tag(target_ty) == .type_expr and std.mem.eql(u8, ast.tokenSlice(ast.mainToken(target_ty)), "float")) break :blk .float_cast;
                        break :blk .int_trunc_cast;
                    },
                    else => return diag.failAt(ast.tokens[ast.mainToken(expr)].start, "unsupported unary operator in bytecode generator", .{}),
                };
                const cast_target_id: u32 = if (op == .keyword_cast and opcode == .int_trunc_cast and ast.data(expr).rhs != @import("Ast.zig").null_node) blk: {
                    const raw_target_ty = ast.data(expr).rhs;
                    const target_ty: u32 = raw_target_ty & 0x7fffffff;
                    break :blk try typeIdFromTypeExpr(ast, target_ty, diag);
                } else 0;
                try proc.instructions.append(program.allocator, .{ .opcode = opcode, .dest = reg, .arg1 = operand_reg, .arg2 = cast_target_id, .source_node = expr });
                if (op == .star) {
                    if (ctx.resolved.local_values.get(operand)) |decl| {
                        try ctx.pointer_addrs.put(program.allocator, reg, decl);
                    }
                }
                return reg;
            },
            .identifier => {
                if (ctx.resolved.local_values.get(expr)) |decl| {
                    if (decl == @import("Ast.zig").null_node) {
                        if (isBuiltinTypeName(ast.tokenSlice(ast.mainToken(expr)))) {
                            const reg = proc.num_registers;
                            proc.num_registers += 1;
                            const type_id = try typeIdFromTypeName(ast, expr, diag);
                            try proc.instructions.append(program.allocator, .{ .opcode = .load_type, .dest = reg, .arg1 = type_id, .source_node = expr });
                            return reg;
                        }
                        return ctx.genTypedPlaceholderValue(expr, diag);
                    }
                    if (ast.tag(decl) == .for_stmt and ctx.isLoopIndexIdentifier(expr, decl)) {
                        if (ctx.loop_index_registers.get(decl)) |index_reg| return index_reg;
                    }
                    if (ctx.decl_registers.get(decl)) |reg| return reg;
                    switch (ast.tag(decl)) {
                        .var_decl => {
                            const init = ast.data(decl).rhs;
                            const reg = if (init == using_param_sentinel)
                                try ctx.genTypedPlaceholderValue(expr, diag)
                            else if (init != @import("Ast.zig").null_node and ast.tag(init) != .undefined_literal)
                                try ctx.genExpr(init, diag)
                            else if (init != @import("Ast.zig").null_node and ast.tag(init) == .undefined_literal)
                                try ctx.genUndefinedValue(ast.data(decl).lhs, decl, diag)
                            else
                                try ctx.genDefaultValue(ast.data(decl).lhs, decl, diag);
                            try ctx.decl_registers.put(program.allocator, decl, reg);
                            return reg;
                        },
                        .const_decl => {
                            const reg = try ctx.genExpr(ast.data(decl).lhs, diag);
                            try ctx.decl_registers.put(program.allocator, decl, reg);
                            return reg;
                        },
                        .proc_decl => {
                            const reg = proc.num_registers;
                            proc.num_registers += 1;
                            try proc.instructions.append(program.allocator, .{ .opcode = .proc_addr, .dest = reg, .source_node = expr });
                            return reg;
                        },
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
            .proc_decl => {
                const reg = proc.num_registers;
                proc.num_registers += 1;
                try proc.instructions.append(program.allocator, .{ .opcode = .proc_addr, .dest = reg, .source_node = expr });
                return reg;
            },
            .binary_expr => {
                const op = ast.tokens[ast.mainToken(expr)].tag;
                if (isCompoundAssignmentOp(op)) {
                    return try ctx.emitCompoundAssignment(ast.data(expr).lhs, ast.data(expr).rhs, op, expr, diag);
                }
                if (ast.tag(ast.data(expr).lhs) == .unary_expr and ast.tokens[ast.mainToken(ast.data(expr).lhs)].tag == .shift_left and (op == .star_equal or op == .plus_equal or op == .minus_equal or op == .slash_equal)) {
                    _ = try ctx.genExpr(ast.data(expr).lhs, diag);
                    _ = try ctx.genExpr(ast.data(expr).rhs, diag);
                    return try ctx.genTypedPlaceholderValue(expr, diag);
                }
                if (ctx.typed) |typed| {
                    const lhs_ty = typed.typeOf(ast.data(expr).lhs);
                    const rhs_ty = typed.typeOf(ast.data(expr).rhs);
                    const comparison = op == .less_than or op == .less_equal or op == .greater_than or op == .greater_equal or op == .equal_equal or op == .bang_equal;
                    const pointerish = lhs_ty.isPointer() or rhs_ty.isPointer() or lhs_ty.isAny() or rhs_ty.isAny();
                    const source_typed_scalar = if (typeTextForExpr(ctx, ast.data(expr).lhs, diag)) |text| typeTextIsScalarComparable(text) else false;
                    const rhs_source_typed_scalar = if (typeTextForExpr(ctx, ast.data(expr).rhs, diag)) |text| typeTextIsScalarComparable(text) else false;
                    const pointerish_arithmetic = pointerish or lhs_ty.isString() or rhs_ty.isString();
                    if (pointerish_arithmetic and !source_typed_scalar and !rhs_source_typed_scalar and (op == .star or op == .star_equal or op == .plus or op == .plus_equal or op == .minus or op == .minus_equal or op == .slash or op == .slash_equal)) {
                        _ = try ctx.genExpr(ast.data(expr).lhs, diag);
                        _ = try ctx.genExpr(ast.data(expr).rhs, diag);
                        return try ctx.genTypedPlaceholderValue(expr, diag);
                    }
                    if (pointerish and comparison and op != .equal_equal and op != .bang_equal and !source_typed_scalar and !rhs_source_typed_scalar) {
                        _ = try ctx.genExpr(ast.data(expr).lhs, diag);
                        _ = try ctx.genExpr(ast.data(expr).rhs, diag);
                        const reg = proc.num_registers;
                        proc.num_registers += 1;
                        try proc.instructions.append(program.allocator, .{ .opcode = .load_bool, .dest = reg, .arg1 = if (op == .bang_equal) 0 else 1, .source_node = expr });
                        return reg;
                    }
                }
                const opcode: Bytecode.Opcode = switch (op) {
                    .star, .star_equal => if (ctx.typed != null and (ctx.typed.?.typeOf(ast.data(expr).lhs).isFloat() or ctx.typed.?.typeOf(ast.data(expr).rhs).isFloat())) .mul_float else .mul_int,
                    .percent => .rem_int,
                    .ampersand, .ampersand_equal => .bit_and,
                    .pipe, .pipe_equal => .bit_or,
                    .caret, .caret_equal => .bit_xor,
                    .shift_left => .shl_int,
                    .shift_right => .shr_int,
                    .shift_left_rotate => .rotl_int,
                    .shift_right_rotate => .shr_int,
                    .plus, .plus_equal => if (ctx.typed != null and (ctx.typed.?.typeOf(ast.data(expr).lhs).isFloat() or ctx.typed.?.typeOf(ast.data(expr).rhs).isFloat())) .add_float else .add_int,
                    .slash, .slash_equal => if (ctx.typed != null and (ctx.typed.?.typeOf(ast.data(expr).lhs).isFloat() or ctx.typed.?.typeOf(ast.data(expr).rhs).isFloat())) .div_float else .div_int,
                    .minus, .minus_equal => if (ctx.typed != null and (ctx.typed.?.typeOf(ast.data(expr).lhs).isFloat() or ctx.typed.?.typeOf(ast.data(expr).rhs).isFloat())) .sub_float else .sub_int,
                    .equal_equal, .keyword_case => .cmp_eq,
                    .bang_equal => .cmp_ne,
                    .less_than => .cmp_lt_int,
                    .less_equal => .cmp_le_int,
                    .greater_than => .cmp_gt_int,
                    .greater_equal => .cmp_ge_int,
                    .ampersand_ampersand => .bool_and,
                    .pipe_pipe, .pipe_pipe_equal => .bool_or,
                    else => return diag.failAt(ast.tokens[ast.mainToken(expr)].start, "Phase 2 bytecode currently supports only arithmetic/equality/logical binary expressions", .{}),
                };
                const lhs = try ctx.genExpr(ast.data(expr).lhs, diag);
                const rhs = try ctx.genExpr(ast.data(expr).rhs, diag);
                const compound_assignment = op == .star_equal or op == .plus_equal or op == .minus_equal or op == .slash_equal or op == .ampersand_equal or op == .pipe_equal or op == .caret_equal or op == .pipe_pipe_equal;
                const reg = if (compound_assignment and ast.tag(ast.data(expr).lhs) == .identifier)
                    lhs
                else blk: {
                    const tmp = proc.num_registers;
                    proc.num_registers += 1;
                    break :blk tmp;
                };
                try proc.instructions.append(program.allocator, .{ .opcode = opcode, .dest = reg, .arg1 = lhs, .arg2 = rhs, .source_node = expr });
                if (compound_assignment and ast.tag(ast.data(expr).lhs) == .field_access) {
                    const addr = try genAddressOfLvalue(ctx, ast.data(expr).lhs, diag);
                    try proc.instructions.append(program.allocator, .{ .opcode = .store_ptr, .dest = addr, .arg1 = reg, .source_node = expr });
                }
                return reg;
            },
            .ifx_expr => {
                const raw_cond = try ctx.genExpr(ast.data(expr).lhs, diag);
                const cond = if (ctx.typed != null and !ctx.typed.?.typeOf(ast.data(expr).lhs).isBool()) blk: {
                    const bool_reg = proc.num_registers;
                    proc.num_registers += 1;
                    try proc.instructions.append(program.allocator, .{ .opcode = .int_to_bool_cast, .dest = bool_reg, .arg1 = raw_cond, .source_node = expr });
                    break :blk bool_reg;
                } else raw_cond;
                const arms = ast.extraSlice(ast.data(expr).rhs);
                if (arms.len != 2) return diag.failAt(ast.tokens[ast.mainToken(expr)].start, "internal error: ifx requires two arms", .{});
                const then_reg = try ctx.genExpr(@intCast(arms[0]), diag);
                const else_reg = try ctx.genExpr(@intCast(arms[1]), diag);
                if (ctx.typed) |typed| {
                    const then_ty = typed.typeOf(@intCast(arms[0]));
                    const else_ty = typed.typeOf(@intCast(arms[1]));
                    const then_supported = then_ty.isBool() or then_ty.isInteger() or then_ty.isFloat();
                    const else_supported = else_ty.isBool() or else_ty.isInteger() or else_ty.isFloat();
                    if (!then_supported or !else_supported) {
                        return then_reg;
                    }
                }
                const reg = proc.num_registers;
                proc.num_registers += 1;
                try proc.instructions.append(program.allocator, .{ .opcode = .select_value, .dest = reg, .arg1 = cond, .arg2 = then_reg, .arg3 = else_reg, .source_node = expr });
                return reg;
            },
            .aggregate_literal => {
                const elems = ast.extraSlice(ast.data(expr).lhs);
                if (elems.len == 3) {
                    for (elems) |elem_idx| {
                        const elem: NodeIndex = @intCast(elem_idx);
                        if (ast.tag(elem) == .assign_stmt)
                            _ = try ctx.genExpr(ast.data(elem).rhs, diag)
                        else
                            _ = try ctx.genExpr(elem, diag);
                    }
                    const reg = proc.num_registers;
                    proc.num_registers += 1;
                    try proc.instructions.append(program.allocator, .{ .opcode = .make_vector3, .dest = reg, .source_node = expr });
                    return reg;
                }
                for (elems) |elem_idx| {
                    const elem: NodeIndex = @intCast(elem_idx);
                    if (ast.tag(elem) == .assign_stmt)
                        _ = try ctx.genExpr(ast.data(elem).rhs, diag)
                    else
                        _ = try ctx.genExpr(elem, diag);
                }
                const reg = proc.num_registers;
                proc.num_registers += 1;
                try proc.instructions.append(program.allocator, .{ .opcode = .load_int, .dest = reg, .arg1 = 0, .source_node = expr });
                return reg;
            },
            .typed_aggregate_literal => {
                const payload = ast.extraSlice(ast.data(expr).lhs);
                const fields = ast.extraSlice(payload[1]);
                for (fields) |field_idx| {
                    const field: NodeIndex = @intCast(field_idx);
                    if (ast.tag(field) == .assign_stmt)
                        _ = try ctx.genExpr(ast.data(field).rhs, diag)
                    else
                        _ = try ctx.genExpr(field, diag);
                }
                const reg = proc.num_registers;
                proc.num_registers += 1;
                try proc.instructions.append(program.allocator, .{ .opcode = .load_int, .dest = reg, .arg1 = 0, .source_node = expr });
                return reg;
            },
            .typed_array_literal => {
                const payload = ast.extraSlice(ast.data(expr).lhs);
                const elems = ast.extraSlice(payload[1]);
                for (elems) |elem| _ = try ctx.genExpr(@intCast(elem), diag);
                const reg = proc.num_registers;
                proc.num_registers += 1;
                try proc.instructions.append(program.allocator, .{ .opcode = .load_int, .dest = reg, .arg1 = 0, .source_node = expr });
                return reg;
            },
            .field_access => {
                if (ast.data(expr).lhs == @import("Ast.zig").null_node) {
                    const field_name = ast.tokenSlice(ast.data(expr).rhs);
                    const reg = proc.num_registers;
                    proc.num_registers += 1;
                    const value: u32 = if (try enumValueByName(ctx, field_name, diag)) |enum_value|
                        enum_value
                    else if (std.mem.eql(u8, field_name, "FAILED") or std.mem.eql(u8, field_name, "YES") or std.mem.eql(u8, field_name, "TRUE"))
                        1
                    else
                        0;
                    try proc.instructions.append(program.allocator, .{ .opcode = .load_int, .dest = reg, .arg1 = value, .source_node = expr });
                    return reg;
                }
                const field_name = ast.tokenSlice(ast.data(expr).rhs);
                if (ast.data(expr).lhs != @import("Ast.zig").null_node and ast.tag(ast.data(expr).lhs) == .identifier and std.mem.eql(u8, ast.tokenSlice(ast.mainToken(ast.data(expr).lhs)), "Type_Info_Tag")) {
                    const value: u32 = typeInfoTagValue(field_name) orelse return diag.failAt(ast.tokens[ast.data(expr).rhs].start, "unsupported Type_Info_Tag value '{s}'", .{field_name});
                    const reg = proc.num_registers;
                    proc.num_registers += 1;
                    try proc.instructions.append(program.allocator, .{ .opcode = .load_int, .dest = reg, .arg1 = value, .source_node = expr });
                    return reg;
                }
                if (ast.data(expr).lhs != @import("Ast.zig").null_node and ast.tag(ast.data(expr).lhs) == .call_expr) {
                    const lhs_call = ast.data(expr).lhs;
                    const callee = ast.data(lhs_call).lhs;
                    if (ast.tag(callee) == .identifier and (std.mem.eql(u8, ast.tokenSlice(ast.mainToken(callee)), "current_time_monotonic") or std.mem.eql(u8, ast.tokenSlice(ast.mainToken(callee)), "current_time_consensus"))) {
                        if (!std.mem.eql(u8, field_name, "low")) return diag.failAt(ast.tokens[ast.data(expr).rhs].start, "unsupported Apollo_Time field '{s}'", .{field_name});
                        return try ctx.genExpr(lhs_call, diag);
                    }
                }
                const base_reg = try ctx.genExpr(ast.data(expr).lhs, diag);
                if (ctx.field_values.get(fieldValueKey(base_reg, field_name))) |value_reg| return value_reg;
                if (typeTextForExpr(ctx, ast.data(expr).lhs, diag)) |base_text| {
                    if (std.mem.eql(u8, firstTypeWord(base_text), "string")) {
                        if (std.mem.eql(u8, field_name, "count")) {
                            const reg = proc.num_registers;
                            proc.num_registers += 1;
                            try proc.instructions.append(program.allocator, .{ .opcode = .string_len, .dest = reg, .arg1 = base_reg, .source_node = expr });
                            return reg;
                        }
                        if (std.mem.eql(u8, field_name, "data")) {
                            const reg = proc.num_registers;
                            proc.num_registers += 1;
                            try proc.instructions.append(program.allocator, .{ .opcode = .string_data, .dest = reg, .arg1 = base_reg, .source_node = expr });
                            return reg;
                        }
                    }
                    if (dynamicArrayElementText(base_text) != null and std.mem.eql(u8, field_name, "count")) {
                        const reg = proc.num_registers;
                        proc.num_registers += 1;
                        try proc.instructions.append(program.allocator, .{ .opcode = .array_count, .dest = reg, .arg1 = base_reg, .source_node = expr });
                        return reg;
                    }
                    if (try fieldInfoFromTypeText(ctx, base_text, field_name, diag)) |info| {
                        const addr = if (info.offset == 0) base_reg else blk: {
                            const tmp = proc.num_registers;
                            proc.num_registers += 1;
                            try proc.instructions.append(program.allocator, .{ .opcode = .ptr_offset, .dest = tmp, .arg1 = base_reg, .arg2 = @intCast(info.offset), .source_node = expr });
                            break :blk tmp;
                        };
                        const clean_field_type = std.mem.trim(u8, info.type_text, " \t\r\n");
                        if (isDynamicArrayTypeText(clean_field_type) or try typeTextIsStruct(ctx, clean_field_type, diag)) return addr;
                        const reg = proc.num_registers;
                        proc.num_registers += 1;
                        if (std.mem.eql(u8, firstTypeWord(clean_field_type), "string")) {
                            try proc.instructions.append(program.allocator, .{ .opcode = .load_ptr_string, .dest = reg, .arg1 = addr, .source_node = expr });
                        } else {
                            try proc.instructions.append(program.allocator, .{ .opcode = .load_ptr, .dest = reg, .arg1 = addr, .source_node = expr });
                        }
                        return reg;
                    }
                }
                const lhs_ty = if (ctx.typed) |typed| typed.typeOf(ast.data(expr).lhs) else Type.voidType();
                if (lhs_ty.isString()) {
                    if (std.mem.eql(u8, field_name, "count")) {
                        const reg = proc.num_registers;
                        proc.num_registers += 1;
                        try proc.instructions.append(program.allocator, .{ .opcode = .string_len, .dest = reg, .arg1 = base_reg, .source_node = expr });
                        return reg;
                    }
                    if (std.mem.eql(u8, field_name, "data")) {
                        const reg = proc.num_registers;
                        proc.num_registers += 1;
                        try proc.instructions.append(program.allocator, .{ .opcode = .string_data, .dest = reg, .arg1 = base_reg, .source_node = expr });
                        return reg;
                    }
                }
                if (lhs_ty.isAny() or lhs_ty.isPointer()) {
                    if (std.mem.eql(u8, field_name, "value_pointer")) {
                        const reg = proc.num_registers;
                        proc.num_registers += 1;
                        try proc.instructions.append(program.allocator, .{ .opcode = .load_null_ptr, .dest = reg, .source_node = expr });
                        return reg;
                    }
                    if (std.mem.eql(u8, field_name, "type") and lhs_ty.isAny()) {
                        const reg = proc.num_registers;
                        proc.num_registers += 1;
                        try proc.instructions.append(program.allocator, .{ .opcode = .load_null_ptr, .dest = reg, .source_node = expr });
                        return reg;
                    }
                    if (std.mem.eql(u8, field_name, "type") or
                        std.mem.eql(u8, field_name, "offset_in_bytes") or
                        std.mem.eql(u8, field_name, "flags") or
                        std.mem.eql(u8, field_name, "enum_type_flags") or
                        std.mem.eql(u8, field_name, "runtime_size"))
                    {
                        const reg = proc.num_registers;
                        proc.num_registers += 1;
                        try proc.instructions.append(program.allocator, .{ .opcode = .load_int, .dest = reg, .arg1 = 0, .source_node = expr });
                        return reg;
                    }
                    if (std.mem.eql(u8, field_name, "name")) {
                        const reg = proc.num_registers;
                        proc.num_registers += 1;
                        const string_idx = try program.addString("");
                        try proc.instructions.append(program.allocator, .{ .opcode = .load_string, .dest = reg, .arg1 = string_idx, .source_node = expr });
                        return reg;
                    }
                    if (std.mem.eql(u8, field_name, "members") or std.mem.eql(u8, field_name, "notes")) {
                        return try ctx.genTypedPlaceholderValue(expr, diag);
                    }
                }
                if (lhs_ty.index == InternPool.well_known.type_type) {
                    if (std.mem.eql(u8, field_name, "name")) {
                        const reg = proc.num_registers;
                        proc.num_registers += 1;
                        const string_idx = try program.addString("");
                        try proc.instructions.append(program.allocator, .{ .opcode = .load_string, .dest = reg, .arg1 = string_idx, .source_node = expr });
                        return reg;
                    }
                    if (std.mem.eql(u8, field_name, "members") or std.mem.eql(u8, field_name, "notes")) {
                        return try ctx.genTypedPlaceholderValue(expr, diag);
                    }
                    const reg = proc.num_registers;
                    proc.num_registers += 1;
                    try proc.instructions.append(program.allocator, .{ .opcode = .load_int, .dest = reg, .arg1 = 0, .source_node = expr });
                    return reg;
                }
                if (lhs_ty.index == InternPool.well_known.calendar_type) {
                    const reg = proc.num_registers;
                    proc.num_registers += 1;
                    try proc.instructions.append(program.allocator, .{ .opcode = .load_calendar_field, .dest = reg, .arg1 = base_reg, .arg2 = try calendarFieldId(ast, ast.data(expr).rhs, diag), .source_node = expr });
                    return reg;
                }
                return try ctx.genExpr(ast.data(expr).lhs, diag);
            },
            .index_expr => {
                const base = ast.data(expr).lhs;
                const index = ast.data(expr).rhs;
                const base_reg = try ctx.genExpr(base, diag);
                const index_reg = try ctx.genExpr(index, diag);
                const base_ty = if (ctx.typed) |typed| typed.typeOf(base) else Type.voidType();
                if (base_ty.isString()) {
                    const reg = proc.num_registers;
                    proc.num_registers += 1;
                    try proc.instructions.append(program.allocator, .{ .opcode = .string_index, .dest = reg, .arg1 = base_reg, .arg2 = index_reg, .source_node = expr });
                    return reg;
                }
                if (typeTextForExpr(ctx, base, diag)) |base_text| {
                    if (std.mem.eql(u8, firstTypeWord(base_text), "string")) {
                        const reg = proc.num_registers;
                        proc.num_registers += 1;
                        try proc.instructions.append(program.allocator, .{ .opcode = .string_index, .dest = reg, .arg1 = base_reg, .arg2 = index_reg, .source_node = expr });
                        return reg;
                    }
                    if (dynamicArrayElementText(base_text)) |elem_text| {
                        const elem_size = try typeTextSize(ctx, elem_text, diag);
                        const elem_is_struct = try typeTextIsStruct(ctx, elem_text, diag);
                        const elem_kind: u32 = if (elem_is_struct) 1 else if (std.mem.eql(u8, firstTypeWord(elem_text), "string")) 2 else 0;
                        const reg = proc.num_registers;
                        proc.num_registers += 1;
                        try proc.instructions.append(program.allocator, .{ .opcode = .array_index, .dest = reg, .arg1 = base_reg, .arg2 = index_reg, .arg3 = @intCast(elem_size), .arg4 = elem_kind, .source_node = expr });
                        return reg;
                    }
                }
                return base_reg;
            },
            .call_expr => {
                const callee = ast.data(expr).lhs;
                if (ast.tag(callee) == .proc_decl) {
                    const args = ast.extraSlice(ast.data(expr).rhs);
                    if (std.mem.eql(u8, ast.tokenSlice(ast.mainToken(callee)), "string_slice")) return try ctx.emitStringSliceCall(args, expr, diag);
                    if (try ctx.tryInlineProcCall(callee, args, expr, diag)) |reg| return reg;
                    for (args) |arg_idx| {
                        const arg: NodeIndex = @intCast(arg_idx);
                        if (ast.tag(arg) == .assign_stmt)
                            _ = try ctx.genExpr(ast.data(arg).rhs, diag)
                        else
                            _ = try ctx.genExpr(arg, diag);
                    }
                    return try ctx.genTypedPlaceholderValue(expr, diag);
                }
                if (ast.tag(callee) == .field_access) {
                    _ = try ctx.genExpr(ast.data(callee).lhs, diag);
                    const args = ast.extraSlice(ast.data(expr).rhs);
                    for (args) |arg_idx| {
                        const arg: NodeIndex = @intCast(arg_idx);
                        if (ast.tag(arg) == .assign_stmt) {
                            const rhs = ast.data(arg).rhs;
                            if (ast.tag(rhs) == .unary_expr and ast.tokens[ast.mainToken(rhs)].tag == .dot_dot)
                                _ = try ctx.genExpr(ast.data(rhs).lhs, diag)
                            else
                                _ = try ctx.genExpr(rhs, diag);
                        } else if (ast.tag(arg) == .unary_expr and ast.tokens[ast.mainToken(arg)].tag == .dot_dot) {
                            _ = try ctx.genExpr(ast.data(arg).lhs, diag);
                        } else {
                            _ = try ctx.genExpr(arg, diag);
                        }
                    }
                    return try ctx.genTypedPlaceholderValue(expr, diag);
                }
                const name = ast.tokenSlice(ast.mainToken(callee));
                if (try ctx.genCompilerIntrinsicCall(name, expr, diag)) |intrinsic_reg| return intrinsic_reg;
                if (std.mem.eql(u8, name, "thread_init") or
                    std.mem.eql(u8, name, "thread_start") or
                    std.mem.eql(u8, name, "thread_deinit") or
                    std.mem.eql(u8, name, "thread_destroy"))
                {
                    const args = ast.extraSlice(ast.data(expr).rhs);
                    for (args) |arg| _ = try genCallArg(ctx, @intCast(arg), diag);
                    return try ctx.emitInt(expr, 0);
                }
                if (std.mem.eql(u8, name, "thread_is_done")) {
                    const args = ast.extraSlice(ast.data(expr).rhs);
                    for (args) |arg| _ = try genCallArg(ctx, @intCast(arg), diag);
                    return try ctx.emitBool(expr, true);
                }
                if (ctx.resolved.lookup(name)) |sym| {
                    if (sym == .placeholder and ctx.resolved.overloads(name) == null) {
                        const args = ast.extraSlice(ast.data(expr).rhs);
                        for (args) |arg_idx| {
                            const arg: NodeIndex = @intCast(arg_idx);
                            if (ast.tag(arg) == .assign_stmt)
                                _ = try ctx.genExpr(ast.data(arg).rhs, diag)
                            else
                                _ = try ctx.genExpr(arg, diag);
                        }
                        return try ctx.genTypedPlaceholderValue(expr, diag);
                    }
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
                    if (args.len < 1) return diag.failAt(ast.tokens[ast.mainToken(expr)].start, "New expects one type argument", .{});
                    for (args[1..]) |arg| _ = try genCallArg(ctx, @intCast(arg), diag);
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
                if (std.mem.eql(u8, name, "alloc")) {
                    const args = ast.extraSlice(ast.data(expr).rhs);
                    if (args.len < 1) return diag.failAt(ast.tokens[ast.mainToken(expr)].start, "alloc expects one byte-count argument", .{});
                    for (args[1..]) |arg| _ = try genCallArg(ctx, @intCast(arg), diag);
                    const size_reg = try ctx.genExpr(@intCast(args[0]), diag);
                    const reg = proc.num_registers;
                    proc.num_registers += 1;
                    try proc.instructions.append(program.allocator, .{ .opcode = .alloc_heap, .dest = reg, .arg1 = size_reg, .source_node = expr });
                    return reg;
                }
                if (std.mem.eql(u8, name, "compiler_arg_count")) {
                    const args = ast.extraSlice(ast.data(expr).rhs);
                    if (args.len != 0) return diag.failAt(ast.tokens[ast.mainToken(expr)].start, "compiler_arg_count expects no arguments", .{});
                    const reg = proc.num_registers;
                    proc.num_registers += 1;
                    try proc.instructions.append(program.allocator, .{ .opcode = .compiler_arg_count, .dest = reg, .source_node = expr });
                    return reg;
                }
                if (std.mem.eql(u8, name, "compiler_arg")) {
                    const args = ast.extraSlice(ast.data(expr).rhs);
                    if (args.len != 1) return diag.failAt(ast.tokens[ast.mainToken(expr)].start, "compiler_arg expects one integer index", .{});
                    const index_reg = try ctx.genExpr(@intCast(args[0]), diag);
                    const reg = proc.num_registers;
                    proc.num_registers += 1;
                    try proc.instructions.append(program.allocator, .{ .opcode = .compiler_arg, .dest = reg, .arg1 = index_reg, .source_node = expr });
                    return reg;
                }
                if (std.mem.eql(u8, name, "compiler_read_file")) {
                    const args = ast.extraSlice(ast.data(expr).rhs);
                    if (args.len != 1) return diag.failAt(ast.tokens[ast.mainToken(expr)].start, "compiler_read_file expects one path string", .{});
                    const path_reg = try ctx.genExpr(@intCast(args[0]), diag);
                    const reg = proc.num_registers;
                    proc.num_registers += 1;
                    try proc.instructions.append(program.allocator, .{ .opcode = .compiler_read_file, .dest = reg, .arg1 = path_reg, .source_node = expr });
                    return reg;
                }
                if (std.mem.eql(u8, name, "string_slice")) {
                    const args = ast.extraSlice(ast.data(expr).rhs);
                    return try ctx.emitStringSliceCall(args, expr, diag);
                }
                if (std.mem.eql(u8, name, "array_add")) {
                    const args = ast.extraSlice(ast.data(expr).rhs);
                    if (args.len == 0) return diag.failAt(ast.tokens[ast.mainToken(expr)].start, "array_add expects an array argument", .{});
                    const array_arg: NodeIndex = @intCast(args[0]);
                    const array_operand = if (ast.tag(array_arg) == .unary_expr and ast.tokens[ast.mainToken(array_arg)].tag == .star) ast.data(array_arg).lhs else array_arg;
                    const elem_text = typeTextForExpr(ctx, array_operand, diag) orelse {
                        for (args[1..]) |arg| _ = try ctx.genExpr(@intCast(arg), diag);
                        return try ctx.genTypedPlaceholderValue(expr, diag);
                    };
                    const elem_ty = dynamicArrayElementText(elem_text) orelse {
                        for (args[1..]) |arg| _ = try ctx.genExpr(@intCast(arg), diag);
                        return try ctx.genTypedPlaceholderValue(expr, diag);
                    };
                    const array_slot = if (ast.tag(array_arg) == .unary_expr and ast.tokens[ast.mainToken(array_arg)].tag == .star)
                        try genAddressOfLvalue(ctx, array_operand, diag)
                    else
                        try ctx.genExpr(array_operand, diag);
                    const elem_size = try typeTextSize(ctx, elem_ty, diag);
                    const elem_is_struct = try typeTextIsStruct(ctx, elem_ty, diag);
                    var last_reg: ?Bytecode.Register = null;
                    if (args.len == 1) {
                        last_reg = try ctx.genDefaultValue(@import("Ast.zig").null_node, expr, diag);
                    } else {
                        for (args[1..]) |item_idx| {
                            const item_reg = try ctx.genExpr(@intCast(item_idx), diag);
                            const reg = proc.num_registers;
                            proc.num_registers += 1;
                            try proc.instructions.append(program.allocator, .{ .opcode = .array_add, .dest = reg, .arg1 = array_slot, .arg2 = item_reg, .arg3 = @intCast(elem_size), .arg4 = if (elem_is_struct) 1 else 0, .source_node = expr });
                            last_reg = reg;
                        }
                    }
                    const result = last_reg orelse try ctx.genTypedPlaceholderValue(expr, diag);
                    if (ast.tag(array_operand) == .identifier) if (ctx.resolved.local_values.get(array_operand)) |decl| try ctx.array_last_items.put(program.allocator, decl, result);
                    return result;
                }
                if (std.mem.eql(u8, name, "assert")) {
                    const args = ast.extraSlice(ast.data(expr).rhs);
                    if (args.len < 1) return diag.failAt(ast.tokens[ast.mainToken(expr)].start, "assert expects at least one argument", .{});
                    const cond = try ctx.genExpr(@intCast(args[0]), diag);
                    for (args[1..]) |arg| _ = try genCallArg(ctx, @intCast(arg), diag);
                    try proc.instructions.append(program.allocator, .{ .opcode = .assert_true, .arg1 = cond, .source_node = ast.tokens[ast.mainToken(expr)].start });
                    return cond;
                }
                if (std.mem.eql(u8, name, "memcpy")) {
                    const args = ast.extraSlice(ast.data(expr).rhs);
                    if (args.len != 3) return diag.failAt(ast.tokens[ast.mainToken(expr)].start, "memcpy expects three arguments", .{});
                    const dst = try ctx.genExpr(@intCast(args[0]), diag);
                    const src = try ctx.genExpr(@intCast(args[1]), diag);
                    const count = try ctx.genExpr(@intCast(args[2]), diag);
                    if (ctx.typed) |typed| {
                        const dst_ty = typed.typeOf(@intCast(args[0]));
                        const src_ty = typed.typeOf(@intCast(args[1]));
                        if (!dst_ty.isPointer() or !src_ty.isPointer()) return dst;
                    }
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
                if (std.mem.eql(u8, name, "formatInt")) {
                    const args = ast.extraSlice(ast.data(expr).rhs);
                    if (args.len < 1) return diag.failAt(ast.tokens[ast.mainToken(expr)].start, "formatInt expects an integer value", .{});
                    const value_reg = try ctx.genExpr(@intCast(args[0]), diag);
                    const reg = proc.num_registers;
                    proc.num_registers += 1;
                    const base = try formatNamedIntOption(ctx, args[1..], "base", 10, "formatInt", diag);
                    const min_digits = try formatNamedIntOption(ctx, args[1..], "minimum_digits", 0, "formatInt", diag);
                    try proc.instructions.append(program.allocator, .{ .opcode = .format_int_value, .dest = reg, .arg1 = value_reg, .arg2 = base, .arg3 = min_digits, .source_node = expr });
                    return reg;
                }
                if (std.mem.eql(u8, name, "formatFloat")) {
                    const args = ast.extraSlice(ast.data(expr).rhs);
                    if (args.len < 1) return diag.failAt(ast.tokens[ast.mainToken(expr)].start, "formatFloat expects a numeric value", .{});
                    const value_reg = try ctx.genExpr(@intCast(args[0]), diag);
                    const reg = proc.num_registers;
                    proc.num_registers += 1;
                    const width = try formatNamedIntOption(ctx, args[1..], "width", 0, "formatFloat", diag);
                    const trailing_width = try formatNamedIntOption(ctx, args[1..], "trailing_width", 6, "formatFloat", diag);
                    const zero_removal = try formatNamedEnumOption(ast, args[1..], "zero_removal", 1, diag);
                    const mode = try formatNamedEnumOption(ast, args[1..], "mode", 0, diag);
                    try proc.instructions.append(program.allocator, .{ .opcode = .format_float_value, .dest = reg, .arg1 = value_reg, .arg2 = width, .arg3 = trailing_width, .arg4 = zero_removal, .arg5 = mode, .source_node = expr });
                    return reg;
                }
                if (std.mem.eql(u8, name, "to_calendar")) {
                    const args = ast.extraSlice(ast.data(expr).rhs);
                    if (args.len < 1 or args.len > 2) return diag.failAt(ast.tokens[ast.mainToken(expr)].start, "to_calendar expects one or two arguments", .{});
                    const time_reg = try ctx.genExpr(@intCast(args[0]), diag);
                    const tz = if (args.len == 2) try timezoneLiteralValue(ast, @intCast(args[1]), diag) else 1;
                    const reg = proc.num_registers;
                    proc.num_registers += 1;
                    try proc.instructions.append(program.allocator, .{ .opcode = .to_calendar, .dest = reg, .arg1 = time_reg, .arg2 = tz, .source_node = expr });
                    return reg;
                }
                if (std.mem.eql(u8, name, "calendar_to_string")) {
                    const args = ast.extraSlice(ast.data(expr).rhs);
                    if (args.len != 1) return diag.failAt(ast.tokens[ast.mainToken(expr)].start, "calendar_to_string expects one argument", .{});
                    const calendar_reg = try ctx.genExpr(@intCast(args[0]), diag);
                    const reg = proc.num_registers;
                    proc.num_registers += 1;
                    try proc.instructions.append(program.allocator, .{ .opcode = .calendar_to_string, .dest = reg, .arg1 = calendar_reg, .source_node = expr });
                    return reg;
                }
                if (std.mem.eql(u8, name, "random_seed")) {
                    const args = ast.extraSlice(ast.data(expr).rhs);
                    const seed_reg = if (args.len == 0) return diag.failAt(ast.tokens[ast.mainToken(expr)].start, "random_seed expects one argument", .{}) else try ctx.genExpr(@intCast(args[0]), diag);
                    try proc.instructions.append(program.allocator, .{ .opcode = .random_seed, .arg1 = seed_reg, .source_node = expr });
                    return seed_reg;
                }
                if (std.mem.eql(u8, name, "random_get")) {
                    const args = ast.extraSlice(ast.data(expr).rhs);
                    if (args.len != 0) return diag.failAt(ast.tokens[ast.mainToken(expr)].start, "random_get expects no arguments", .{});
                    const reg = proc.num_registers;
                    proc.num_registers += 1;
                    try proc.instructions.append(program.allocator, .{ .opcode = .random_get, .dest = reg, .source_node = expr });
                    return reg;
                }
                if (std.mem.eql(u8, name, "random_get_zero_to_one")) {
                    const args = ast.extraSlice(ast.data(expr).rhs);
                    if (args.len != 0) return diag.failAt(ast.tokens[ast.mainToken(expr)].start, "random_get_zero_to_one expects no arguments", .{});
                    const reg = proc.num_registers;
                    proc.num_registers += 1;
                    try proc.instructions.append(program.allocator, .{ .opcode = .random_get_zero_to_one, .dest = reg, .source_node = expr });
                    return reg;
                }
                if (std.mem.eql(u8, name, "random_get_within_range")) {
                    const args = ast.extraSlice(ast.data(expr).rhs);
                    if (args.len != 2) return diag.failAt(ast.tokens[ast.mainToken(expr)].start, "random_get_within_range expects two arguments", .{});
                    const min_reg = try ctx.genExpr(@intCast(args[0]), diag);
                    const max_reg = try ctx.genExpr(@intCast(args[1]), diag);
                    const reg = proc.num_registers;
                    proc.num_registers += 1;
                    try proc.instructions.append(program.allocator, .{ .opcode = .random_get_within_range, .dest = reg, .arg1 = min_reg, .arg2 = max_reg, .source_node = expr });
                    return reg;
                }
                if (std.mem.eql(u8, name, "current_time_consensus")) {
                    const args = ast.extraSlice(ast.data(expr).rhs);
                    if (args.len != 0) return diag.failAt(ast.tokens[ast.mainToken(expr)].start, "current_time_consensus expects no arguments", .{});
                    const reg = proc.num_registers;
                    proc.num_registers += 1;
                    try proc.instructions.append(program.allocator, .{ .opcode = .current_time_consensus_low, .dest = reg, .source_node = expr });
                    return reg;
                }
                if (std.mem.eql(u8, name, "current_time_monotonic")) {
                    const args = ast.extraSlice(ast.data(expr).rhs);
                    if (args.len != 0) return diag.failAt(ast.tokens[ast.mainToken(expr)].start, "current_time_monotonic expects no arguments", .{});
                    const reg = proc.num_registers;
                    proc.num_registers += 1;
                    try proc.instructions.append(program.allocator, .{ .opcode = .current_time_monotonic_low, .dest = reg, .source_node = expr });
                    return reg;
                }
                if (std.mem.eql(u8, name, "get_time") or std.mem.eql(u8, name, "seconds_since_init")) {
                    const args = ast.extraSlice(ast.data(expr).rhs);
                    if (args.len != 0) return diag.failAt(ast.tokens[ast.mainToken(expr)].start, "{s} expects no arguments", .{name});
                    const reg = proc.num_registers;
                    proc.num_registers += 1;
                    const bits: u64 = @bitCast(@as(f64, 0.0));
                    try proc.instructions.append(program.allocator, .{ .opcode = .load_float, .dest = reg, .arg1 = @truncate(bits), .arg2 = @truncate(bits >> 32), .source_node = expr });
                    return reg;
                }
                if (std.mem.eql(u8, name, "sleep_milliseconds")) {
                    const args = ast.extraSlice(ast.data(expr).rhs);
                    if (args.len != 1) return diag.failAt(ast.tokens[ast.mainToken(expr)].start, "sleep_milliseconds expects one argument", .{});
                    _ = try ctx.genExpr(@intCast(args[0]), diag);
                    const reg = proc.num_registers;
                    proc.num_registers += 1;
                    try proc.instructions.append(program.allocator, .{ .opcode = .load_int, .dest = reg, .arg1 = 0, .source_node = expr });
                    return reg;
                }
                if (std.mem.eql(u8, name, "array_free")) {
                    const args = ast.extraSlice(ast.data(expr).rhs);
                    if (args.len != 1) return diag.failAt(ast.tokens[ast.mainToken(expr)].start, "array_free expects one argument", .{});
                    _ = try ctx.genExpr(@intCast(args[0]), diag);
                    const reg = proc.num_registers;
                    proc.num_registers += 1;
                    try proc.instructions.append(program.allocator, .{ .opcode = .load_int, .dest = reg, .arg1 = 0, .source_node = expr });
                    return reg;
                }
                if (std.mem.eql(u8, name, "abs")) {
                    const args = ast.extraSlice(ast.data(expr).rhs);
                    if (args.len != 1) return diag.failAt(ast.tokens[ast.mainToken(expr)].start, "abs expects one argument", .{});
                    return try ctx.genExpr(@intCast(args[0]), diag);
                }
                if (std.mem.eql(u8, name, "to_float64_seconds")) {
                    const args = ast.extraSlice(ast.data(expr).rhs);
                    if (args.len != 1) return diag.failAt(ast.tokens[ast.mainToken(expr)].start, "to_float64_seconds expects one argument", .{});
                    _ = try ctx.genExpr(@intCast(args[0]), diag);
                    const reg = proc.num_registers;
                    proc.num_registers += 1;
                    const bits: u64 = @bitCast(@as(f64, 0.0));
                    try proc.instructions.append(program.allocator, .{ .opcode = .load_float, .dest = reg, .arg1 = @truncate(bits), .arg2 = @truncate(bits >> 32), .source_node = expr });
                    return reg;
                }
                if (std.mem.eql(u8, name, "get_field")) {
                    const args = ast.extraSlice(ast.data(expr).rhs);
                    for (args) |arg| _ = try ctx.genExpr(@intCast(arg), diag);
                    return try ctx.genTypedPlaceholderValue(expr, diag);
                }
                if (std.mem.eql(u8, name, "type_to_string")) {
                    const args = ast.extraSlice(ast.data(expr).rhs);
                    if (args.len != 1) return diag.failAt(ast.tokens[ast.mainToken(expr)].start, "type_to_string expects one argument", .{});
                    _ = try ctx.genExpr(@intCast(args[0]), diag);
                    const reg = proc.num_registers;
                    proc.num_registers += 1;
                    const string_idx = try program.addString("");
                    try proc.instructions.append(program.allocator, .{ .opcode = .load_string, .dest = reg, .arg1 = string_idx, .source_node = expr });
                    return reg;
                }
                if (std.mem.eql(u8, name, "enum_range")) {
                    const args = ast.extraSlice(ast.data(expr).rhs);
                    if (args.len != 1) return diag.failAt(ast.tokens[ast.mainToken(expr)].start, "enum_range expects one argument", .{});
                    _ = try ctx.genExpr(@intCast(args[0]), diag);
                    return try ctx.genTypedPlaceholderValue(expr, diag);
                }
                if (std.mem.eql(u8, name, "enum_values_as_s64") or std.mem.eql(u8, name, "enum_names")) {
                    const args = ast.extraSlice(ast.data(expr).rhs);
                    if (args.len != 1) return diag.failAt(ast.tokens[ast.mainToken(expr)].start, "{s} expects one argument", .{name});
                    _ = try ctx.genExpr(@intCast(args[0]), diag);
                    return try ctx.genTypedPlaceholderValue(expr, diag);
                }
                if (std.mem.eql(u8, name, "formatStruct")) {
                    const args = ast.extraSlice(ast.data(expr).rhs);
                    if (args.len < 1) return diag.failAt(ast.tokens[ast.mainToken(expr)].start, "formatStruct expects a value", .{});
                    for (args) |arg_idx| {
                        const arg: NodeIndex = @intCast(arg_idx);
                        if (ast.tag(arg) == .assign_stmt) _ = try ctx.genExpr(ast.data(arg).rhs, diag) else _ = try ctx.genExpr(arg, diag);
                    }
                    const reg = proc.num_registers;
                    proc.num_registers += 1;
                    const string_idx = try program.addString("{...}");
                    try proc.instructions.append(program.allocator, .{ .opcode = .load_string, .dest = reg, .arg1 = string_idx, .source_node = expr });
                    return reg;
                }
                if (std.mem.eql(u8, name, "to_upper") or std.mem.eql(u8, name, "to_lower")) {
                    const args = ast.extraSlice(ast.data(expr).rhs);
                    if (args.len != 1) return diag.failAt(ast.tokens[ast.mainToken(expr)].start, "{s} expects one argument", .{name});
                    return try ctx.genExpr(@intCast(args[0]), diag);
                }
                if ((std.mem.eql(u8, name, "is_digit") or std.mem.eql(u8, name, "is_alpha") or std.mem.eql(u8, name, "is_alnum") or std.mem.eql(u8, name, "is_space") or std.mem.eql(u8, name, "is_any")) and !ctx.nameResolvesToUserProc(name)) {
                    const args = ast.extraSlice(ast.data(expr).rhs);
                    for (args) |arg| _ = try ctx.genExpr(@intCast(arg), diag);
                    const reg = proc.num_registers;
                    proc.num_registers += 1;
                    try proc.instructions.append(program.allocator, .{ .opcode = .load_bool, .dest = reg, .arg1 = 1, .source_node = expr });
                    return reg;
                }
                if (!std.mem.eql(u8, name, "print") and !std.mem.eql(u8, name, "log")) {
                    const args = ast.extraSlice(ast.data(expr).rhs);
                    var is_user_proc_call = false;
                    if (ctx.resolved.local_values.get(callee)) |decl| {
                        is_user_proc_call = decl != @import("Ast.zig").null_node and (ast.tag(decl) == .proc_decl or
                            (ast.tag(decl) == .var_decl and ast.data(decl).rhs != @import("Ast.zig").null_node and ast.tag(ast.data(decl).rhs) == .proc_decl) or
                            (ast.tag(decl) == .var_decl and ast.data(decl).lhs != @import("Ast.zig").null_node and ast.tag(ast.data(decl).lhs) == .proc_type));
                    }
                    if (!is_user_proc_call and ctx.resolved.overloads(name) != null) {
                        is_user_proc_call = true;
                    }
                    if (!is_user_proc_call) {
                        if (ctx.resolved.lookup(name)) |sym| switch (sym) {
                            .proc => is_user_proc_call = true,
                            else => {},
                        };
                    }
                    if (is_user_proc_call) {
                        if (ctx.resolveProcCallTarget(callee, name, args.len)) |target_proc| {
                            if (try ctx.tryInlineProcCall(target_proc, args, expr, diag)) |reg| return reg;
                        }
                        for (args) |arg_idx| {
                            const arg: NodeIndex = @intCast(arg_idx);
                            if (ast.tag(arg) == .assign_stmt) {
                                const rhs = ast.data(arg).rhs;
                                if (ast.tag(rhs) == .unary_expr and ast.tokens[ast.mainToken(rhs)].tag == .dot_dot)
                                    _ = try ctx.genExpr(ast.data(rhs).lhs, diag)
                                else
                                    _ = try ctx.genExpr(rhs, diag);
                            } else if (ast.tag(arg) == .unary_expr and ast.tokens[ast.mainToken(arg)].tag == .dot_dot)
                                _ = try ctx.genExpr(ast.data(arg).lhs, diag)
                            else
                                _ = try ctx.genExpr(arg, diag);
                        }
                        return try ctx.genTypedPlaceholderValue(expr, diag);
                    }
                    if (std.mem.eql(u8, name, "swap")) {
                        if (args.len != 2) return diag.failAt(ast.tokens[ast.mainToken(expr)].start, "swap expects exactly two arguments", .{});
                        const lhs_decl = try ctx.swapArgDecl(@intCast(args[0]), diag);
                        const rhs_decl = try ctx.swapArgDecl(@intCast(args[1]), diag);
                        const lhs_reg = ctx.decl_registers.get(lhs_decl) orelse return diag.failAt(ast.tokens[ast.mainToken(@intCast(args[0]))].start, "swap left argument has no generated storage", .{});
                        const rhs_reg = ctx.decl_registers.get(rhs_decl) orelse return diag.failAt(ast.tokens[ast.mainToken(@intCast(args[1]))].start, "swap right argument has no generated storage", .{});
                        try ctx.decl_registers.put(program.allocator, lhs_decl, rhs_reg);
                        try ctx.decl_registers.put(program.allocator, rhs_decl, lhs_reg);
                        return lhs_reg;
                    }
                    for (args) |arg_idx| {
                        const arg: NodeIndex = @intCast(arg_idx);
                        if (ast.tag(arg) == .assign_stmt) {
                            const rhs = ast.data(arg).rhs;
                            if (ast.tag(rhs) == .unary_expr and ast.tokens[ast.mainToken(rhs)].tag == .dot_dot)
                                _ = try ctx.genExpr(ast.data(rhs).lhs, diag)
                            else
                                _ = try ctx.genExpr(rhs, diag);
                        } else if (ast.tag(arg) == .unary_expr and ast.tokens[ast.mainToken(arg)].tag == .dot_dot) {
                            _ = try ctx.genExpr(ast.data(arg).lhs, diag);
                        } else {
                            _ = try ctx.genExpr(arg, diag);
                        }
                    }
                    return try ctx.genTypedPlaceholderValue(expr, diag);
                }
                const args = ast.extraSlice(ast.data(expr).rhs);
                if (args.len == 0) return diag.failAt(ast.tokens[ast.mainToken(expr)].start, "print expects at least one argument", .{});
                const first_reg = try ctx.genExpr(@intCast(args[0]), diag);
                if (args.len == 1) {
                    try proc.instructions.append(program.allocator, .{ .opcode = .call_extern, .dest = @intFromEnum(Bytecode.ExternSymbol.openjai_print), .arg1 = first_reg, .source_node = expr });
                    return first_reg;
                }
                if (ast.tag(@intCast(args[0])) != .string_literal) {
                    for (args[1..]) |arg| _ = try genCallArg(ctx, @intCast(arg), diag);
                    return first_reg;
                }
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

    fn genCompilerIntrinsicCall(ctx: *GenContext, name: []const u8, expr: NodeIndex, diag: Diagnostic) !?Bytecode.Register {
        const ast = ctx.ast;
        const args = ast.extraSlice(ast.data(expr).rhs);

        if (std.mem.eql(u8, name, "compiler_create_workspace")) {
            for (args) |arg| _ = try ctx.genExpr(@intCast(arg), diag);
            return try ctx.emitInt(expr, 3);
        }
        if (std.mem.eql(u8, name, "get_current_workspace")) {
            for (args) |arg| _ = try ctx.genExpr(@intCast(arg), diag);
            return try ctx.emitInt(expr, 2);
        }
        if (std.mem.eql(u8, name, "compiler_wait_for_message")) {
            for (args) |arg| _ = try ctx.genExpr(@intCast(arg), diag);
            return try ctx.emitInt(expr, 0);
        }
        if (std.mem.eql(u8, name, "run_command") or std.mem.eql(u8, name, "add_global_data")) {
            for (args) |arg| _ = try genCallArg(ctx, @intCast(arg), diag);
            return try ctx.emitInt(expr, 0);
        }
        if (std.mem.eql(u8, name, "parse_plugin_arguments")) {
            for (args) |arg| _ = try genCallArg(ctx, @intCast(arg), diag);
            return try ctx.emitBool(expr, true);
        }
        if (std.mem.eql(u8, name, "builder_to_string") or std.mem.eql(u8, name, "code_to_string")) {
            for (args) |arg| _ = try genCallArg(ctx, @intCast(arg), diag);
            return try ctx.emitString(expr, ctx.firstCodeDirectiveSource() orelse "");
        }
        if (std.mem.eql(u8, name, "get_build_options") or
            std.mem.eql(u8, name, "compiler_get_nodes") or
            std.mem.eql(u8, name, "compiler_get_code") or
            std.mem.eql(u8, name, "make_location"))
        {
            for (args) |arg| _ = try ctx.genExpr(@intCast(arg), diag);
            return try ctx.genTypedPlaceholderValue(expr, diag);
        }
        if (std.mem.eql(u8, name, "set_build_options") or
            std.mem.eql(u8, name, "set_build_options_dc") or
            std.mem.eql(u8, name, "set_optimization") or
            std.mem.eql(u8, name, "compiler_begin_intercept") or
            std.mem.eql(u8, name, "compiler_end_intercept") or
            std.mem.eql(u8, name, "compiler_set_workspace_status") or
            std.mem.eql(u8, name, "compiler_report") or
            std.mem.eql(u8, name, "add_build_file") or
            std.mem.eql(u8, name, "add_build_string") or
            std.mem.eql(u8, name, "print_expression"))
        {
            for (args) |arg| _ = try ctx.genExpr(@intCast(arg), diag);
            return try ctx.emitInt(expr, 0);
        }
        return null;
    }

    fn nameResolvesToUserProc(ctx: *GenContext, name: []const u8) bool {
        if (ctx.resolved.lookup(name)) |sym| switch (sym) {
            .proc => return true,
            else => {},
        };
        return ctx.resolved.overloads(name) != null;
    }

    fn genInlineResultSlot(ctx: *GenContext, source_node: NodeIndex, diag: Diagnostic) !Bytecode.Register {
        const result = try ctx.genTypedPlaceholderValue(source_node, diag);
        const should_stack_back = if (ctx.typed) |typed| blk: {
            const ty = typed.typeOf(source_node);
            break :blk !ty.isString() and !ty.isFloat() and !ty.isPointer();
        } else true;
        if (should_stack_back) {
            const addr_reg = ctx.proc.num_registers;
            ctx.proc.num_registers += 1;
            try ctx.proc.instructions.append(ctx.program.allocator, .{ .opcode = .addr_of_local, .dest = addr_reg, .arg1 = result, .source_node = source_node });
        }
        return result;
    }

    fn genInlineResultSlotForReturn(ctx: *GenContext, return_type: NodeIndex, source_node: NodeIndex, diag: Diagnostic) !Bytecode.Register {
        if (return_type != @import("Ast.zig").null_node) {
            const result = try ctx.genDefaultValue(return_type, source_node, diag);
            const return_text = std.mem.trim(u8, ctx.nodeSource(return_type), " \t\r\n");
            const stack_back = !std.mem.eql(u8, firstTypeWord(return_text), "string") and
                !std.mem.eql(u8, firstTypeWord(return_text), "float") and
                !std.mem.eql(u8, firstTypeWord(return_text), "float32") and
                !std.mem.eql(u8, firstTypeWord(return_text), "float64") and
                !std.mem.startsWith(u8, return_text, "*") and
                std.mem.indexOf(u8, return_text, "->") == null and
                !isDynamicArrayTypeText(return_text) and
                !(try typeTextIsStruct(ctx, return_text, diag));
            if (stack_back) {
                const addr_reg = ctx.proc.num_registers;
                ctx.proc.num_registers += 1;
                try ctx.proc.instructions.append(ctx.program.allocator, .{ .opcode = .addr_of_local, .dest = addr_reg, .arg1 = result, .source_node = source_node });
            }
            return result;
        }
        return try ctx.genInlineResultSlot(source_node, diag);
    }

    fn emitInt(ctx: *GenContext, source_node: NodeIndex, value: i64) !Bytecode.Register {
        const reg = ctx.proc.num_registers;
        ctx.proc.num_registers += 1;
        try ctx.proc.instructions.append(ctx.program.allocator, .{ .opcode = .load_int, .dest = reg, .arg1 = @intCast(value), .source_node = source_node });
        return reg;
    }

    fn emitBool(ctx: *GenContext, source_node: NodeIndex, value: bool) !Bytecode.Register {
        const reg = ctx.proc.num_registers;
        ctx.proc.num_registers += 1;
        try ctx.proc.instructions.append(ctx.program.allocator, .{ .opcode = .load_bool, .dest = reg, .arg1 = if (value) 1 else 0, .source_node = source_node });
        return reg;
    }

    fn emitString(ctx: *GenContext, source_node: NodeIndex, value: []const u8) !Bytecode.Register {
        const string_idx = try ctx.program.addString(value);
        const reg = ctx.proc.num_registers;
        ctx.proc.num_registers += 1;
        try ctx.proc.instructions.append(ctx.program.allocator, .{ .opcode = .load_string, .dest = reg, .arg1 = string_idx, .source_node = source_node });
        return reg;
    }

    fn emitStringSliceCall(ctx: *GenContext, args: []const u32, source_node: NodeIndex, diag: Diagnostic) !Bytecode.Register {
        if (args.len != 3) return diag.failAt(ctx.ast.tokens[ctx.ast.mainToken(source_node)].start, "string_slice expects source, start, and end", .{});
        const source_reg = try ctx.genExpr(@intCast(args[0]), diag);
        const start_reg = try ctx.genExpr(@intCast(args[1]), diag);
        const end_reg = try ctx.genExpr(@intCast(args[2]), diag);
        const len_reg = ctx.proc.num_registers;
        ctx.proc.num_registers += 1;
        try ctx.proc.instructions.append(ctx.program.allocator, .{ .opcode = .sub_int, .dest = len_reg, .arg1 = end_reg, .arg2 = start_reg, .source_node = source_node });
        const reg = ctx.proc.num_registers;
        ctx.proc.num_registers += 1;
        try ctx.proc.instructions.append(ctx.program.allocator, .{ .opcode = .string_slice, .dest = reg, .arg1 = source_reg, .arg2 = start_reg, .arg3 = len_reg, .source_node = source_node });
        return reg;
    }

    fn firstCodeDirectiveSource(ctx: *GenContext) ?[]const u8 {
        for (ctx.ast.node_tags.items, 0..) |tag, i| {
            if (tag != .meta_expr) continue;
            const node: NodeIndex = @intCast(i);
            const tok = ctx.ast.mainToken(node);
            if (ctx.ast.tokens[tok].tag != .directive_code) continue;
            const payload = ctx.ast.data(node).lhs;
            if (payload == @import("Ast.zig").null_node) return ctx.codeDirectiveTokenSource(tok);
            return ctx.nodeSource(payload);
        }
        return null;
    }

    fn codeDirectiveTokenSource(ctx: *GenContext, tok: @import("Token.zig").Token.Index) []const u8 {
        if (tok + 1 >= ctx.ast.tokens.len) return "";
        const start = ctx.ast.tokens[tok + 1].start;
        var scan = tok + 1;
        var end = start;
        while (scan < ctx.ast.tokens.len) : (scan += 1) {
            if (ctx.ast.tokens[scan].tag == .semicolon or ctx.ast.tokens[scan].tag == .eof) break;
            end = ctx.ast.tokens[scan].end;
        }
        if (end < start) return "";
        return std.mem.trim(u8, ctx.ast.source[start..end], " \t\r\n;");
    }

    fn nodeSource(ctx: *GenContext, node: NodeIndex) []const u8 {
        const start = ctx.ast.tokens[ctx.ast.mainToken(node)].start;
        var end = ctx.ast.tokens[ctx.ast.mainToken(node)].end;
        collectNodeEnd(ctx.ast, node, &end);
        return std.mem.trim(u8, ctx.ast.source[start..@min(end, ctx.ast.source.len)], " \t\r\n;");
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
        if (type_expr == @import("Ast.zig").null_node) return diag.failAt(ast.tokens[ast.mainToken(source_node)].start, "explicit uninitialization requires an explicit type", .{});
        if (ast.tag(type_expr) != .type_expr) return try ctx.genTypedPlaceholderValue(source_node, diag);
        const type_name = ast.tokenSlice(ast.mainToken(type_expr));
        const reg = ctx.proc.num_registers;
        ctx.proc.num_registers += 1;
        const type_kind: u32 = if (std.mem.eql(u8, type_name, "string")) 14 else if (std.mem.eql(u8, type_name, "bool")) 1 else if (std.mem.eql(u8, type_name, "float") or std.mem.eql(u8, type_name, "float32") or std.mem.eql(u8, type_name, "float64")) 12 else if (std.mem.eql(u8, type_name, "void")) 0 else 5;
        try ctx.proc.instructions.append(ctx.program.allocator, .{ .opcode = .load_undef, .dest = reg, .arg1 = type_kind, .source_node = source_node });
        return reg;
    }

    fn genTypedPlaceholderValue(ctx: *GenContext, source_node: NodeIndex, diag: Diagnostic) !Bytecode.Register {
        if (ctx.typed) |typed| return ctx.genPlaceholderForType(typed.typeOf(source_node), source_node, diag);
        const reg = ctx.proc.num_registers;
        ctx.proc.num_registers += 1;
        try ctx.proc.instructions.append(ctx.program.allocator, .{ .opcode = .load_int, .dest = reg, .arg1 = 0, .source_node = source_node });
        return reg;
    }

    fn genPlaceholderForType(ctx: *GenContext, ty: Type, source_node: NodeIndex, diag: Diagnostic) !Bytecode.Register {
        const reg = ctx.proc.num_registers;
        ctx.proc.num_registers += 1;
        const type_id: u32 = if (typeIdFromType(ty)) |id| id else if (ty.isPointer()) 10 else 5;
        switch (type_id) {
            1 => try ctx.proc.instructions.append(ctx.program.allocator, .{ .opcode = .load_bool, .dest = reg, .arg1 = 0, .source_node = source_node }),
            10 => try ctx.proc.instructions.append(ctx.program.allocator, .{ .opcode = .load_null_ptr, .dest = reg, .source_node = source_node }),
            12, 13 => {
                const bits: u64 = @bitCast(@as(f64, 0.0));
                try ctx.proc.instructions.append(ctx.program.allocator, .{ .opcode = .load_float, .dest = reg, .arg1 = @truncate(bits), .arg2 = @truncate(bits >> 32), .source_node = source_node });
            },
            14 => {
                const string_idx = try ctx.program.addString("");
                try ctx.proc.instructions.append(ctx.program.allocator, .{ .opcode = .load_string, .dest = reg, .arg1 = string_idx, .source_node = source_node });
            },
            15 => try ctx.proc.instructions.append(ctx.program.allocator, .{ .opcode = .load_type, .dest = reg, .arg1 = 0, .source_node = source_node }),
            else => try ctx.proc.instructions.append(ctx.program.allocator, .{ .opcode = .load_int, .dest = reg, .arg1 = 0, .source_node = source_node }),
        }
        _ = diag;
        return reg;
    }

    fn phase2TypeId(ctx: *GenContext, operand: NodeIndex, diag: Diagnostic) !u32 {
        if (ctx.typed) |typed| {
            if (ctx.typeIdFromTypedNode(typed, operand)) |type_id| return type_id;
            if (ctx.ast.tag(operand) == .identifier) {
                const decl = ctx.resolved.local_values.get(operand) orelse {
                    const name = ctx.ast.tokenSlice(ctx.ast.mainToken(operand));
                    if (isBuiltinTypeName(name)) return typeIdFromTypeName(ctx.ast, operand, diag);
                    if (ctx.resolved.lookup(name)) |sym| switch (sym) {
                        .proc => |proc_node| return procTypeId(ctx.ast, proc_node, diag),
                        else => {},
                    };
                    return diag.failAt(ctx.ast.tokens[ctx.ast.mainToken(operand)].start, "type_of identifier is unresolved", .{});
                };
                if (decl == @import("Ast.zig").null_node) return typeIdFromTypeName(ctx.ast, operand, diag);
                if (ctx.ast.tag(decl) == .proc_decl) return procTypeId(ctx.ast, decl, diag);
                if (ctx.typeIdFromTypedNode(typed, decl)) |type_id| return type_id;
                switch (ctx.ast.tag(decl)) {
                    .var_decl => {
                        if (ctx.ast.data(decl).lhs != @import("Ast.zig").null_node) return typeIdFromTypeExpr(ctx.ast, ctx.ast.data(decl).lhs, diag);
                        if (ctx.ast.data(decl).rhs != @import("Ast.zig").null_node) {
                            if (ctx.typeIdFromTypedNode(typed, ctx.ast.data(decl).rhs)) |type_id| return type_id;
                        }
                    },
                    .const_decl => {
                        if (ctx.ast.data(decl).rhs != 0) return typeIdFromToken(ctx.ast, ctx.ast.data(decl).rhs, diag);
                        if (ctx.typeIdFromTypedNode(typed, ctx.ast.data(decl).lhs)) |type_id| return type_id;
                    },
                    else => {},
                }
                return diag.failAt(ctx.ast.tokens[ctx.ast.mainToken(operand)].start, "type_of identifier has no typed declaration information", .{});
            }
            return diag.failAt(ctx.ast.tokens[ctx.ast.mainToken(operand)].start, "type_of expression has no semantic type information", .{});
        }
        return phase2TypeIdNoResolve(ctx.ast, operand, diag);
    }

    fn typeIdFromTypedNode(ctx: *GenContext, typed: *const Typed, node: NodeIndex) ?u32 {
        _ = ctx;
        if (node == @import("Ast.zig").null_node or node >= typed.node_types.len) return null;
        return typeIdFromType(typed.typeOf(node));
    }

    fn genDefaultValue(ctx: *GenContext, type_expr: NodeIndex, source_node: NodeIndex, diag: Diagnostic) !Bytecode.Register {
        const ast = ctx.ast;
        if (type_expr == @import("Ast.zig").null_node) return ctx.genTypedPlaceholderValue(source_node, diag);
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
        if (ast.tag(type_expr) == .array_type) {
            const type_source = ctx.nodeSource(type_expr);
            const reg = ctx.proc.num_registers;
            ctx.proc.num_registers += 1;
            if (isDynamicArrayTypeText(type_source))
                try ctx.proc.instructions.append(ctx.program.allocator, .{ .opcode = .alloc_local_bytes, .dest = reg, .arg1 = 8, .source_node = source_node })
            else
                try ctx.proc.instructions.append(ctx.program.allocator, .{ .opcode = .load_int, .dest = reg, .arg1 = 0, .source_node = source_node });
            return reg;
        }
        if (ast.tag(type_expr) == .struct_type or ast.tag(type_expr) == .union_type) {
            const size = try containerSizeFromSource(ctx, type_expr, diag);
            const reg = ctx.proc.num_registers;
            ctx.proc.num_registers += 1;
            try ctx.proc.instructions.append(ctx.program.allocator, .{ .opcode = .alloc_heap, .dest = reg, .arg1 = @intCast(@max(size, 1)), .source_node = source_node });
            return reg;
        }
        if (ast.tag(type_expr) == .enum_type) {
            const reg = ctx.proc.num_registers;
            ctx.proc.num_registers += 1;
            try ctx.proc.instructions.append(ctx.program.allocator, .{ .opcode = .load_int, .dest = reg, .arg1 = 0, .source_node = source_node });
            return reg;
        }
        if (ast.tag(type_expr) != .type_expr and ast.tag(type_expr) != .identifier) return ctx.genTypedPlaceholderValue(source_node, diag);
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
        } else if (try structSizeByName(ctx, type_name, diag)) |size| {
            try ctx.proc.instructions.append(ctx.program.allocator, .{ .opcode = .alloc_heap, .dest = reg, .arg1 = @intCast(@max(size, 1)), .source_node = source_node });
        } else {
            try ctx.proc.instructions.append(ctx.program.allocator, .{ .opcode = .load_int, .dest = reg, .arg1 = 0, .source_node = source_node });
        }
        return reg;
    }
};

fn collectNodeEnd(ast: *const Ast, node: NodeIndex, end: *u32) void {
    if (node == @import("Ast.zig").null_node or node >= ast.node_tags.items.len) return;
    const tok = ast.mainToken(node);
    if (tok < ast.tokens.len) end.* = @max(end.*, ast.tokens[tok].end);
    const data = ast.data(node);
    switch (ast.tag(node)) {
        .root, .block, .stmt_list, .aggregate_literal => {
            if (data.lhs < ast.extra_data.items.len) {
                for (ast.extraSlice(data.lhs)) |child| collectNodeEnd(ast, @intCast(child), end);
            }
        },
        .typed_aggregate_literal, .typed_array_literal => {
            if (data.lhs < ast.extra_data.items.len) {
                const payload = ast.extraSlice(data.lhs);
                if (payload.len >= 2) {
                    collectNodeEnd(ast, @intCast(payload[0]), end);
                    for (ast.extraSlice(payload[1])) |child| collectNodeEnd(ast, @intCast(child), end);
                }
            }
        },
        .call_expr => {
            collectNodeEnd(ast, data.lhs, end);
            if (data.rhs < ast.extra_data.items.len) {
                for (ast.extraSlice(data.rhs)) |arg| collectNodeEnd(ast, @intCast(arg), end);
            }
        },
        .if_stmt => {
            collectNodeEnd(ast, data.lhs, end);
            if (data.rhs < ast.extra_data.items.len) {
                for (ast.extraSlice(data.rhs)) |child| collectNodeEnd(ast, @intCast(child), end);
            }
        },
        .for_stmt => {
            if (data.lhs < ast.extra_data.items.len) {
                for (ast.extraSlice(data.lhs)) |operand| {
                    const clean = operand & 0x7fffffff;
                    if (clean < ast.node_tags.items.len) collectNodeEnd(ast, @intCast(clean), end);
                }
            }
            collectNodeEnd(ast, data.rhs, end);
        },
        .field_access => {
            collectNodeEnd(ast, data.lhs, end);
            if (data.rhs < ast.tokens.len) end.* = @max(end.*, ast.tokens[data.rhs].end);
        },
        .proc_type => {
            if (data.lhs < ast.extra_data.items.len) {
                for (ast.extraSlice(data.lhs)) |param_ty| collectNodeEnd(ast, @intCast(param_ty), end);
            }
            collectNodeEnd(ast, data.rhs, end);
        },
        .var_decl, .assign_stmt, .binary_expr, .index_expr, .array_type, .meta_expr, .meta_stmt => {
            collectNodeEnd(ast, data.lhs, end);
            collectNodeEnd(ast, data.rhs, end);
        },
        .const_decl, .expr_stmt, .return_stmt, .pointer_type, .type_of_expr, .size_of_expr, .run_expr, .is_constant_expr, .unary_expr, .defer_stmt => {
            collectNodeEnd(ast, data.lhs, end);
        },
        .proc_decl => {
            collectNodeEnd(ast, data.lhs, end);
            if (data.rhs < ast.extra_data.items.len) {
                for (ast.extraSlice(data.rhs)) |sig_part| {
                    if (sig_part < ast.node_tags.items.len) collectNodeEnd(ast, @intCast(sig_part), end);
                }
            }
        },
        else => {},
    }
}

fn intLiteralArg(value: i64) u32 {
    const bits: u64 = @bitCast(value);
    return @truncate(bits);
}

fn formatNamedIntOption(ctx: *GenContext, args: []const u32, name: []const u8, default_value: u32, owner: []const u8, diag: Diagnostic) !u32 {
    const ast = ctx.ast;
    for (args, 0..) |arg_idx, i| {
        const arg: NodeIndex = @intCast(arg_idx);
        if (ast.tag(arg) != .assign_stmt) {
            if (std.mem.eql(u8, name, "base") and i == 0) {
                const value = evalIntegerConstExpr(ctx, arg, diag) catch return default_value;
                if (value < 0 or value > std.math.maxInt(u32)) return default_value;
                return @intCast(value);
            }
            continue;
        }
        const lhs = ast.data(arg).lhs;
        if (ast.tag(lhs) != .identifier) return diag.failAt(ast.tokens[ast.mainToken(arg)].start, "{s} option name must be an identifier", .{owner});
        if (!std.mem.eql(u8, ast.tokenSlice(ast.mainToken(lhs)), name)) continue;
        const value = try evalIntegerConstExpr(ctx, ast.data(arg).rhs, diag);
        if (value < 0 or value > std.math.maxInt(u32)) return diag.failAt(ast.tokens[ast.mainToken(ast.data(arg).rhs)].start, "{s} option '{s}' is out of range", .{ owner, name });
        return @intCast(value);
    }
    return default_value;
}

fn evalIntegerConstExpr(ctx: *GenContext, node: NodeIndex, diag: Diagnostic) !i64 {
    const ast = ctx.ast;
    return switch (ast.tag(node)) {
        .integer_literal => try parseIntLiteral(ast, node, diag),
        .identifier => blk: {
            if (ctx.resolved.local_values.get(node)) |decl| {
                if (ast.tag(decl) == .const_decl) break :blk try evalIntegerConstExpr(ctx, ast.data(decl).lhs, diag);
                if (ast.tag(decl) == .var_decl and ast.data(decl).rhs != @import("Ast.zig").null_node) break :blk try evalIntegerConstExpr(ctx, ast.data(decl).rhs, diag);
                break :blk try evalIntegerConstExpr(ctx, decl, diag);
            }
            if (ctx.typed) |typed| {
                var it = typed.comptime_ints.iterator();
                while (it.next()) |entry| if (entry.key_ptr.* == node) break :blk entry.value_ptr.*;
            }
            return diag.failAt(ast.tokens[ast.mainToken(node)].start, "integer constant option identifier is unresolved", .{});
        },
        .unary_expr => blk: {
            if (ast.tokens[ast.mainToken(node)].tag != .minus) return diag.failAt(ast.tokens[ast.mainToken(node)].start, "unsupported unary operator in integer constant option", .{});
            break :blk -(try evalIntegerConstExpr(ctx, ast.data(node).lhs, diag));
        },
        .binary_expr => blk: {
            const lhs = try evalIntegerConstExpr(ctx, ast.data(node).lhs, diag);
            const rhs = try evalIntegerConstExpr(ctx, ast.data(node).rhs, diag);
            break :blk switch (ast.tokens[ast.mainToken(node)].tag) {
                .plus => lhs + rhs,
                .minus => lhs - rhs,
                .star => lhs * rhs,
                .slash => @divTrunc(lhs, rhs),
                else => return diag.failAt(ast.tokens[ast.mainToken(node)].start, "unsupported binary operator in integer constant option", .{}),
            };
        },
        else => return diag.failAt(ast.tokens[ast.mainToken(node)].start, "integer constant option requires a compile-time integer expression", .{}),
    };
}

fn calendarFieldId(ast: *const Ast, field_token: u32, diag: Diagnostic) !u32 {
    const name = ast.tokenSlice(field_token);
    if (std.mem.eql(u8, name, "year")) return 0;
    if (std.mem.eql(u8, name, "month_starting_at_0")) return 1;
    if (std.mem.eql(u8, name, "day_of_month_starting_at_0")) return 2;
    if (std.mem.eql(u8, name, "day_of_week_starting_at_0")) return 3;
    if (std.mem.eql(u8, name, "hour")) return 4;
    if (std.mem.eql(u8, name, "minute")) return 5;
    if (std.mem.eql(u8, name, "second")) return 6;
    if (std.mem.eql(u8, name, "millisecond")) return 7;
    if (std.mem.eql(u8, name, "time_zone")) return 8;
    return diag.failAt(ast.tokens[field_token].start, "unsupported Calendar field '{s}'", .{name});
}

fn timezoneLiteralValue(ast: *const Ast, node: NodeIndex, diag: Diagnostic) !u32 {
    if (ast.tag(node) != .field_access or ast.data(node).lhs != @import("Ast.zig").null_node) return diag.failAt(ast.tokens[ast.mainToken(node)].start, "timezone argument must be .UTC or .LOCAL", .{});
    const name = ast.tokenSlice(ast.data(node).rhs);
    if (std.mem.eql(u8, name, "UTC")) return 0;
    if (std.mem.eql(u8, name, "LOCAL")) return 1;
    return diag.failAt(ast.tokens[ast.data(node).rhs].start, "unsupported timezone literal '.{s}'", .{name});
}

fn formatNamedEnumOption(ast: *const Ast, args: []const u32, name: []const u8, default_value: u32, diag: Diagnostic) !u32 {
    for (args) |arg_idx| {
        const arg: NodeIndex = @intCast(arg_idx);
        if (ast.tag(arg) != .assign_stmt) return diag.failAt(ast.tokens[ast.mainToken(arg)].start, "formatFloat options must be named arguments", .{});
        const lhs = ast.data(arg).lhs;
        if (ast.tag(lhs) != .identifier) return diag.failAt(ast.tokens[ast.mainToken(arg)].start, "formatFloat option name must be an identifier", .{});
        if (!std.mem.eql(u8, ast.tokenSlice(ast.mainToken(lhs)), name)) continue;
        const rhs = ast.data(arg).rhs;
        if (ast.tag(rhs) != .field_access or ast.data(rhs).lhs != @import("Ast.zig").null_node) return diag.failAt(ast.tokens[ast.mainToken(rhs)].start, "formatFloat option '{s}' currently requires an enum literal", .{name});
        const value_name = ast.tokenSlice(ast.data(rhs).rhs);
        if (std.mem.eql(u8, name, "zero_removal")) {
            if (std.mem.eql(u8, value_name, "NO")) return 0;
            if (std.mem.eql(u8, value_name, "YES")) return 1;
        } else if (std.mem.eql(u8, name, "mode")) {
            if (std.mem.eql(u8, value_name, "DECIMAL")) return 0;
            if (std.mem.eql(u8, value_name, "SCIENTIFIC")) return 1;
        }
        return diag.failAt(ast.tokens[ast.data(rhs).rhs].start, "unsupported formatFloat option '{s}' value '{s}'", .{ name, value_name });
    }
    return default_value;
}

fn genCallArg(ctx: *GenContext, arg: NodeIndex, diag: Diagnostic) !Bytecode.Register {
    if (ctx.ast.tag(arg) == .assign_stmt) return ctx.genExpr(ctx.ast.data(arg).rhs, diag);
    if (ctx.ast.tag(arg) == .unary_expr and ctx.ast.tokens[ctx.ast.mainToken(arg)].tag == .dot_dot) return ctx.genExpr(ctx.ast.data(arg).lhs, diag);
    return ctx.genExpr(arg, diag);
}

fn fieldValueKey(base: Bytecode.Register, name: []const u8) u64 {
    var h: u64 = 14695981039346656037;
    for (name) |c| {
        h ^= c;
        h *%= 1099511628211;
    }
    return (@as(u64, base) << 32) ^ (h & 0xffff_ffff);
}

const FieldInfo = struct {
    offset: u64,
    type_text: []const u8,
};

fn genAddressOfLvalue(ctx: *GenContext, expr: NodeIndex, diag: Diagnostic) !Bytecode.Register {
    const ast = ctx.ast;
    const proc = ctx.proc;
    const program = ctx.program;
    switch (ast.tag(expr)) {
        .identifier => {
            const value = try ctx.genExpr(expr, diag);
            if (typeTextForExpr(ctx, expr, diag)) |ty| {
                const clean = stripPointerText(ty);
                if (isDynamicArrayTypeText(clean) or (try typeTextIsStruct(ctx, clean, diag))) return value;
            }
            const addr = proc.num_registers;
            proc.num_registers += 1;
            try proc.instructions.append(program.allocator, .{ .opcode = .addr_of_local, .dest = addr, .arg1 = value, .source_node = expr });
            return addr;
        },
        .field_access => {
            const base = ast.data(expr).lhs;
            const base_reg = try ctx.genExpr(base, diag);
            const base_ty = typeTextForExpr(ctx, base, diag) orelse return ctx.genTypedPlaceholderValue(expr, diag);
            const field_name = ast.tokenSlice(ast.data(expr).rhs);
            const info = try fieldInfoFromTypeText(ctx, base_ty, field_name, diag) orelse return ctx.genTypedPlaceholderValue(expr, diag);
            if (info.offset == 0) return base_reg;
            const addr = proc.num_registers;
            proc.num_registers += 1;
            try proc.instructions.append(program.allocator, .{ .opcode = .ptr_offset, .dest = addr, .arg1 = base_reg, .arg2 = @intCast(info.offset), .source_node = expr });
            return addr;
        },
        .index_expr => {
            const base = ast.data(expr).lhs;
            const base_ty = typeTextForExpr(ctx, base, diag) orelse return ctx.genTypedPlaceholderValue(expr, diag);
            const elem_ty = dynamicArrayElementText(base_ty) orelse return ctx.genTypedPlaceholderValue(expr, diag);
            const base_reg = try ctx.genExpr(base, diag);
            const index_reg = try ctx.genExpr(ast.data(expr).rhs, diag);
            const elem_size = try typeTextSize(ctx, elem_ty, diag);
            const is_struct = try typeTextIsStruct(ctx, elem_ty, diag);
            const addr = proc.num_registers;
            proc.num_registers += 1;
            try proc.instructions.append(program.allocator, .{ .opcode = .array_index, .dest = addr, .arg1 = base_reg, .arg2 = index_reg, .arg3 = @intCast(elem_size), .arg4 = if (is_struct) 1 else 0, .source_node = expr });
            return addr;
        },
        else => return ctx.genTypedPlaceholderValue(expr, diag),
    }
}

fn typeTextForExpr(ctx: *GenContext, expr: NodeIndex, diag: Diagnostic) ?[]const u8 {
    const ast = ctx.ast;
    if (expr == @import("Ast.zig").null_node or expr >= ast.node_tags.items.len) return null;
    switch (ast.tag(expr)) {
        .identifier => {
            const decl = ctx.resolved.local_values.get(expr) orelse return null;
            if (decl == @import("Ast.zig").null_node) return null;
            if (ast.tag(decl) == .var_decl or ast.tag(decl) == .const_decl) {
                const type_node = if (ast.tag(decl) == .var_decl) ast.data(decl).lhs else ast.data(decl).rhs;
                if (type_node != @import("Ast.zig").null_node) return ctx.nodeSource(type_node);
                if (ast.tag(decl) == .var_decl and ast.data(decl).rhs != @import("Ast.zig").null_node) {
                    return typeTextForExpr(ctx, ast.data(decl).rhs, diag);
                }
            }
            return null;
        },
        .field_access => {
            const base_ty = typeTextForExpr(ctx, ast.data(expr).lhs, diag) orelse return null;
            const field_name = ast.tokenSlice(ast.data(expr).rhs);
            if (std.mem.eql(u8, firstTypeWord(base_ty), "string")) {
                if (std.mem.eql(u8, field_name, "count")) return "int";
                if (std.mem.eql(u8, field_name, "data")) return "*u8";
            }
            if (dynamicArrayElementText(base_ty) != null) {
                if (std.mem.eql(u8, field_name, "count")) return "int";
                if (std.mem.eql(u8, field_name, "data")) return "*u8";
            }
            const info = fieldInfoFromTypeText(ctx, base_ty, field_name, diag) catch return null;
            return if (info) |actual| actual.type_text else null;
        },
        .index_expr => {
            const base_ty = typeTextForExpr(ctx, ast.data(expr).lhs, diag) orelse return null;
            return dynamicArrayElementText(base_ty);
        },
        .unary_expr => {
            const op = ast.tokens[ast.mainToken(expr)].tag;
            if (op == .star) {
                const operand_ty = typeTextForExpr(ctx, ast.data(expr).lhs, diag) orelse return null;
                return std.mem.trim(u8, stripPointerText(operand_ty), " \t\r\n");
            }
            return typeTextForExpr(ctx, ast.data(expr).lhs, diag);
        },
        .call_expr => {
            const callee = ast.data(expr).lhs;
            const args = if (ast.data(expr).rhs < ast.extra_data.items.len) ast.extraSlice(ast.data(expr).rhs) else &[_]u32{};
            if (ast.tag(callee) == .identifier) {
                const name = ast.tokenSlice(ast.mainToken(callee));
                if (std.mem.eql(u8, name, "compiler_arg") or
                    std.mem.eql(u8, name, "compiler_read_file") or
                    std.mem.eql(u8, name, "string_slice") or
                    std.mem.eql(u8, name, "formatInt") or
                    std.mem.eql(u8, name, "formatFloat") or
                    std.mem.eql(u8, name, "calendar_to_string") or
                    std.mem.eql(u8, name, "builder_to_string") or
                    std.mem.eql(u8, name, "code_to_string") or
                    std.mem.eql(u8, name, "type_to_string"))
                {
                    return "string";
                }
                if (std.mem.eql(u8, name, "compiler_arg_count") or
                    std.mem.eql(u8, name, "array_count") or
                    std.mem.eql(u8, name, "write_string") or
                    std.mem.eql(u8, name, "write_strings") or
                    std.mem.eql(u8, name, "write_number") or
                    std.mem.eql(u8, name, "write_nonnegative_number"))
                {
                    return "int";
                }
                if (std.mem.eql(u8, name, "thread_is_done") or
                    std.mem.eql(u8, name, "is_digit") or
                    std.mem.eql(u8, name, "is_alpha") or
                    std.mem.eql(u8, name, "is_alnum") or
                    std.mem.eql(u8, name, "is_space") or
                    std.mem.eql(u8, name, "is_any"))
                {
                    return "bool";
                }
            }
            const target = if (ast.tag(callee) == .proc_decl)
                callee
            else if (ast.tag(callee) == .identifier)
                ctx.resolveProcCallTarget(callee, ast.tokenSlice(ast.mainToken(callee)), args.len) orelse return null
            else
                return null;
            const sig = procSignature(ast, target) orelse return null;
            if (sig.return_type == @import("Ast.zig").null_node) return null;
            return ctx.nodeSource(sig.return_type);
        },
        else => return null,
    }
}

fn stripPointerText(raw: []const u8) []const u8 {
    var ty = std.mem.trim(u8, raw, " \t\r\n");
    while (std.mem.startsWith(u8, ty, "*")) ty = std.mem.trim(u8, ty[1..], " \t\r\n");
    return ty;
}

fn isDynamicArrayTypeText(raw: []const u8) bool {
    const ty = std.mem.trim(u8, raw, " \t\r\n");
    return std.mem.startsWith(u8, ty, "[..]");
}

fn dynamicArrayElementText(raw: []const u8) ?[]const u8 {
    const ty = std.mem.trim(u8, stripPointerText(raw), " \t\r\n");
    if (!std.mem.startsWith(u8, ty, "[..]")) return null;
    return std.mem.trim(u8, ty[4..], " \t\r\n");
}

fn typeTextIsScalarComparable(raw: []const u8) bool {
    const name = firstTypeWord(std.mem.trim(u8, stripPointerText(raw), " \t\r\n"));
    return std.mem.eql(u8, name, "int") or
        std.mem.eql(u8, name, "s64") or
        std.mem.eql(u8, name, "u64") or
        std.mem.eql(u8, name, "s32") or
        std.mem.eql(u8, name, "u32") or
        std.mem.eql(u8, name, "s16") or
        std.mem.eql(u8, name, "u16") or
        std.mem.eql(u8, name, "s8") or
        std.mem.eql(u8, name, "u8") or
        std.mem.eql(u8, name, "bool") or
        std.mem.eql(u8, name, "float") or
        std.mem.eql(u8, name, "float32") or
        std.mem.eql(u8, name, "float64");
}

fn fieldInfoFromTypeText(ctx: *GenContext, raw_type: []const u8, field_name: []const u8, diag: Diagnostic) !?FieldInfo {
    const type_name = firstTypeWord(stripPointerText(raw_type));
    if (type_name.len == 0) return null;
    const type_node = try structTypeNodeByName(ctx, type_name) orelse return null;
    return try containerFieldInfoFromSource(ctx, type_node, field_name, diag);
}

fn typeTextIsStruct(ctx: *GenContext, raw_type: []const u8, diag: Diagnostic) !bool {
    _ = diag;
    const type_name = firstTypeWord(stripPointerText(raw_type));
    if (type_name.len == 0) return false;
    return (try structTypeNodeByName(ctx, type_name)) != null;
}

fn structTypeNodeByName(ctx: *GenContext, name: []const u8) !?NodeIndex {
    const ast = ctx.ast;
    const sym = ctx.resolved.lookup(name) orelse return null;
    const decl = switch (sym) {
        .const_value => |node| node,
        else => return null,
    };
    if (decl == @import("Ast.zig").null_node or decl >= ast.node_tags.items.len) return null;
    const type_node = if (ast.tag(decl) == .const_decl) ast.data(decl).lhs else decl;
    if (ast.tag(type_node) == .identifier or ast.tag(type_node) == .type_expr) return try structTypeNodeByName(ctx, ast.tokenSlice(ast.mainToken(type_node)));
    if (ast.tag(type_node) != .struct_type and ast.tag(type_node) != .union_type) return null;
    return type_node;
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
    return std.mem.eql(u8, name, "void") or std.mem.eql(u8, name, "bool") or std.mem.eql(u8, name, "string") or std.mem.eql(u8, name, "int") or std.mem.eql(u8, name, "s64") or std.mem.eql(u8, name, "float") or std.mem.eql(u8, name, "float32") or std.mem.eql(u8, name, "float64") or std.mem.eql(u8, name, "s32") or std.mem.eql(u8, name, "u8") or std.mem.eql(u8, name, "u16") or std.mem.eql(u8, name, "u32") or std.mem.eql(u8, name, "u64") or std.mem.eql(u8, name, "Vector2") or std.mem.eql(u8, name, "Vector3") or std.mem.eql(u8, name, "Type") or std.mem.eql(u8, name, "Any");
}

fn typeInfoTagValue(name: []const u8) ?u32 {
    if (std.mem.eql(u8, name, "INTEGER")) return 1;
    if (std.mem.eql(u8, name, "FLOAT")) return 2;
    if (std.mem.eql(u8, name, "BOOL")) return 3;
    if (std.mem.eql(u8, name, "POINTER")) return 4;
    if (std.mem.eql(u8, name, "ARRAY")) return 5;
    if (std.mem.eql(u8, name, "STRUCT")) return 6;
    if (std.mem.eql(u8, name, "ENUM")) return 7;
    if (std.mem.eql(u8, name, "PROCEDURE")) return 8;
    if (std.mem.eql(u8, name, "STRING")) return 9;
    return null;
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
        .identifier => if (resolved.local_values.get(operand)) |decl|
            if (decl == @import("Ast.zig").null_node)
                try typeIdFromTypeName(ast, operand, diag)
            else
                try typeIdForDecl(ast, decl, diag)
        else blk: {
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
        .meta_expr => 16,
        .call_expr => {
            const callee = ast.data(init).lhs;
            if (ast.tag(callee) == .identifier and std.mem.eql(u8, ast.tokenSlice(ast.mainToken(callee)), "New")) return 10;
            return diag.failAt(ast.tokens[ast.mainToken(decl)].start, "Phase 2 type_of cannot infer declaration type", .{});
        },
        .binary_expr => blk: {
            const op = ast.tokens[ast.mainToken(init)].tag;
            const lhs = try typeIdForExpr(ast, ast.data(init).lhs, diag);
            const rhs = try typeIdForExpr(ast, ast.data(init).rhs, diag);
            break :blk switch (op) {
                .plus, .minus, .star, .slash, .plus_equal, .minus_equal, .star_equal, .slash_equal => if (lhs == 12 or lhs == 13 or rhs == 12 or rhs == 13) 12 else 5,
                .percent, .ampersand, .pipe, .caret, .ampersand_equal, .pipe_equal, .caret_equal, .shift_left, .shift_right, .shift_left_rotate, .shift_right_rotate => 5,
                .equal_equal, .bang_equal, .ampersand_ampersand, .pipe_pipe => 1,
                else => return diag.failAt(ast.tokens[ast.mainToken(init)].start, "Phase 2 type_of cannot infer binary expression type", .{}),
            };
        },
        .unary_expr => blk: {
            const op = ast.tokens[ast.mainToken(init)].tag;
            break :blk switch (op) {
                .bang => 1,
                .minus, .keyword_xx, .keyword_cast => try typeIdForExpr(ast, init, diag),
                else => return diag.failAt(ast.tokens[ast.mainToken(init)].start, "Phase 2 type_of cannot infer unary expression type", .{}),
            };
        },
        .ifx_expr => try typeIdForExpr(ast, init, diag),
        else => diag.failAt(ast.tokens[ast.mainToken(decl)].start, "Phase 2 type_of cannot infer declaration type", .{}),
    };
}

fn typeIdForExpr(ast: *const Ast, expr: NodeIndex, diag: Diagnostic) !u32 {
    return switch (ast.tag(expr)) {
        .string_literal => 14,
        .integer_literal, .char_literal => 5,
        .float_literal => 12,
        .bool_literal => 1,
        .type_expr => try typeIdFromToken(ast, ast.mainToken(expr), diag),
        .binary_expr => blk: {
            const op = ast.tokens[ast.mainToken(expr)].tag;
            const lhs = try typeIdForExpr(ast, ast.data(expr).lhs, diag);
            const rhs = try typeIdForExpr(ast, ast.data(expr).rhs, diag);
            break :blk switch (op) {
                .plus, .minus, .star, .slash, .plus_equal, .minus_equal, .star_equal, .slash_equal => if (lhs == 12 or lhs == 13 or rhs == 12 or rhs == 13) 12 else 5,
                .percent, .ampersand, .pipe, .caret, .ampersand_equal, .pipe_equal, .caret_equal, .shift_left, .shift_right, .shift_left_rotate, .shift_right_rotate => 5,
                .equal_equal, .bang_equal, .ampersand_ampersand, .pipe_pipe => 1,
                else => return diag.failAt(ast.tokens[ast.mainToken(expr)].start, "Phase 2 type query cannot infer binary expression type", .{}),
            };
        },
        .unary_expr => blk: {
            const op = ast.tokens[ast.mainToken(expr)].tag;
            if (op == .bang) break :blk 1;
            if (op == .keyword_cast) {
                const raw_target_ty = ast.data(expr).rhs;
                const target_ty: u32 = raw_target_ty & 0x7fffffff;
                break :blk try typeIdFromTypeExpr(ast, target_ty, diag);
            }
            break :blk try typeIdForExpr(ast, ast.data(expr).lhs, diag);
        },
        .ifx_expr => {
            const arms = ast.extraSlice(ast.data(expr).rhs);
            if (arms.len != 2) return diag.failAt(ast.tokens[ast.mainToken(expr)].start, "ifx requires two arms for type query", .{});
            const lhs = try typeIdForExpr(ast, @intCast(arms[0]), diag);
            const rhs = try typeIdForExpr(ast, @intCast(arms[1]), diag);
            return if (lhs == rhs) lhs else if (lhs == 12 or lhs == 13 or rhs == 12 or rhs == 13) 12 else 5;
        },
        else => diag.failAt(ast.tokens[ast.mainToken(expr)].start, "Phase 2 type query cannot infer expression type", .{}),
    };
}

fn typeIdFromType(ty: Type) ?u32 {
    return switch (ty.index) {
        InternPool.well_known.void_type => 0,
        InternPool.well_known.bool_type => 1,
        InternPool.well_known.s32_type => 4,
        InternPool.well_known.s64_type => 5,
        InternPool.well_known.u8_type => 7,
        InternPool.well_known.u16_type => 8,
        InternPool.well_known.u32_type => 9,
        InternPool.well_known.u64_type => 10,
        InternPool.well_known.float32_type => 12,
        InternPool.well_known.float64_type => 13,
        InternPool.well_known.string_type => 14,
        InternPool.well_known.type_type => 15,
        InternPool.well_known.any_type => 16,
        else => if (ty.isPointer()) 10 else null,
    };
}

fn phase2TypeIdResolved(ctx: *GenContext, operand: NodeIndex, diag: Diagnostic) !u32 {
    const ast = ctx.ast;
    if (ast.tag(operand) == .identifier) {
        const decl = ctx.resolved.local_values.get(operand) orelse {
            const name = ast.tokenSlice(ast.mainToken(operand));
            if (isBuiltinTypeName(name)) return typeIdFromTypeName(ast, operand, diag);
            if (ctx.resolved.lookup(name)) |sym| switch (sym) {
                .proc => |proc_node| return procTypeId(ast, proc_node, diag),
                else => {},
            };
            return diag.failAt(ast.tokens[ast.mainToken(operand)].start, "type_of identifier is unresolved", .{});
        };
        if (ast.tag(decl) == .var_decl and ast.data(decl).lhs != @import("Ast.zig").null_node) return typeIdFromTypeExpr(ast, ast.data(decl).lhs, diag);
        if (ast.tag(decl) == .var_decl and ctx.typed != null and ast.data(decl).rhs != @import("Ast.zig").null_node) {
            if (ctx.typeIdFromTypedNode(ctx.typed.?, ast.data(decl).rhs)) |type_id| return type_id;
        }
        if (ast.tag(decl) == .const_decl and ast.data(decl).rhs != 0) return typeIdFromToken(ast, ast.data(decl).rhs, diag);
        return diag.failAt(ast.tokens[ast.mainToken(operand)].start, "type_of identifier requires an explicit declared type", .{});
    }
    return phase2TypeIdNoResolve(ast, operand, diag);
}

fn procTypeId(ast: *const Ast, proc_node: NodeIndex, diag: Diagnostic) !u32 {
    const sig = procSignature(ast, proc_node) orelse return 31;
    const params = ast.extraSlice(sig.params_extra);
    if (params.len == 0 and sig.return_type == @import("Ast.zig").null_node) return 31;
    return diag.failAt(ast.tokens[ast.mainToken(proc_node)].start, "type_of procedure currently supports only zero-argument void procedures", .{});
}

const ProcSig = struct { params_extra: u32, return_type: NodeIndex };
fn procSignature(ast: *const Ast, proc: NodeIndex) ?ProcSig {
    if (ast.data(proc).rhs == @import("Ast.zig").null_node) return null;
    const sig = ast.extraSlice(ast.data(proc).rhs);
    if (sig.len < 2) return null;
    return .{ .params_extra = sig[0], .return_type = sig[1] };
}

fn isCompoundAssignmentOp(op: TokenTag) bool {
    return op == .plus_equal or
        op == .minus_equal or
        op == .star_equal or
        op == .slash_equal or
        op == .ampersand_equal or
        op == .pipe_equal or
        op == .pipe_pipe_equal or
        op == .caret_equal;
}

fn compoundAssignmentOpcode(ctx: *GenContext, lhs: NodeIndex, rhs: NodeIndex, op: TokenTag) Bytecode.Opcode {
    const float_arithmetic = ctx.typed != null and (ctx.typed.?.typeOf(lhs).isFloat() or ctx.typed.?.typeOf(rhs).isFloat());
    return switch (op) {
        .plus_equal => if (float_arithmetic) .add_float else .add_int,
        .minus_equal => if (float_arithmetic) .sub_float else .sub_int,
        .star_equal => if (float_arithmetic) .mul_float else .mul_int,
        .slash_equal => if (float_arithmetic) .div_float else .div_int,
        .ampersand_equal => .bit_and,
        .pipe_equal => .bit_or,
        .pipe_pipe_equal => .bool_or,
        .caret_equal => .bit_xor,
        else => unreachable,
    };
}

fn parseIntLiteral(ast: *const Ast, expr: NodeIndex, diag: Diagnostic) !i64 {
    if (ast.tokens[ast.mainToken(expr)].tag == .directive_line) return sourceLineNumber(ast.source, ast.tokens[ast.mainToken(expr)].start);
    const raw = ast.tokenSlice(ast.mainToken(expr));
    var base: u8 = 10;
    var start: usize = 0;
    if (raw.len >= 2 and raw[0] == '0' and (raw[1] == 'b' or raw[1] == 'B')) {
        base = 2;
        start = 2;
    } else if (raw.len >= 2 and raw[0] == '0' and (raw[1] == 'x' or raw[1] == 'X')) {
        base = 16;
        start = 2;
    }
    var value: i64 = 0;
    for (raw[start..]) |ch| {
        if (ch == '_') continue;
        const digit: i64 = switch (ch) {
            '0'...'9' => ch - '0',
            'a'...'f' => 10 + ch - 'a',
            'A'...'F' => 10 + ch - 'A',
            else => return diag.failAt(ast.tokens[ast.mainToken(expr)].start, "invalid integer literal '{s}'", .{raw}),
        };
        if (digit >= base) return diag.failAt(ast.tokens[ast.mainToken(expr)].start, "invalid integer literal '{s}'", .{raw});
        value = value * base + digit;
    }
    return value;
}

fn sourceLineNumber(source: []const u8, offset: u32) i64 {
    var line: i64 = 1;
    var i: usize = 0;
    const limit: usize = @min(offset, source.len);
    while (i < limit) : (i += 1) {
        if (source[i] == '\n') line += 1;
    }
    return line;
}

fn phase2TypeIdNoResolve(ast: *const Ast, operand: NodeIndex, diag: Diagnostic) !u32 {
    return switch (ast.tag(operand)) {
        .string_literal => 14,
        .type_expr => if (isBuiltinTypeName(ast.tokenSlice(ast.mainToken(operand)))) try typeIdFromToken(ast, ast.mainToken(operand), diag) else 16,
        .identifier => if (isBuiltinTypeName(ast.tokenSlice(ast.mainToken(operand)))) try typeIdFromTypeName(ast, operand, diag) else 16,
        .integer_literal, .char_literal => 5,
        .float_literal => 12,
        .bool_literal => 1,
        .field_access => 10,
        .index_expr, .call_expr, .type_of_expr, .size_of_expr => 16,
        else => 16,
    };
}

fn typeIdFromTypeExpr(ast: *const Ast, node: NodeIndex, diag: Diagnostic) !u32 {
    return switch (ast.tag(node)) {
        .pointer_type => 10,
        .array_type, .struct_type, .union_type, .enum_type, .proc_type => 16,
        .type_expr => typeIdFromToken(ast, ast.mainToken(node), diag),
        .identifier => 16,
        else => diag.failAt(ast.tokens[ast.mainToken(node)].start, "expected type expression", .{}),
    };
}

fn typeIdFromToken(ast: *const Ast, token: u32, diag: Diagnostic) !u32 {
    const name = ast.tokenSlice(token);
    if (std.mem.eql(u8, name, "int") or std.mem.eql(u8, name, "s64")) return 5;
    if (std.mem.eql(u8, name, "s32")) return 4;
    if (std.mem.eql(u8, name, "u8")) return 7;
    if (std.mem.eql(u8, name, "u16")) return 8;
    if (std.mem.eql(u8, name, "u32")) return 9;
    if (std.mem.eql(u8, name, "u64")) return 10;
    if (std.mem.eql(u8, name, "float") or std.mem.eql(u8, name, "float32")) return 12;
    if (std.mem.eql(u8, name, "float64")) return 13;
    if (std.mem.eql(u8, name, "string")) return 14;
    if (std.mem.eql(u8, name, "bool")) return 1;
    if (std.mem.eql(u8, name, "Type")) return 15;
    if (std.mem.eql(u8, name, "Any")) return 16;
    _ = diag;
    return 16;
}

fn phase3SizeOf(ctx: *GenContext, operand: NodeIndex, diag: Diagnostic) !u64 {
    const ast = ctx.ast;
    if (ast.tag(operand) == .identifier or ast.tag(operand) == .type_expr) {
        const name = ast.tokenSlice(ast.mainToken(operand));
        if (try structSizeByName(ctx, name, diag)) |size| return size;
    }
    if (ast.tag(operand) == .type_of_expr and ast.tag(ast.data(operand).lhs) == .field_access) {
        if (try structFieldSizeFromAccess(ctx, ast.data(operand).lhs, diag)) |size| return size;
    }
    const type_id = switch (ast.tag(operand)) {
        .type_expr => try typeIdFromToken(ast, ast.mainToken(operand), diag),
        .identifier => blk: {
            const name = ast.tokenSlice(ast.mainToken(operand));
            if (isBuiltinTypeName(name)) break :blk try typeIdFromTypeName(ast, operand, diag);
            if (ctx.resolved.local_values.get(operand)) |decl| {
                if (decl == @import("Ast.zig").null_node) break :blk 16;
                if (ast.tag(decl) == .type_expr) break :blk try typeIdFromToken(ast, ast.mainToken(decl), diag);
                if (ast.tag(decl) == .const_decl and ast.tag(ast.data(decl).lhs) == .type_expr) break :blk try typeIdFromToken(ast, ast.mainToken(ast.data(decl).lhs), diag);
                if (ast.tag(decl) == .const_decl and (ast.tag(ast.data(decl).lhs) == .struct_type or ast.tag(ast.data(decl).lhs) == .union_type)) break :blk 10;
                if (ast.tag(decl) == .const_decl and (ast.tag(ast.data(decl).lhs) == .enum_type or ast.tag(ast.data(decl).lhs) == .array_type)) break :blk 16;
                if (ctx.typed) |typed| if (ctx.typeIdFromTypedNode(typed, decl)) |type_id| break :blk type_id;
            }
            break :blk 16;
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
        else => 8,
    };
}

fn structSizeByName(ctx: *GenContext, name: []const u8, diag: Diagnostic) anyerror!?u64 {
    const ast = ctx.ast;
    const sym = ctx.resolved.lookup(name) orelse return null;
    const decl = switch (sym) {
        .const_value => |node| node,
        else => return null,
    };
    if (decl == @import("Ast.zig").null_node or decl >= ast.node_tags.items.len) return null;
    const type_node = if (ast.tag(decl) == .const_decl) ast.data(decl).lhs else decl;
    if (ast.tag(type_node) == .identifier or ast.tag(type_node) == .type_expr) return try structSizeByName(ctx, ast.tokenSlice(ast.mainToken(type_node)), diag);
    if (ast.tag(type_node) != .struct_type and ast.tag(type_node) != .union_type) return null;
    return try containerSizeFromSource(ctx, type_node, diag);
}

fn structFieldSizeFromAccess(ctx: *GenContext, access: NodeIndex, diag: Diagnostic) !?u64 {
    const ast = ctx.ast;
    const lhs = ast.data(access).lhs;
    if (ast.tag(lhs) != .identifier) return null;
    const type_name = ast.tokenSlice(ast.mainToken(lhs));
    const field_name = ast.tokenSlice(ast.data(access).rhs);
    const sym = ctx.resolved.lookup(type_name) orelse return null;
    const decl = switch (sym) {
        .const_value => |node| node,
        else => return null,
    };
    if (decl == @import("Ast.zig").null_node or decl >= ast.node_tags.items.len) return null;
    const type_node = if (ast.tag(decl) == .const_decl) ast.data(decl).lhs else decl;
    if (ast.tag(type_node) == .identifier or ast.tag(type_node) == .type_expr) {
        const alias = ast.tokenSlice(ast.mainToken(type_node));
        const alias_sym = ctx.resolved.lookup(alias) orelse return null;
        const alias_decl = switch (alias_sym) {
            .const_value => |node| node,
            else => return null,
        };
        const alias_type = if (ast.tag(alias_decl) == .const_decl) ast.data(alias_decl).lhs else alias_decl;
        if (ast.tag(alias_type) == .identifier or ast.tag(alias_type) == .type_expr) {
            const alias_size = try structSizeByName(ctx, ast.tokenSlice(ast.mainToken(alias_type)), diag) orelse return null;
            _ = alias_size;
            return null;
        }
        if (ast.tag(alias_type) != .struct_type and ast.tag(alias_type) != .union_type) return null;
        return try containerFieldSizeFromSource(ctx, alias_type, field_name, diag);
    }
    if (ast.tag(type_node) != .struct_type and ast.tag(type_node) != .union_type) return null;
    return try containerFieldSizeFromSource(ctx, type_node, field_name, diag);
}

fn fieldOffsetFromAccess(ctx: *GenContext, access: NodeIndex, diag: Diagnostic) !?u64 {
    const ast = ctx.ast;
    const lhs = ast.data(access).lhs;
    if (ast.tag(lhs) != .identifier) return null;
    const base_decl = ctx.resolved.local_values.get(lhs) orelse return null;
    if (base_decl == @import("Ast.zig").null_node or ast.tag(base_decl) != .var_decl) return null;
    const type_expr = ast.data(base_decl).lhs;
    if (type_expr == @import("Ast.zig").null_node or ast.tag(type_expr) != .type_expr) return null;
    const type_name = ast.tokenSlice(ast.mainToken(type_expr));
    const field_name = ast.tokenSlice(ast.data(access).rhs);
    const sym = ctx.resolved.lookup(type_name) orelse return null;
    const decl = switch (sym) {
        .const_value => |node| node,
        else => return null,
    };
    if (decl == @import("Ast.zig").null_node or decl >= ast.node_tags.items.len) return null;
    const type_node = if (ast.tag(decl) == .const_decl) ast.data(decl).lhs else decl;
    if (ast.tag(type_node) != .struct_type and ast.tag(type_node) != .union_type) return null;
    return try containerFieldOffsetFromSource(ctx, type_node, field_name, diag);
}

fn containerSizeFromSource(ctx: *GenContext, type_node: NodeIndex, diag: Diagnostic) anyerror!u64 {
    const body = containerBodySource(ctx.ast, type_node) orelse return 8;
    var total: u64 = 0;
    var it = FieldSegmentIterator{ .source = body };
    var max_align: u64 = 1;
    while (it.next()) |segment| {
        const parsed = parseFieldSegment(segment) orelse continue;
        const field_size = try typeTextSize(ctx, parsed.type_text, diag);
        const field_align = try typeTextAlign(ctx, parsed.type_text, diag);
        max_align = @max(max_align, field_align);
        var n: u64 = 0;
        while (n < parsed.name_count) : (n += 1) {
            total = alignForward(total, field_align);
            total += field_size;
        }
    }
    return if (total == 0) 0 else alignForward(total, max_align);
}

fn containerFieldSizeFromSource(ctx: *GenContext, type_node: NodeIndex, field_name: []const u8, diag: Diagnostic) !?u64 {
    const body = containerBodySource(ctx.ast, type_node) orelse return null;
    var it = FieldSegmentIterator{ .source = body };
    while (it.next()) |segment| {
        const parsed = parseFieldSegment(segment) orelse continue;
        if (!fieldListContains(parsed.names_text, field_name)) continue;
        return try typeTextSize(ctx, parsed.type_text, diag);
    }
    return null;
}

fn containerFieldOffsetFromSource(ctx: *GenContext, type_node: NodeIndex, field_name: []const u8, diag: Diagnostic) !?u64 {
    const body = containerBodySource(ctx.ast, type_node) orelse return null;
    var offset: u64 = 0;
    var it = FieldSegmentIterator{ .source = body };
    while (it.next()) |segment| {
        const parsed = parseFieldSegment(segment) orelse continue;
        const field_size = try typeTextSize(ctx, parsed.type_text, diag);
        const field_align = try typeTextAlign(ctx, parsed.type_text, diag);
        var split = std.mem.splitScalar(u8, parsed.names_text, ',');
        while (split.next()) |raw| {
            offset = alignForward(offset, field_align);
            const name = lastWord(std.mem.trim(u8, raw, " \t\r\n"));
            if (std.mem.eql(u8, name, field_name)) return offset;
            offset += field_size;
        }
    }
    return null;
}

fn containerFieldInfoFromSource(ctx: *GenContext, type_node: NodeIndex, field_name: []const u8, diag: Diagnostic) !?FieldInfo {
    const body = containerBodySource(ctx.ast, type_node) orelse return null;
    var offset: u64 = 0;
    var it = FieldSegmentIterator{ .source = body };
    while (it.next()) |segment| {
        const parsed = parseFieldSegment(segment) orelse continue;
        const field_size = try typeTextSize(ctx, parsed.type_text, diag);
        const field_align = try typeTextAlign(ctx, parsed.type_text, diag);
        var split = std.mem.splitScalar(u8, parsed.names_text, ',');
        while (split.next()) |raw| {
            offset = alignForward(offset, field_align);
            const name = lastWord(std.mem.trim(u8, raw, " \t\r\n"));
            if (std.mem.eql(u8, name, field_name)) return .{ .offset = offset, .type_text = parsed.type_text };
            offset += field_size;
        }
    }
    return null;
}

fn containerFieldInfoAtIndex(ctx: *GenContext, type_node: NodeIndex, target_index: usize, diag: Diagnostic) !?FieldInfo {
    const body = containerBodySource(ctx.ast, type_node) orelse return null;
    var offset: u64 = 0;
    var field_index: usize = 0;
    var it = FieldSegmentIterator{ .source = body };
    while (it.next()) |segment| {
        const parsed = parseFieldSegment(segment) orelse continue;
        const field_size = try typeTextSize(ctx, parsed.type_text, diag);
        const field_align = try typeTextAlign(ctx, parsed.type_text, diag);
        var split = std.mem.splitScalar(u8, parsed.names_text, ',');
        while (split.next()) |_| {
            offset = alignForward(offset, field_align);
            if (field_index == target_index) return .{ .offset = offset, .type_text = parsed.type_text };
            offset += field_size;
            field_index += 1;
        }
    }
    return null;
}

fn containerBodySource(ast: *const Ast, type_node: NodeIndex) ?[]const u8 {
    var i: usize = ast.tokens[ast.mainToken(type_node)].end;
    while (i < ast.source.len and ast.source[i] != '{') : (i += 1) {}
    if (i >= ast.source.len) return null;
    const start = i + 1;
    var depth: usize = 1;
    i += 1;
    while (i < ast.source.len) : (i += 1) {
        switch (ast.source[i]) {
            '{' => depth += 1,
            '}' => {
                depth -= 1;
                if (depth == 0) return ast.source[start..i];
            },
            else => {},
        }
    }
    return null;
}

const FieldSegmentIterator = struct {
    source: []const u8,
    index: usize = 0,

    fn next(it: *FieldSegmentIterator) ?[]const u8 {
        while (it.index < it.source.len) {
            const start = it.index;
            var depth: usize = 0;
            while (it.index < it.source.len) : (it.index += 1) {
                const c = it.source[it.index];
                if (c == '{' or c == '(' or c == '[') depth += 1;
                if ((c == '}' or c == ')' or c == ']') and depth > 0) depth -= 1;
                if ((c == ';' or c == '\n') and depth == 0) break;
            }
            const end = it.index;
            if (it.index < it.source.len) it.index += 1;
            const segment = std.mem.trim(u8, it.source[start..end], " \t\r\n");
            if (segment.len != 0) return segment;
        }
        return null;
    }
};

const ParsedFieldSegment = struct {
    names_text: []const u8,
    type_text: []const u8,
    name_count: u64,
};

fn parseFieldSegment(segment: []const u8) ?ParsedFieldSegment {
    var clean = std.mem.trim(u8, segment, " \t\r\n");
    if (std.mem.startsWith(u8, clean, "//")) return null;
    if (std.mem.indexOf(u8, clean, "//")) |comment_pos| clean = std.mem.trim(u8, clean[0..comment_pos], " \t\r\n");
    if (std.mem.indexOf(u8, clean, "::") != null) return null;
    const colon = std.mem.indexOfScalar(u8, clean, ':') orelse return null;
    var names = std.mem.trim(u8, clean[0..colon], " \t\r\n");
    if (names.len == 0) return null;
    while (std.mem.startsWith(u8, names, "#as")) names = std.mem.trim(u8, names[3..], " \t\r\n");
    while (std.mem.startsWith(u8, names, "using")) names = std.mem.trim(u8, names[5..], " \t\r\n");
    var type_text = std.mem.trim(u8, clean[colon + 1 ..], " \t\r\n");
    if (std.mem.indexOfScalar(u8, type_text, '#')) |pos| type_text = std.mem.trim(u8, type_text[0..pos], " \t\r\n");
    if (std.mem.indexOfScalar(u8, type_text, '=')) |pos| type_text = std.mem.trim(u8, type_text[0..pos], " \t\r\n");
    if (type_text.len == 0) return null;
    return .{ .names_text = names, .type_text = type_text, .name_count = countFieldNames(names) };
}

fn countFieldNames(names: []const u8) u64 {
    var count: u64 = 1;
    for (names) |c| {
        if (c == ',') count += 1;
    }
    return count;
}

fn fieldListContains(names: []const u8, field_name: []const u8) bool {
    var split = std.mem.splitScalar(u8, names, ',');
    while (split.next()) |raw| {
        const name = lastWord(std.mem.trim(u8, raw, " \t\r\n"));
        if (std.mem.eql(u8, name, field_name)) return true;
    }
    return false;
}

fn lastWord(text: []const u8) []const u8 {
    var end = text.len;
    while (end > 0 and std.ascii.isWhitespace(text[end - 1])) end -= 1;
    var start = end;
    while (start > 0 and !std.ascii.isWhitespace(text[start - 1])) start -= 1;
    return text[start..end];
}

fn enumValueByName(ctx: *GenContext, field_name: []const u8, diag: Diagnostic) anyerror!?u32 {
    _ = diag;
    if (knownTokenTagValue(field_name)) |value| return value;
    for (ctx.ast.node_tags.items, 0..) |tag, node_index| {
        if (tag != .enum_type) continue;
        var tok = ctx.ast.mainToken(@intCast(node_index));
        while (tok < ctx.ast.tokens.len and ctx.ast.tokens[tok].tag != .l_brace) tok += 1;
        if (tok >= ctx.ast.tokens.len) continue;
        tok += 1;
        var value: u32 = 0;
        var depth: u32 = 1;
        var waiting_for_member = true;
        while (tok < ctx.ast.tokens.len and depth != 0) : (tok += 1) {
            switch (ctx.ast.tokens[tok].tag) {
                .l_brace => depth += 1,
                .r_brace => depth -= 1,
                .semicolon, .comma => {
                    if (depth == 1) waiting_for_member = true;
                },
                .identifier => if (depth == 1 and waiting_for_member) {
                    if (std.mem.eql(u8, ctx.ast.tokenSlice(tok), field_name)) return value;
                    value += 1;
                    waiting_for_member = false;
                },
                else => {},
            }
        }
    }
    return null;
}

fn knownTokenTagValue(field_name: []const u8) ?u32 {
    const names = [_][]const u8{
        "invalid", "eof", "identifier", "integer_literal", "float_literal", "string_literal", "keyword_if", "keyword_else", "keyword_then", "keyword_ifx", "keyword_for", "keyword_while", "keyword_return", "keyword_break", "keyword_continue", "keyword_defer", "keyword_using", "keyword_struct", "keyword_union", "keyword_enum", "keyword_enum_flags", "keyword_cast", "keyword_xx", "keyword_inline", "keyword_no_inline", "keyword_null", "keyword_true", "keyword_false", "keyword_void", "keyword_it", "keyword_it_index", "keyword_push_context", "keyword_operator", "keyword_case", "keyword_size_of", "keyword_type_of", "keyword_type_info", "keyword_is_constant", "keyword_interface", "directive_run", "directive_if", "directive_ifx", "directive_else", "directive_import", "directive_load", "directive_insert", "directive_code", "directive_expand", "directive_char", "directive_string", "directive_foreign", "directive_foreign_library", "directive_system_library", "directive_library", "directive_type", "directive_scope_file", "directive_scope_export", "directive_scope_module", "directive_as", "directive_place", "directive_align", "directive_no_padding", "directive_specified", "directive_through", "directive_complete", "directive_must", "directive_this", "directive_procedure_name", "directive_deprecated", "directive_assert", "directive_dump", "directive_symmetric", "directive_poke_name", "directive_compile_time", "directive_no_reset", "directive_no_abc", "directive_no_context", "directive_c_call", "directive_add_context", "directive_asm", "directive_bytes", "directive_intrinsic", "directive_program_export", "directive_cpp_method", "directive_elsewhere", "directive_runtime_support", "directive_bake_arguments", "directive_bake_constants", "directive_modify", "directive_module_parameters", "directive_type_info_none", "directive_type_info_procedures_are_void_pointers", "directive_placeholder", "directive_compiler", "directive_file", "directive_line", "directive_filepath", "directive_location", "directive_caller_location", "directive_caller_code", "directive_procedure_of_call", "colon_colon", "colon_equal", "colon", "equal", "equal_equal", "bang_equal", "less_than", "less_equal", "greater_than", "greater_equal", "plus", "minus", "star", "slash", "percent", "ampersand", "pipe", "caret", "tilde", "shift_left", "shift_right", "shift_left_rotate", "shift_right_rotate", "ampersand_ampersand", "pipe_pipe", "pipe_pipe_equal", "bang", "plus_equal", "minus_equal", "star_equal", "slash_equal", "ampersand_equal", "pipe_equal", "caret_equal", "dot_dot", "dot", "comma", "semicolon", "l_paren", "r_paren", "l_brace", "r_brace", "l_bracket", "r_bracket", "arrow", "fat_arrow", "dollar", "dollar_dollar", "at", "triple_minus", "dot_star",
    };
    for (names, 0..) |name, i| {
        if (std.mem.eql(u8, name, field_name)) return @intCast(i);
    }
    return null;
}

fn typeTextSize(ctx: *GenContext, raw_type: []const u8, diag: Diagnostic) anyerror!u64 {
    var ty = std.mem.trim(u8, raw_type, " \t\r\n");
    while (std.mem.startsWith(u8, ty, "using")) ty = std.mem.trim(u8, ty[5..], " \t\r\n");
    if (ty.len == 0) return 0;
    if (ty[0] == '*') return 8;
    if (std.mem.indexOf(u8, ty, "->") != null) return 8;
    if (std.mem.startsWith(u8, ty, "[..]")) return 8;
    if (ty[0] == '[') {
        const close = std.mem.indexOfScalar(u8, ty, ']') orelse return 8;
        const count_text = std.mem.trim(u8, ty[1..close], " \t\r\n");
        const count = std.fmt.parseInt(u64, count_text, 10) catch 1;
        return count * try typeTextSize(ctx, ty[close + 1 ..], diag);
    }
    const name = firstTypeWord(ty);
    if (std.mem.eql(u8, name, "float") or std.mem.eql(u8, name, "float32") or std.mem.eql(u8, name, "s32") or std.mem.eql(u8, name, "u32")) return 4;
    if (std.mem.eql(u8, name, "u8") or std.mem.eql(u8, name, "s8") or std.mem.eql(u8, name, "bool")) return 1;
    if (std.mem.eql(u8, name, "u16") or std.mem.eql(u8, name, "s16")) return 2;
    if (std.mem.eql(u8, name, "int") or std.mem.eql(u8, name, "s64") or std.mem.eql(u8, name, "u64") or std.mem.eql(u8, name, "float64") or std.mem.eql(u8, name, "Type") or std.mem.eql(u8, name, "string")) return 8;
    if (std.mem.eql(u8, name, "Any")) return 16;
    if (try structSizeByName(ctx, name, diag)) |size| return size;
    return 8;
}

fn typeTextAlign(ctx: *GenContext, raw_type: []const u8, diag: Diagnostic) anyerror!u64 {
    var ty = std.mem.trim(u8, raw_type, " \t\r\n");
    while (std.mem.startsWith(u8, ty, "using")) ty = std.mem.trim(u8, ty[5..], " \t\r\n");
    if (ty.len == 0) return 1;
    if (ty[0] == '*' or std.mem.indexOf(u8, ty, "->") != null) return 8;
    if (std.mem.startsWith(u8, ty, "[..]")) return 8;
    if (ty[0] == '[') {
        const close = std.mem.indexOfScalar(u8, ty, ']') orelse return 8;
        return try typeTextAlign(ctx, ty[close + 1 ..], diag);
    }
    const name = firstTypeWord(ty);
    if (std.mem.eql(u8, name, "u8") or std.mem.eql(u8, name, "s8") or std.mem.eql(u8, name, "bool")) return 1;
    if (std.mem.eql(u8, name, "u16") or std.mem.eql(u8, name, "s16")) return 2;
    if (std.mem.eql(u8, name, "float") or std.mem.eql(u8, name, "float32") or std.mem.eql(u8, name, "s32") or std.mem.eql(u8, name, "u32")) return 4;
    if (std.mem.eql(u8, name, "int") or std.mem.eql(u8, name, "s64") or std.mem.eql(u8, name, "u64") or std.mem.eql(u8, name, "float64") or std.mem.eql(u8, name, "Type")) return 8;
    return try structAlignByName(ctx, name, diag) orelse 8;
}

fn structAlignByName(ctx: *GenContext, name: []const u8, diag: Diagnostic) anyerror!?u64 {
    const ast = ctx.ast;
    const sym = ctx.resolved.lookup(name) orelse return null;
    const decl = switch (sym) {
        .const_value => |node| node,
        else => return null,
    };
    if (decl == @import("Ast.zig").null_node or decl >= ast.node_tags.items.len) return null;
    const type_node = if (ast.tag(decl) == .const_decl) ast.data(decl).lhs else decl;
    if (ast.tag(type_node) == .identifier or ast.tag(type_node) == .type_expr) return try structAlignByName(ctx, ast.tokenSlice(ast.mainToken(type_node)), diag);
    if (ast.tag(type_node) != .struct_type and ast.tag(type_node) != .union_type) return null;
    const body = containerBodySource(ast, type_node) orelse return 8;
    var max_align: u64 = 1;
    var it = FieldSegmentIterator{ .source = body };
    while (it.next()) |segment| {
        const parsed = parseFieldSegment(segment) orelse continue;
        max_align = @max(max_align, try typeTextAlign(ctx, parsed.type_text, diag));
    }
    return max_align;
}

fn alignForward(value: u64, alignment: u64) u64 {
    if (alignment <= 1) return value;
    const remainder = value % alignment;
    return if (remainder == 0) value else value + alignment - remainder;
}

fn firstTypeWord(text: []const u8) []const u8 {
    var end: usize = 0;
    while (end < text.len) : (end += 1) {
        const c = text[end];
        if (!(std.ascii.isAlphanumeric(c) or c == '_')) break;
    }
    return text[0..end];
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
            try emitLiteralPrint(program, proc, fmt[start .. i + 1], fmt_node);
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
        if (next_start + 1 < fmt.len and fmt[next_start] == ' ' and fmt[next_start + 1] == '\n') {
            start = next_start + 1;
        } else {
            start = next_start;
        }
    }
    if (start < fmt.len) try emitLiteralPrint(program, proc, fmt[start..], fmt_node);
    if (arg_index > arg_nodes.len) return diag.failAt(ast.tokens[ast.mainToken(fmt_node)].start, "print format consumed more arguments than provided", .{});
}

fn isReturnedPrint(ctx: *GenContext, call: NodeIndex) bool {
    var it = ctx.resolved.local_values.iterator();
    while (it.next()) |entry| {
        const decl = entry.value_ptr.*;
        if (decl == @import("Ast.zig").null_node) continue;
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

    var resolved = try resolve.resolve(std.testing.allocator, &ast, diag, true);
    defer resolved.deinit();

    var ip = try InternPool.init(std.testing.allocator);
    defer ip.deinit();

    var typed = try sema.analyze(std.testing.allocator, &ast, &resolved, &ip, diag);
    defer typed.deinit();

    var program = try generate(std.testing.allocator, &ast, &typed, &resolved, diag);
    defer program.deinit();

    const proc = &program.procs.items[program.main_proc.?];
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

    var resolved = try resolve.resolve(std.testing.allocator, &ast, diag, true);
    defer resolved.deinit();

    var ip = try InternPool.init(std.testing.allocator);
    defer ip.deinit();

    var typed = try sema.analyze(std.testing.allocator, &ast, &resolved, &ip, diag);
    defer typed.deinit();

    var program = try generate(std.testing.allocator, &ast, &typed, &resolved, diag);
    defer program.deinit();

    try std.testing.expectEqual(@as(usize, 1), program.procs.items.len);
    const proc = &program.procs.items[program.main_proc.?];
    try std.testing.expectEqual(@as(usize, 3), proc.instructions.items.len);
    try std.testing.expectEqual(Bytecode.Opcode.load_string, proc.instructions.items[0].opcode);
    try std.testing.expectEqual(@as(u32, 0), proc.instructions.items[0].dest);
    try std.testing.expectEqual(Bytecode.Opcode.call_extern, proc.instructions.items[1].opcode);
    try std.testing.expectEqual(@intFromEnum(Bytecode.ExternSymbol.openjai_print), proc.instructions.items[1].dest);
    try std.testing.expectEqual(@as(u32, 0), proc.instructions.items[1].arg1);
    try std.testing.expectEqual(Bytecode.Opcode.ret_void, proc.instructions.items[2].opcode);
    try std.testing.expectEqualSlices(u8, "Hello, Sailor from Jai!\n", program.strings.items[proc.instructions.items[0].arg1]);
}

test "push_context emits the nested block body" {
    const lexer = @import("lexer.zig");
    const parser = @import("parser.zig");
    const resolve = @import("resolve.zig");
    const sema = @import("Sema.zig");

    const source = "#import \"Basic\";\nmain :: () {\n ctx := 0;\n push_context ctx {\n  print(\"inner\\n\");\n }\n print(\"outer\\n\");\n}\n";
    const diag = Diagnostic.init(std.testing.allocator, "push_context.jai", source);

    var tokens = try lexer.tokenize(std.testing.allocator, source, diag);
    defer tokens.deinit(std.testing.allocator);

    const token_slice = tokens.slice();
    var ast = try parser.parse(std.testing.allocator, source, token_slice.items(.tag), token_slice.items(.start), token_slice.items(.end), diag);
    defer {
        std.testing.allocator.free(ast.tokens);
        ast.deinit();
    }

    var resolved = try resolve.resolve(std.testing.allocator, &ast, diag, true);
    defer resolved.deinit();

    var ip = try InternPool.init(std.testing.allocator);
    defer ip.deinit();

    var typed = try sema.analyze(std.testing.allocator, &ast, &resolved, &ip, diag);
    defer typed.deinit();

    var program = try generate(std.testing.allocator, &ast, &typed, &resolved, diag);
    defer program.deinit();

    const proc = &program.procs.items[program.main_proc.?];
    var print_calls: usize = 0;
    for (proc.instructions.items) |inst| {
        if (inst.opcode == .call_extern and inst.dest == @intFromEnum(Bytecode.ExternSymbol.openjai_print)) {
            print_calls += 1;
        }
    }
    try std.testing.expectEqual(@as(usize, 2), print_calls);
}
