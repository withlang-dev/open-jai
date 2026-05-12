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
const vm_mod = @import("vm.zig");

const Resolved = @import("resolve.zig").Resolved;

const allocator_proc_default: u32 = 1;
const allocator_proc_pool: u32 = 2;
const allocator_proc_flat_pool: u32 = 3;
const allocator_proc_rpmalloc: u32 = 4;
const allocator_cap_is_this_yours: u32 = 1 << 3;

pub fn generate(allocator: std.mem.Allocator, ast: *const Ast, typed: *const Typed, resolved: *const Resolved, diag: Diagnostic) !Bytecode.Program {
    var program = Bytecode.Program.init(allocator);
    errdefer program.deinit();
    const root_decls = ast.extraSlice(ast.data(ast.root).lhs);
    for (root_decls, 0..) |decl_idx, i| {
        const decl: NodeIndex = @intCast(decl_idx);
        if (ast.tag(decl) != .proc_decl) continue;
        const next_decl: NodeIndex = if (i + 1 < root_decls.len) @intCast(root_decls[i + 1]) else @import("Ast.zig").null_node;
        if (procHasExpandModifier(ast, decl, next_decl)) continue;
        if (procContainsCompileTimeOnlyCompilerApi(ast, decl)) continue;
        if (procHasSourceLocationAbi(ast, decl)) continue;
        if (typed.main_proc != null and decl == typed.main_proc.?) continue;
        var helper = Bytecode.ProcBytecode{ .name = ast.tokenSlice(ast.mainToken(decl)) };
        errdefer helper.deinit(allocator);
        try initProcBytecodeSignature(allocator, ast, decl, &helper, diag);
        const helper_index: u32 = @intCast(program.procs.items.len);
        var helper_ctx = GenContext{ .ast = ast, .program = &program, .proc = &helper, .resolved = resolved, .typed = typed, .allow_root_proc_calls = true, .current_proc_node = decl, .current_proc_index = helper_index };
        defer helper_ctx.deinit();
        try helper_ctx.bindProcParams(decl, helper.param_count, diag);
        try helper_ctx.genBlock(ast.data(decl).lhs, diag);
        try helper.instructions.append(allocator, .{ .opcode = .ret_void });
        _ = try program.addProc(helper, decl);
    }
    if (typed.main_proc) |main_proc| {
        var proc = Bytecode.ProcBytecode{ .name = ast.tokenSlice(ast.mainToken(main_proc)) };
        errdefer proc.deinit(allocator);
        try initProcBytecodeSignature(allocator, ast, main_proc, &proc, diag);
        const main_idx: u32 = @intCast(program.procs.items.len);
        var ctx = GenContext{ .ast = ast, .program = &program, .proc = &proc, .resolved = resolved, .typed = typed, .allow_root_proc_calls = true, .current_proc_node = main_proc, .current_proc_index = main_idx };
        defer ctx.deinit();
        try ctx.bindProcParams(main_proc, proc.param_count, diag);
        try ctx.genBlock(ast.data(main_proc).lhs, diag);
        try proc.instructions.append(allocator, .{ .opcode = .ret_void });
        _ = try program.addProc(proc, main_proc);
        program.main_proc = main_idx;
    }
    return program;
}

fn initProcBytecodeSignature(allocator: std.mem.Allocator, ast: *const Ast, proc_node: NodeIndex, proc: *Bytecode.ProcBytecode, diag: Diagnostic) !void {
    if (procSignature(ast, proc_node)) |sig| {
        const params = ast.extraSlice(sig.params_extra);
        proc.param_count = @intCast(params.len);
        proc.num_registers = proc.param_count;
        for (params) |param_idx| {
            const param: NodeIndex = @intCast(param_idx);
            const param_type = ast.data(param).lhs;
            const type_id: u32 = if (param_type != @import("Ast.zig").null_node)
                try typeIdFromTypeExpr(ast, param_type, diag)
            else
                16;
            try proc.param_types.append(allocator, type_id);
        }
        proc.return_type = if (sig.return_type != @import("Ast.zig").null_node)
            try typeIdFromTypeExpr(ast, sig.return_type, diag)
        else
            0;
    }
}

pub fn generateProc(allocator: std.mem.Allocator, ast: *const Ast, resolved: *const Resolved, proc_node: NodeIndex, diag: Diagnostic) !Bytecode.Program {
    return generateProcWithParamCount(allocator, ast, resolved, null, proc_node, diag, 0);
}

pub fn generateProcWithParamCount(allocator: std.mem.Allocator, ast: *const Ast, resolved: *const Resolved, typed: ?*const Typed, proc_node: NodeIndex, diag: Diagnostic, param_count: usize) !Bytecode.Program {
    return generateProcInternal(allocator, ast, resolved, typed, proc_node, null, diag, param_count);
}

pub fn generateProcForCall(allocator: std.mem.Allocator, ast: *const Ast, resolved: *const Resolved, typed: ?*const Typed, proc_node: NodeIndex, call_expr: NodeIndex, diag: Diagnostic) !Bytecode.Program {
    const call_args = if (ast.data(call_expr).rhs < ast.extra_data.items.len) ast.extraSlice(ast.data(call_expr).rhs) else &[_]u32{};
    var reachable = try collectReachableProcs(allocator, ast, resolved, proc_node, call_expr);
    defer reachable.deinit(allocator);
    var program = Bytecode.Program.init(allocator);
    errdefer program.deinit();
    const root_decls = if (ast.root != @import("Ast.zig").null_node) ast.extraSlice(ast.data(ast.root).lhs) else &[_]u32{};
    var emitted_target = false;
    for (root_decls, 0..) |decl_idx, i| {
        const decl: NodeIndex = @intCast(decl_idx);
        if (ast.tag(decl) != .proc_decl) continue;
        if (!reachable.contains(decl)) continue;
        const next_decl: NodeIndex = if (i + 1 < root_decls.len) @intCast(root_decls[i + 1]) else @import("Ast.zig").null_node;
        if (procHasExpandModifier(ast, decl, next_decl) and decl != proc_node) continue;
        if (typed) |t| if (t.main_proc != null and decl == t.main_proc.?) continue;

        var proc = Bytecode.ProcBytecode{ .name = ast.tokenSlice(ast.mainToken(decl)) };
        errdefer proc.deinit(allocator);
        try initProcBytecodeSignature(allocator, ast, decl, &proc, diag);
        const effective_param_count = if (decl == proc_node) effectiveCallParamCount(ast, decl, call_args.len) else @as(usize, @intCast(proc.param_count));
        proc.num_registers = @max(proc.num_registers, @as(u32, @intCast(effective_param_count)));
        const return_type_node = if (procSignature(ast, decl)) |sig| sig.return_type else @import("Ast.zig").null_node;
        const proc_index: u32 = @intCast(program.procs.items.len);
        var ctx = GenContext{ .ast = ast, .resolved = resolved, .program = &program, .proc = &proc, .typed = typed, .allow_root_proc_calls = true, .compile_time_host = true, .current_proc_node = decl, .current_proc_index = proc_index };
        defer ctx.deinit();
        ctx.return_type_node = return_type_node;
        if (decl == proc_node) {
            try ctx.bindPolymorphTypes(decl, call_expr, diag);
            try ctx.bindProcParams(decl, effective_param_count, diag);
        } else {
            try ctx.bindProcParams(decl, proc.param_count, diag);
        }
        try ctx.genBlock(ast.data(decl).lhs, diag);
        try proc.instructions.append(allocator, .{ .opcode = .ret_void, .source_node = decl });
        _ = try program.addProc(proc, decl);
        if (decl == proc_node) {
            program.main_proc = proc_index;
            emitted_target = true;
        }
    }
    if (!emitted_target) return generateProcInternal(allocator, ast, resolved, typed, proc_node, call_expr, diag, call_args.len);
    return program;
}

fn generateProcInternal(allocator: std.mem.Allocator, ast: *const Ast, resolved: *const Resolved, typed: ?*const Typed, proc_node: NodeIndex, call_expr: ?NodeIndex, diag: Diagnostic, param_count: usize) !Bytecode.Program {
    var program = Bytecode.Program.init(allocator);
    errdefer program.deinit();
    var proc = Bytecode.ProcBytecode{ .name = ast.tokenSlice(ast.mainToken(proc_node)) };
    errdefer proc.deinit(allocator);
    try initProcBytecodeSignature(allocator, ast, proc_node, &proc, diag);
    proc.num_registers = @max(proc.num_registers, @as(u32, @intCast(param_count)));
    const return_type_node = if (procSignature(ast, proc_node)) |sig| sig.return_type else @import("Ast.zig").null_node;
    var ctx = GenContext{ .ast = ast, .resolved = resolved, .program = &program, .proc = &proc, .typed = typed, .compile_time_host = true, .current_proc_node = proc_node, .current_proc_index = 0 };
    defer ctx.deinit();
    ctx.return_type_node = return_type_node;
    if (call_expr) |call| try ctx.bindPolymorphTypes(proc_node, call, diag);
    try ctx.bindProcParams(proc_node, param_count, diag);
    try ctx.genBlock(ast.data(proc_node).lhs, diag);
    try proc.instructions.append(allocator, .{ .opcode = .ret_void, .source_node = proc_node });
    _ = try program.addProc(proc, proc_node);
    program.main_proc = 0;
    return program;
}

fn effectiveCallParamCount(ast: *const Ast, proc_node: NodeIndex, arg_count: usize) usize {
    const sig = procSignature(ast, proc_node) orelse return arg_count;
    const params = ast.extraSlice(sig.params_extra);
    if (arg_count >= params.len) return arg_count;
    var i = arg_count;
    while (i < params.len) : (i += 1) {
        const param: NodeIndex = @intCast(params[i]);
        if (ast.data(param).rhs == @import("Ast.zig").null_node) return arg_count;
    }
    return params.len;
}

pub fn generateBlockProc(allocator: std.mem.Allocator, ast: *const Ast, resolved: *const Resolved, block: NodeIndex, diag: Diagnostic) !Bytecode.Program {
    var program = Bytecode.Program.init(allocator);
    errdefer program.deinit();
    var proc = Bytecode.ProcBytecode{ .name = "#run_block" };
    var ctx = GenContext{ .ast = ast, .resolved = resolved, .program = &program, .proc = &proc, .compile_time_host = true, .current_proc_node = @import("Ast.zig").null_node, .current_proc_index = 0 };
    defer ctx.deinit();
    try ctx.genBlock(block, diag);
    try proc.instructions.append(allocator, .{ .opcode = .ret_void, .source_node = block });
    _ = try program.addProc(proc, @import("Ast.zig").null_node);
    program.main_proc = 0;
    return program;
}

const GenContext = struct {
    ast: *const Ast,
    program: *Bytecode.Program,
    proc: *Bytecode.ProcBytecode,
    resolved: *const Resolved,
    typed: ?*const Typed = null,
    allow_root_proc_calls: bool = false,
    compile_time_host: bool = false,
    current_proc_node: NodeIndex = @import("Ast.zig").null_node,
    current_proc_index: u32 = 0,
    decl_registers: std.AutoHashMapUnmanaged(NodeIndex, Bytecode.Register) = .empty,
    pointer_addrs: std.AutoHashMapUnmanaged(Bytecode.Register, Bytecode.Register) = .empty,
    field_values: std.AutoHashMapUnmanaged(u64, Bytecode.Register) = .empty,
    array_last_items: std.AutoHashMapUnmanaged(NodeIndex, Bytecode.Register) = .empty,
    loop_index_registers: std.AutoHashMapUnmanaged(NodeIndex, Bytecode.Register) = .empty,
    polymorph_types: std.StringHashMapUnmanaged([]const u8) = .empty,
    type_overrides: std.AutoHashMapUnmanaged(NodeIndex, []const u8) = .empty,
    external_registers: std.StringHashMapUnmanaged(Bytecode.Register) = .empty,
    external_lvalue_addresses: std.StringHashMapUnmanaged(Bytecode.Register) = .empty,
    external_types: std.StringHashMapUnmanaged([]const u8) = .empty,
    local_type_decls: std.StringHashMapUnmanaged(NodeIndex) = .empty,
    for_expansion_it_alias: ?[]const u8 = null,
    for_expansion_index_alias: ?[]const u8 = null,
    type_context_parent: ?*GenContext = null,
    binding_option_fields: std.StringHashMapUnmanaged(Bytecode.Register) = .empty,
    emitted_specialized_runs: std.StringHashMapUnmanaged(void) = .empty,
    local_code_bindings: std.ArrayList(CodeBinding) = .empty,
    owned_type_texts: std.ArrayList([]const u8) = .empty,
    return_type_node: NodeIndex = @import("Ast.zig").null_node,
    // Loop control: tracks break/continue patch targets for each active loop.
    loop_stack: std.ArrayList(LoopFrame) = .empty,
    // Deferred statements: LIFO stack, emitted at scope exit.
    defer_stmts: std.ArrayList(NodeIndex) = .empty,
    // Procedure bodies currently inline simple calls for runtime codegen. This
    // stack prevents recursive inlining from turning recursion into compiler recursion.
    inline_stack: std.ArrayList(NodeIndex) = .empty,
    inline_return: ?*InlineReturnFrame = null,

    const CodeBinding = struct {
        decl: NodeIndex,
        name: []const u8,
        code: []const u8,
    };

    const LoopFrame = struct {
        label: []const u8, // empty = anonymous
        continue_target: u32, // instruction index to jump to on 'continue'
        continue_patches: std.ArrayList(usize), // instruction indices to patch when continue target is not known yet
        break_patches: std.ArrayList(usize), // instruction indices to patch on 'break'
        defer_depth: usize, // defer_stmts.items.len at loop entry
    };

    const InlineReturnFrame = struct {
        result_reg: Bytecode.Register,
        result_type: NodeIndex = @import("Ast.zig").null_node,
        defer_depth: usize = 0,
        patches: std.ArrayList(usize) = .empty,
    };

    pub fn deinit(ctx: *GenContext) void {
        ctx.decl_registers.deinit(ctx.program.allocator);
        ctx.pointer_addrs.deinit(ctx.program.allocator);
        ctx.field_values.deinit(ctx.program.allocator);
        ctx.array_last_items.deinit(ctx.program.allocator);
        ctx.loop_index_registers.deinit(ctx.program.allocator);
        ctx.polymorph_types.deinit(ctx.program.allocator);
        ctx.type_overrides.deinit(ctx.program.allocator);
        ctx.external_registers.deinit(ctx.program.allocator);
        ctx.external_lvalue_addresses.deinit(ctx.program.allocator);
        ctx.external_types.deinit(ctx.program.allocator);
        ctx.local_type_decls.deinit(ctx.program.allocator);
        ctx.binding_option_fields.deinit(ctx.program.allocator);
        ctx.emitted_specialized_runs.deinit(ctx.program.allocator);
        for (ctx.loop_stack.items) |*frame| {
            frame.continue_patches.deinit(ctx.program.allocator);
            frame.break_patches.deinit(ctx.program.allocator);
        }
        ctx.loop_stack.deinit(ctx.program.allocator);
        ctx.defer_stmts.deinit(ctx.program.allocator);
        ctx.inline_stack.deinit(ctx.program.allocator);
        ctx.local_code_bindings.deinit(ctx.program.allocator);
        for (ctx.owned_type_texts.items) |text| ctx.program.allocator.free(text);
        ctx.owned_type_texts.deinit(ctx.program.allocator);
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
        const helper_index: u32 = @intCast(ctx.program.procs.items.len);
        var helper_ctx = GenContext{ .ast = ctx.ast, .program = ctx.program, .proc = &helper, .resolved = ctx.resolved, .typed = ctx.typed, .compile_time_host = ctx.compile_time_host, .current_proc_node = proc_node, .current_proc_index = helper_index };
        defer helper_ctx.deinit();
        try helper_ctx.genBlock(ctx.ast.data(proc_node).lhs, diag);
        try helper.instructions.append(ctx.program.allocator, .{ .opcode = .ret_void });
        const idx = try ctx.program.addProc(helper, proc_node);
        return idx;
    }

    fn bindPolymorphTypes(ctx: *GenContext, proc_node: NodeIndex, call_expr: NodeIndex, diag: Diagnostic) !void {
        const sig = procSignature(ctx.ast, proc_node) orelse return;
        const params = ctx.ast.extraSlice(sig.params_extra);
        const args = if (ctx.ast.data(call_expr).rhs < ctx.ast.extra_data.items.len) ctx.ast.extraSlice(ctx.ast.data(call_expr).rhs) else &[_]u32{};
        var arg_index: usize = 0;
        for (params) |param_idx| {
            if (arg_index >= args.len) break;
            const param: NodeIndex = @intCast(param_idx);
            const param_type = ctx.ast.data(param).lhs;
            if (param_type == @import("Ast.zig").null_node) {
                arg_index += 1;
                continue;
            }
            var type_text = std.mem.trim(u8, ctx.nodeSource(param_type), " \t\r\n");
            if (std.mem.startsWith(u8, type_text, "$")) type_text = std.mem.trim(u8, type_text[1..], " \t\r\n");
            const name = firstTypeWord(type_text);
            if (name.len == 0) {
                arg_index += 1;
                continue;
            }
            if (isBuiltinTypeName(name) or ctx.resolved.lookup(name) != null) {
                arg_index += 1;
                continue;
            }
            const arg: NodeIndex = @intCast(args[arg_index]);
            const actual_type = typeTextForExpr(ctx, arg, diag) orelse return diag.failAt(ctx.ast.tokens[ctx.ast.mainToken(arg)].start, "cannot infer polymorphic compile-time argument type for ${s}", .{name});
            try ctx.polymorph_types.put(ctx.program.allocator, name, actual_type);
            arg_index += 1;
        }
    }

    fn bindInlinePolymorphTypes(ctx: *GenContext, params: []const u32, param_args: []const NodeIndex, restores: *std.ArrayList(TypeArgRestore), diag: Diagnostic) !void {
        for (params, 0..) |param_idx, i| {
            const param: NodeIndex = @intCast(param_idx);
            const param_type = ctx.ast.data(param).lhs;
            if (param_type == @import("Ast.zig").null_node) continue;
            var type_text = std.mem.trim(u8, ctx.nodeSource(param_type), " \t\r\n");
            const explicitly_polymorphic = std.mem.startsWith(u8, type_text, "$");
            if (explicitly_polymorphic) type_text = std.mem.trim(u8, type_text[1..], " \t\r\n");
            const name = firstTypeWord(type_text);
            if (name.len == 0) continue;
            if (!explicitly_polymorphic and (isBuiltinTypeName(name) or ctx.resolved.lookup(name) != null)) continue;
            const source = if (i < param_args.len and param_args[i] != @import("Ast.zig").null_node)
                param_args[i]
            else if (ctx.ast.data(param).rhs != @import("Ast.zig").null_node)
                ctx.ast.data(param).rhs
            else
                continue;
            const actual_type = typeTextForExpr(ctx, source, diag) orelse
                return diag.failAt(ctx.ast.tokens[ctx.ast.mainToken(source)].start, "cannot infer polymorphic argument type for ${s}", .{name});
            try restores.append(ctx.program.allocator, .{
                .name = name,
                .had_old = ctx.polymorph_types.contains(name),
                .old = ctx.polymorph_types.get(name) orelse "",
            });
            try ctx.polymorph_types.put(ctx.program.allocator, name, actual_type);
        }
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

    fn tryEmitDirectProcCall(ctx: *GenContext, proc_node: NodeIndex, args: []const u32, call_expr: NodeIndex, diag: Diagnostic) !?Bytecode.Register {
        if (!ctx.allow_root_proc_calls) return null;
        const ast = ctx.ast;
        if (procHasExpandModifierLocal(ast, proc_node)) return null;
        const sig = procSignature(ast, proc_node) orelse return null;
        const params = ast.extraSlice(sig.params_extra);
        if (args.len != params.len) return null;

        const target_index = ctx.procIndexForNode(proc_node) orelse return null;
        var arg_regs = std.ArrayList(Bytecode.Register).empty;
        defer arg_regs.deinit(ctx.program.allocator);
        for (args) |arg_idx| {
            const arg: NodeIndex = @intCast(arg_idx);
            const source = if (ast.tag(arg) == .assign_stmt) ast.data(arg).rhs else arg;
            try arg_regs.append(ctx.program.allocator, try genCallArg(ctx, source, diag));
        }

        const return_type = if (sig.return_type != @import("Ast.zig").null_node)
            try typeIdFromTypeExpr(ast, sig.return_type, diag)
        else
            0;
        if (!typeIdCanUseDirectCall(return_type)) return null;
        for (params) |param_idx| {
            const param: NodeIndex = @intCast(param_idx);
            const param_type = ast.data(param).lhs;
            const param_type_id: u32 = if (param_type != @import("Ast.zig").null_node)
                try typeIdFromTypeExpr(ast, param_type, diag)
            else
                16;
            if (!typeIdCanUseDirectCall(param_type_id)) return null;
        }
        const dest: Bytecode.Register = if (return_type == 0) 0 else blk: {
            const reg = ctx.proc.num_registers;
            ctx.proc.num_registers += 1;
            break :blk reg;
        };
        const arg_start = try ctx.program.addCallArgs(arg_regs.items);
        try ctx.proc.instructions.append(ctx.program.allocator, .{
            .opcode = .call,
            .dest = dest,
            .arg1 = target_index,
            .arg2 = @intCast(arg_regs.items.len),
            .arg3 = arg_start,
            .source_node = call_expr,
        });
        return dest;
    }

    fn typeIdCanUseDirectCall(type_id: u32) bool {
        return type_id == 0 or type_id == 1 or (type_id >= 2 and type_id <= 15);
    }

    fn procIndexForNode(ctx: *GenContext, proc_node: NodeIndex) ?u32 {
        if (proc_node == ctx.current_proc_node) return ctx.current_proc_index;
        for (ctx.program.proc_nodes.items, 0..) |node, index| {
            if (node == proc_node) return @intCast(index);
        }
        return null;
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

    fn tryEmitSelfBinaryAssignment(ctx: *GenContext, lhs: NodeIndex, rhs_node: NodeIndex, source_node: NodeIndex, diag: Diagnostic) !?Bytecode.Register {
        const ast = ctx.ast;
        if (ast.tag(rhs_node) != .binary_expr) return null;
        const rhs_lhs = ast.data(rhs_node).lhs;
        if (!std.mem.eql(u8, ctx.nodeSource(lhs), ctx.nodeSource(rhs_lhs))) return null;
        const op = ast.tokens[ast.mainToken(rhs_node)].tag;
        const compound_op: TokenTag = switch (op) {
            .plus => .plus_equal,
            .minus => .minus_equal,
            .star => .star_equal,
            .slash => .slash_equal,
            .ampersand => .ampersand_equal,
            .pipe => .pipe_equal,
            .caret => .caret_equal,
            else => return null,
        };
        return try ctx.emitCompoundAssignment(lhs, ast.data(rhs_node).rhs, compound_op, source_node, diag);
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
                if (ast.tag(lhs) == .field_access and std.mem.eql(u8, ast.tokenSlice(ast.data(lhs).rhs), "_s64") and isCodeNodeExpression(ctx, ast.data(lhs).lhs, diag)) {
                    const base = try ctx.genExpr(ast.data(lhs).lhs, diag);
                    try ctx.proc.instructions.append(ctx.program.allocator, .{ .opcode = .code_literal_set_s64, .dest = result, .arg1 = base, .arg2 = result, .source_node = source_node });
                    return result;
                }
                const addr = try genAddressOfLvalue(ctx, lhs, diag);
                const store_opcode: Bytecode.Opcode = if (ast.tag(lhs) == .index_expr) blk: {
                    const base_text = typeTextForExpr(ctx, ast.data(lhs).lhs, diag);
                    break :blk if (base_text != null and std.mem.eql(u8, firstTypeWord(base_text.?), "string")) .store_ptr_byte else .store_ptr;
                } else .store_ptr;
                try ctx.proc.instructions.append(ctx.program.allocator, .{ .opcode = store_opcode, .dest = addr, .arg1 = result, .source_node = source_node });
            },
            .unary_expr => {
                const tok = ast.tokens[ast.mainToken(lhs)].tag;
                if (tok == .shift_left or tok == .dot_star) {
                    const ptr = try ctx.genExpr(ast.data(lhs).lhs, diag);
                    try ctx.proc.instructions.append(ctx.program.allocator, .{ .opcode = .store_ptr, .dest = ptr, .arg1 = result, .source_node = source_node });
                }
            },
            .identifier => {
                const name = ast.tokenSlice(ast.mainToken(lhs));
                if (ctx.external_lvalue_addresses.get(name)) |addr| {
                    try ctx.storeExternalLvalue(name, addr, result, source_node, diag);
                    try ctx.external_registers.put(ctx.program.allocator, name, result);
                    return result;
                }
                if (ctx.external_registers.get(name)) |old_reg| {
                    try ctx.proc.instructions.append(ctx.program.allocator, .{ .opcode = .load, .dest = old_reg, .arg1 = result, .source_node = source_node });
                    try ctx.external_registers.put(ctx.program.allocator, name, old_reg);
                    return old_reg;
                }
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
        const elems = if (ast.tag(aggregate) == .typed_aggregate_literal) blk: {
            const payload = ast.extraSlice(ast.data(aggregate).lhs);
            break :blk if (payload.len >= 2) ast.extraSlice(payload[1]) else &[_]u32{};
        } else ast.extraSlice(ast.data(aggregate).lhs);
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
            if (try typeTextIsEmbeddedStruct(ctx, clean_field_type, diag)) {
                const size_reg = try ctx.emitInt(source_node, @intCast(try typeTextSize(ctx, clean_field_type, diag)));
                try ctx.proc.instructions.append(ctx.program.allocator, .{ .opcode = .memcpy, .dest = addr, .arg1 = value_reg, .arg2 = size_reg, .source_node = source_node });
            } else {
                try ctx.proc.instructions.append(ctx.program.allocator, .{ .opcode = .store_ptr, .dest = addr, .arg1 = value_reg, .source_node = source_node });
            }
        }
    }

    fn tryInlineProcCall(ctx: *GenContext, proc_node: NodeIndex, args: []const u32, call_expr: NodeIndex, diag: Diagnostic) !?Bytecode.Register {
        const ast = ctx.ast;
        if (procHasExpandModifierLocal(ast, proc_node)) return null;
        for (ctx.inline_stack.items) |active_proc| if (active_proc == proc_node) return null;
        try ctx.inline_stack.append(ctx.program.allocator, proc_node);
        defer _ = ctx.inline_stack.pop();
        const sig = procSignature(ast, proc_node) orelse {
            if (args.len != 0) return null;
            const result = try ctx.genInlineResultSlot(call_expr, diag);
            var frame = InlineReturnFrame{ .result_reg = result, .defer_depth = ctx.defer_stmts.items.len };
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
        const has_variadic = params.len != 0 and ast.data(@as(NodeIndex, @intCast(params[params.len - 1]))).rhs == 1;
        if (args.len > params.len and !has_variadic) return null;
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
                if (has_variadic and positional_index >= params.len - 1) {
                    positional_index += 1;
                    continue;
                }
                if (positional_index >= params.len) return null;
                param_args[positional_index] = arg;
                positional_index += 1;
            }
        }

        var type_arg_restores = std.ArrayList(TypeArgRestore).empty;
        defer {
            restoreContainerTypeArgs(ctx, type_arg_restores.items) catch {};
            type_arg_restores.deinit(allocator);
        }
        try ctx.bindInlinePolymorphTypes(params, param_args, &type_arg_restores, diag);

        var restores = std.ArrayList(ParamBindingRestore).empty;
        defer restores.deinit(allocator);
        var type_restores = std.ArrayList(TypeOverrideRestore).empty;
        defer {
            ctx.restoreTypeOverrides(type_restores.items) catch {};
            type_restores.deinit(allocator);
        }
        const code_binding_base = ctx.local_code_bindings.items.len;
        defer ctx.local_code_bindings.shrinkRetainingCapacity(code_binding_base);
        for (params, 0..) |param_idx, i| {
            const param: NodeIndex = @intCast(param_idx);
            if (has_variadic and i == params.len - 1) {
                const elem_text = if (ast.data(param).lhs != @import("Ast.zig").null_node) ctx.nodeSource(ast.data(param).lhs) else "Any";
                const elem_size = try typeTextSize(ctx, elem_text, diag);
                const elem_is_struct = try typeTextIsEmbeddedStruct(ctx, elem_text, diag);
                const array_reg = ctx.proc.num_registers;
                ctx.proc.num_registers += 1;
                try ctx.proc.instructions.append(ctx.program.allocator, .{ .opcode = .new_array, .dest = array_reg, .arg1 = 0, .arg2 = @intCast(@max(elem_size, 1)), .arg3 = 8, .source_node = call_expr });
                const slot_reg = ctx.proc.num_registers;
                ctx.proc.num_registers += 1;
                try ctx.proc.instructions.append(ctx.program.allocator, .{ .opcode = .alloc_local_bytes, .dest = slot_reg, .arg1 = 8, .source_node = call_expr });
                try ctx.proc.instructions.append(ctx.program.allocator, .{ .opcode = .store_ptr, .dest = slot_reg, .arg1 = array_reg, .source_node = call_expr });
                for (args[i..]) |var_arg_idx| {
                    const item_reg = try genCallArg(ctx, @intCast(var_arg_idx), diag);
                    const added_reg = ctx.proc.num_registers;
                    ctx.proc.num_registers += 1;
                    try ctx.proc.instructions.append(ctx.program.allocator, .{ .opcode = .array_add, .dest = added_reg, .arg1 = slot_reg, .arg2 = item_reg, .arg3 = @intCast(@max(elem_size, 1)), .arg4 = if (elem_is_struct) 1 else 0, .source_node = call_expr });
                }
                const final_array = ctx.proc.num_registers;
                ctx.proc.num_registers += 1;
                try ctx.proc.instructions.append(ctx.program.allocator, .{ .opcode = .load_ptr, .dest = final_array, .arg1 = slot_reg, .source_node = call_expr });
                const old = ctx.decl_registers.get(param);
                try restores.append(allocator, .{ .decl = param, .had_old = old != null, .old = old orelse 0 });
                try ctx.decl_registers.put(allocator, param, final_array);
                const array_type_text = if (std.mem.eql(u8, firstTypeWord(elem_text), "Allocator"))
                    "[..]Allocator"
                else
                    try std.fmt.allocPrint(ctx.program.allocator, "[..]{s}", .{elem_text});
                try ctx.type_overrides.put(ctx.program.allocator, param, array_type_text);
                continue;
            }
            const source = if (param_args[i] != @import("Ast.zig").null_node)
                param_args[i]
            else if (ast.data(param).rhs != @import("Ast.zig").null_node)
                ast.data(param).rhs
            else
                return null;
            const param_type = ast.data(param).lhs;
            const param_type_text = if (param_type != @import("Ast.zig").null_node) std.mem.trim(u8, ctx.nodeSource(param_type), " \t\r\n") else "";
            const captures_syntax = std.mem.eql(u8, param_type_text, "Code") or isCallerCodeExpr(ast, source);
            const code = if (captures_syntax and !(ast.tag(source) == .meta_expr and ast.tokens[ast.mainToken(source)].tag == .directive_code))
                ctx.nodeSource(source)
            else
                try ctx.codeTextForMacroArg(source, &[_]MacroCodeBinding{}, diag);
            try ctx.rememberLocalCode(param, code);
            const arg_reg = if (param_args[i] == @import("Ast.zig").null_node and isCallerLocationExpr(ast, source))
                try ctx.emitSourceLocation(call_expr, call_expr, diag)
            else if (captures_syntax)
                try ctx.emitString(source, code)
            else
                try genCallArg(ctx, source, diag);
            const old = ctx.decl_registers.get(param);
            try restores.append(allocator, .{ .decl = param, .had_old = old != null, .old = old orelse 0 });
            try ctx.decl_registers.put(allocator, param, arg_reg);
            const inline_type = if (std.mem.eql(u8, param_type_text, "Code"))
                "Code"
            else
                typeTextForExpr(ctx, source, diag);
            if (inline_type) |actual_type| {
                try type_restores.append(allocator, .{
                    .decl = param,
                    .had_old = ctx.type_overrides.contains(param),
                    .old = ctx.type_overrides.get(param) orelse "",
                });
                try ctx.type_overrides.put(ctx.program.allocator, param, actual_type);
            }
        }

        const result = try ctx.genInlineResultSlotForReturn(sig.return_type, call_expr, diag);
        var frame = InlineReturnFrame{ .result_reg = result, .result_type = sig.return_type, .defer_depth = ctx.defer_stmts.items.len };
        defer frame.patches.deinit(allocator);
        const previous_return = ctx.inline_return;
        ctx.inline_return = &frame;
        defer ctx.inline_return = previous_return;
        const previous_proc_node = ctx.current_proc_node;
        ctx.current_proc_node = proc_node;
        defer ctx.current_proc_node = previous_proc_node;
        const stmts = ast.extraSlice(ast.data(ast.data(proc_node).lhs).lhs);
        for (stmts) |stmt_idx| try ctx.genStmt(@intCast(stmt_idx), diag);
        const end_index: u32 = @intCast(ctx.proc.instructions.items.len);
        for (frame.patches.items) |patch| ctx.proc.instructions.items[patch].arg1 = end_index;
        try ctx.restoreParamBindings(restores.items);
        try ctx.restoreTypeOverrides(type_restores.items);
        return result;
    }

    const MacroCodeBinding = struct {
        decl: NodeIndex,
        code: []const u8,
    };

    const TypeOverrideRestore = struct {
        decl: NodeIndex,
        had_old: bool,
        old: []const u8 = "",
    };

    fn localCodeForIdentifier(ctx: *GenContext, ident: NodeIndex) ?[]const u8 {
        const ast = ctx.ast;
        if (ast.tag(ident) != .identifier) return null;
        const name = ast.tokenSlice(ast.mainToken(ident));
        const decl = ctx.resolved.local_values.get(ident) orelse @import("Ast.zig").null_node;
        var i = ctx.local_code_bindings.items.len;
        while (i > 0) {
            i -= 1;
            const binding = ctx.local_code_bindings.items[i];
            if (std.mem.eql(u8, binding.name, name)) return binding.code;
        }
        i = ctx.local_code_bindings.items.len;
        while (i > 0) {
            i -= 1;
            const binding = ctx.local_code_bindings.items[i];
            if (decl != @import("Ast.zig").null_node and binding.decl == decl) return binding.code;
        }
        return null;
    }

    fn rememberLocalCode(ctx: *GenContext, decl: NodeIndex, code: []const u8) !void {
        try ctx.local_code_bindings.append(ctx.program.allocator, .{
            .decl = decl,
            .name = ctx.ast.tokenSlice(ctx.ast.mainToken(decl)),
            .code = code,
        });
    }

    fn rememberLocalTypeDecl(ctx: *GenContext, decl: NodeIndex) !void {
        const ast = ctx.ast;
        if (decl == @import("Ast.zig").null_node or decl >= ast.node_tags.items.len) return;
        if (ast.tag(decl) != .const_decl and ast.tag(decl) != .var_decl) return;

        const value = if (ast.tag(decl) == .const_decl) ast.data(decl).lhs else ast.data(decl).rhs;
        if (value == @import("Ast.zig").null_node) return;
        switch (ast.tag(value)) {
            .struct_type, .union_type, .enum_type, .array_type, .type_expr, .identifier => {
                try ctx.local_type_decls.put(ctx.program.allocator, ast.tokenSlice(ast.mainToken(decl)), value);
            },
            else => {},
        }
    }

    fn tryEmitExpandProcCall(ctx: *GenContext, expr: NodeIndex, diag: Diagnostic) anyerror!bool {
        const ast = ctx.ast;
        if (expr == @import("Ast.zig").null_node or ast.tag(expr) != .call_expr) return false;
        const callee = ast.data(expr).lhs;
        if (ast.tag(callee) != .identifier) return false;
        const name = ast.tokenSlice(ast.mainToken(callee));
        const args = ast.extraSlice(ast.data(expr).rhs);
        const target = ctx.resolveProcCallTarget(callee, name, args.len) orelse return false;
        if (!procHasExpandModifierLocal(ast, target)) return false;
        const sig = procSignature(ast, target) orelse return false;
        const params = ast.extraSlice(sig.params_extra);
        if (args.len > params.len) return diag.failAt(ast.tokens[ast.mainToken(expr)].start, "#expand call has too many arguments", .{});

        var bindings = std.ArrayList(MacroCodeBinding).empty;
        defer bindings.deinit(ctx.program.allocator);
        var param_restores = std.ArrayList(ParamBindingRestore).empty;
        defer param_restores.deinit(ctx.program.allocator);
        var type_restores = std.ArrayList(TypeOverrideRestore).empty;
        defer type_restores.deinit(ctx.program.allocator);
        const code_binding_base = ctx.local_code_bindings.items.len;
        defer ctx.local_code_bindings.shrinkRetainingCapacity(code_binding_base);

        for (params, 0..) |param_idx, i| {
            const param: NodeIndex = @intCast(param_idx);
            const using_default = i >= args.len;
            const arg = if (!using_default) @as(NodeIndex, @intCast(args[i])) else ast.data(param).rhs;
            if (arg == @import("Ast.zig").null_node) return diag.failAt(ast.tokens[ast.mainToken(param)].start, "#expand parameter has no argument or default value", .{});
            const param_type = ast.data(param).lhs;
            const param_type_text = if (param_type != @import("Ast.zig").null_node) std.mem.trim(u8, ctx.nodeSource(param_type), " \t\r\n") else "";
            const captures_syntax = std.mem.eql(u8, param_type_text, "Code") or (using_default and isCallerCodeExpr(ast, arg));
            const actual_is_code_value = !using_default and std.mem.eql(u8, param_type_text, "Code") and ctx.exprNamesCodeValue(arg, diag);
            const code = if (using_default and isCallerCodeExpr(ast, arg))
                ctx.nodeSource(expr)
            else if (captures_syntax and !actual_is_code_value and !(ast.tag(arg) == .meta_expr and ast.tokens[ast.mainToken(arg)].tag == .directive_code))
                ctx.nodeSource(arg)
            else
                try ctx.codeTextForMacroArg(arg, bindings.items, diag);
            try bindings.append(ctx.program.allocator, .{ .decl = param, .code = code });
            try ctx.rememberLocalCode(param, code);
            if (std.mem.eql(u8, param_type_text, "Code") or (using_default and isCallerCodeExpr(ast, arg))) {
                continue;
            }
            try param_restores.append(ctx.program.allocator, .{
                .decl = param,
                .had_old = ctx.decl_registers.contains(param),
                .old = ctx.decl_registers.get(param) orelse 0,
            });
            const arg_reg = try ctx.genExpr(arg, diag);
            try ctx.decl_registers.put(ctx.program.allocator, param, arg_reg);
            if (typeTextForExpr(ctx, arg, diag)) |actual_type| {
                try type_restores.append(ctx.program.allocator, .{
                    .decl = param,
                    .had_old = ctx.type_overrides.contains(param),
                    .old = ctx.type_overrides.get(param) orelse "",
                });
                try ctx.type_overrides.put(ctx.program.allocator, param, actual_type);
            }
        }
        defer ctx.restoreParamBindings(param_restores.items) catch {};
        defer ctx.restoreTypeOverrides(type_restores.items) catch {};

        const body = ast.data(target).lhs;
        if (body == @import("Ast.zig").null_node or ast.tag(body) != .block) return false;
        try ctx.genExpandBlock(body, bindings.items, diag);
        return true;
    }

    fn genExpandBlock(ctx: *GenContext, body: NodeIndex, bindings: []const MacroCodeBinding, diag: Diagnostic) anyerror!void {
        const ast = ctx.ast;
        for (ast.extraSlice(ast.data(body).lhs)) |stmt_idx| {
            const stmt: NodeIndex = @intCast(stmt_idx);
            switch (ast.tag(stmt)) {
                .const_decl, .var_decl => {
                    const init = if (ast.tag(stmt) == .const_decl) ast.data(stmt).lhs else ast.data(stmt).rhs;
                    if (init != @import("Ast.zig").null_node and ast.tag(init) == .run_expr) {
                        const code = try ctx.executeMacroRun(init, bindings, diag);
                        try ctx.rememberLocalCode(stmt, code);
                        continue;
                    }
                    try ctx.genStmt(stmt, diag);
                },
                .meta_stmt => {
                    if (ast.tokens[ast.mainToken(stmt)].tag == .directive_insert) {
                        const inserted = try ctx.codeTextForMacroArg(ast.data(stmt).lhs, bindings, diag);
                        try ctx.emitInsertedCode(inserted, bindings, stmt, diag);
                    } else {
                        try ctx.genStmt(stmt, diag);
                    }
                },
                else => try ctx.genStmt(stmt, diag),
            }
        }
    }

    fn exprNamesCodeValue(ctx: *GenContext, expr: NodeIndex, diag: Diagnostic) bool {
        const ast = ctx.ast;
        if (expr == @import("Ast.zig").null_node or expr >= ast.node_tags.items.len) return false;
        if (ast.tag(expr) == .meta_expr and ast.tokens[ast.mainToken(expr)].tag == .directive_code) return true;
        if (typeTextForExpr(ctx, expr, diag)) |actual_type| {
            if (std.mem.eql(u8, firstTypeWord(actual_type), "Code")) return true;
        }
        if (ast.tag(expr) != .identifier) return false;
        if (ctx.localCodeForIdentifier(expr) != null) return true;
        const decl = ctx.resolved.local_values.get(expr) orelse @import("Ast.zig").null_node;
        if (decl == @import("Ast.zig").null_node or decl >= ast.node_tags.items.len) return false;
        if (ast.tag(decl) != .const_decl and ast.tag(decl) != .var_decl) return false;
        const type_node = if (ast.tag(decl) == .var_decl) ast.data(decl).lhs else ast.data(decl).rhs;
        if (type_node != @import("Ast.zig").null_node and std.mem.eql(u8, firstTypeWord(ctx.nodeSource(type_node)), "Code")) return true;
        const init = if (ast.tag(decl) == .const_decl) ast.data(decl).lhs else ast.data(decl).rhs;
        return init != @import("Ast.zig").null_node and ast.tag(init) == .meta_expr and ast.tokens[ast.mainToken(init)].tag == .directive_code;
    }

    fn tryEmitForExpansion(ctx: *GenContext, stmt: NodeIndex, range: []const u32, diag: Diagnostic) !bool {
        const ast = ctx.ast;
        const is_explicit = range.len == 4 and (range[1] & 0x80000000) != 0;
        const iterated: NodeIndex = @intCast(range[0]);
        const expansion_name = if (is_explicit)
            ast.tokenSlice(range[1] & 0x7fffffff)
        else blk: {
            if (!(range.len == 1 or (range.len == 2 and (range[1] & 0x80000000) != 0) or range.len == 3)) return false;
            const iterated_type = typeTextForExpr(ctx, iterated, diag) orelse return false;
            if (dynamicArrayElementText(iterated_type) != null or staticArrayElementText(iterated_type) != null) return false;
            break :blk "for_expansion";
        };
        const target = ctx.resolveProcCallTarget(stmt, expansion_name, 3) orelse return if (is_explicit)
            diag.failAt(ast.tokens[ast.mainToken(stmt)].start, "unresolved for-expansion macro '{s}'", .{expansion_name})
        else
            false;
        if (!procHasExpandModifierLocal(ast, target)) return if (is_explicit)
            diag.failAt(ast.tokens[ast.mainToken(target)].start, "for-expansion target '{s}' must be marked #expand", .{expansion_name})
        else
            false;
        const sig = procSignature(ast, target) orelse return diag.failAt(ast.tokens[ast.mainToken(target)].start, "for-expansion target '{s}' must have parameters", .{expansion_name});
        const params = ast.extraSlice(sig.params_extra);
        if (params.len < 2) return diag.failAt(ast.tokens[ast.mainToken(target)].start, "for-expansion target '{s}' must accept iterator and body parameters", .{expansion_name});

        var param_restores = std.ArrayList(ParamBindingRestore).empty;
        defer param_restores.deinit(ctx.program.allocator);
        var type_restores = std.ArrayList(TypeOverrideRestore).empty;
        defer type_restores.deinit(ctx.program.allocator);
        var bindings = std.ArrayList(MacroCodeBinding).empty;
        defer bindings.deinit(ctx.program.allocator);
        const code_binding_base = ctx.local_code_bindings.items.len;
        defer ctx.local_code_bindings.shrinkRetainingCapacity(code_binding_base);

        const iterator_param: NodeIndex = @intCast(params[0]);
        try param_restores.append(ctx.program.allocator, .{
            .decl = iterator_param,
            .had_old = ctx.decl_registers.contains(iterator_param),
            .old = ctx.decl_registers.get(iterator_param) orelse 0,
        });
        const iterator_reg = try ctx.genExpr(iterated, diag);
        try ctx.decl_registers.put(ctx.program.allocator, iterator_param, iterator_reg);
        if (typeTextForExpr(ctx, iterated, diag)) |iterated_type| {
            try type_restores.append(ctx.program.allocator, .{
                .decl = iterator_param,
                .had_old = ctx.type_overrides.contains(iterator_param),
                .old = ctx.type_overrides.get(iterator_param) orelse "",
            });
            try ctx.type_overrides.put(ctx.program.allocator, iterator_param, iterated_type);
        }

        const body_param: NodeIndex = @intCast(params[1]);
        const body_code = ctx.nodeSource(ast.data(stmt).rhs);
        try bindings.append(ctx.program.allocator, .{ .decl = body_param, .code = body_code });
        try ctx.rememberLocalCode(body_param, body_code);
        try type_restores.append(ctx.program.allocator, .{
            .decl = body_param,
            .had_old = ctx.type_overrides.contains(body_param),
            .old = ctx.type_overrides.get(body_param) orelse "",
        });
        try ctx.type_overrides.put(ctx.program.allocator, body_param, "Code");

        if (params.len >= 3) {
            const flags_param: NodeIndex = @intCast(params[2]);
            try param_restores.append(ctx.program.allocator, .{
                .decl = flags_param,
                .had_old = ctx.decl_registers.contains(flags_param),
                .old = ctx.decl_registers.get(flags_param) orelse 0,
            });
            try ctx.decl_registers.put(ctx.program.allocator, flags_param, try ctx.emitInt(stmt, 0));
            try type_restores.append(ctx.program.allocator, .{
                .decl = flags_param,
                .had_old = ctx.type_overrides.contains(flags_param),
                .old = ctx.type_overrides.get(flags_param) orelse "",
            });
            try ctx.type_overrides.put(ctx.program.allocator, flags_param, "For_Flags");
        }
        defer ctx.restoreParamBindings(param_restores.items) catch {};
        defer ctx.restoreTypeOverrides(type_restores.items) catch {};

        const old_it_alias = ctx.for_expansion_it_alias;
        const old_index_alias = ctx.for_expansion_index_alias;
        if (is_explicit) {
            ctx.for_expansion_it_alias = if (range[2] & 0x80000000 != 0) ast.tokenSlice(range[2] & 0x7fffffff) else null;
            ctx.for_expansion_index_alias = if (range[3] != 0) ast.tokenSlice(range[3]) else null;
        } else {
            ctx.for_expansion_it_alias = if (range.len >= 2 and (range[1] & 0x80000000) != 0) ast.tokenSlice(range[1] & 0x7fffffff) else null;
            ctx.for_expansion_index_alias = if (range.len >= 3) ast.tokenSlice(range[2]) else null;
        }
        defer {
            ctx.for_expansion_it_alias = old_it_alias;
            ctx.for_expansion_index_alias = old_index_alias;
        }

        const body = ast.data(target).lhs;
        if (body == @import("Ast.zig").null_node or ast.tag(body) != .block) return diag.failAt(ast.tokens[ast.mainToken(target)].start, "for-expansion target '{s}' must have a block body", .{expansion_name});
        try ctx.genExpandBlock(body, bindings.items, diag);
        return true;
    }

    fn restoreTypeOverrides(ctx: *GenContext, restores: []const TypeOverrideRestore) !void {
        for (restores) |restore| {
            if (restore.had_old) {
                try ctx.type_overrides.put(ctx.program.allocator, restore.decl, restore.old);
            } else {
                _ = ctx.type_overrides.remove(restore.decl);
            }
        }
    }

    fn tryEmitLegacyExpandInsertProcCall(ctx: *GenContext, target: NodeIndex, bindings: []const MacroCodeBinding, diag: Diagnostic) !void {
        const ast = ctx.ast;
        const body = ast.data(target).lhs;
        if (body == @import("Ast.zig").null_node or ast.tag(body) != .block) return;
        for (ast.extraSlice(ast.data(body).lhs)) |stmt_idx| {
            const stmt: NodeIndex = @intCast(stmt_idx);
            switch (ast.tag(stmt)) {
                .const_decl, .var_decl => {
                    const init = if (ast.tag(stmt) == .const_decl) ast.data(stmt).lhs else ast.data(stmt).rhs;
                    if (init != @import("Ast.zig").null_node and ast.tag(init) == .run_expr) {
                        _ = try ctx.executeMacroRun(init, bindings, diag);
                    }
                },
                .meta_stmt => {
                    if (ast.tokens[ast.mainToken(stmt)].tag != .directive_insert) continue;
                    const inserted = try ctx.codeTextForMacroArg(ast.data(stmt).lhs, bindings, diag);
                    try ctx.emitInsertedCode(inserted, bindings, stmt, diag);
                },
                else => {},
            }
        }
    }

    fn codeTextForMacroArg(ctx: *GenContext, node: NodeIndex, bindings: []const MacroCodeBinding, diag: Diagnostic) ![]const u8 {
        const ast = ctx.ast;
        if (node == @import("Ast.zig").null_node) return "";
        if (ast.tag(node) == .meta_expr and ast.tokens[ast.mainToken(node)].tag == .directive_insert) {
            if (ast.data(node).rhs != @import("Ast.zig").null_node and ast.tag(ast.data(node).lhs) == .block) {
                return try ctx.executeInsertArrowBlock(ast.data(node).lhs, ast.data(node).rhs, bindings, diag);
            }
            return ctx.codeTextForMacroArg(ast.data(node).lhs, bindings, diag);
        }
        if (ast.tag(node) == .meta_expr and ast.tokens[ast.mainToken(node)].tag == .directive_code) {
            const payload = ast.data(node).lhs;
            return if (payload == @import("Ast.zig").null_node) ctx.codeDirectiveTokenSource(ast.mainToken(node)) else ctx.nodeSource(payload);
        }
        if (ast.tag(node) == .run_expr) {
            return try ctx.executeTextRun(node, bindings, diag);
        }
        if (ctx.typed) |typed| {
            if (typed.comptime_strings.get(node)) |value| return value;
            if (typed.comptime_bytes.get(node)) |value| return value;
        }
        if (ast.tag(node) == .identifier) {
            if (ctx.localCodeForIdentifier(node)) |code| return code;
            const ident_name = ast.tokenSlice(ast.mainToken(node));
            const decl = ctx.resolved.local_values.get(node) orelse @import("Ast.zig").null_node;
            for (bindings) |binding| if (binding.decl == decl) return binding.code;
            for (bindings) |binding| {
                if (std.mem.eql(u8, ast.tokenSlice(ast.mainToken(binding.decl)), ident_name)) return binding.code;
            }
            if (decl != @import("Ast.zig").null_node and decl < ast.node_tags.items.len) {
                if (ctx.typed) |typed| {
                    if (typed.comptime_strings.get(decl)) |value| return value;
                    if (typed.comptime_bytes.get(decl)) |value| return value;
                }
                if (ast.tag(decl) == .const_decl or ast.tag(decl) == .var_decl) {
                    const init = if (ast.tag(decl) == .const_decl) ast.data(decl).lhs else ast.data(decl).rhs;
                    if (init != @import("Ast.zig").null_node) return try ctx.codeTextForMacroArg(init, bindings, diag);
                    if (ctx.resolved.lookup(ident_name)) |sym| switch (sym) {
                        .const_value => |top_decl| if (top_decl != decl and top_decl < ast.node_tags.items.len and ast.tag(top_decl) == .const_decl) {
                            return try ctx.codeTextForMacroArg(ast.data(top_decl).lhs, bindings, diag);
                        },
                        else => {},
                    };
                    if (topLevelConstDeclByName(ast, ident_name)) |top_decl| {
                        if (top_decl != decl) return try ctx.codeTextForMacroArg(ast.data(top_decl).lhs, bindings, diag);
                    }
                }
            }
            if (ctx.resolved.lookup(ident_name)) |sym| switch (sym) {
                .const_value => |top_decl| if (top_decl < ast.node_tags.items.len and ast.tag(top_decl) == .const_decl) {
                    return try ctx.codeTextForMacroArg(ast.data(top_decl).lhs, bindings, diag);
                },
                else => {},
            };
            if (topLevelConstDeclByName(ast, ident_name)) |top_decl| {
                return try ctx.codeTextForMacroArg(ast.data(top_decl).lhs, bindings, diag);
            }
        }
        if (ast.tag(node) == .string_literal) {
            return ast.stringTokenContents(ast.mainToken(node));
        }
        return ctx.nodeSource(node);
    }

    fn executeTextRun(ctx: *GenContext, run_expr: NodeIndex, bindings: []const MacroCodeBinding, diag: Diagnostic) ![]const u8 {
        const result = try ctx.executeRunValue(run_expr, bindings, diag);
        const text = switch (result) {
            .string => |value| value,
            .bytes => |value| value,
            else => return diag.failAt(ctx.ast.tokens[ctx.ast.mainToken(run_expr)].start, "#insert #run must return Code or string", .{}),
        };
        const idx = try ctx.program.addByteArray(text);
        return ctx.program.byte_arrays.items[idx];
    }

    fn executeRunValue(ctx: *GenContext, expr: NodeIndex, bindings: []const MacroCodeBinding, diag: Diagnostic) anyerror!vm_mod.Value {
        const ast = ctx.ast;
        if (expr == @import("Ast.zig").null_node) return .void;
        if (ctx.typed) |typed| {
            if (typed.comptime_ints.get(expr)) |value| return .{ .int = value };
            if (typed.comptime_floats.get(expr)) |value| return .{ .float = value };
            if (typed.comptime_strings.get(expr)) |value| return .{ .string = value };
            if (typed.comptime_bytes.get(expr)) |value| return .{ .bytes = value };
        }
        return switch (ast.tag(expr)) {
            .run_expr => try ctx.executeRunValue(ast.data(expr).lhs, bindings, diag),
            .call_expr => try ctx.executeRunCallValue(expr, bindings, diag),
            .integer_literal, .char_literal, .unary_expr, .binary_expr, .size_of_expr => .{ .int = try evalIntegerConstExpr(ctx, expr, diag) },
            .float_literal => .{ .float = try std.fmt.parseFloat(f64, ast.tokenSlice(ast.mainToken(expr))) },
            .bool_literal => .{ .bool = ast.data(expr).lhs != 2 and ast.data(expr).lhs != 0 },
            .string_literal => blk: {
                const decoded = try decodeString(ctx.program.allocator, ast.stringTokenContents(ast.mainToken(expr)), diag, ast.tokens[ast.mainToken(expr)].start);
                defer ctx.program.allocator.free(decoded);
                const idx = try ctx.program.addByteArray(decoded);
                break :blk .{ .string = ctx.program.byte_arrays.items[idx] };
            },
            .meta_expr => blk: {
                if (ast.tokens[ast.mainToken(expr)].tag == .directive_code) {
                    break :blk .{ .string = try ctx.codeTextForMacroArg(expr, bindings, diag) };
                }
                return diag.failAt(ast.tokens[ast.mainToken(expr)].start, "unsupported #run meta argument", .{});
            },
            .identifier => blk: {
                const name = ast.tokenSlice(ast.mainToken(expr));
                for (bindings) |binding| {
                    if (std.mem.eql(u8, ast.tokenSlice(ast.mainToken(binding.decl)), name)) break :blk .{ .string = binding.code };
                }
                if (ctx.polymorph_types.get(name)) |actual_type| {
                    try ctx.ensureTypeInfoForText(actual_type, diag);
                    break :blk .{ .type_text = actual_type };
                }
                const decl = ctx.resolved.local_values.get(expr) orelse blk_decl: {
                    if (ctx.resolved.lookup(name)) |sym| switch (sym) {
                        .const_value => |node| break :blk_decl node,
                        else => {},
                    };
                    return diag.failAt(ast.tokens[ast.mainToken(expr)].start, "unresolved #run argument '{s}'", .{name});
                };
                if (decl == @import("Ast.zig").null_node or decl >= ast.node_tags.items.len) {
                    return diag.failAt(ast.tokens[ast.mainToken(expr)].start, "unsupported #run argument '{s}'", .{name});
                }
                if (ctx.typed) |typed| {
                    if (typed.comptime_ints.get(decl)) |value| break :blk .{ .int = value };
                    if (typed.comptime_floats.get(decl)) |value| break :blk .{ .float = value };
                    if (typed.comptime_strings.get(decl)) |value| break :blk .{ .string = value };
                    if (typed.comptime_bytes.get(decl)) |value| break :blk .{ .bytes = value };
                }
                if (ast.tag(decl) == .const_decl or ast.tag(decl) == .var_decl) {
                    const init = if (ast.tag(decl) == .const_decl) ast.data(decl).lhs else ast.data(decl).rhs;
                    if (init != @import("Ast.zig").null_node) break :blk try ctx.executeRunValue(init, bindings, diag);
                }
                return diag.failAt(ast.tokens[ast.mainToken(expr)].start, "unsupported #run argument '{s}'", .{name});
            },
            else => return diag.failAt(ast.tokens[ast.mainToken(expr)].start, "unsupported #run argument kind {s}", .{@tagName(ast.tag(expr))}),
        };
    }

    fn executeRunCallValue(ctx: *GenContext, call: NodeIndex, bindings: []const MacroCodeBinding, diag: Diagnostic) anyerror!vm_mod.Value {
        const ast = ctx.ast;
        const callee = ast.data(call).lhs;
        if (callee == @import("Ast.zig").null_node or ast.tag(callee) != .identifier) {
            return diag.failAt(ast.tokens[ast.mainToken(call)].start, "#run currently requires an identifier callee", .{});
        }
        const name = ast.tokenSlice(ast.mainToken(callee));
        const args = ast.extraSlice(ast.data(call).rhs);
        const target = ctx.resolveProcCallTarget(callee, name, args.len) orelse {
            return diag.failAt(ast.tokens[ast.mainToken(callee)].start, "unresolved #run target '{s}'", .{name});
        };
        var program = try generateProcForCall(ctx.program.allocator, ast, ctx.resolved, ctx.typed, target, call, diag);
        defer program.deinit();
        var values = std.ArrayList(vm_mod.Value).empty;
        defer values.deinit(ctx.program.allocator);
        for (args) |arg_idx| {
            const value = try ctx.executeRunValue(@intCast(arg_idx), bindings, diag);
            switch (value) {
                .type_text => |type_text| {
                    try ctx.ensureTypeInfoForText(type_text, diag);
                    const type_name = firstTypeWord(stripPointerText(type_text));
                    if (ctx.program.typeInfoIndexByName(type_name)) |info_index| {
                        const info = ctx.program.type_infos.items[info_index];
                        _ = try program.addTypeInfo(info.name, info.tag, info.members);
                    }
                },
                else => {},
            }
            try values.append(ctx.program.allocator, value);
        }
        var vm = vm_mod.VM.init(ctx.program.allocator, &program);
        defer vm.deinit();
        return try ctx.copyRunValue(try vm.runProcWithArgs(program.main_proc.?, values.items, diag));
    }

    fn copyRunValue(ctx: *GenContext, value: vm_mod.Value) !vm_mod.Value {
        return switch (value) {
            .string => |text| blk: {
                const idx = try ctx.program.addByteArray(text);
                break :blk .{ .string = ctx.program.byte_arrays.items[idx] };
            },
            .bytes => |bytes| blk: {
                const idx = try ctx.program.addByteArray(bytes);
                break :blk .{ .bytes = ctx.program.byte_arrays.items[idx] };
            },
            .type_text => |text| blk: {
                const idx = try ctx.program.addByteArray(text);
                break :blk .{ .type_text = ctx.program.byte_arrays.items[idx] };
            },
            else => value,
        };
    }

    fn executeMacroRun(ctx: *GenContext, run_expr: NodeIndex, bindings: []const MacroCodeBinding, diag: Diagnostic) ![]const u8 {
        const ast = ctx.ast;
        const call = ast.data(run_expr).lhs;
        if (call == @import("Ast.zig").null_node or ast.tag(call) != .call_expr) return diag.failAt(ast.tokens[ast.mainToken(run_expr)].start, "#expand currently requires #run of a procedure call", .{});
        const callee = ast.data(call).lhs;
        if (ast.tag(callee) != .identifier) return diag.failAt(ast.tokens[ast.mainToken(callee)].start, "#expand #run currently requires an identifier callee", .{});
        const name = ast.tokenSlice(ast.mainToken(callee));
        const args = ast.extraSlice(ast.data(call).rhs);
        const target = ctx.resolveProcCallTarget(callee, name, args.len) orelse return diag.failAt(ast.tokens[ast.mainToken(callee)].start, "unresolved #expand #run target '{s}'", .{name});
        var program = try generateProcForCall(ctx.program.allocator, ast, ctx.resolved, ctx.typed, target, call, diag);
        defer program.deinit();
        var values = std.ArrayList(vm_mod.Value).empty;
        defer values.deinit(ctx.program.allocator);
        for (args) |arg_idx| {
            const arg: NodeIndex = @intCast(arg_idx);
            try values.append(ctx.program.allocator, .{ .string = try ctx.codeTextForMacroArg(arg, bindings, diag) });
        }
        var vm = vm_mod.VM.init(ctx.program.allocator, &program);
        defer vm.deinit();
        const result = try vm.runProcWithArgs(program.main_proc.?, values.items, diag);
        return switch (result) {
            .string => |value| blk: {
                const idx = try ctx.program.addByteArray(value);
                break :blk ctx.program.byte_arrays.items[idx];
            },
            .bytes => |value| blk: {
                const idx = try ctx.program.addByteArray(value);
                break :blk ctx.program.byte_arrays.items[idx];
            },
            else => diag.failAt(ast.tokens[ast.mainToken(run_expr)].start, "#expand #run must return Code or string", .{}),
        };
    }

    fn executeInsertArrowBlock(ctx: *GenContext, block: NodeIndex, return_type: NodeIndex, bindings: []const MacroCodeBinding, diag: Diagnostic) ![]const u8 {
        const ast = ctx.ast;
        const return_type_text = std.mem.trim(u8, ctx.nodeSource(return_type), " \t\r\n");
        if (!std.mem.eql(u8, return_type_text, "string") and !std.mem.eql(u8, return_type_text, "Code")) {
            return diag.failAt(ast.tokens[ast.mainToken(return_type)].start, "#insert -> currently requires string or Code return type", .{});
        }

        var program = Bytecode.Program.init(ctx.program.allocator);
        defer program.deinit();
        var proc = Bytecode.ProcBytecode{ .name = "#insert_arrow" };
        var proc_owned_by_program = false;
        errdefer if (!proc_owned_by_program) proc.deinit(ctx.program.allocator);
        proc.return_type = 14;
        var exec_ctx = GenContext{
            .ast = ast,
            .resolved = ctx.resolved,
            .typed = ctx.typed,
            .program = &program,
            .proc = &proc,
            .current_proc_node = @import("Ast.zig").null_node,
            .current_proc_index = 0,
            .allow_root_proc_calls = true,
            .compile_time_host = true,
            .return_type_node = return_type,
        };
        defer exec_ctx.deinit();

        for (bindings) |binding| {
            const reg = try exec_ctx.emitMacroBindingValue(binding.decl, binding.code, block, diag);
            try exec_ctx.decl_registers.put(ctx.program.allocator, binding.decl, reg);
        }
        for (ctx.local_code_bindings.items) |binding| {
            if (exec_ctx.decl_registers.contains(binding.decl)) continue;
            const reg = try exec_ctx.emitMacroBindingValue(binding.decl, binding.code, block, diag);
            try exec_ctx.decl_registers.put(ctx.program.allocator, binding.decl, reg);
        }

        try exec_ctx.genBlock(block, diag);
        try proc.instructions.append(ctx.program.allocator, .{ .opcode = .ret_void, .source_node = block });
        _ = try program.addProc(proc, @import("Ast.zig").null_node);
        proc_owned_by_program = true;
        program.main_proc = 0;

        var vm = vm_mod.VM.init(ctx.program.allocator, &program);
        defer vm.deinit();
        const result = try vm.runProc(program.main_proc.?, diag);
        const text = switch (result) {
            .string => |value| value,
            .bytes => |value| value,
            else => return diag.failAt(ast.tokens[ast.mainToken(block)].start, "#insert -> string/Code block returned a non-text value", .{}),
        };
        const idx = try ctx.program.addByteArray(text);
        return ctx.program.byte_arrays.items[idx];
    }

    fn emitMacroBindingValue(ctx: *GenContext, decl: NodeIndex, code: []const u8, source_node: NodeIndex, diag: Diagnostic) !Bytecode.Register {
        const ast = ctx.ast;
        const type_node = if (decl != @import("Ast.zig").null_node and decl < ast.node_tags.items.len and ast.tag(decl) == .var_decl) ast.data(decl).lhs else @import("Ast.zig").null_node;
        const type_text = if (type_node != @import("Ast.zig").null_node) std.mem.trim(u8, ctx.nodeSource(type_node), " \t\r\n") else "";
        if (std.mem.eql(u8, type_text, "int") or std.mem.eql(u8, type_text, "s64") or std.mem.eql(u8, type_text, "s32") or std.mem.eql(u8, type_text, "u64") or std.mem.eql(u8, type_text, "u32")) {
            const value = std.fmt.parseInt(i64, std.mem.trim(u8, code, " \t\r\n"), 10) catch |err| {
                return diag.failAt(ast.tokens[ast.mainToken(source_node)].start, "macro integer argument '{s}' is not a constant integer: {s}", .{ code, @errorName(err) });
            };
            return try ctx.emitInt(source_node, value);
        }
        return try ctx.emitString(source_node, code);
    }

    fn genCodeValueExpr(ctx: *GenContext, arg: NodeIndex, source_node: NodeIndex, diag: Diagnostic) !Bytecode.Register {
        const ast = ctx.ast;
        if (arg != @import("Ast.zig").null_node) {
            if (ast.tag(arg) == .meta_expr and ast.tokens[ast.mainToken(arg)].tag == .directive_code) {
                return try ctx.emitString(source_node, try ctx.codeTextForMacroArg(arg, &[_]MacroCodeBinding{}, diag));
            }
            if (ast.tag(arg) == .identifier) {
                if (ctx.localCodeForIdentifier(arg)) |code| {
                    return try ctx.emitString(source_node, code);
                }
            }
        }
        return try ctx.genExpr(arg, diag);
    }

    fn emitInsertedCode(ctx: *GenContext, raw: []const u8, bindings: []const MacroCodeBinding, source_node: NodeIndex, diag: Diagnostic) !void {
        const expanded = try ctx.expandGeneratedInsertDirectives(std.mem.trim(u8, raw, " \t\r\n;"), bindings, source_node, diag);
        defer ctx.program.allocator.free(expanded);
        var code = std.mem.trim(u8, expanded, " \t\r\n");
        if (std.mem.startsWith(u8, code, "{") and std.mem.endsWith(u8, code, "}")) {
            code = std.mem.trim(u8, code[1 .. code.len - 1], " \t\r\n;");
        }
        if (shouldParseInsertedCode(code)) {
            return try ctx.emitParsedInsertedCode(code, source_node, diag);
        }
        var rest = code;
        while (rest.len != 0) {
            const semi = std.mem.indexOfScalar(u8, rest, ';') orelse rest.len;
            const stmt = std.mem.trim(u8, rest[0..semi], " \t\r\n");
            if (stmt.len != 0) try ctx.emitSimpleInsertedStatement(stmt, source_node, diag);
            rest = if (semi < rest.len) rest[semi + 1 ..] else "";
        }
    }

    fn expandGeneratedInsertDirectives(ctx: *GenContext, raw: []const u8, bindings: []const MacroCodeBinding, source_node: NodeIndex, diag: Diagnostic) ![]const u8 {
        const allocator = ctx.program.allocator;
        var out = std.ArrayList(u8).empty;
        errdefer out.deinit(allocator);
        var i: usize = 0;
        while (i < raw.len) {
            if (!std.mem.startsWith(u8, raw[i..], "#insert")) {
                try out.append(allocator, raw[i]);
                i += 1;
                continue;
            }
            var cursor = i + "#insert".len;
            while (cursor < raw.len and std.ascii.isWhitespace(raw[cursor])) cursor += 1;
            const name_start = cursor;
            if (cursor >= raw.len or !(std.ascii.isAlphabetic(raw[cursor]) or raw[cursor] == '_')) {
                try out.appendSlice(allocator, raw[i .. i + "#insert".len]);
                i += "#insert".len;
                continue;
            }
            cursor += 1;
            while (cursor < raw.len and (std.ascii.isAlphanumeric(raw[cursor]) or raw[cursor] == '_')) cursor += 1;
            const name = raw[name_start..cursor];
            while (cursor < raw.len and std.ascii.isWhitespace(raw[cursor])) cursor += 1;
            if (cursor < raw.len and raw[cursor] == ';') cursor += 1;
            var found: ?[]const u8 = null;
            for (bindings) |binding| {
                if (std.mem.eql(u8, ctx.ast.tokenSlice(ctx.ast.mainToken(binding.decl)), name)) {
                    found = binding.code;
                    break;
                }
            }
            if (found == null) {
                var binding_index = ctx.local_code_bindings.items.len;
                while (binding_index > 0) {
                    binding_index -= 1;
                    const binding = ctx.local_code_bindings.items[binding_index];
                    if (std.mem.eql(u8, binding.name, name)) {
                        found = binding.code;
                        break;
                    }
                }
            }
            if (found) |replacement| {
                var clean_replacement = std.mem.trim(u8, replacement, " \t\r\n");
                if (std.mem.startsWith(u8, clean_replacement, "{") and std.mem.endsWith(u8, clean_replacement, "}")) {
                    clean_replacement = std.mem.trim(u8, clean_replacement[1 .. clean_replacement.len - 1], " \t\r\n;");
                }
                try out.appendSlice(allocator, clean_replacement);
                if (clean_replacement.len == 0 or clean_replacement[clean_replacement.len - 1] != '\n') try out.append(allocator, '\n');
                i = cursor;
            } else {
                return diag.failAt(ctx.ast.tokens[ctx.ast.mainToken(source_node)].start, "generated #insert target '{s}' is unresolved", .{name});
            }
        }
        return try out.toOwnedSlice(allocator);
    }

    fn shouldParseInsertedCode(code: []const u8) bool {
        return std.mem.indexOf(u8, code, ":") != null or
            std.mem.indexOfScalar(u8, code, '=') != null or
            std.mem.indexOf(u8, code, "print(") != null or
            std.mem.indexOf(u8, code, "for ") != null or
            std.mem.indexOf(u8, code, "if ") != null or
            std.mem.indexOf(u8, code, "#insert") != null;
    }

    fn emitParsedInsertedCode(ctx: *GenContext, code: []const u8, source_node: NodeIndex, diag: Diagnostic) !void {
        const allocator = ctx.program.allocator;
        const suffix: []const u8 = if (insertedStatementNeedsSemicolon(code)) ";" else "";
        var visible_procs = std.ArrayList(u8).empty;
        defer visible_procs.deinit(allocator);
        try ctx.appendVisibleInsertedProcSources(&visible_procs);
        const source = try std.fmt.allocPrint(allocator, "#import \"Basic\";\n{s}\nmain :: () {{\n{s}{s}\n}}\n", .{ visible_procs.items, code, suffix });
        defer allocator.free(source);

        const lexer = @import("lexer.zig");
        const parser = @import("parser.zig");
        const resolve_mod = @import("resolve.zig");
        const insert_diag = Diagnostic.init(allocator, "#insert", source);
        var tokens = try lexer.tokenize(allocator, source, insert_diag);
        defer tokens.deinit(allocator);
        const slice = tokens.slice();
        var inserted_ast = try parser.parse(allocator, source, slice.items(.tag), slice.items(.start), slice.items(.end), insert_diag);
        defer {
            allocator.free(inserted_ast.tokens);
            inserted_ast.deinit();
        }
        var inserted_resolved = try resolve_mod.resolve(allocator, &inserted_ast, insert_diag, true);
        defer inserted_resolved.deinit();
        const main_proc = inserted_resolved.main_proc orelse return diag.failAt(ctx.ast.tokens[ctx.ast.mainToken(source_node)].start, "generated #insert code did not contain a main block", .{});
        var child_ctx = GenContext{
            .ast = &inserted_ast,
            .resolved = &inserted_resolved,
            .typed = null,
            .program = ctx.program,
            .proc = ctx.proc,
            .allow_root_proc_calls = true,
            .compile_time_host = ctx.compile_time_host,
            .current_proc_node = main_proc,
            .current_proc_index = ctx.current_proc_index,
            .type_context_parent = ctx,
        };
        defer child_ctx.deinit();
        try ctx.exportVisibleValueNames(&child_ctx, diag);
        try child_ctx.genBlock(inserted_ast.data(main_proc).lhs, insert_diag);
        try ctx.importInsertedLocals(&child_ctx, main_proc, diag);
    }

    fn appendVisibleInsertedProcSources(ctx: *GenContext, out: *std.ArrayList(u8)) !void {
        const ast = ctx.ast;
        if (ast.root == @import("Ast.zig").null_node) return;
        const decls = ast.extraSlice(ast.data(ast.root).lhs);
        for (decls) |decl_idx| {
            const decl: NodeIndex = @intCast(decl_idx);
            if (decl == ctx.current_proc_node or decl >= ast.node_tags.items.len or ast.tag(decl) != .proc_decl) continue;
            if (procHasExpandModifierLocal(ast, decl) or procContainsCompileTimeOnlyCompilerApi(ast, decl)) continue;
            try out.appendSlice(ctx.program.allocator, topLevelDeclSourceText(ast, decl));
            try out.appendSlice(ctx.program.allocator, "\n");
        }
    }

    fn topLevelDeclSourceText(ast: *const Ast, decl: NodeIndex) []const u8 {
        var end = ast.tokens[ast.mainToken(decl)].end;
        collectNodeEnd(ast, decl, &end);
        return std.mem.trim(u8, ast.source[ast.tokens[ast.mainToken(decl)].start..@min(end, ast.source.len)], " \t\r\n;");
    }

    fn insertedStatementNeedsSemicolon(code: []const u8) bool {
        const clean = std.mem.trim(u8, code, " \t\r\n");
        if (clean.len == 0) return false;
        const last = clean[clean.len - 1];
        if (last == ';' or last == '}') return false;
        return std.mem.indexOfScalar(u8, clean, '=') != null or
            std.mem.indexOf(u8, clean, "if ") != null or
            std.mem.startsWith(u8, clean, "return ") or
            std.mem.indexOf(u8, clean, "print(") != null;
    }

    fn emitParsedInsertedExpression(ctx: *GenContext, code: []const u8, source_node: NodeIndex, diag: Diagnostic) !Bytecode.Register {
        const allocator = ctx.program.allocator;
        const source = try std.fmt.allocPrint(allocator, "main :: () {{\n__openjai_insert_value := ({s});\n}}\n", .{std.mem.trim(u8, code, " \t\r\n;")});
        defer allocator.free(source);

        const lexer = @import("lexer.zig");
        const parser = @import("parser.zig");
        const resolve_mod = @import("resolve.zig");
        const insert_diag = Diagnostic.init(allocator, "#insert-expression", source);
        var tokens = try lexer.tokenize(allocator, source, insert_diag);
        defer tokens.deinit(allocator);
        const slice = tokens.slice();
        var inserted_ast = try parser.parse(allocator, source, slice.items(.tag), slice.items(.start), slice.items(.end), insert_diag);
        defer {
            allocator.free(inserted_ast.tokens);
            inserted_ast.deinit();
        }
        var inserted_resolved = try resolve_mod.resolve(allocator, &inserted_ast, insert_diag, false);
        defer inserted_resolved.deinit();
        const main_proc = inserted_resolved.main_proc orelse return diag.failAt(ctx.ast.tokens[ctx.ast.mainToken(source_node)].start, "generated #insert expression did not contain a main block", .{});
        const block = inserted_ast.data(main_proc).lhs;
        const stmts = inserted_ast.extraSlice(inserted_ast.data(block).lhs);
        if (stmts.len != 1) return diag.failAt(ctx.ast.tokens[ctx.ast.mainToken(source_node)].start, "generated #insert expression wrapper is malformed", .{});
        const stmt: NodeIndex = @intCast(stmts[0]);
        if (inserted_ast.tag(stmt) != .const_decl and inserted_ast.tag(stmt) != .var_decl) {
            return diag.failAt(ctx.ast.tokens[ctx.ast.mainToken(source_node)].start, "generated #insert expression wrapper did not produce a value declaration", .{});
        }
        const value_expr = if (inserted_ast.tag(stmt) == .const_decl) inserted_ast.data(stmt).lhs else inserted_ast.data(stmt).rhs;
        var child_ctx = GenContext{
            .ast = &inserted_ast,
            .resolved = &inserted_resolved,
            .typed = null,
            .program = ctx.program,
            .proc = ctx.proc,
            .allow_root_proc_calls = true,
            .compile_time_host = ctx.compile_time_host,
            .current_proc_node = main_proc,
            .current_proc_index = ctx.current_proc_index,
            .type_context_parent = ctx,
        };
        defer child_ctx.deinit();
        try ctx.exportVisibleValueNames(&child_ctx, diag);
        const value = try child_ctx.genExpr(value_expr, insert_diag);
        const copy = ctx.proc.num_registers;
        ctx.proc.num_registers += 1;
        const value_type = typeTextForExpr(&child_ctx, value_expr, insert_diag);
        if (value_type != null and (std.mem.eql(u8, firstTypeWord(value_type.?), "int") or std.mem.eql(u8, firstTypeWord(value_type.?), "s64") or std.mem.eql(u8, firstTypeWord(value_type.?), "u8") or std.mem.eql(u8, firstTypeWord(value_type.?), "s32"))) {
            const zero = ctx.proc.num_registers;
            ctx.proc.num_registers += 1;
            try ctx.proc.instructions.append(ctx.program.allocator, .{ .opcode = .load_int, .dest = zero, .arg1 = 0, .source_node = source_node });
            try ctx.proc.instructions.append(ctx.program.allocator, .{ .opcode = .add_int, .dest = copy, .arg1 = value, .arg2 = zero, .source_node = source_node });
        } else {
            try ctx.proc.instructions.append(ctx.program.allocator, .{ .opcode = .load, .dest = copy, .arg1 = value, .source_node = source_node });
        }
        return copy;
    }

    fn typeIdForCodeText(ctx: *GenContext, code: []const u8, source_node: NodeIndex, diag: Diagnostic) !u32 {
        const allocator = ctx.program.allocator;
        const source = try std.fmt.allocPrint(allocator, "main :: () {{\n__openjai_code_type_value := ({s});\n}}\n", .{std.mem.trim(u8, code, " \t\r\n;")});
        defer allocator.free(source);

        const lexer = @import("lexer.zig");
        const parser = @import("parser.zig");
        const resolve_mod = @import("resolve.zig");
        const type_diag = Diagnostic.init(allocator, "#code-type", source);
        var tokens = try lexer.tokenize(allocator, source, type_diag);
        defer tokens.deinit(allocator);
        const slice = tokens.slice();
        var code_ast = try parser.parse(allocator, source, slice.items(.tag), slice.items(.start), slice.items(.end), type_diag);
        defer {
            allocator.free(code_ast.tokens);
            code_ast.deinit();
        }
        var code_resolved = try resolve_mod.resolve(allocator, &code_ast, type_diag, false);
        defer code_resolved.deinit();
        const main_proc = code_resolved.main_proc orelse return diag.failAt(ctx.ast.tokens[ctx.ast.mainToken(source_node)].start, "Code.type could not wrap captured code as an expression", .{});
        const block = code_ast.data(main_proc).lhs;
        const stmts = code_ast.extraSlice(code_ast.data(block).lhs);
        if (stmts.len != 1) return diag.failAt(ctx.ast.tokens[ctx.ast.mainToken(source_node)].start, "Code.type expression wrapper is malformed", .{});
        const stmt: NodeIndex = @intCast(stmts[0]);
        if (code_ast.tag(stmt) != .const_decl and code_ast.tag(stmt) != .var_decl) {
            return diag.failAt(ctx.ast.tokens[ctx.ast.mainToken(source_node)].start, "Code.type wrapper did not produce a value declaration", .{});
        }
        const value_expr = if (code_ast.tag(stmt) == .const_decl) code_ast.data(stmt).lhs else code_ast.data(stmt).rhs;
        var child_ctx = GenContext{
            .ast = &code_ast,
            .resolved = &code_resolved,
            .typed = null,
            .program = ctx.program,
            .proc = ctx.proc,
            .allow_root_proc_calls = true,
            .compile_time_host = ctx.compile_time_host,
            .current_proc_node = main_proc,
            .current_proc_index = ctx.current_proc_index,
            .type_context_parent = ctx,
        };
        defer child_ctx.deinit();
        try ctx.exportVisibleValueNames(&child_ctx, diag);
        const type_text = typeTextForExpr(&child_ctx, value_expr, type_diag) orelse {
            return diag.failAt(ctx.ast.tokens[ctx.ast.mainToken(source_node)].start, "Code.type cannot infer the type of captured code '{s}'", .{code});
        };
        return typeIdFromTypeText(type_text);
    }

    fn exportVisibleValueNames(ctx: *GenContext, child: *GenContext, diag: Diagnostic) !void {
        var inherited_regs = ctx.external_registers.iterator();
        while (inherited_regs.next()) |entry| {
            try child.external_registers.put(child.program.allocator, entry.key_ptr.*, entry.value_ptr.*);
        }
        var inherited_lvalues = ctx.external_lvalue_addresses.iterator();
        while (inherited_lvalues.next()) |entry| {
            try child.external_lvalue_addresses.put(child.program.allocator, entry.key_ptr.*, entry.value_ptr.*);
        }
        var inherited_types = ctx.external_types.iterator();
        while (inherited_types.next()) |entry| {
            try child.external_types.put(child.program.allocator, entry.key_ptr.*, entry.value_ptr.*);
        }
        try ctx.exportTopLevelMutableValues(child, diag);
        var it = ctx.decl_registers.iterator();
        while (it.next()) |entry| {
            const decl = entry.key_ptr.*;
            if (decl == @import("Ast.zig").null_node or decl >= ctx.ast.node_tags.items.len) continue;
            switch (ctx.ast.tag(decl)) {
                .var_decl, .const_decl, .placeholder_decl => {},
                .for_stmt => {
                    const range = ctx.ast.extraSlice(ctx.ast.data(decl).lhs);
                    const iterator_name = forStmtIteratorName(ctx.ast, range) orelse continue;
                    const name = externalNameForSourceName(iterator_name);
                    try child.external_registers.put(child.program.allocator, name, entry.value_ptr.*);
                    if (ctx.type_overrides.get(decl)) |ty| try child.external_types.put(child.program.allocator, name, ty);
                    if (std.mem.eql(u8, name, "it")) {
                        if (ctx.for_expansion_it_alias) |alias| {
                            try child.external_registers.put(child.program.allocator, alias, entry.value_ptr.*);
                            if (ctx.type_overrides.get(decl)) |ty| try child.external_types.put(child.program.allocator, alias, ty);
                        }
                    }
                    if (forStmtIndexName(ctx.ast, range)) |index_name_raw| {
                        if (ctx.loop_index_registers.get(decl)) |index_reg| {
                            const index_name = externalNameForSourceName(index_name_raw);
                            try child.external_registers.put(child.program.allocator, index_name, index_reg);
                            try child.external_types.put(child.program.allocator, index_name, "int");
                            if (std.mem.eql(u8, index_name, "it_index")) {
                                if (ctx.for_expansion_index_alias) |alias| {
                                    try child.external_registers.put(child.program.allocator, alias, index_reg);
                                    try child.external_types.put(child.program.allocator, alias, "int");
                                }
                            }
                        }
                    }
                    continue;
                },
                else => continue,
            }
            const name = externalNameForSourceName(ctx.ast.tokenSlice(ctx.ast.mainToken(decl)));
            try child.external_registers.put(child.program.allocator, name, entry.value_ptr.*);
            if (typeTextForDecl(ctx, decl, diag)) |ty| {
                try child.external_types.put(child.program.allocator, name, ty);
            }
            if (std.mem.eql(u8, name, "it")) {
                if (ctx.for_expansion_it_alias) |alias| {
                    try child.external_registers.put(child.program.allocator, alias, entry.value_ptr.*);
                    if (typeTextForDecl(ctx, decl, diag)) |ty| try child.external_types.put(child.program.allocator, alias, ty);
                }
            } else if (std.mem.eql(u8, name, "it_index")) {
                if (ctx.for_expansion_index_alias) |alias| {
                    try child.external_registers.put(child.program.allocator, alias, entry.value_ptr.*);
                    if (typeTextForDecl(ctx, decl, diag)) |ty| try child.external_types.put(child.program.allocator, alias, ty);
                }
            }
        }
        if (procSignature(ctx.ast, ctx.current_proc_node)) |sig| {
            const params = ctx.ast.extraSlice(sig.params_extra);
            for (params) |param_idx| {
                const param: NodeIndex = @intCast(param_idx);
                const reg = ctx.decl_registers.get(param) orelse continue;
                const name = externalNameForSourceName(ctx.ast.tokenSlice(ctx.ast.mainToken(param)));
                try child.external_registers.put(child.program.allocator, name, reg);
                if (typeTextForDecl(ctx, param, diag)) |ty| {
                    try child.external_types.put(child.program.allocator, name, ty);
                }
            }
        }
    }

    fn exportTopLevelMutableValues(ctx: *GenContext, child: *GenContext, diag: Diagnostic) !void {
        if (ctx.ast.root == @import("Ast.zig").null_node) return;
        for (ctx.ast.extraSlice(ctx.ast.data(ctx.ast.root).lhs)) |decl_idx| {
            const decl: NodeIndex = @intCast(decl_idx);
            if (decl >= ctx.ast.node_tags.items.len or ctx.ast.tag(decl) != .var_decl) continue;
            const raw_name = ctx.ast.tokenSlice(ctx.ast.mainToken(decl));
            const name = externalNameForSourceName(raw_name);
            if (child.external_lvalue_addresses.contains(name)) continue;
            const type_text = typeTextForDecl(ctx, decl, diag) orelse "int";
            const addr = try ctx.emitGlobalAddress(decl, decl, type_text, diag);
            const value = try emitLoadFromAddressForType(ctx, addr, type_text, decl, diag);
            try child.external_registers.put(child.program.allocator, name, value);
            try child.external_lvalue_addresses.put(child.program.allocator, name, addr);
            try child.external_types.put(child.program.allocator, name, type_text);
        }
    }

    fn importInsertedLocals(ctx: *GenContext, child: *GenContext, child_proc: NodeIndex, diag: Diagnostic) !void {
        const block = child.ast.data(child_proc).lhs;
        if (block == @import("Ast.zig").null_node or child.ast.tag(block) != .block) return;
        for (child.ast.extraSlice(child.ast.data(block).lhs)) |stmt_idx| {
            const stmt: NodeIndex = @intCast(stmt_idx);
            if (stmt >= child.ast.node_tags.items.len) continue;
            switch (child.ast.tag(stmt)) {
                .var_decl, .const_decl => {},
                else => continue,
            }
            const reg = child.decl_registers.get(stmt) orelse continue;
            const raw_name = externalNameForSourceName(child.ast.tokenSlice(child.ast.mainToken(stmt)));
            const name = ctx.external_registers.getKey(raw_name) orelse blk: {
                const name_index = try ctx.program.addByteArray(raw_name);
                break :blk ctx.program.byte_arrays.items[name_index];
            };
            try ctx.external_registers.put(ctx.program.allocator, name, reg);
            if (typeTextForDecl(child, stmt, diag)) |ty| {
                const ty_index = try ctx.program.addByteArray(ty);
                try ctx.external_types.put(ctx.program.allocator, name, ctx.program.byte_arrays.items[ty_index]);
            }
        }
    }

    fn emitSimpleInsertedStatement(ctx: *GenContext, stmt: []const u8, source_node: NodeIndex, diag: Diagnostic) !void {
        const ops = [_]struct { text: []const u8, tag: TokenTag }{
            .{ .text = "*=", .tag = .star_equal },
            .{ .text = "+=", .tag = .plus_equal },
            .{ .text = "-=", .tag = .minus_equal },
            .{ .text = "/=", .tag = .slash_equal },
            .{ .text = "=", .tag = .equal },
        };
        for (ops) |op| {
            if (std.mem.indexOf(u8, stmt, op.text)) |pos| {
                const lhs_name = std.mem.trim(u8, stmt[0..pos], " \t\r\n");
                const rhs_text = std.mem.trim(u8, stmt[pos + op.text.len ..], " \t\r\n");
                const lhs_decl = ctx.resolved.lookup(lhs_name) orelse return diag.failAt(ctx.ast.tokens[ctx.ast.mainToken(source_node)].start, "#insert target '{s}' is unresolved", .{lhs_name});
                const decl = switch (lhs_decl) {
                    .const_value => |node| node,
                    else => return diag.failAt(ctx.ast.tokens[ctx.ast.mainToken(source_node)].start, "#insert target '{s}' is not assignable", .{lhs_name}),
                };
                const rhs_value = std.fmt.parseInt(i64, rhs_text, 10) catch |err| return diag.failAt(ctx.ast.tokens[ctx.ast.mainToken(source_node)].start, "#insert currently requires integer literal RHS, got '{s}': {s}", .{ rhs_text, @errorName(err) });
                const lhs_reg = if (ctx.decl_registers.get(decl)) |reg| reg else blk: {
                    const reg = try ctx.emitGlobalAddress(decl, source_node, "int", diag);
                    const value = ctx.proc.num_registers;
                    ctx.proc.num_registers += 1;
                    try ctx.proc.instructions.append(ctx.program.allocator, .{ .opcode = .load_ptr, .dest = value, .arg1 = reg, .source_node = source_node });
                    break :blk value;
                };
                const rhs_reg = try ctx.emitInt(source_node, rhs_value);
                const result = if (op.tag == .equal) rhs_reg else blk: {
                    const reg = ctx.proc.num_registers;
                    ctx.proc.num_registers += 1;
                    try ctx.proc.instructions.append(ctx.program.allocator, .{
                        .opcode = compoundAssignmentOpcode(ctx, source_node, source_node, op.tag),
                        .dest = reg,
                        .arg1 = lhs_reg,
                        .arg2 = rhs_reg,
                        .source_node = source_node,
                    });
                    break :blk reg;
                };
                try ctx.decl_registers.put(ctx.program.allocator, decl, result);
                if (ctx.isTopLevelVarDecl(decl)) {
                    const addr = try ctx.emitGlobalAddress(decl, source_node, "int", diag);
                    try ctx.proc.instructions.append(ctx.program.allocator, .{ .opcode = .store_ptr, .dest = addr, .arg1 = result, .source_node = source_node });
                }
                return;
            }
        }
        return diag.failAt(ctx.ast.tokens[ctx.ast.mainToken(source_node)].start, "#insert cannot yet lower statement '{s}'", .{stmt});
    }

    pub fn genBlock(ctx: *GenContext, block: NodeIndex, diag: Diagnostic) anyerror!void {
        const defer_base = ctx.defer_stmts.items.len;
        const code_binding_base = ctx.local_code_bindings.items.len;
        defer ctx.local_code_bindings.shrinkRetainingCapacity(code_binding_base);
        for (ctx.ast.extraSlice(ctx.ast.data(block).lhs)) |stmt| try ctx.genStmt(@intCast(stmt), diag);
        // Emit deferred statements added in this block (LIFO), then pop them.
        try ctx.emitDeferred(defer_base, diag);
        ctx.defer_stmts.shrinkRetainingCapacity(defer_base);
    }

    fn tryEmitStringMultiReturn(ctx: *GenContext, stmt: NodeIndex, diag: Diagnostic) !bool {
        const ast = ctx.ast;
        const children = ast.extraSlice(ast.data(stmt).lhs);
        if (children.len < 2 or children.len > 3) return false;
        const first: NodeIndex = @intCast(children[0]);
        const rhs = stmtInitOrAssignRhs(ast, first) orelse return false;
        if (ast.tag(rhs) != .call_expr) return false;
        const callee = ast.data(rhs).lhs;
        if (ast.tag(callee) != .identifier) return false;
        const name = ast.tokenSlice(ast.mainToken(callee));
        const is_int_parse = std.mem.eql(u8, name, "string_to_int") or std.mem.eql(u8, name, "parse_int") or std.mem.eql(u8, name, "to_integer");
        const is_float_parse = std.mem.eql(u8, name, "string_to_float");
        if (!is_int_parse and !is_float_parse) return false;
        for (children) |child_idx| {
            const child: NodeIndex = @intCast(child_idx);
            if ((stmtInitOrAssignRhs(ast, child) orelse return false) != rhs) return false;
        }
        const args = ast.extraSlice(ast.data(rhs).rhs);
        if (args.len != 1) return diag.failAt(ast.tokens[ast.mainToken(rhs)].start, "{s} expects one string", .{name});
        const source = try ctx.genExpr(handleArgNode(ast, @intCast(args[0])), diag);
        const value_reg = ctx.proc.num_registers;
        ctx.proc.num_registers += 1;
        const ok_reg = ctx.proc.num_registers;
        ctx.proc.num_registers += 1;
        try ctx.proc.instructions.append(ctx.program.allocator, .{ .opcode = if (is_float_parse) .string_parse_float else .string_parse_int, .dest = value_reg, .arg1 = source, .arg2 = ok_reg, .source_node = rhs });
        try ctx.bindStmtTarget(@intCast(children[0]), value_reg, diag);
        try ctx.bindStmtTarget(@intCast(children[1]), ok_reg, diag);
        if (children.len == 3) {
            const zero = try ctx.emitInt(@intCast(children[2]), 0);
            try ctx.bindStmtTarget(@intCast(children[2]), zero, diag);
        }
        return true;
    }

    fn tryEmitCompilerGetNodesMultiReturn(ctx: *GenContext, stmt: NodeIndex, diag: Diagnostic) !bool {
        const ast = ctx.ast;
        const children = ast.extraSlice(ast.data(stmt).lhs);
        if (children.len != 2) return false;
        const first: NodeIndex = @intCast(children[0]);
        const rhs = stmtInitOrAssignRhs(ast, first) orelse return false;
        if (ast.tag(rhs) != .call_expr) return false;
        const callee = ast.data(rhs).lhs;
        if (ast.tag(callee) != .identifier or !std.mem.eql(u8, ast.tokenSlice(ast.mainToken(callee)), "compiler_get_nodes")) return false;
        const second: NodeIndex = @intCast(children[1]);
        if ((stmtInitOrAssignRhs(ast, second) orelse return false) != rhs) return false;
        const args = ast.extraSlice(ast.data(rhs).rhs);
        if (args.len != 1) return diag.failAt(ast.tokens[ast.mainToken(rhs)].start, "compiler_get_nodes expects one Code argument", .{});

        const source = try ctx.genCodeValueExpr(@intCast(args[0]), rhs, diag);
        const root_reg = ctx.proc.num_registers;
        ctx.proc.num_registers += 1;
        const exprs_reg = ctx.proc.num_registers;
        ctx.proc.num_registers += 1;
        try ctx.proc.instructions.append(ctx.program.allocator, .{ .opcode = .compiler_get_nodes_root, .dest = root_reg, .arg1 = source, .source_node = rhs });
        try ctx.proc.instructions.append(ctx.program.allocator, .{ .opcode = .compiler_get_nodes_exprs, .dest = exprs_reg, .arg1 = source, .source_node = rhs });
        try ctx.bindStmtTarget(first, root_reg, diag);
        try ctx.bindStmtTarget(second, exprs_reg, diag);
        try ctx.type_overrides.put(ctx.program.allocator, first, "*Code_Node");
        try ctx.type_overrides.put(ctx.program.allocator, second, "[] Code_Node");
        return true;
    }

    fn tryEmitAllocatorCapabilitiesMultiReturn(ctx: *GenContext, stmt: NodeIndex, diag: Diagnostic) !bool {
        const ast = ctx.ast;
        const children = ast.extraSlice(ast.data(stmt).lhs);
        if (children.len != 2) return false;
        const first: NodeIndex = @intCast(children[0]);
        const rhs = stmtInitOrAssignRhs(ast, first) orelse return false;
        if (ast.tag(rhs) != .call_expr) return false;
        const callee = ast.data(rhs).lhs;
        if (ast.tag(callee) != .identifier or !std.mem.eql(u8, ast.tokenSlice(ast.mainToken(callee)), "get_capabilities")) return false;
        const second: NodeIndex = @intCast(children[1]);
        if ((stmtInitOrAssignRhs(ast, second) orelse return false) != rhs) return false;
        const args = ast.extraSlice(ast.data(rhs).rhs);
        if (args.len != 1) return diag.failAt(ast.tokens[ast.mainToken(rhs)].start, "get_capabilities expects one Allocator", .{});

        const allocator_reg = try ctx.genExpr(@intCast(args[0]), diag);
        const flags_reg = ctx.proc.num_registers;
        ctx.proc.num_registers += 1;
        const name_reg = ctx.proc.num_registers;
        ctx.proc.num_registers += 1;
        try ctx.proc.instructions.append(ctx.program.allocator, .{ .opcode = .allocator_cap_flags, .dest = flags_reg, .arg1 = allocator_reg, .source_node = rhs });
        try ctx.proc.instructions.append(ctx.program.allocator, .{ .opcode = .allocator_cap_name, .dest = name_reg, .arg1 = allocator_reg, .source_node = rhs });
        try ctx.bindStmtTarget(first, flags_reg, diag);
        try ctx.bindStmtTarget(second, name_reg, diag);
        return true;
    }

    fn bindStmtTarget(ctx: *GenContext, stmt: NodeIndex, reg: Bytecode.Register, diag: Diagnostic) !void {
        const ast = ctx.ast;
        switch (ast.tag(stmt)) {
            .var_decl, .const_decl => try ctx.decl_registers.put(ctx.program.allocator, stmt, reg),
            .assign_stmt => {
                const lhs = ast.data(stmt).lhs;
                const decl = ctx.resolved.local_values.get(lhs) orelse return diag.failAt(ast.tokens[ast.mainToken(lhs)].start, "assignment target must resolve to a local variable", .{});
                if (ctx.decl_registers.get(decl)) |old_reg| {
                    try ctx.proc.instructions.append(ctx.program.allocator, .{ .opcode = .load, .dest = old_reg, .arg1 = reg, .source_node = stmt });
                } else {
                    try ctx.decl_registers.put(ctx.program.allocator, decl, reg);
                }
            },
            else => return diag.failAt(ast.tokens[ast.mainToken(stmt)].start, "internal error: unsupported multi-return target", .{}),
        }
    }

    fn genStmt(ctx: *GenContext, stmt: NodeIndex, diag: Diagnostic) !void {
        const ast = ctx.ast;
        switch (ast.tag(stmt)) {
            .import_decl, .load_decl, .scope_decl => {},
            .expr_stmt => {
                if (try ctx.tryEmitExpandProcCall(ast.data(stmt).lhs, diag)) return;
                _ = try ctx.genExpr(ast.data(stmt).lhs, diag);
            },
            .stmt_list => {
                if (try ctx.tryEmitCompilerGetNodesMultiReturn(stmt, diag)) return;
                if (try ctx.tryEmitAllocatorCapabilitiesMultiReturn(stmt, diag)) return;
                if (try ctx.tryEmitStringMultiReturn(stmt, diag)) return;
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
                if (try ctx.tryEmitSelfBinaryAssignment(lhs, rhs_node, stmt, diag)) |_| return;
                if (try ctx.tryEmitStaticArrayLiteralAssignment(lhs, rhs_node, stmt, diag)) return;
                if (ast.tag(lhs) == .field_access) {
                    if (typeTextForExpr(ctx, ast.data(lhs).lhs, diag)) |base_text| {
                        if (isBuildOptionsValueType(base_text)) {
                            const base = try ctx.genExpr(ast.data(lhs).lhs, diag);
                            const field_name = ast.tokenSlice(ast.data(lhs).rhs);
                            const rhs = try ctx.genBuildOptionsFieldAssignmentValue(field_name, rhs_node, diag);
                            const field_index = try ctx.program.addString(field_name);
                            try ctx.proc.instructions.append(ctx.program.allocator, .{ .opcode = .build_options_set_field, .dest = base, .arg1 = base, .arg2 = field_index, .arg3 = rhs, .source_node = stmt });
                            return;
                        }
                    }
                }
                const rhs = try ctx.genExpr(rhs_node, diag);
                if (ast.tag(lhs) == .meta_expr and ast.tokens[ast.mainToken(lhs)].tag == .directive_insert) {
                    try ctx.storeInsertedLvalue(lhs, rhs, stmt, diag);
                    return;
                }
                if (ast.tag(lhs) == .field_access) {
                    if (std.mem.eql(u8, ast.tokenSlice(ast.data(lhs).rhs), "_s64") and isCodeNodeExpression(ctx, ast.data(lhs).lhs, diag)) {
                        const base = try ctx.genExpr(ast.data(lhs).lhs, diag);
                        try ctx.proc.instructions.append(ctx.program.allocator, .{ .opcode = .code_literal_set_s64, .dest = rhs, .arg1 = base, .arg2 = rhs, .source_node = stmt });
                        return;
                    }
                    const field_info = blk: {
                        const base_text = typeTextForExpr(ctx, ast.data(lhs).lhs, diag) orelse break :blk null;
                        break :blk try fieldInfoFromTypeText(ctx, base_text, ast.tokenSlice(ast.data(lhs).rhs), diag);
                    };
                    if (field_info) |info| {
                        const addr = try genAddressOfLvalue(ctx, lhs, diag);
                        const clean_field_type = std.mem.trim(u8, info.type_text, " \t\r\n");
                        if (try typeTextIsEmbeddedStruct(ctx, clean_field_type, diag)) {
                            const size_reg = try ctx.emitInt(stmt, @intCast(try typeTextSize(ctx, clean_field_type, diag)));
                            try ctx.proc.instructions.append(ctx.program.allocator, .{ .opcode = .memcpy, .dest = addr, .arg1 = rhs, .arg2 = size_reg, .source_node = stmt });
                        } else {
                            const opcode: Bytecode.Opcode = if (std.mem.eql(u8, firstTypeWord(clean_field_type), "float") or std.mem.eql(u8, firstTypeWord(clean_field_type), "float32") or std.mem.eql(u8, firstTypeWord(clean_field_type), "float64")) .store_ptr_float else .store_ptr;
                            try ctx.proc.instructions.append(ctx.program.allocator, .{ .opcode = opcode, .dest = addr, .arg1 = rhs, .source_node = stmt });
                        }
                    } else {
                        const base = try ctx.genExpr(ast.data(lhs).lhs, diag);
                        try ctx.field_values.put(ctx.program.allocator, fieldValueKey(base, ast.tokenSlice(ast.data(lhs).rhs)), rhs);
                    }
                    return;
                }
                if (ast.tag(lhs) == .index_expr) {
                    const addr = try genAddressOfLvalue(ctx, lhs, diag);
                    const base_text = typeTextForExpr(ctx, ast.data(lhs).lhs, diag);
                    const elem_text = if (base_text) |text|
                        dynamicArrayElementText(text) orelse staticArrayElementText(text) orelse if (std.mem.startsWith(u8, std.mem.trim(u8, text, " \t\r\n"), "*")) stripPointerText(text) else null
                    else
                        null;
                    const store_opcode: Bytecode.Opcode = if (base_text != null and std.mem.eql(u8, firstTypeWord(base_text.?), "string"))
                        .store_ptr_byte
                    else if (elem_text != null and try typeTextSize(ctx, elem_text.?, diag) == 1)
                        .store_ptr_byte
                    else if (elem_text != null and (std.mem.eql(u8, firstTypeWord(elem_text.?), "float") or std.mem.eql(u8, firstTypeWord(elem_text.?), "float32") or std.mem.eql(u8, firstTypeWord(elem_text.?), "float64")))
                        .store_ptr_float
                    else
                        .store_ptr;
                    try ctx.proc.instructions.append(ctx.program.allocator, .{ .opcode = store_opcode, .dest = addr, .arg1 = rhs, .source_node = stmt });
                    return;
                }
                if (ast.tag(lhs) == .unary_expr and (ast.tokens[ast.mainToken(lhs)].tag == .shift_left or ast.tokens[ast.mainToken(lhs)].tag == .dot_star)) {
                    const ptr = try ctx.genExpr(ast.data(lhs).lhs, diag);
                    try ctx.proc.instructions.append(ctx.program.allocator, .{ .opcode = .store_ptr, .dest = ptr, .arg1 = rhs, .source_node = stmt });
                    if (ctx.pointer_addrs.get(ptr)) |addr_reg| try ctx.decl_registers.put(ctx.program.allocator, addr_reg, rhs);
                    return;
                }
                if (ast.tag(lhs) == .identifier) {
                    const lhs_name = ast.tokenSlice(ast.mainToken(lhs));
                    if (isBindingOptionField(lhs_name)) {
                        _ = try ctx.genSyntheticBindingOptionField(lhs_name, lhs, diag);
                        if (isBindingOptionArrayField(lhs_name)) {
                            const slot = ctx.binding_option_fields.get(lhs_name) orelse unreachable;
                            try ctx.proc.instructions.append(ctx.program.allocator, .{ .opcode = .load, .dest = slot, .arg1 = rhs, .source_node = stmt });
                        } else {
                            try ctx.binding_option_fields.put(ctx.program.allocator, lhs_name, rhs);
                        }
                        return;
                    }
                    if (ctx.external_registers.get(lhs_name)) |old_reg| {
                        if (ctx.external_lvalue_addresses.get(lhs_name)) |addr| {
                            try ctx.storeExternalLvalue(lhs_name, addr, rhs, stmt, diag);
                            try ctx.external_registers.put(ctx.program.allocator, lhs_name, rhs);
                            return;
                        }
                        try ctx.proc.instructions.append(ctx.program.allocator, .{ .opcode = .load, .dest = old_reg, .arg1 = rhs, .source_node = stmt });
                        try ctx.external_registers.put(ctx.program.allocator, lhs_name, old_reg);
                        return;
                    }
                }
                if (ctx.resolved.local_values.get(lhs)) |decl| {
                    if (ctx.isTopLevelVarDecl(decl)) {
                        const type_node = ast.data(decl).lhs;
                        const type_text = if (type_node != @import("Ast.zig").null_node) ctx.nodeSource(type_node) else typeTextForExpr(ctx, lhs, diag) orelse "int";
                        const addr = try ctx.emitGlobalAddress(decl, lhs, type_text, diag);
                        try ctx.proc.instructions.append(ctx.program.allocator, .{ .opcode = .store_ptr, .dest = addr, .arg1 = rhs, .source_node = stmt });
                        return;
                    }
                    if (ctx.decl_registers.get(decl)) |old_reg| {
                        try ctx.proc.instructions.append(ctx.program.allocator, .{ .opcode = .load, .dest = old_reg, .arg1 = rhs, .source_node = stmt });
                        return;
                    }
                    try ctx.decl_registers.put(ctx.program.allocator, decl, rhs);
                }
                try ctx.proc.instructions.append(ctx.program.allocator, .{ .opcode = .store, .dest = rhs, .arg1 = rhs, .source_node = stmt });
            },
            .var_decl, .const_decl => {
                try ctx.rememberLocalTypeDecl(stmt);
                const init = if (ast.tag(stmt) == .var_decl) ast.data(stmt).rhs else ast.data(stmt).lhs;
                if (init == using_param_sentinel) {
                    const reg = try ctx.genTypedPlaceholderValue(stmt, diag);
                    try ctx.decl_registers.put(ctx.program.allocator, stmt, reg);
                } else if (init != @import("Ast.zig").null_node and ast.tag(init) != .undefined_literal) {
                    if (ast.tag(init) == .meta_expr and ast.tokens[ast.mainToken(init)].tag == .directive_code) {
                        try ctx.rememberLocalCode(stmt, try ctx.codeTextForMacroArg(init, &[_]MacroCodeBinding{}, diag));
                    }
                    if (try ctx.tryEmitStaticArrayLiteralDeclaration(stmt, init, diag)) return;
                    const reg = try ctx.genExpr(init, diag);
                    const ty = if (ctx.typed) |typed| typed.typeOf(stmt) else Type.init(InternPool.well_known.any_type);
                    const init_type_text = typeTextForExpr(ctx, init, diag);
                    const init_first_word = if (init_type_text) |text| firstTypeWord(text) else "";
                    const init_is_code_node = if (init_type_text) |text| isCodeNodeTypeText(text) else false;
                    const init_is_type_info_handle = if (init_type_text) |text| blk: {
                        const handle_name = firstTypeWord(stripPointerText(text));
                        break :blk std.mem.eql(u8, handle_name, "Type_Info_Struct") or std.mem.eql(u8, handle_name, "Type_Info_Struct_Member");
                    } else false;
                    const init_is_addressable_scalar = isAddressableScalarTypeWord(init_first_word) or
                        (init_type_text != null and std.mem.startsWith(u8, std.mem.trim(u8, init_type_text.?, " \t\r\n"), "*"));
                    var bind_reg = reg;
                    if (!init_is_code_node and !init_is_type_info_handle and (ty.isInteger() or ty.isBool() or ty.isString() or ty.isPointer() or init_is_addressable_scalar)) {
                        bind_reg = ctx.proc.num_registers;
                        ctx.proc.num_registers += 1;
                        try ctx.proc.instructions.append(ctx.program.allocator, .{ .opcode = .load, .dest = bind_reg, .arg1 = reg, .source_node = stmt });
                        const addr_reg = ctx.proc.num_registers;
                        ctx.proc.num_registers += 1;
                        try ctx.proc.instructions.append(ctx.program.allocator, .{ .opcode = .addr_of_local, .dest = addr_reg, .arg1 = bind_reg, .source_node = stmt });
                    }
                    try ctx.decl_registers.put(ctx.program.allocator, stmt, bind_reg);
                } else if (ast.tag(stmt) == .var_decl and init == @import("Ast.zig").null_node) {
                    const reg = try ctx.genDefaultValue(ast.data(stmt).lhs, stmt, diag);
                    try ctx.decl_registers.put(ctx.program.allocator, stmt, reg);
                } else if (ast.tag(stmt) == .var_decl and ast.tag(init) == .undefined_literal) {
                    const reg = try ctx.genUndefinedValue(ast.data(stmt).lhs, stmt, diag);
                    try ctx.decl_registers.put(ctx.program.allocator, stmt, reg);
                }
            },
            .placeholder_decl => {},
            .meta_stmt => {
                if (ast.tokens[ast.mainToken(stmt)].tag == .directive_insert) {
                    const inserted = try ctx.codeTextForMacroArg(ast.data(stmt).lhs, &[_]MacroCodeBinding{}, diag);
                    try ctx.emitInsertedCode(inserted, &[_]MacroCodeBinding{}, stmt, diag);
                }
                return;
            },
            .run_expr => {
                if (ast.tokens[ast.mainToken(stmt)].tag == .keyword_push_context) {
                    _ = try ctx.genExpr(ast.data(stmt).rhs, diag);
                    try ctx.genBlock(ast.data(stmt).lhs, diag);
                    return;
                }
                if (ctx.polymorph_types.count() != 0) {
                    if (try tryExecuteSpecializedRunPrint(ctx, stmt, diag)) return;
                    return diag.failAt(ast.tokens[ast.mainToken(stmt)].start, "unsupported specialized #run in polymorphic procedure", .{});
                }
                // `#run` is executed by Compilation before bytecode generation. It must
                // not leave a runtime expression behind; otherwise compile-time-only
                // compiler APIs can leak into the generated executable as placeholders.
                return;
            },
            .proc_decl => {},
            .return_stmt => {
                const value = ast.data(stmt).lhs;
                if (ctx.inline_return) |frame| {
                    if (value != @import("Ast.zig").null_node) {
                        if (frame.result_type != @import("Ast.zig").null_node) {
                            const result_type_text = std.mem.trim(u8, ctx.nodeSource(frame.result_type), " \t\r\n");
                            if (try typeTextIsEmbeddedStruct(ctx, result_type_text, diag)) {
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
                    try ctx.emitDeferred(frame.defer_depth, diag);
                    const patch_idx = ctx.proc.instructions.items.len;
                    try ctx.proc.instructions.append(ctx.program.allocator, .{ .opcode = .jump, .arg1 = 0, .source_node = stmt });
                    try frame.patches.append(ctx.program.allocator, patch_idx);
                    return;
                }
                if (value == @import("Ast.zig").null_node) {
                    try ctx.emitDeferred(0, diag);
                    try ctx.proc.instructions.append(ctx.program.allocator, .{ .opcode = .ret_void, .source_node = stmt });
                } else {
                    const reg = blk: {
                        if (ctx.return_type_node != @import("Ast.zig").null_node) {
                            const return_text = std.mem.trim(u8, ctx.nodeSource(ctx.return_type_node), " \t\r\n");
                            if (try typeTextIsEmbeddedStruct(ctx, return_text, diag)) {
                                if (ast.tag(value) == .aggregate_literal or ast.tag(value) == .typed_aggregate_literal) {
                                    const result = try ctx.genDefaultValueFromText(return_text, stmt, diag);
                                    try ctx.emitAggregateToStruct(value, result, return_text, stmt, diag);
                                    break :blk result;
                                }
                            }
                        }
                        break :blk try ctx.genExpr(value, diag);
                    };
                    try ctx.emitDeferred(0, diag);
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
                    .continue_patches = std.ArrayList(usize).empty,
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
                frame.continue_patches.deinit(ctx.program.allocator);
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
                        const patch_idx = ctx.proc.instructions.items.len;
                        try ctx.proc.instructions.append(ctx.program.allocator, .{ .opcode = .jump, .arg1 = if (f.continue_target == std.math.maxInt(u32)) 0 else f.continue_target, .source_node = stmt });
                        if (f.continue_target == std.math.maxInt(u32)) try f.continue_patches.append(ctx.program.allocator, patch_idx);
                        return;
                    }
                }
                return diag.failAt(ast.tokens[ast.mainToken(stmt)].start, "continue outside of loop", .{});
            },
            .for_stmt => {
                const range = ast.extraSlice(ast.data(stmt).lhs);
                if (try ctx.tryEmitForExpansion(stmt, range, diag)) return;
                if (range.len == 1 or (range.len == 2 and (range[1] & 0x80000000) != 0) or range.len == 3) {
                    const iterated: NodeIndex = @intCast(range[0]);
                    const array_slot = try ctx.genExpr(iterated, diag);
                    const elem_text = if (typeTextForExpr(ctx, iterated, diag)) |iterated_text|
                        dynamicArrayElementText(iterated_text)
                    else
                        null;
                    const elem_size = if (elem_text) |text| try typeTextSize(ctx, text, diag) else 8;
                    const elem_is_struct = if (elem_text) |text| try typeTextIsEmbeddedStruct(ctx, text, diag) else false;
                    const elem_is_string = if (elem_text) |text| std.mem.eql(u8, firstTypeWord(text), "string") else false;
                    const elem_is_type_info_member = if (elem_text) |text| std.mem.eql(u8, firstTypeWord(stripPointerText(text)), "Type_Info_Struct_Member") else false;

                    const count_reg = ctx.proc.num_registers;
                    ctx.proc.num_registers += 1;
                    try ctx.proc.instructions.append(ctx.program.allocator, .{ .opcode = .array_count, .dest = count_reg, .arg1 = array_slot, .source_node = stmt });

                    const index_reg = ctx.proc.num_registers;
                    ctx.proc.num_registers += 1;
                    try ctx.proc.instructions.append(ctx.program.allocator, .{ .opcode = .load_int, .dest = index_reg, .arg1 = 0, .source_node = stmt });
                    const index_addr = ctx.proc.num_registers;
                    ctx.proc.num_registers += 1;
                    try ctx.proc.instructions.append(ctx.program.allocator, .{ .opcode = .addr_of_local, .dest = index_addr, .arg1 = index_reg, .source_node = stmt });
                    const old_loop_index_reg = ctx.loop_index_registers.get(stmt);
                    try ctx.loop_index_registers.put(ctx.program.allocator, stmt, index_reg);
                    defer {
                        if (old_loop_index_reg) |reg| {
                            ctx.loop_index_registers.put(ctx.program.allocator, stmt, reg) catch {};
                        } else {
                            _ = ctx.loop_index_registers.remove(stmt);
                        }
                    }

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
                        .arg4 = if (elem_is_type_info_member) 3 else if (elem_is_struct) 1 else if (elem_is_string) 2 else 0,
                        .source_node = stmt,
                    });
                    const old_iter_reg = ctx.decl_registers.get(stmt);
                    try ctx.decl_registers.put(ctx.program.allocator, stmt, it_reg);
                    defer {
                        if (old_iter_reg) |reg| {
                            ctx.decl_registers.put(ctx.program.allocator, stmt, reg) catch {};
                        } else {
                            _ = ctx.decl_registers.remove(stmt);
                        }
                    }
                    const old_iter_type = ctx.type_overrides.get(stmt);
                    if (elem_text) |text| try ctx.type_overrides.put(ctx.program.allocator, stmt, text);
                    defer {
                        if (old_iter_type) |text| {
                            ctx.type_overrides.put(ctx.program.allocator, stmt, text) catch {};
                        } else {
                            _ = ctx.type_overrides.remove(stmt);
                        }
                    }

                    var frame = LoopFrame{
                        .label = if (range.len >= 2 and (range[1] & 0x80000000) != 0) ast.tokenSlice(range[1] & 0x7fffffff) else "",
                        .continue_target = std.math.maxInt(u32),
                        .continue_patches = std.ArrayList(usize).empty,
                        .break_patches = std.ArrayList(usize).empty,
                        .defer_depth = ctx.defer_stmts.items.len,
                    };
                    try ctx.loop_stack.append(ctx.program.allocator, frame);
                    try ctx.genBlock(ast.data(stmt).rhs, diag);
                    frame = ctx.loop_stack.pop().?;
                    const continue_target: u32 = @intCast(ctx.proc.instructions.items.len);
                    for (frame.continue_patches.items) |patch_idx| ctx.proc.instructions.items[patch_idx].arg1 = continue_target;
                    const one_reg = ctx.proc.num_registers;
                    ctx.proc.num_registers += 1;
                    try ctx.proc.instructions.append(ctx.program.allocator, .{ .opcode = .load_int, .dest = one_reg, .arg1 = 1, .source_node = stmt });
                    try ctx.proc.instructions.append(ctx.program.allocator, .{ .opcode = .add_int, .dest = index_reg, .arg1 = index_reg, .arg2 = one_reg, .source_node = stmt });
                    try ctx.proc.instructions.append(ctx.program.allocator, .{ .opcode = .jump, .arg1 = loop_start, .source_node = stmt });
                    const end_index: u32 = @intCast(ctx.proc.instructions.items.len);
                    ctx.proc.instructions.items[jump_if_index].arg2 = end_index;
                    var popped = frame;
                    for (popped.break_patches.items) |patch_idx| ctx.proc.instructions.items[patch_idx].arg1 = end_index;
                    popped.continue_patches.deinit(ctx.program.allocator);
                    popped.break_patches.deinit(ctx.program.allocator);
                } else if (range.len == 4 or (range.len == 2 and (range[1] & 0x80000000) == 0)) {
                    const is_reverse = range.len == 4 and range[3] != 0;
                    const iterator_tok: u32 = if (range.len == 4) range[2] else 0;
                    const index_reg = try ctx.genExpr(@intCast(range[0]), diag);
                    const end_reg = try ctx.genExpr(@intCast(range[1]), diag);
                    const index_addr = ctx.proc.num_registers;
                    ctx.proc.num_registers += 1;
                    try ctx.proc.instructions.append(ctx.program.allocator, .{ .opcode = .addr_of_local, .dest = index_addr, .arg1 = index_reg, .source_node = stmt });
                    const old_iter_reg = ctx.decl_registers.get(stmt);
                    try ctx.decl_registers.put(ctx.program.allocator, stmt, index_reg);
                    defer {
                        if (old_iter_reg) |reg| {
                            ctx.decl_registers.put(ctx.program.allocator, stmt, reg) catch {};
                        } else {
                            _ = ctx.decl_registers.remove(stmt);
                        }
                    }
                    const loop_start: u32 = @intCast(ctx.proc.instructions.items.len);
                    const cond_reg = ctx.proc.num_registers;
                    ctx.proc.num_registers += 1;
                    if (is_reverse) {
                        try ctx.proc.instructions.append(ctx.program.allocator, .{ .opcode = .cmp_ge_int, .dest = cond_reg, .arg1 = index_reg, .arg2 = end_reg, .source_node = stmt });
                    } else {
                        try ctx.proc.instructions.append(ctx.program.allocator, .{ .opcode = .cmp_le_int, .dest = cond_reg, .arg1 = index_reg, .arg2 = end_reg, .source_node = stmt });
                    }
                    const jump_if_index = ctx.proc.instructions.items.len;
                    try ctx.proc.instructions.append(ctx.program.allocator, .{ .opcode = .jump_if_false, .arg1 = cond_reg, .arg2 = 0, .source_node = stmt });
                    // Push loop frame with iterator name as label.
                    const iter_label: []const u8 = if (iterator_tok != 0) ast.tokenSlice(iterator_tok) else "";
                    var frame = LoopFrame{
                        .label = iter_label,
                        .continue_target = std.math.maxInt(u32),
                        .continue_patches = std.ArrayList(usize).empty,
                        .break_patches = std.ArrayList(usize).empty,
                        .defer_depth = ctx.defer_stmts.items.len,
                    };
                    try ctx.loop_stack.append(ctx.program.allocator, frame);
                    try ctx.genBlock(ast.data(stmt).rhs, diag);
                    frame = ctx.loop_stack.pop().?;
                    const continue_target: u32 = @intCast(ctx.proc.instructions.items.len);
                    for (frame.continue_patches.items) |patch_idx| ctx.proc.instructions.items[patch_idx].arg1 = continue_target;
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
                    for (frame.break_patches.items) |patch_idx| {
                        ctx.proc.instructions.items[patch_idx].arg1 = loop_exit;
                    }
                    frame.continue_patches.deinit(ctx.program.allocator);
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

    fn storeInsertedLvalue(ctx: *GenContext, lhs: NodeIndex, rhs: Bytecode.Register, source_node: NodeIndex, diag: Diagnostic) !void {
        const ast = ctx.ast;
        const raw = try ctx.codeTextForMacroArg(ast.data(lhs).lhs, &[_]MacroCodeBinding{}, diag);
        const clean = std.mem.trim(u8, raw, " \t\r\n;()");
        if (clean.len == 0) return diag.failAt(ast.tokens[ast.mainToken(lhs)].start, "#insert lvalue produced empty code", .{});
        if (isSimpleIdentifierText(clean)) {
            const target = try ctx.visibleRegisterForName(clean, lhs, diag);
            try ctx.proc.instructions.append(ctx.program.allocator, .{ .opcode = .load, .dest = target, .arg1 = rhs, .source_node = source_node });
            try ctx.external_registers.put(ctx.program.allocator, clean, target);
            return;
        }
        return diag.failAt(ast.tokens[ast.mainToken(lhs)].start, "#insert lvalue currently requires an assignable identifier, got '{s}'", .{clean});
    }

    fn storeExternalLvalue(ctx: *GenContext, name: []const u8, addr: Bytecode.Register, rhs: Bytecode.Register, source_node: NodeIndex, diag: Diagnostic) !void {
        const type_text = ctx.external_types.get(name) orelse "int";
        const first = firstTypeWord(type_text);
        const opcode: Bytecode.Opcode = if (std.mem.eql(u8, first, "float") or std.mem.eql(u8, first, "float32") or std.mem.eql(u8, first, "float64"))
            .store_ptr_float
        else if ((try typeTextSize(ctx, type_text, diag)) == 1)
            .store_ptr_byte
        else
            .store_ptr;
        try ctx.proc.instructions.append(ctx.program.allocator, .{ .opcode = opcode, .dest = addr, .arg1 = rhs, .source_node = source_node });
    }

    fn visibleRegisterForName(ctx: *GenContext, name: []const u8, source_node: NodeIndex, diag: Diagnostic) !Bytecode.Register {
        if (ctx.external_registers.get(name)) |reg| return reg;
        var it = ctx.decl_registers.iterator();
        while (it.next()) |entry| {
            const decl = entry.key_ptr.*;
            if (decl == @import("Ast.zig").null_node or decl >= ctx.ast.node_tags.items.len) continue;
            switch (ctx.ast.tag(decl)) {
                .var_decl, .const_decl => {},
                else => continue,
            }
            if (std.mem.eql(u8, ctx.ast.tokenSlice(ctx.ast.mainToken(decl)), name)) return entry.value_ptr.*;
        }
        if (ctx.resolved.lookup(name)) |sym| switch (sym) {
            .const_value => |decl| {
                if (ctx.decl_registers.get(decl)) |reg| return reg;
                if (ctx.isTopLevelVarDecl(decl)) {
                    const type_node = ctx.ast.data(decl).lhs;
                    const type_text = if (type_node != @import("Ast.zig").null_node) ctx.nodeSource(type_node) else "int";
                    const addr = try ctx.emitGlobalAddress(decl, source_node, type_text, diag);
                    const reg = ctx.proc.num_registers;
                    ctx.proc.num_registers += 1;
                    try ctx.proc.instructions.append(ctx.program.allocator, .{ .opcode = .load_ptr, .dest = reg, .arg1 = addr, .source_node = source_node });
                    return reg;
                }
            },
            else => {},
        };
        return diag.failAt(ctx.ast.tokens[ctx.ast.mainToken(source_node)].start, "#insert lvalue target '{s}' is unresolved", .{name});
    }

    fn tryEmitStaticArrayLiteralDeclaration(ctx: *GenContext, decl: NodeIndex, init: NodeIndex, diag: Diagnostic) !bool {
        const ast = ctx.ast;
        if (ast.tag(decl) != .var_decl) return false;
        if (!isArrayLiteralNode(ast, init)) return false;
        const type_node = ast.data(decl).lhs;
        const type_text: []const u8 = if (type_node != @import("Ast.zig").null_node and ast.tag(type_node) == .array_type and ast.data(type_node).lhs != @import("Ast.zig").null_node)
            ctx.nodeSource(type_node)
        else if (type_node == @import("Ast.zig").null_node and ast.tag(init) == .typed_array_literal)
            typedArrayLiteralTypeText(ctx, init) orelse return false
        else
            return false;
        const reg = if (type_node != @import("Ast.zig").null_node)
            try ctx.genDefaultValue(type_node, decl, diag)
        else
            try ctx.genDefaultValueFromText(type_text, decl, diag);
        try ctx.decl_registers.put(ctx.program.allocator, decl, reg);
        try ctx.emitStaticArrayLiteralIntoAddress(reg, init, type_text, decl, diag);
        return true;
    }

    fn tryEmitStaticArrayLiteralAssignment(ctx: *GenContext, lhs: NodeIndex, rhs: NodeIndex, source_node: NodeIndex, diag: Diagnostic) !bool {
        const ast = ctx.ast;
        if (!isArrayLiteralNode(ast, rhs)) return false;
        const lhs_type = typeTextForExpr(ctx, lhs, diag) orelse return false;
        if (staticArrayElementText(lhs_type) == null) return false;
        const addr = try genAddressOfLvalue(ctx, lhs, diag);
        try ctx.emitStaticArrayLiteralIntoAddress(addr, rhs, lhs_type, source_node, diag);
        return true;
    }

    fn emitStaticArrayLiteralIntoAddress(ctx: *GenContext, dest: Bytecode.Register, literal: NodeIndex, type_text: []const u8, source_node: NodeIndex, diag: Diagnostic) !void {
        const ast = ctx.ast;
        const elem_text = staticArrayElementText(type_text) orelse return diag.failAt(ast.tokens[ast.mainToken(source_node)].start, "static array literal assignment requires a static array destination", .{});
        const expected_count = try staticArrayCountFromText(ctx, type_text, diag) orelse return diag.failAt(ast.tokens[ast.mainToken(source_node)].start, "static array literal assignment requires a known destination count", .{});
        const elems = arrayLiteralElements(ast, literal) orelse return diag.failAt(ast.tokens[ast.mainToken(literal)].start, "expected array literal for static array assignment", .{});
        if (elems.len > expected_count) {
            return diag.failAt(ast.tokens[ast.mainToken(literal)].start, "array literal has {d} elements but destination only has {d}", .{ elems.len, expected_count });
        }

        const elem_size = try typeTextSize(ctx, elem_text, diag);
        for (elems, 0..) |elem_idx, i| {
            const elem: NodeIndex = @intCast(elem_idx);
            const value_node = if (ast.tag(elem) == .assign_stmt) ast.data(elem).rhs else elem;
            const value_reg = try ctx.genExpr(value_node, diag);
            const addr = if (i == 0) dest else blk: {
                const tmp = ctx.proc.num_registers;
                ctx.proc.num_registers += 1;
                try ctx.proc.instructions.append(ctx.program.allocator, .{
                    .opcode = .ptr_offset,
                    .dest = tmp,
                    .arg1 = dest,
                    .arg2 = @intCast(i * elem_size),
                    .source_node = source_node,
                });
                break :blk tmp;
            };
            if (try typeTextIsEmbeddedStruct(ctx, elem_text, diag)) {
                const size_reg = try ctx.emitInt(source_node, @intCast(elem_size));
                try ctx.proc.instructions.append(ctx.program.allocator, .{ .opcode = .memcpy, .dest = addr, .arg1 = value_reg, .arg2 = size_reg, .source_node = source_node });
            } else {
                const opcode: Bytecode.Opcode = if (elem_size == 1)
                    .store_ptr_byte
                else if (std.mem.eql(u8, firstTypeWord(elem_text), "float") or std.mem.eql(u8, firstTypeWord(elem_text), "float32") or std.mem.eql(u8, firstTypeWord(elem_text), "float64"))
                    .store_ptr_float
                else
                    .store_ptr;
                try ctx.proc.instructions.append(ctx.program.allocator, .{ .opcode = opcode, .dest = addr, .arg1 = value_reg, .source_node = source_node });
            }
        }
    }

    fn emitContainerGeneratedInitializers(ctx: *GenContext, dest: Bytecode.Register, raw_type: []const u8, source_node: NodeIndex, diag: Diagnostic) !void {
        const type_name = firstTypeWord(stripPointerText(raw_type));
        const type_node = try structTypeNodeByName(ctx, type_name) orelse return;
        const body = containerBodySource(ctx.ast, type_node) orelse return;
        var restores = try bindContainerTypeArgs(ctx, raw_type, type_node);
        defer {
            restoreContainerTypeArgs(ctx, restores.items) catch {};
            restores.deinit(ctx.program.allocator);
        }

        var rest = body;
        while (std.mem.indexOf(u8, rest, "#insert")) |insert_pos| {
            rest = rest[insert_pos + "#insert".len ..];
            var clean = std.mem.trim(u8, rest, " \t\r\n");
            if (!std.mem.startsWith(u8, clean, "#run")) continue;
            clean = std.mem.trim(u8, clean["#run".len..], " \t\r\n");
            const semi = std.mem.indexOfScalar(u8, clean, ';') orelse clean.len;
            const call_text = std.mem.trim(u8, clean[0..semi], " \t\r\n");
            if (call_text.len == 0) continue;
            const generated = try ctx.executeTextReturningCompileTimeCall(call_text, source_node, diag);
            try ctx.emitContainerInsertedAssignments(dest, raw_type, generated, source_node, diag);
            rest = if (semi < clean.len) clean[semi + 1 ..] else "";
        }
    }

    fn executeTextReturningCompileTimeCall(ctx: *GenContext, call_text: []const u8, source_node: NodeIndex, diag: Diagnostic) ![]const u8 {
        const open = std.mem.indexOfScalar(u8, call_text, '(') orelse return diag.failAt(ctx.ast.tokens[ctx.ast.mainToken(source_node)].start, "container #insert #run requires a procedure call", .{});
        const close = matchingParenIndex(call_text, open) orelse return diag.failAt(ctx.ast.tokens[ctx.ast.mainToken(source_node)].start, "container #insert #run call has unbalanced parentheses", .{});
        const name = std.mem.trim(u8, call_text[0..open], " \t\r\n");
        const args_text = call_text[open + 1 .. close];
        const target = ctx.resolveProcCallTarget(source_node, name, countCommaSeparatedArgs(args_text)) orelse return diag.failAt(ctx.ast.tokens[ctx.ast.mainToken(source_node)].start, "unresolved container #insert #run procedure '{s}'", .{name});

        var values = std.ArrayList(vm_mod.Value).empty;
        defer values.deinit(ctx.program.allocator);
        var args_it = std.mem.splitScalar(u8, args_text, ',');
        while (args_it.next()) |raw_arg| {
            const arg = std.mem.trim(u8, raw_arg, " \t\r\n");
            if (arg.len == 0) continue;
            const value = try evalIntegerTextExpr(ctx, arg);
            try values.append(ctx.program.allocator, .{ .int = value });
        }

        var program = try generateProcWithParamCount(ctx.program.allocator, ctx.ast, ctx.resolved, ctx.typed, target, diag, values.items.len);
        defer program.deinit();
        var vm = vm_mod.VM.init(ctx.program.allocator, &program);
        defer vm.deinit();
        const result = try vm.runProcWithArgs(program.main_proc.?, values.items, diag);
        return switch (result) {
            .string => |value| blk: {
                const idx = try ctx.program.addByteArray(value);
                break :blk ctx.program.byte_arrays.items[idx];
            },
            .bytes => |value| blk: {
                const idx = try ctx.program.addByteArray(value);
                break :blk ctx.program.byte_arrays.items[idx];
            },
            else => diag.failAt(ctx.ast.tokens[ctx.ast.mainToken(source_node)].start, "container #insert #run must return string or Code", .{}),
        };
    }

    fn emitContainerInsertedAssignments(ctx: *GenContext, dest: Bytecode.Register, raw_type: []const u8, generated: []const u8, source_node: NodeIndex, diag: Diagnostic) !void {
        var rest = generated;
        while (rest.len != 0) {
            const semi = std.mem.indexOfScalar(u8, rest, ';') orelse rest.len;
            const stmt = std.mem.trim(u8, rest[0..semi], " \t\r\n");
            if (stmt.len != 0) try ctx.emitContainerInsertedAssignment(dest, raw_type, stmt, source_node, diag);
            rest = if (semi < rest.len) rest[semi + 1 ..] else "";
        }
    }

    fn emitContainerInsertedAssignment(ctx: *GenContext, dest: Bytecode.Register, raw_type: []const u8, stmt: []const u8, source_node: NodeIndex, diag: Diagnostic) !void {
        const eq = std.mem.indexOfScalar(u8, stmt, '=') orelse return diag.failAt(ctx.ast.tokens[ctx.ast.mainToken(source_node)].start, "container #insert assignment missing '=': {s}", .{stmt});
        const lhs = std.mem.trim(u8, stmt[0..eq], " \t\r\n");
        const rhs_text = std.mem.trim(u8, stmt[eq + 1 ..], " \t\r\n");
        const bracket = std.mem.indexOfScalar(u8, lhs, '[') orelse return diag.failAt(ctx.ast.tokens[ctx.ast.mainToken(source_node)].start, "container #insert assignment requires field[index] lvalue: {s}", .{stmt});
        const close = std.mem.lastIndexOfScalar(u8, lhs, ']') orelse return diag.failAt(ctx.ast.tokens[ctx.ast.mainToken(source_node)].start, "container #insert assignment has unbalanced index: {s}", .{stmt});
        const field_name = std.mem.trim(u8, lhs[0..bracket], " \t\r\n");
        const index_text = std.mem.trim(u8, lhs[bracket + 1 .. close], " \t\r\n");
        const field = try fieldInfoFromTypeText(ctx, raw_type, field_name, diag) orelse return diag.failAt(ctx.ast.tokens[ctx.ast.mainToken(source_node)].start, "container #insert field '{s}' is unresolved", .{field_name});
        const elem_text = staticArrayElementText(field.type_text) orelse return diag.failAt(ctx.ast.tokens[ctx.ast.mainToken(source_node)].start, "container #insert field '{s}' is not a static array", .{field_name});
        const elem_size = try typeTextSize(ctx, elem_text, diag);
        const index = try evalIntegerTextExpr(ctx, index_text);
        if (index < 0) return diag.failAt(ctx.ast.tokens[ctx.ast.mainToken(source_node)].start, "container #insert index must be non-negative", .{});
        const byte_offset = field.offset + @as(u64, @intCast(index)) * elem_size;
        const addr = if (byte_offset == 0) dest else blk: {
            const tmp = ctx.proc.num_registers;
            ctx.proc.num_registers += 1;
            try ctx.proc.instructions.append(ctx.program.allocator, .{ .opcode = .ptr_offset, .dest = tmp, .arg1 = dest, .arg2 = @intCast(byte_offset), .source_node = source_node });
            break :blk tmp;
        };
        const rhs = try evalIntegerTextExpr(ctx, rhs_text);
        const value = if (std.mem.eql(u8, firstTypeWord(elem_text), "float") or std.mem.eql(u8, firstTypeWord(elem_text), "float32") or std.mem.eql(u8, firstTypeWord(elem_text), "float64")) blk: {
            const reg = ctx.proc.num_registers;
            ctx.proc.num_registers += 1;
            const bits: u64 = @bitCast(@as(f64, @floatFromInt(rhs)));
            try ctx.proc.instructions.append(ctx.program.allocator, .{ .opcode = .load_float, .dest = reg, .arg1 = @truncate(bits), .arg2 = @truncate(bits >> 32), .source_node = source_node });
            break :blk reg;
        } else try ctx.emitInt(source_node, rhs);
        const opcode: Bytecode.Opcode = if (std.mem.eql(u8, firstTypeWord(elem_text), "float") or std.mem.eql(u8, firstTypeWord(elem_text), "float32") or std.mem.eql(u8, firstTypeWord(elem_text), "float64")) .store_ptr_float else .store_ptr;
        try ctx.proc.instructions.append(ctx.program.allocator, .{ .opcode = opcode, .dest = addr, .arg1 = value, .source_node = source_node });
    }

    fn emitTypeText(ctx: *GenContext, source_node: NodeIndex, raw_type: []const u8, diag: Diagnostic) !Bytecode.Register {
        const clean = std.mem.trim(u8, raw_type, " \t\r\n");
        try ctx.ensureTypeInfoForText(clean, diag);
        const type_idx = try ctx.program.addString(clean);
        const reg = ctx.proc.num_registers;
        ctx.proc.num_registers += 1;
        try ctx.proc.instructions.append(ctx.program.allocator, .{ .opcode = .load_type_text, .dest = reg, .arg1 = type_idx, .source_node = source_node });
        return reg;
    }

    fn ensureTypeInfoForText(ctx: *GenContext, raw_type: []const u8, diag: Diagnostic) !void {
        const type_name = firstTypeWord(stripPointerText(raw_type));
        if (type_name.len == 0 or ctx.program.typeInfoIndexByName(type_name) != null) return;
        const type_node = try structTypeNodeByName(ctx, type_name) orelse return;
        const body = containerBodySource(ctx.ast, type_node) orelse return;
        var members = std.ArrayList(Bytecode.TypeInfoMember).empty;
        defer members.deinit(ctx.program.allocator);
        var field_it = FieldSegmentIterator{ .source = body };
        while (field_it.next()) |segment| {
            const parsed = parseFieldSegment(segment) orelse continue;
            var names_it = std.mem.splitScalar(u8, parsed.names_text, ',');
            while (names_it.next()) |raw_name| {
                var name = std.mem.trim(u8, raw_name, " \t\r\n");
                if (std.mem.startsWith(u8, name, "using")) name = std.mem.trim(u8, name[5..], " \t\r\n");
                if (name.len == 0) continue;
                try members.append(ctx.program.allocator, .{ .name = name, .type_name = parsed.type_text, .flags = 0 });
            }
        }
        const tag: u32 = if (ctx.ast.tag(type_node) == .union_type) typeInfoTagValue("UNION").? else typeInfoTagValue("STRUCT").?;
        _ = try ctx.program.addTypeInfo(type_name, tag, members.items);
        _ = diag;
    }

    fn genExpr(ctx: *GenContext, expr: NodeIndex, diag: Diagnostic) anyerror!Bytecode.Register {
        const ast = ctx.ast;
        const program = ctx.program;
        const proc = ctx.proc;
        switch (ast.tag(expr)) {
            .string_literal => {
                const token_tag = ast.tokens[ast.mainToken(expr)].tag;
                if (token_tag == .directive_file) return try ctx.emitString(expr, std.fs.path.basename(diag.file_path));
                if (token_tag == .directive_filepath) {
                    const path = try canonicalSourcePath(program.allocator, diag.file_path);
                    defer program.allocator.free(path);
                    return try ctx.emitString(expr, path);
                }
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
                const type_id = if (typeTextForExpr(ctx, ast.data(expr).lhs, diag)) |type_text|
                    typeIdFromTypeText(type_text)
                else
                    try ctx.phase2TypeId(ast.data(expr).lhs, diag);
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
                if (ast.tokens[ast.mainToken(expr)].tag == .directive_code) {
                    const payload = ast.data(expr).lhs;
                    const text = if (payload == @import("Ast.zig").null_node)
                        ctx.codeDirectiveTokenSource(ast.mainToken(expr))
                    else
                        ctx.nodeSource(payload);
                    return try ctx.emitString(expr, text);
                }
                if (ast.tokens[ast.mainToken(expr)].tag == .directive_insert) {
                    const inserted = try ctx.codeTextForMacroArg(ast.data(expr).lhs, &[_]MacroCodeBinding{}, diag);
                    return try ctx.emitParsedInsertedExpression(inserted, expr, diag);
                }
                if (ast.tokens[ast.mainToken(expr)].tag == .directive_location) {
                    const target = ctx.locationTargetNode(ast.data(expr).lhs);
                    return try ctx.emitSourceLocation(target, expr, diag);
                }
                if (ast.tokens[ast.mainToken(expr)].tag == .directive_caller_location) {
                    return try ctx.emitSourceLocation(expr, expr, diag);
                }
                return diag.failAt(ast.tokens[ast.mainToken(expr)].start, "unsupported compile-time meta expression in bytecode generator", .{});
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
                    if (typed.comptime_bytes.get(expr)) |value| {
                        const idx = try program.addByteArray(value);
                        const reg = proc.num_registers;
                        proc.num_registers += 1;
                        try proc.instructions.append(program.allocator, .{ .opcode = .load_bytes, .dest = reg, .arg1 = idx, .source_node = expr });
                        return reg;
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
                    const operand_source_is_pointer = if (typeTextForExpr(ctx, operand, diag)) |operand_ty|
                        std.mem.startsWith(u8, std.mem.trim(u8, operand_ty, " \t\r\n"), "*")
                    else
                        false;
                    if (ctx.typed != null and !ctx.typed.?.typeOf(operand).isPointer() and !operand_source_is_pointer) return operand_reg;
                    if (ctx.pointer_addrs.get(operand_reg)) |addr_decl| {
                        return ctx.decl_registers.get(addr_decl) orelse return diag.failAt(ast.tokens[ast.mainToken(expr)].start, "pointer dereference target has no generated storage", .{});
                    }
                    if (ctx.resolved.local_values.get(operand)) |decl| {
                        if (typeTextForExpr(ctx, operand, diag)) |operand_ty| {
                            if (!std.mem.startsWith(u8, std.mem.trim(u8, operand_ty, " \t\r\n"), "*")) {
                                if (ctx.decl_registers.get(decl)) |decl_reg| return decl_reg;
                            }
                        }
                    }
                    const reg = proc.num_registers;
                    proc.num_registers += 1;
                    const opcode: Bytecode.Opcode = if (typeTextForExpr(ctx, operand, diag)) |operand_ty| blk: {
                        const clean = std.mem.trim(u8, operand_ty, " \t\r\n");
                        break :blk if (std.mem.eql(u8, clean, "*u8")) .load_ptr_byte else .load_ptr;
                    } else .load_ptr;
                    try proc.instructions.append(program.allocator, .{ .opcode = opcode, .dest = reg, .arg1 = operand_reg, .source_node = expr });
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
                if (op == .keyword_xx) {
                    if (typeTextForExpr(ctx, operand, diag)) |operand_ty| {
                        const clean = std.mem.trim(u8, operand_ty, " \t\r\n");
                        if (std.mem.eql(u8, firstTypeWord(clean), "string") or std.mem.startsWith(u8, clean, "*")) return operand_reg;
                    }
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
                        if ((ast.tag(target_ty) == .type_expr or ast.tag(target_ty) == .identifier) and std.mem.eql(u8, ast.tokenSlice(ast.mainToken(target_ty)), "bool")) break :blk .int_to_bool_cast;
                        if ((ast.tag(target_ty) == .type_expr or ast.tag(target_ty) == .identifier) and std.mem.eql(u8, ast.tokenSlice(ast.mainToken(target_ty)), "float")) break :blk .float_cast;
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
                const identifier_name = ast.tokenSlice(ast.mainToken(expr));
                if (allocatorProcIdByName(identifier_name)) |proc_id| return try ctx.emitInt(expr, proc_id);
                if (ctx.polymorph_types.get(identifier_name)) |actual_type| {
                    return try ctx.emitTypeText(expr, actual_type, diag);
                }
                if (ctx.resolved.local_values.get(expr)) |decl| {
                    if (decl == @import("Ast.zig").null_node) {
                        const unresolved_name = ast.tokenSlice(ast.mainToken(expr));
                        if (ctx.external_registers.get(unresolved_name)) |reg| return reg;
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
                    if (ctx.isTopLevelVarDecl(decl)) {
                        const type_node = ast.data(decl).lhs;
                        const type_text = if (type_node != @import("Ast.zig").null_node) ctx.nodeSource(type_node) else typeTextForExpr(ctx, expr, diag) orelse "int";
                        const addr = try ctx.emitGlobalAddress(decl, expr, type_text, diag);
                        if (isStorageValueTypeText(type_text) or try typeTextIsStruct(ctx, stripPointerText(type_text), diag)) return addr;
                        const reg = proc.num_registers;
                        proc.num_registers += 1;
                        try proc.instructions.append(program.allocator, .{ .opcode = .load_ptr, .dest = reg, .arg1 = addr, .source_node = expr });
                        return reg;
                    }
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
                const name = ast.tokenSlice(ast.mainToken(expr));
                if (std.mem.eql(u8, name, "OS")) {
                    return try ctx.emitString(expr, hostOsName());
                }
                if (allocatorProcIdByName(name)) |proc_id| return try ctx.emitInt(expr, proc_id);
                if (std.mem.eql(u8, name, "context")) return try ctx.genTypedPlaceholderValue(expr, diag);
                if (std.mem.eql(u8, name, "STDIN_FILENO")) return try ctx.emitInt(expr, 0);
                if (std.mem.eql(u8, name, "STDOUT_FILENO")) return try ctx.emitInt(expr, 1);
                if (std.mem.eql(u8, name, "STDERR_FILENO")) return try ctx.emitInt(expr, 2);
                if (std.mem.eql(u8, name, "STD_INPUT_HANDLE")) return try ctx.emitInt(expr, -10);
                if (std.mem.eql(u8, name, "STD_OUTPUT_HANDLE")) return try ctx.emitInt(expr, -11);
                if (std.mem.eql(u8, name, "STD_ERROR_HANDLE")) return try ctx.emitInt(expr, -12);
                if (std.mem.eql(u8, name, "PI")) return try ctx.emitFloat(expr, std.math.pi);
                if (std.mem.eql(u8, name, "GENERATOR_DEFAULT_SYSTEM_INCLUDE_PATH")) return try ctx.emitString(expr, "/usr/include");
                if (isBindingOptionField(name)) return try ctx.genSyntheticBindingOptionField(name, expr, diag);
                if (ctx.external_registers.get(name)) |reg| return reg;
                const reg = proc.num_registers;
                proc.num_registers += 1;
                if (isBuiltinTypeName(name)) {
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
                    const then_supported = then_ty.isBool() or then_ty.isInteger() or then_ty.isFloat() or then_ty.isString();
                    const else_supported = else_ty.isBool() or else_ty.isInteger() or else_ty.isFloat() or else_ty.isString();
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
                if (payload.len < 2) return diag.failAt(ast.tokens[ast.mainToken(expr)].start, "typed aggregate literal is malformed", .{});
                const type_node: NodeIndex = @intCast(payload[0]);
                const type_text = std.mem.trim(u8, ctx.nodeSource(type_node), " \t\r\n");
                if (std.mem.eql(u8, firstTypeWord(type_text), "Allocator")) {
                    const elems = ast.extraSlice(payload[1]);
                    const proc_id = if (elems.len > 0) try ctx.genExpr(@intCast(elems[0]), diag) else try ctx.emitInt(expr, allocator_proc_default);
                    const data = if (elems.len > 1) try ctx.genExpr(@intCast(elems[1]), diag) else blk: {
                        const data_reg = proc.num_registers;
                        proc.num_registers += 1;
                        try proc.instructions.append(program.allocator, .{ .opcode = .load_null_ptr, .dest = data_reg, .source_node = expr });
                        break :blk data_reg;
                    };
                    return try ctx.emitAllocatorValue(expr, proc_id, data);
                }
                if (!(try typeTextIsEmbeddedStruct(ctx, type_text, diag))) return diag.failAt(ast.tokens[ast.mainToken(expr)].start, "typed aggregate literal currently requires a concrete struct type", .{});
                const reg = try ctx.genDefaultValueFromText(type_text, expr, diag);
                try ctx.emitAggregateToStruct(expr, reg, type_text, expr, diag);
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
                    if (isCodeNodeKindName(field_name)) {
                        return try ctx.emitString(expr, field_name);
                    }
                    if (isOsEnumName(field_name)) {
                        return try ctx.emitString(expr, field_name);
                    }
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
                if (ast.tag(ast.data(expr).lhs) == .identifier and std.mem.eql(u8, ast.tokenSlice(ast.mainToken(ast.data(expr).lhs)), "x86_Feature_Flag")) {
                    return try ctx.emitInt(expr, x86FeatureFlagId(field_name));
                }
                if (ast.tag(ast.data(expr).lhs) == .identifier and std.mem.eql(u8, ast.tokenSlice(ast.mainToken(ast.data(expr).lhs)), "context")) {
                    if (std.mem.eql(u8, field_name, "default_allocator") or std.mem.eql(u8, field_name, "allocator")) {
                        return try ctx.emitDefaultAllocatorValue(expr);
                    }
                }
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
                if (typeTextForExpr(ctx, ast.data(expr).lhs, diag)) |base_text| {
                    const base_name = firstTypeWord(stripPointerText(base_text));
                    if (std.mem.eql(u8, base_name, "Type_Info_Struct")) {
                        const field_idx = try program.addString(field_name);
                        const reg = proc.num_registers;
                        proc.num_registers += 1;
                        try proc.instructions.append(program.allocator, .{ .opcode = .type_info_field, .dest = reg, .arg1 = base_reg, .arg2 = field_idx, .source_node = expr });
                        return reg;
                    }
                    if (std.mem.eql(u8, base_name, "Type_Info_Struct_Member")) {
                        const field_idx = try program.addString(field_name);
                        const reg = proc.num_registers;
                        proc.num_registers += 1;
                        try proc.instructions.append(program.allocator, .{ .opcode = .type_info_member_field, .dest = reg, .arg1 = base_reg, .arg2 = field_idx, .source_node = expr });
                        return reg;
                    }
                }
                if (std.mem.eql(u8, field_name, "kind") or std.mem.eql(u8, field_name, "node_flags") or std.mem.eql(u8, field_name, "arguments_unsorted") or std.mem.eql(u8, field_name, "value_type") or std.mem.eql(u8, field_name, "_s64")) {
                    if (isCodeNodeExpression(ctx, ast.data(expr).lhs, diag)) {
                        const reg = proc.num_registers;
                        proc.num_registers += 1;
                        const opcode: Bytecode.Opcode = if (std.mem.eql(u8, field_name, "kind"))
                            .code_node_field_kind
                        else if (std.mem.eql(u8, field_name, "node_flags"))
                            .code_node_field_flags
                        else if (std.mem.eql(u8, field_name, "arguments_unsorted"))
                            .code_proc_call_arguments
                        else if (std.mem.eql(u8, field_name, "value_type"))
                            .code_literal_field_value_type
                        else
                            .code_literal_field_s64;
                        try proc.instructions.append(program.allocator, .{
                            .opcode = opcode,
                            .dest = reg,
                            .arg1 = base_reg,
                            .source_node = expr,
                        });
                        return reg;
                    }
                }
                if (std.mem.eql(u8, field_name, "expression") and (isCodeArgumentExpression(ctx, ast.data(expr).lhs, diag) or isCodeArgumentSyntax(ast, ast.data(expr).lhs))) {
                    const reg = proc.num_registers;
                    proc.num_registers += 1;
                    try proc.instructions.append(program.allocator, .{
                        .opcode = .code_argument_field_expression,
                        .dest = reg,
                        .arg1 = base_reg,
                        .source_node = expr,
                    });
                    return reg;
                }
                if (ctx.field_values.get(fieldValueKey(base_reg, field_name))) |value_reg| return value_reg;
                if (staticArrayTypeNodeForExpr(ctx, ast.data(expr).lhs)) |array_type| {
                    if (std.mem.eql(u8, field_name, "count")) {
                        const len_node = ast.data(array_type).lhs;
                        const count = if (len_node == @import("Ast.zig").null_node) 0 else try evalIntegerConstExpr(ctx, len_node, diag);
                        return try ctx.emitInt(expr, @intCast(@max(count, 0)));
                    }
                    if (std.mem.eql(u8, field_name, "data")) return base_reg;
                }
                if (typeTextForExpr(ctx, ast.data(expr).lhs, diag)) |base_text| {
                    if (std.mem.eql(u8, firstTypeWord(base_text), "Code") and std.mem.eql(u8, field_name, "type")) {
                        const lhs = ast.data(expr).lhs;
                        const code = ctx.localCodeForIdentifier(lhs) orelse try ctx.codeTextForMacroArg(lhs, &[_]MacroCodeBinding{}, diag);
                        const type_id = try ctx.typeIdForCodeText(code, expr, diag);
                        const reg = proc.num_registers;
                        proc.num_registers += 1;
                        try proc.instructions.append(program.allocator, .{ .opcode = .load_type, .dest = reg, .arg1 = type_id, .source_node = expr });
                        return reg;
                    }
                    if (std.mem.eql(u8, firstTypeWord(base_text), "Pool")) {
                        if (std.mem.eql(u8, field_name, "memblock_size")) return try ctx.emitInt(expr, 65536);
                        if (std.mem.eql(u8, field_name, "bytes_left")) {
                            const reg = proc.num_registers;
                            proc.num_registers += 1;
                            try proc.instructions.append(program.allocator, .{ .opcode = .pool_bytes_left, .dest = reg, .arg1 = base_reg, .source_node = expr });
                            return reg;
                        }
                    }
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
                    if (staticArrayElementText(base_text) != null) {
                        if (std.mem.eql(u8, field_name, "count")) {
                            const count = try staticArrayCountFromText(ctx, base_text, diag) orelse 0;
                            return try ctx.emitInt(expr, @intCast(count));
                        }
                        if (std.mem.eql(u8, field_name, "data")) return base_reg;
                    }
                    if (dynamicArrayElementText(base_text) != null and std.mem.eql(u8, field_name, "count")) {
                        const reg = proc.num_registers;
                        proc.num_registers += 1;
                        try proc.instructions.append(program.allocator, .{ .opcode = .array_count, .dest = reg, .arg1 = base_reg, .source_node = expr });
                        return reg;
                    }
                    if (dynamicArrayElementText(base_text) != null and std.mem.eql(u8, field_name, "data")) {
                        const reg = proc.num_registers;
                        proc.num_registers += 1;
                        try proc.instructions.append(program.allocator, .{ .opcode = .array_data, .dest = reg, .arg1 = base_reg, .source_node = expr });
                        return reg;
                    }
                    if (std.mem.eql(u8, firstTypeWord(base_text), "Source_Code_Location")) {
                        const reg = proc.num_registers;
                        proc.num_registers += 1;
                        const field_index = try program.addString(field_name);
                        try proc.instructions.append(program.allocator, .{ .opcode = .source_location_get_field, .dest = reg, .arg1 = base_reg, .arg2 = field_index, .source_node = expr });
                        return reg;
                    }
                    if (isBuildOptionsValueType(base_text)) {
                        const reg = proc.num_registers;
                        proc.num_registers += 1;
                        const field_index = try program.addString(field_name);
                        try proc.instructions.append(program.allocator, .{ .opcode = .build_options_get_field, .dest = reg, .arg1 = base_reg, .arg2 = field_index, .source_node = expr });
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
                        if (isDynamicArrayTypeText(clean_field_type) or isStaticArrayTypeText(clean_field_type) or try typeTextIsEmbeddedStruct(ctx, clean_field_type, diag)) return addr;
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
                    if (staticArrayElementText(base_text)) |elem_text| {
                        const addr = try ctx.emitStaticArrayElementAddress(base, index, base_text, expr, diag);
                        if (try typeTextIsEmbeddedStruct(ctx, elem_text, diag)) return addr;
                        const reg = proc.num_registers;
                        proc.num_registers += 1;
                        const opcode: Bytecode.Opcode = if (try typeTextSize(ctx, elem_text, diag) == 1)
                            .load_ptr_byte
                        else if (std.mem.eql(u8, firstTypeWord(elem_text), "float") or std.mem.eql(u8, firstTypeWord(elem_text), "float32") or std.mem.eql(u8, firstTypeWord(elem_text), "float64"))
                            .load_ptr_float
                        else
                            .load_ptr;
                        try proc.instructions.append(program.allocator, .{ .opcode = opcode, .dest = reg, .arg1 = addr, .source_node = expr });
                        return reg;
                    }
                    if (dynamicArrayElementText(base_text)) |elem_text| {
                        const elem_size = try typeTextSize(ctx, elem_text, diag);
                        const elem_is_struct = try typeTextIsEmbeddedStruct(ctx, elem_text, diag);
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
                    if (!procContainsCompileTimeOnlyCompilerApi(ast, callee)) {
                        if (try ctx.tryEmitDirectProcCall(callee, args, expr, diag)) |reg| return reg;
                    }
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
                    const args = ast.extraSlice(ast.data(expr).rhs);
                    const field_name = ast.tokenSlice(ast.data(callee).rhs);
                    if (std.mem.eql(u8, field_name, "proc")) {
                        const allocator_reg = try ctx.genExpr(ast.data(callee).lhs, diag);
                        if (args.len >= 1) {
                            const mode_arg: NodeIndex = @intCast(args[0]);
                            if (ast.tag(mode_arg) == .field_access and ast.data(mode_arg).lhs == @import("Ast.zig").null_node) {
                                const mode_name = ast.tokenSlice(ast.data(mode_arg).rhs);
                                if (std.mem.eql(u8, mode_name, "STARTUP")) {
                                    for (args[1..]) |arg_idx| _ = try genCallArg(ctx, @intCast(arg_idx), diag);
                                    const reg = proc.num_registers;
                                    proc.num_registers += 1;
                                    try proc.instructions.append(program.allocator, .{ .opcode = .load_null_ptr, .dest = reg, .source_node = expr });
                                    return reg;
                                }
                                if (std.mem.eql(u8, mode_name, "IS_THIS_YOURS")) {
                                    if (args.len < 4) return diag.failAt(ast.tokens[ast.mainToken(expr)].start, "Allocator IS_THIS_YOURS call expects old memory as the fourth argument", .{});
                                    _ = try genCallArg(ctx, @intCast(args[1]), diag);
                                    _ = try genCallArg(ctx, @intCast(args[2]), diag);
                                    const memory_reg = try genCallArg(ctx, @intCast(args[3]), diag);
                                    if (args.len > 4) _ = try genCallArg(ctx, @intCast(args[4]), diag);
                                    const reg = proc.num_registers;
                                    proc.num_registers += 1;
                                    try proc.instructions.append(program.allocator, .{ .opcode = .allocator_owns, .dest = reg, .arg1 = allocator_reg, .arg2 = memory_reg, .source_node = expr });
                                    return reg;
                                }
                            }
                        }
                        var arg_regs = std.ArrayList(Bytecode.Register).empty;
                        defer arg_regs.deinit(program.allocator);
                        for (args) |arg_idx| {
                            const arg: NodeIndex = @intCast(arg_idx);
                            if (arg_regs.items.len == 5) break;
                            const source = if (ast.tag(arg) == .assign_stmt) ast.data(arg).rhs else arg;
                            try arg_regs.append(program.allocator, try ctx.genExpr(source, diag));
                        }
                        while (arg_regs.items.len < 5) try arg_regs.append(program.allocator, try ctx.emitInt(expr, 0));
                        const arg_start = try program.addCallArgs(arg_regs.items);
                        const reg = proc.num_registers;
                        proc.num_registers += 1;
                        try proc.instructions.append(program.allocator, .{ .opcode = .allocator_proc_call, .dest = reg, .arg1 = allocator_reg, .arg2 = @intCast(arg_regs.items.len), .arg3 = arg_start, .source_node = expr });
                        return reg;
                    }
                    _ = try ctx.genExpr(ast.data(callee).lhs, diag);
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
                if (std.mem.eql(u8, name, "quick_sort") or std.mem.eql(u8, name, "bubble_sort")) {
                    const args = ast.extraSlice(ast.data(expr).rhs);
                    if (args.len < 1) return diag.failAt(ast.tokens[ast.mainToken(expr)].start, "{s} expects an array argument", .{name});
                    const array_node: NodeIndex = @intCast(args[0]);
                    const array_type = typeTextForExpr(ctx, array_node, diag) orelse return diag.failAt(ast.tokens[ast.mainToken(array_node)].start, "{s} requires an array with known element type", .{name});
                    const static_elem = staticArrayElementText(array_type);
                    const dynamic_elem = dynamicArrayElementText(array_type);
                    const elem_type = static_elem orelse dynamic_elem orelse return diag.failAt(ast.tokens[ast.mainToken(array_node)].start, "{s} requires a static or dynamic array", .{name});
                    const kind = sortKindForElementText(elem_type) orelse return diag.failAt(ast.tokens[ast.mainToken(array_node)].start, "{s} does not support sorting element type '{s}' yet", .{ name, elem_type });
                    const elem_size = try typeTextSize(ctx, elem_type, diag);
                    const count: u32 = if (static_elem != null)
                        @intCast(try staticArrayCountFromText(ctx, array_type, diag) orelse return diag.failAt(ast.tokens[ast.mainToken(array_node)].start, "{s} requires a known static array count", .{name}))
                    else
                        0;
                    const array_reg = if (static_elem != null) try genAddressOfLvalue(ctx, array_node, diag) else try ctx.genExpr(array_node, diag);
                    const result = proc.num_registers;
                    proc.num_registers += 1;
                    try proc.instructions.append(program.allocator, .{
                        .opcode = .sort_array,
                        .dest = result,
                        .arg1 = array_reg,
                        .arg2 = count,
                        .arg3 = @intCast(@max(elem_size, 1)),
                        .arg4 = kind,
                        .arg5 = if (static_elem != null) 1 else 0,
                        .source_node = expr,
                    });
                    return result;
                }
                if (std.mem.eql(u8, name, "thread_init") or
                    std.mem.eql(u8, name, "thread_start") or
                    std.mem.eql(u8, name, "thread_deinit") or
                    std.mem.eql(u8, name, "thread_destroy") or
                    std.mem.eql(u8, name, "init") or
                    std.mem.eql(u8, name, "start") or
                    std.mem.eql(u8, name, "add_work") or
                    std.mem.eql(u8, name, "shutdown") or
                    std.mem.eql(u8, name, "lock") or
                    std.mem.eql(u8, name, "unlock") or
                    std.mem.eql(u8, name, "table_add") or
                    std.mem.eql(u8, name, "table_remove"))
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
                    var allocator_reg: ?Bytecode.Register = null;
                    for (args[1..]) |arg_idx| {
                        const arg: NodeIndex = @intCast(arg_idx);
                        if (ast.tag(arg) == .assign_stmt and std.mem.eql(u8, ast.tokenSlice(ast.mainToken(ast.data(arg).lhs)), "allocator")) {
                            allocator_reg = try ctx.genExpr(ast.data(arg).rhs, diag);
                        } else {
                            _ = try genCallArg(ctx, arg, diag);
                        }
                    }
                    const elem_size = try typeTextSize(ctx, ctx.nodeSource(@intCast(args[0])), diag);
                    const reg = proc.num_registers;
                    proc.num_registers += 1;
                    if (allocator_reg) |alloc_reg| {
                        const size_reg = try ctx.emitInt(expr, @intCast(@max(elem_size, 1)));
                        try proc.instructions.append(program.allocator, .{ .opcode = .alloc_heap_owned, .dest = reg, .arg1 = size_reg, .arg2 = alloc_reg, .source_node = expr });
                    } else {
                        try proc.instructions.append(program.allocator, .{ .opcode = .alloc_heap, .dest = reg, .arg1 = @intCast(@max(elem_size, 1)), .source_node = expr });
                    }
                    return reg;
                }
                if (std.mem.eql(u8, name, "NewArray")) {
                    const args = ast.extraSlice(ast.data(expr).rhs);
                    if (args.len < 2) return diag.failAt(ast.tokens[ast.mainToken(expr)].start, "NewArray expects a count and type argument", .{});
                    const count = try evalIntegerConstExpr(ctx, @intCast(args[0]), diag);
                    if (count < 0) return diag.failAt(ast.tokens[ast.mainToken(@as(NodeIndex, @intCast(args[0])))].start, "NewArray count must be non-negative", .{});
                    const elem_type: NodeIndex = @intCast(args[1]);
                    const elem_size = try typeTextSize(ctx, ctx.nodeSource(elem_type), diag);
                    for (args[2..]) |arg| {
                        const arg_node: NodeIndex = @intCast(arg);
                        if (ast.tag(arg_node) == .assign_stmt)
                            _ = try ctx.genExpr(ast.data(arg_node).rhs, diag)
                        else
                            _ = try genCallArg(ctx, arg_node, diag);
                    }
                    const reg = proc.num_registers;
                    proc.num_registers += 1;
                    var alignment: u64 = 0;
                    for (args[2..]) |arg| {
                        const arg_node: NodeIndex = @intCast(arg);
                        if (ast.tag(arg_node) == .assign_stmt and std.mem.eql(u8, ast.tokenSlice(ast.mainToken(ast.data(arg_node).lhs)), "alignment")) {
                            alignment = @intCast(try evalIntegerConstExpr(ctx, ast.data(arg_node).rhs, diag));
                        }
                    }
                    try proc.instructions.append(program.allocator, .{ .opcode = .new_array, .dest = reg, .arg1 = @intCast(count), .arg2 = @intCast(@max(elem_size, 1)), .arg3 = @intCast(alignment), .source_node = expr });
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
                    var allocator_reg: ?Bytecode.Register = null;
                    for (args[1..]) |arg_idx| {
                        const arg: NodeIndex = @intCast(arg_idx);
                        if (ast.tag(arg) == .assign_stmt and std.mem.eql(u8, ast.tokenSlice(ast.mainToken(ast.data(arg).lhs)), "allocator")) {
                            allocator_reg = try ctx.genExpr(ast.data(arg).rhs, diag);
                        } else {
                            _ = try genCallArg(ctx, arg, diag);
                        }
                    }
                    const size_reg = try ctx.genExpr(@intCast(args[0]), diag);
                    const reg = proc.num_registers;
                    proc.num_registers += 1;
                    if (allocator_reg) |alloc_reg| {
                        try proc.instructions.append(program.allocator, .{ .opcode = .alloc_heap_owned, .dest = reg, .arg1 = size_reg, .arg2 = alloc_reg, .source_node = expr });
                    } else {
                        try proc.instructions.append(program.allocator, .{ .opcode = .alloc_heap_reg, .dest = reg, .arg1 = size_reg, .source_node = expr });
                    }
                    return reg;
                }
                if (std.mem.eql(u8, name, "get")) {
                    const args = ast.extraSlice(ast.data(expr).rhs);
                    if (args.len < 2) return diag.failAt(ast.tokens[ast.mainToken(expr)].start, "get expects a pool pointer and size", .{});
                    const pool_ptr = try ctx.genExpr(@intCast(args[0]), diag);
                    const size_reg = try ctx.genExpr(@intCast(args[1]), diag);
                    const kind: u32 = if (typeTextForExpr(ctx, @intCast(args[0]), diag)) |arg_type|
                        if (std.mem.eql(u8, firstTypeWord(stripPointerText(arg_type)), "Flat_Pool")) 1 else 0
                    else
                        0;
                    const reg = proc.num_registers;
                    proc.num_registers += 1;
                    try proc.instructions.append(program.allocator, .{ .opcode = .pool_get, .dest = reg, .arg1 = pool_ptr, .arg2 = size_reg, .arg3 = kind, .source_node = expr });
                    return reg;
                }
                if (std.mem.eql(u8, name, "release") or std.mem.eql(u8, name, "fini")) {
                    const args = ast.extraSlice(ast.data(expr).rhs);
                    if (args.len == 0) return diag.failAt(ast.tokens[ast.mainToken(expr)].start, "{s} expects a pool pointer", .{name});
                    const pool_ptr = try ctx.genExpr(@intCast(args[0]), diag);
                    try proc.instructions.append(program.allocator, .{ .opcode = .pool_release, .arg1 = pool_ptr, .source_node = expr });
                    return pool_ptr;
                }
                if (std.mem.eql(u8, name, "reset")) {
                    const args = ast.extraSlice(ast.data(expr).rhs);
                    if (args.len == 0) return diag.failAt(ast.tokens[ast.mainToken(expr)].start, "reset expects a pool pointer", .{});
                    const pool_ptr = try ctx.genExpr(@intCast(args[0]), diag);
                    try proc.instructions.append(program.allocator, .{ .opcode = .pool_reset, .arg1 = pool_ptr, .source_node = expr });
                    for (args[1..]) |arg_idx| {
                        const arg: NodeIndex = @intCast(arg_idx);
                        if (ast.tag(arg) == .assign_stmt) _ = try ctx.genExpr(ast.data(arg).rhs, diag) else _ = try ctx.genExpr(arg, diag);
                    }
                    return pool_ptr;
                }
                if (std.mem.eql(u8, name, "set_allocators")) {
                    const args = ast.extraSlice(ast.data(expr).rhs);
                    for (args) |arg_idx| _ = try ctx.genExpr(@intCast(arg_idx), diag);
                    return try ctx.emitInt(expr, 0);
                }
                if (std.mem.eql(u8, name, "get_capabilities")) {
                    const args = ast.extraSlice(ast.data(expr).rhs);
                    if (args.len != 1) return diag.failAt(ast.tokens[ast.mainToken(expr)].start, "get_capabilities expects one Allocator", .{});
                    const allocator_reg = try ctx.genExpr(@intCast(args[0]), diag);
                    const reg = proc.num_registers;
                    proc.num_registers += 1;
                    try proc.instructions.append(program.allocator, .{ .opcode = .allocator_cap_flags, .dest = reg, .arg1 = allocator_reg, .source_node = expr });
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
                if (std.mem.eql(u8, name, "get_cpu_info")) {
                    const args = ast.extraSlice(ast.data(expr).rhs);
                    if (args.len != 0) return diag.failAt(ast.tokens[ast.mainToken(expr)].start, "get_cpu_info expects no arguments", .{});
                    return try ctx.emitInt(expr, 0);
                }
                if (std.mem.eql(u8, name, "check_feature") or std.mem.eql(u8, name, "has_feature")) {
                    const args = ast.extraSlice(ast.data(expr).rhs);
                    if (args.len != 2) return diag.failAt(ast.tokens[ast.mainToken(expr)].start, "{s} expects feature leaves and a feature flag", .{name});
                    _ = try ctx.genExpr(@intCast(args[0]), diag);
                    const feature_reg = try ctx.genExpr(@intCast(args[1]), diag);
                    const reg = proc.num_registers;
                    proc.num_registers += 1;
                    try proc.instructions.append(program.allocator, .{ .opcode = .cpu_has_feature, .dest = reg, .arg1 = feature_reg, .source_node = expr });
                    return reg;
                }
                if (std.mem.eql(u8, name, "compiler_read_file") or std.mem.eql(u8, name, "read_entire_file")) {
                    const args = ast.extraSlice(ast.data(expr).rhs);
                    if (args.len != 1) return diag.failAt(ast.tokens[ast.mainToken(expr)].start, "{s} expects one path string", .{name});
                    const path_reg = try ctx.genExpr(@intCast(args[0]), diag);
                    const reg = proc.num_registers;
                    proc.num_registers += 1;
                    try proc.instructions.append(program.allocator, .{ .opcode = .compiler_read_file, .dest = reg, .arg1 = path_reg, .source_node = expr });
                    return reg;
                }
                if (std.mem.eql(u8, name, "compiler_write_file") or std.mem.eql(u8, name, "write_entire_file")) {
                    const args = ast.extraSlice(ast.data(expr).rhs);
                    if (args.len != 2) return diag.failAt(ast.tokens[ast.mainToken(expr)].start, "{s} expects a path string and contents string", .{name});
                    const path_reg = try ctx.genExpr(@intCast(args[0]), diag);
                    const contents_reg = try ctx.genExpr(@intCast(args[1]), diag);
                    const reg = proc.num_registers;
                    proc.num_registers += 1;
                    try proc.instructions.append(program.allocator, .{ .opcode = .compiler_write_file, .dest = reg, .arg1 = path_reg, .arg2 = contents_reg, .source_node = expr });
                    return reg;
                }
                if (std.mem.eql(u8, name, "get_command_line_arguments")) {
                    const args = ast.extraSlice(ast.data(expr).rhs);
                    if (args.len != 0) return diag.failAt(ast.tokens[ast.mainToken(expr)].start, "get_command_line_arguments expects no arguments", .{});
                    const reg = proc.num_registers;
                    proc.num_registers += 1;
                    try proc.instructions.append(program.allocator, .{ .opcode = .get_command_line_arguments, .dest = reg, .source_node = expr });
                    return reg;
                }
                if (std.mem.eql(u8, name, "make_directory_if_it_does_not_exist")) {
                    const args = ast.extraSlice(ast.data(expr).rhs);
                    if (args.len < 1 or args.len > 2) return diag.failAt(ast.tokens[ast.mainToken(expr)].start, "make_directory_if_it_does_not_exist expects a path string and optional recursive flag", .{});
                    const path_reg = try ctx.genExpr(handleArgNode(ast, @intCast(args[0])), diag);
                    if (args.len == 2) _ = try ctx.genExpr(handleArgNode(ast, @intCast(args[1])), diag);
                    const reg = proc.num_registers;
                    proc.num_registers += 1;
                    try proc.instructions.append(program.allocator, .{ .opcode = .make_directory, .dest = reg, .arg1 = path_reg, .source_node = expr });
                    return reg;
                }
                if (std.mem.eql(u8, name, "delete_directory")) {
                    const args = ast.extraSlice(ast.data(expr).rhs);
                    if (args.len != 1) return diag.failAt(ast.tokens[ast.mainToken(expr)].start, "delete_directory expects one path string", .{});
                    const path_reg = try ctx.genExpr(@intCast(args[0]), diag);
                    const reg = proc.num_registers;
                    proc.num_registers += 1;
                    try proc.instructions.append(program.allocator, .{ .opcode = .delete_directory, .dest = reg, .arg1 = path_reg, .source_node = expr });
                    return reg;
                }
                if (std.mem.eql(u8, name, "file_exists")) {
                    const args = ast.extraSlice(ast.data(expr).rhs);
                    if (args.len != 1) return diag.failAt(ast.tokens[ast.mainToken(expr)].start, "file_exists expects one path string", .{});
                    const path_reg = try ctx.genExpr(@intCast(args[0]), diag);
                    const reg = proc.num_registers;
                    proc.num_registers += 1;
                    try proc.instructions.append(program.allocator, .{ .opcode = .file_exists, .dest = reg, .arg1 = path_reg, .source_node = expr });
                    return reg;
                }
                if (std.mem.eql(u8, name, "file_open")) {
                    const args = ast.extraSlice(ast.data(expr).rhs);
                    if (args.len < 1) return diag.failAt(ast.tokens[ast.mainToken(expr)].start, "file_open expects one path string", .{});
                    const path_reg = try ctx.genExpr(@intCast(args[0]), diag);
                    const reg = proc.num_registers;
                    proc.num_registers += 1;
                    try proc.instructions.append(program.allocator, .{ .opcode = .file_open, .dest = reg, .arg1 = path_reg, .arg2 = try namedBoolArg(ctx, args[1..], "for_writing", false, diag), .arg3 = try namedBoolArg(ctx, args[1..], "keep_existing_content", false, diag), .source_node = expr });
                    return reg;
                }
                if (std.mem.eql(u8, name, "file_close")) {
                    const args = ast.extraSlice(ast.data(expr).rhs);
                    if (args.len != 1) return diag.failAt(ast.tokens[ast.mainToken(expr)].start, "file_close expects one file handle", .{});
                    const handle_reg = try ctx.genExpr(handleArgNode(ast, @intCast(args[0])), diag);
                    try proc.instructions.append(program.allocator, .{ .opcode = .file_close, .arg1 = handle_reg, .source_node = expr });
                    return handle_reg;
                }
                if (std.mem.eql(u8, name, "file_length")) {
                    const args = ast.extraSlice(ast.data(expr).rhs);
                    if (args.len != 1) return diag.failAt(ast.tokens[ast.mainToken(expr)].start, "file_length expects one file handle", .{});
                    const handle_reg = try ctx.genExpr(handleArgNode(ast, @intCast(args[0])), diag);
                    const reg = proc.num_registers;
                    proc.num_registers += 1;
                    try proc.instructions.append(program.allocator, .{ .opcode = .file_length, .dest = reg, .arg1 = handle_reg, .source_node = expr });
                    return reg;
                }
                if (std.mem.eql(u8, name, "file_set_position")) {
                    const args = ast.extraSlice(ast.data(expr).rhs);
                    if (args.len != 2) return diag.failAt(ast.tokens[ast.mainToken(expr)].start, "file_set_position expects a file handle and position", .{});
                    const handle_reg = try ctx.genExpr(handleArgNode(ast, @intCast(args[0])), diag);
                    const pos_reg = try ctx.genExpr(@intCast(args[1]), diag);
                    const reg = proc.num_registers;
                    proc.num_registers += 1;
                    try proc.instructions.append(program.allocator, .{ .opcode = .file_set_position, .dest = reg, .arg1 = handle_reg, .arg2 = pos_reg, .source_node = expr });
                    return reg;
                }
                if (std.mem.eql(u8, name, "file_write")) {
                    const args = ast.extraSlice(ast.data(expr).rhs);
                    if (args.len < 2 or args.len > 3) return diag.failAt(ast.tokens[ast.mainToken(expr)].start, "file_write expects a file handle, string or buffer, and optional length", .{});
                    const handle_reg = try ctx.genExpr(handleArgNode(ast, @intCast(args[0])), diag);
                    const data_reg = try ctx.genExpr(@intCast(args[1]), diag);
                    const len_reg = if (args.len == 3) try ctx.genExpr(@intCast(args[2]), diag) else data_reg;
                    const reg = proc.num_registers;
                    proc.num_registers += 1;
                    try proc.instructions.append(program.allocator, .{ .opcode = .file_write, .dest = reg, .arg1 = handle_reg, .arg2 = data_reg, .arg3 = len_reg, .arg4 = if (args.len == 2) 1 else 0, .source_node = expr });
                    return reg;
                }
                if (std.mem.eql(u8, name, "file_read")) {
                    const args = ast.extraSlice(ast.data(expr).rhs);
                    if (args.len != 3) return diag.failAt(ast.tokens[ast.mainToken(expr)].start, "file_read expects a file handle, buffer, and byte count", .{});
                    const handle_reg = try ctx.genExpr(handleArgNode(ast, @intCast(args[0])), diag);
                    const data_reg = try ctx.genExpr(@intCast(args[1]), diag);
                    const len_reg = try ctx.genExpr(@intCast(args[2]), diag);
                    const reg = proc.num_registers;
                    proc.num_registers += 1;
                    try proc.instructions.append(program.allocator, .{ .opcode = .file_read, .dest = reg, .arg1 = handle_reg, .arg2 = data_reg, .arg3 = len_reg, .source_node = expr });
                    return reg;
                }
                if (std.mem.eql(u8, name, "read")) {
                    const args = ast.extraSlice(ast.data(expr).rhs);
                    if (args.len != 3) return diag.failAt(ast.tokens[ast.mainToken(expr)].start, "read expects a file descriptor, buffer, and byte count", .{});
                    const fd_reg = try ctx.genExpr(@intCast(args[0]), diag);
                    const data_reg = try ctx.genExpr(@intCast(args[1]), diag);
                    const len_reg = try ctx.genExpr(@intCast(args[2]), diag);
                    const reg = proc.num_registers;
                    proc.num_registers += 1;
                    try proc.instructions.append(program.allocator, .{ .opcode = .posix_read, .dest = reg, .arg1 = fd_reg, .arg2 = data_reg, .arg3 = len_reg, .source_node = expr });
                    return reg;
                }
                if (std.mem.eql(u8, name, "GetStdHandle")) {
                    const args = ast.extraSlice(ast.data(expr).rhs);
                    if (args.len != 1) return diag.failAt(ast.tokens[ast.mainToken(expr)].start, "GetStdHandle expects one standard-handle selector", .{});
                    _ = try ctx.genExpr(@intCast(args[0]), diag);
                    return try ctx.emitInt(expr, 0);
                }
                if (std.mem.eql(u8, name, "reset_temporary_storage")) {
                    const args = ast.extraSlice(ast.data(expr).rhs);
                    if (args.len != 0) return diag.failAt(ast.tokens[ast.mainToken(expr)].start, "reset_temporary_storage expects no arguments", .{});
                    return try ctx.emitInt(expr, 0);
                }
                if (std.mem.eql(u8, name, "equal")) {
                    const args = ast.extraSlice(ast.data(expr).rhs);
                    if (args.len != 2) return diag.failAt(ast.tokens[ast.mainToken(expr)].start, "equal expects two arguments", .{});
                    const lhs = try ctx.genExpr(@intCast(args[0]), diag);
                    const rhs = try ctx.genExpr(@intCast(args[1]), diag);
                    const reg = proc.num_registers;
                    proc.num_registers += 1;
                    try proc.instructions.append(program.allocator, .{ .opcode = .cmp_eq, .dest = reg, .arg1 = lhs, .arg2 = rhs, .source_node = expr });
                    return reg;
                }
                if (std.mem.eql(u8, name, "push_allocator")) {
                    const args = ast.extraSlice(ast.data(expr).rhs);
                    if (args.len < 1 or args.len > 2) return diag.failAt(ast.tokens[ast.mainToken(expr)].start, "push_allocator expects an allocator and optional data pointer", .{});
                    for (args) |arg| _ = try ctx.genExpr(@intCast(arg), diag);
                    return try ctx.emitInt(expr, 0);
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
                    const elem_is_struct = try typeTextIsEmbeddedStruct(ctx, elem_ty, diag);
                    var last_reg: ?Bytecode.Register = null;
                    if (args.len == 1) {
                        last_reg = try ctx.genDefaultValue(@import("Ast.zig").null_node, expr, diag);
                    } else {
                        for (args[1..]) |item_idx| {
                            const item_node: NodeIndex = @intCast(item_idx);
                            const spread = ast.tag(item_node) == .unary_expr and ast.tokens[ast.mainToken(item_node)].tag == .dot_dot;
                            const item_reg = try ctx.genExpr(if (spread) ast.data(item_node).lhs else item_node, diag);
                            const reg = proc.num_registers;
                            proc.num_registers += 1;
                            try proc.instructions.append(program.allocator, .{ .opcode = .array_add, .dest = reg, .arg1 = array_slot, .arg2 = item_reg, .arg3 = @intCast(elem_size), .arg4 = if (elem_is_struct) 1 else 0, .arg5 = if (spread) 1 else 0, .source_node = expr });
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
                if (std.mem.eql(u8, name, "sqrt") or std.mem.eql(u8, name, "cos")) {
                    const args = ast.extraSlice(ast.data(expr).rhs);
                    if (args.len != 1) return diag.failAt(ast.tokens[ast.mainToken(expr)].start, "{s} expects one numeric argument", .{name});
                    const arg_reg = try ctx.genExpr(@intCast(args[0]), diag);
                    const reg = proc.num_registers;
                    proc.num_registers += 1;
                    try proc.instructions.append(program.allocator, .{ .opcode = if (std.mem.eql(u8, name, "sqrt")) .sqrt_float else .cos_float, .dest = reg, .arg1 = arg_reg, .source_node = expr });
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
                    try proc.instructions.append(program.allocator, .{ .opcode = if (std.mem.eql(u8, name, "get_time")) .get_time_seconds else .seconds_since_init, .dest = reg, .source_node = expr });
                    return reg;
                }
                if (std.mem.eql(u8, name, "sleep_milliseconds")) {
                    const args = ast.extraSlice(ast.data(expr).rhs);
                    if (args.len != 1) return diag.failAt(ast.tokens[ast.mainToken(expr)].start, "sleep_milliseconds expects one argument", .{});
                    const ms_reg = try ctx.genExpr(@intCast(args[0]), diag);
                    const reg = proc.num_registers;
                    proc.num_registers += 1;
                    try proc.instructions.append(program.allocator, .{ .opcode = .sleep_milliseconds, .dest = reg, .arg1 = ms_reg, .source_node = expr });
                    return reg;
                }
                if (std.mem.eql(u8, name, "array_free")) {
                    const args = ast.extraSlice(ast.data(expr).rhs);
                    if (args.len != 1) return diag.failAt(ast.tokens[ast.mainToken(expr)].start, "array_free expects one argument", .{});
                    const array_reg = try ctx.genExpr(@intCast(args[0]), diag);
                    const reg = proc.num_registers;
                    proc.num_registers += 1;
                    try proc.instructions.append(program.allocator, .{ .opcode = .array_free, .arg1 = array_reg, .source_node = expr });
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
                    const source = try ctx.genExpr(@intCast(args[0]), diag);
                    const reg = proc.num_registers;
                    proc.num_registers += 1;
                    try proc.instructions.append(program.allocator, .{ .opcode = .to_float64_seconds, .dest = reg, .arg1 = source, .source_node = expr });
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
                            if (!procContainsCompileTimeOnlyCompilerApi(ast, target_proc)) {
                                if (try ctx.tryEmitDirectProcCall(target_proc, args, expr, diag)) |reg| return reg;
                            }
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

        if (try ctx.genStringRuntimeCall(name, expr, args, diag)) |reg| return reg;

        if (std.mem.eql(u8, name, "get_number_of_processors")) {
            if (args.len != 0) return diag.failAt(ast.tokens[ast.mainToken(expr)].start, "get_number_of_processors expects no arguments", .{});
            const count = std.Thread.getCpuCount() catch 1;
            return try ctx.emitInt(expr, @intCast(count));
        }
        if (std.mem.eql(u8, name, "max")) {
            if (args.len != 2) return diag.failAt(ast.tokens[ast.mainToken(expr)].start, "max expects two arguments", .{});
            const lhs = try ctx.genExpr(handleArgNode(ast, @intCast(args[0])), diag);
            const rhs = try ctx.genExpr(handleArgNode(ast, @intCast(args[1])), diag);
            const cmp = ctx.proc.num_registers;
            ctx.proc.num_registers += 1;
            try ctx.proc.instructions.append(ctx.program.allocator, .{ .opcode = .cmp_gt_int, .dest = cmp, .arg1 = lhs, .arg2 = rhs, .source_node = expr });
            const reg = ctx.proc.num_registers;
            ctx.proc.num_registers += 1;
            try ctx.proc.instructions.append(ctx.program.allocator, .{ .opcode = .select_value, .dest = reg, .arg1 = cmp, .arg2 = lhs, .arg3 = rhs, .source_node = expr });
            return reg;
        }
        if (std.mem.eql(u8, name, "sqrt") or std.mem.eql(u8, name, "cos")) {
            if (args.len != 1) return diag.failAt(ast.tokens[ast.mainToken(expr)].start, "{s} expects one numeric argument", .{name});
            const arg_reg = try ctx.genExpr(handleArgNode(ast, @intCast(args[0])), diag);
            const reg = ctx.proc.num_registers;
            ctx.proc.num_registers += 1;
            try ctx.proc.instructions.append(ctx.program.allocator, .{ .opcode = if (std.mem.eql(u8, name, "sqrt")) .sqrt_float else .cos_float, .dest = reg, .arg1 = arg_reg, .source_node = expr });
            return reg;
        }
        if (std.mem.eql(u8, name, "make_vector2") or std.mem.eql(u8, name, "make_vector3")) {
            for (args) |arg| _ = try ctx.genExpr(handleArgNode(ast, @intCast(arg)), diag);
            return try ctx.genDefaultValueFromText(if (std.mem.eql(u8, name, "make_vector2")) "Vector2" else "Vector3", expr, diag);
        }

        if (std.mem.eql(u8, name, "compiler_create_workspace")) {
            for (args) |arg| _ = try ctx.genExpr(@intCast(arg), diag);
            if (!ctx.compile_time_host) return try ctx.emitInt(expr, 0);
            const reg = ctx.proc.num_registers;
            ctx.proc.num_registers += 1;
            try ctx.proc.instructions.append(ctx.program.allocator, .{ .opcode = .host_compiler_create_workspace, .dest = reg, .source_node = expr });
            return reg;
        }
        if (std.mem.eql(u8, name, "get_current_workspace")) {
            for (args) |arg| _ = try ctx.genExpr(@intCast(arg), diag);
            if (!ctx.compile_time_host) return try ctx.emitInt(expr, 0);
            const reg = ctx.proc.num_registers;
            ctx.proc.num_registers += 1;
            try ctx.proc.instructions.append(ctx.program.allocator, .{ .opcode = .host_get_current_workspace, .dest = reg, .source_node = expr });
            return reg;
        }
        if (std.mem.eql(u8, name, "compiler_wait_for_message")) {
            for (args) |arg| _ = try ctx.genExpr(@intCast(arg), diag);
            return try ctx.emitInt(expr, 0);
        }
        if (std.mem.eql(u8, name, "run_command")) {
            if (args.len != 1) return diag.failAt(ast.tokens[ast.mainToken(expr)].start, "run_command expects one command string", .{});
            const command = try genCallArg(ctx, @intCast(args[0]), diag);
            const reg = ctx.proc.num_registers;
            ctx.proc.num_registers += 1;
            try ctx.proc.instructions.append(ctx.program.allocator, .{ .opcode = .host_run_command, .dest = reg, .arg1 = command, .source_node = expr });
            return reg;
        }
        if (std.mem.eql(u8, name, "copy_file")) {
            if (args.len != 2) return diag.failAt(ast.tokens[ast.mainToken(expr)].start, "copy_file expects source and destination strings", .{});
            const src = try genCallArg(ctx, @intCast(args[0]), diag);
            const dest = try genCallArg(ctx, @intCast(args[1]), diag);
            const reg = ctx.proc.num_registers;
            ctx.proc.num_registers += 1;
            try ctx.proc.instructions.append(ctx.program.allocator, .{ .opcode = .host_copy_file, .dest = reg, .arg1 = src, .arg2 = dest, .source_node = expr });
            return reg;
        }
        if (std.mem.eql(u8, name, "build_cpp_dynamic_lib") or std.mem.eql(u8, name, "build_cpp")) {
            if (args.len < 2) return diag.failAt(ast.tokens[ast.mainToken(expr)].start, "{s} expects a library name and source path", .{name});
            const lib_name = try genCallArg(ctx, handleArgNode(ast, @intCast(args[0])), diag);
            const source = try genCallArg(ctx, handleArgNode(ast, @intCast(args[1])), diag);
            for (args[2..]) |arg| _ = try genCallArg(ctx, handleArgNode(ast, @intCast(arg)), diag);
            const reg = ctx.proc.num_registers;
            ctx.proc.num_registers += 1;
            try ctx.proc.instructions.append(ctx.program.allocator, .{ .opcode = .host_build_cpp_dynamic_lib, .dest = reg, .arg1 = lib_name, .arg2 = source, .source_node = expr });
            return reg;
        }
        if (std.mem.eql(u8, name, "cpp_link_library")) {
            for (args) |arg| _ = try genCallArg(ctx, @intCast(arg), diag);
            return try ctx.emitBool(expr, true);
        }
        if (std.mem.eql(u8, name, "generate_bindings") and args.len == 2) {
            const options = try genCallArg(ctx, @intCast(args[0]), diag);
            const output = try genCallArg(ctx, @intCast(args[1]), diag);
            const reg = ctx.proc.num_registers;
            ctx.proc.num_registers += 1;
            try ctx.proc.instructions.append(ctx.program.allocator, .{ .opcode = .host_generate_bindings, .dest = reg, .arg1 = options, .arg2 = output, .source_node = expr });
            return reg;
        }
        if (std.mem.eql(u8, name, "add_build_string")) {
            if (args.len == 0 or args.len > 2) return diag.failAt(ast.tokens[ast.mainToken(expr)].start, "add_build_string expects source text and an optional workspace", .{});
            const source = try genCallArg(ctx, @intCast(args[0]), diag);
            const workspace = if (args.len >= 2)
                try genCallArg(ctx, @intCast(args[1]), diag)
            else
                try ctx.emitInt(expr, -1);
            const reg = ctx.proc.num_registers;
            ctx.proc.num_registers += 1;
            try ctx.proc.instructions.append(ctx.program.allocator, .{ .opcode = .host_add_build_string, .dest = reg, .arg1 = source, .arg2 = workspace, .source_node = expr });
            return reg;
        }
        if (std.mem.eql(u8, name, "add_global_data")) {
            if (args.len == 0) return diag.failAt(ast.tokens[ast.mainToken(expr)].start, "add_global_data expects at least one data argument", .{});
            const data = try genCallArg(ctx, @intCast(args[0]), diag);
            for (args[1..]) |arg| _ = try genCallArg(ctx, @intCast(arg), diag);
            return data;
        }
        if (std.mem.eql(u8, name, "parse_plugin_arguments")) {
            for (args) |arg| _ = try genCallArg(ctx, @intCast(arg), diag);
            return try ctx.emitBool(expr, true);
        }
        if (std.mem.eql(u8, name, "code_to_string")) {
            if (args.len != 1) return diag.failAt(ast.tokens[ast.mainToken(expr)].start, "code_to_string expects one Code argument", .{});
            return try ctx.genCodeValueExpr(@intCast(args[0]), expr, diag);
        }
        if (std.mem.eql(u8, name, "compiler_get_nodes")) {
            if (args.len != 1) return diag.failAt(ast.tokens[ast.mainToken(expr)].start, "compiler_get_nodes expects one Code argument", .{});
            const source = try ctx.genCodeValueExpr(@intCast(args[0]), expr, diag);
            const reg = ctx.proc.num_registers;
            ctx.proc.num_registers += 1;
            try ctx.proc.instructions.append(ctx.program.allocator, .{ .opcode = .compiler_get_nodes_root, .dest = reg, .arg1 = source, .source_node = expr });
            return reg;
        }
        if (std.mem.eql(u8, name, "compiler_get_code")) {
            if (args.len != 1) return diag.failAt(ast.tokens[ast.mainToken(expr)].start, "compiler_get_code expects one Code_Node argument", .{});
            const node = try ctx.genExpr(@intCast(args[0]), diag);
            const reg = ctx.proc.num_registers;
            ctx.proc.num_registers += 1;
            try ctx.proc.instructions.append(ctx.program.allocator, .{ .opcode = .code_node_to_code, .dest = reg, .arg1 = node, .source_node = expr });
            return reg;
        }
        if (std.mem.eql(u8, name, "get_build_options")) {
            const workspace_reg = if (args.len > 0) try ctx.genExpr(@intCast(args[0]), diag) else std.math.maxInt(u32);
            const reg = ctx.proc.num_registers;
            ctx.proc.num_registers += 1;
            try ctx.proc.instructions.append(ctx.program.allocator, .{ .opcode = .load_build_options, .dest = reg, .arg1 = workspace_reg, .source_node = expr });
            return reg;
        }
        if (std.mem.eql(u8, name, "make_location")) {
            const target = if (args.len > 0) ctx.locationTargetNode(@intCast(args[0])) else expr;
            return try ctx.emitSourceLocation(target, expr, diag);
        }
        if (std.mem.eql(u8, name, "print_expression")) {
            if (args.len != 2) return diag.failAt(ast.tokens[ast.mainToken(expr)].start, "print_expression expects a builder pointer and a Code_Node", .{});
            const slot = try builderSlotArg(ctx, @intCast(args[0]), diag);
            const node = try ctx.genExpr(@intCast(args[1]), diag);
            try ctx.proc.instructions.append(ctx.program.allocator, .{ .opcode = .string_builder_append_string, .arg1 = slot, .arg2 = node, .source_node = expr });
            return slot;
        }
        if (std.mem.eql(u8, name, "set_build_options") or
            std.mem.eql(u8, name, "set_build_options_dc") or
            std.mem.eql(u8, name, "set_optimization") or
            std.mem.eql(u8, name, "compiler_begin_intercept") or
            std.mem.eql(u8, name, "compiler_end_intercept") or
            std.mem.eql(u8, name, "compiler_set_workspace_status") or
            std.mem.eql(u8, name, "compiler_report") or
            std.mem.eql(u8, name, "add_build_file"))
        {
            for (args) |arg| _ = try ctx.genExpr(@intCast(arg), diag);
            return try ctx.emitInt(expr, 0);
        }
        return null;
    }

    fn genStringRuntimeCall(ctx: *GenContext, name: []const u8, expr: NodeIndex, args: []const u32, diag: Diagnostic) !?Bytecode.Register {
        const ast = ctx.ast;
        const proc = ctx.proc;
        const program = ctx.program;
        if (std.mem.eql(u8, name, "init_string_builder")) {
            if (args.len != 1) return diag.failAt(ast.tokens[ast.mainToken(expr)].start, "init_string_builder expects one builder pointer", .{});
            const slot = try builderSlotArg(ctx, @intCast(args[0]), diag);
            try proc.instructions.append(program.allocator, .{ .opcode = .string_builder_init, .arg1 = slot, .source_node = expr });
            return slot;
        }
        if (std.mem.eql(u8, name, "free_buffers")) {
            if (args.len != 1) return diag.failAt(ast.tokens[ast.mainToken(expr)].start, "free_buffers expects one builder pointer", .{});
            const slot = try builderSlotArg(ctx, @intCast(args[0]), diag);
            try proc.instructions.append(program.allocator, .{ .opcode = .string_builder_free, .arg1 = slot, .source_node = expr });
            return slot;
        }
        if (std.mem.eql(u8, name, "append")) {
            if (args.len != 2) return diag.failAt(ast.tokens[ast.mainToken(expr)].start, "append expects a builder pointer and value", .{});
            const slot = try builderSlotArg(ctx, @intCast(args[0]), diag);
            const value = try genCallArg(ctx, @intCast(args[1]), diag);
            try proc.instructions.append(program.allocator, .{ .opcode = .string_builder_append_string, .arg1 = slot, .arg2 = value, .source_node = expr });
            return value;
        }
        if (std.mem.eql(u8, name, "print_to_builder")) {
            if (args.len < 2) return diag.failAt(ast.tokens[ast.mainToken(expr)].start, "print_to_builder expects a builder pointer, format string, and optional arguments", .{});
            const slot = try builderSlotArg(ctx, @intCast(args[0]), diag);
            const fmt_node: NodeIndex = @intCast(args[1]);
            if (stringLiteralPayloadNode(ctx, fmt_node)) |literal_fmt| {
                try emitFormattedBuilderAppend(ctx, slot, literal_fmt, args[2..], diag);
            } else {
                const fmt = try ctx.genExpr(fmt_node, diag);
                if (args.len == 2) {
                    try proc.instructions.append(program.allocator, .{ .opcode = .string_builder_append_string, .arg1 = slot, .arg2 = fmt, .source_node = fmt_node });
                } else {
                    var arg_regs = std.ArrayList(Bytecode.Register).empty;
                    defer arg_regs.deinit(program.allocator);
                    for (args[2..]) |arg| try arg_regs.append(program.allocator, try genCallArg(ctx, @intCast(arg), diag));
                    const start = try program.addCallArgs(arg_regs.items);
                    try proc.instructions.append(program.allocator, .{ .opcode = .string_builder_append_format, .arg1 = slot, .arg2 = fmt, .arg3 = start, .arg4 = @intCast(arg_regs.items.len), .source_node = expr });
                }
            }
            return slot;
        }
        if (std.mem.eql(u8, name, "builder_string_length")) {
            if (args.len != 1) return diag.failAt(ast.tokens[ast.mainToken(expr)].start, "builder_string_length expects one builder pointer", .{});
            const slot = try builderSlotArg(ctx, @intCast(args[0]), diag);
            const reg = proc.num_registers;
            proc.num_registers += 1;
            try proc.instructions.append(program.allocator, .{ .opcode = .string_builder_length, .dest = reg, .arg1 = slot, .source_node = expr });
            return reg;
        }
        if (std.mem.eql(u8, name, "builder_to_string")) {
            if (args.len < 1) return diag.failAt(ast.tokens[ast.mainToken(expr)].start, "builder_to_string expects one builder pointer", .{});
            const slot = try builderSlotArg(ctx, @intCast(args[0]), diag);
            for (args[1..]) |arg_idx| {
                const arg: NodeIndex = @intCast(arg_idx);
                if (ast.tag(arg) != .assign_stmt) _ = try ctx.genExpr(arg, diag);
            }
            const reg = proc.num_registers;
            proc.num_registers += 1;
            try proc.instructions.append(program.allocator, .{ .opcode = .string_builder_to_string, .dest = reg, .arg1 = slot, .source_node = expr });
            return reg;
        }
        if (std.mem.eql(u8, name, "sprint") or std.mem.eql(u8, name, "tprint") or std.mem.eql(u8, name, "join")) {
            return try ctx.genStringBuildResult(name, expr, args, diag);
        }
        if (std.mem.eql(u8, name, "copy_string")) {
            if (args.len != 1) return diag.failAt(ast.tokens[ast.mainToken(expr)].start, "copy_string expects one string", .{});
            const source = try ctx.genExpr(@intCast(args[0]), diag);
            const reg = proc.num_registers;
            proc.num_registers += 1;
            try proc.instructions.append(program.allocator, .{ .opcode = .string_copy, .dest = reg, .arg1 = source, .source_node = expr });
            return reg;
        }
        if (std.mem.eql(u8, name, "to_c_string")) {
            if (args.len != 1) return diag.failAt(ast.tokens[ast.mainToken(expr)].start, "to_c_string expects one string", .{});
            const source = try ctx.genExpr(@intCast(args[0]), diag);
            const reg = proc.num_registers;
            proc.num_registers += 1;
            try proc.instructions.append(program.allocator, .{ .opcode = .string_to_c, .dest = reg, .arg1 = source, .source_node = expr });
            return reg;
        }
        if (std.mem.eql(u8, name, "to_string")) {
            if (args.len != 1 and args.len != 2) return diag.failAt(ast.tokens[ast.mainToken(expr)].start, "to_string expects a C string pointer or data pointer and byte count", .{});
            const source = try ctx.genExpr(@intCast(args[0]), diag);
            const reg = proc.num_registers;
            proc.num_registers += 1;
            if (args.len == 1) {
                try proc.instructions.append(program.allocator, .{ .opcode = .string_from_c, .dest = reg, .arg1 = source, .source_node = expr });
            } else {
                const len = try ctx.genExpr(@intCast(args[1]), diag);
                try proc.instructions.append(program.allocator, .{ .opcode = .string_from_parts, .dest = reg, .arg1 = source, .arg2 = len, .source_node = expr });
            }
            return reg;
        }
        if (std.mem.eql(u8, name, "c_style_strlen")) {
            if (args.len != 1) return diag.failAt(ast.tokens[ast.mainToken(expr)].start, "c_style_strlen expects one C string pointer", .{});
            const source = try ctx.genExpr(@intCast(args[0]), diag);
            const string_reg = proc.num_registers;
            proc.num_registers += 1;
            try proc.instructions.append(program.allocator, .{ .opcode = .string_from_c, .dest = string_reg, .arg1 = source, .source_node = expr });
            const len_reg = proc.num_registers;
            proc.num_registers += 1;
            try proc.instructions.append(program.allocator, .{ .opcode = .string_len, .dest = len_reg, .arg1 = string_reg, .source_node = expr });
            return len_reg;
        }
        if (std.mem.eql(u8, name, "trim")) {
            if (args.len != 1) return diag.failAt(ast.tokens[ast.mainToken(expr)].start, "trim expects one string", .{});
            const source = try ctx.genExpr(@intCast(args[0]), diag);
            const reg = proc.num_registers;
            proc.num_registers += 1;
            try proc.instructions.append(program.allocator, .{ .opcode = .string_trim, .dest = reg, .arg1 = source, .source_node = expr });
            return reg;
        }
        if (std.mem.eql(u8, name, "string_to_int") or std.mem.eql(u8, name, "parse_int") or std.mem.eql(u8, name, "to_integer") or std.mem.eql(u8, name, "string_to_float")) {
            if (args.len != 1) return diag.failAt(ast.tokens[ast.mainToken(expr)].start, "{s} expects one string", .{name});
            const source = try ctx.genExpr(handleArgNode(ast, @intCast(args[0])), diag);
            const reg = proc.num_registers;
            proc.num_registers += 1;
            const ok_reg = proc.num_registers;
            proc.num_registers += 1;
            try proc.instructions.append(program.allocator, .{ .opcode = if (std.mem.eql(u8, name, "string_to_float")) .string_parse_float else .string_parse_int, .dest = reg, .arg1 = source, .arg2 = ok_reg, .source_node = expr });
            return reg;
        }
        if (std.mem.eql(u8, name, "replace")) {
            if (args.len != 3) return diag.failAt(ast.tokens[ast.mainToken(expr)].start, "replace expects source, search string, and replacement string", .{});
            const source = try ctx.genExpr(@intCast(args[0]), diag);
            const needle = try ctx.genExpr(@intCast(args[1]), diag);
            const replacement = try ctx.genExpr(@intCast(args[2]), diag);
            const reg = proc.num_registers;
            proc.num_registers += 1;
            try proc.instructions.append(program.allocator, .{ .opcode = .string_replace, .dest = reg, .arg1 = source, .arg2 = needle, .arg3 = replacement, .source_node = expr });
            return reg;
        }
        if (std.mem.eql(u8, name, "slice")) {
            if (args.len != 3) return diag.failAt(ast.tokens[ast.mainToken(expr)].start, "slice expects source, start, and count", .{});
            const source = try ctx.genExpr(@intCast(args[0]), diag);
            const start = try ctx.genExpr(@intCast(args[1]), diag);
            const len = try ctx.genExpr(@intCast(args[2]), diag);
            const reg = proc.num_registers;
            proc.num_registers += 1;
            try proc.instructions.append(program.allocator, .{ .opcode = .string_slice, .dest = reg, .arg1 = source, .arg2 = start, .arg3 = len, .source_node = expr });
            return reg;
        }
        if (std.mem.eql(u8, name, "compare") or std.mem.eql(u8, name, "compare_strings") or std.mem.eql(u8, name, "contains") or std.mem.eql(u8, name, "begins_with") or std.mem.eql(u8, name, "find_index_from_left") or std.mem.eql(u8, name, "find_index_from_right")) {
            if (args.len != 2) return diag.failAt(ast.tokens[ast.mainToken(expr)].start, "{s} expects two strings", .{name});
            const lhs = try ctx.genExpr(@intCast(args[0]), diag);
            const rhs = try ctx.genExpr(@intCast(args[1]), diag);
            const reg = proc.num_registers;
            proc.num_registers += 1;
            const opcode: Bytecode.Opcode = if (std.mem.eql(u8, name, "compare") or std.mem.eql(u8, name, "compare_strings"))
                .string_compare
            else if (std.mem.eql(u8, name, "contains"))
                .string_contains
            else if (std.mem.eql(u8, name, "begins_with"))
                .string_begins_with
            else
                .string_find;
            try proc.instructions.append(program.allocator, .{ .opcode = opcode, .dest = reg, .arg1 = lhs, .arg2 = rhs, .arg3 = if (std.mem.eql(u8, name, "find_index_from_right")) 1 else 0, .source_node = expr });
            return reg;
        }
        if (std.mem.eql(u8, name, "split")) {
            if (args.len != 2) return diag.failAt(ast.tokens[ast.mainToken(expr)].start, "split expects a string and separator", .{});
            const source = try ctx.genExpr(@intCast(args[0]), diag);
            const sep = try ctx.genExpr(@intCast(args[1]), diag);
            const reg = proc.num_registers;
            proc.num_registers += 1;
            try proc.instructions.append(program.allocator, .{ .opcode = .string_split, .dest = reg, .arg1 = source, .arg2 = sep, .source_node = expr });
            return reg;
        }
        return null;
    }

    fn genStringBuildResult(ctx: *GenContext, name: []const u8, expr: NodeIndex, args: []const u32, diag: Diagnostic) !Bytecode.Register {
        const ast = ctx.ast;
        if (std.mem.eql(u8, name, "join")) {
            if (args.len == 0) return ctx.emitString(expr, "");
        } else if (args.len == 0) {
            return diag.failAt(ast.tokens[ast.mainToken(expr)].start, "{s} expects a format string", .{name});
        }
        const builder_reg = ctx.proc.num_registers;
        ctx.proc.num_registers += 1;
        try ctx.proc.instructions.append(ctx.program.allocator, .{ .opcode = .load_int, .dest = builder_reg, .arg1 = 0, .source_node = expr });
        const builder_slot = ctx.proc.num_registers;
        ctx.proc.num_registers += 1;
        try ctx.proc.instructions.append(ctx.program.allocator, .{ .opcode = .addr_of_local, .dest = builder_slot, .arg1 = builder_reg, .source_node = expr });
        try ctx.proc.instructions.append(ctx.program.allocator, .{ .opcode = .string_builder_init, .arg1 = builder_slot, .source_node = expr });
        if (std.mem.eql(u8, name, "join")) {
            try emitJoinAppend(ctx, builder_slot, expr, args, diag);
        } else {
            const fmt_node: NodeIndex = @intCast(args[0]);
            if (stringLiteralPayloadNode(ctx, fmt_node)) |literal_fmt| {
                try emitFormattedBuilderAppend(ctx, builder_slot, literal_fmt, args[1..], diag);
            } else {
                const fmt = try ctx.genExpr(fmt_node, diag);
                try ctx.proc.instructions.append(ctx.program.allocator, .{ .opcode = .string_builder_append_string, .arg1 = builder_slot, .arg2 = fmt, .source_node = fmt_node });
            }
        }
        const result = ctx.proc.num_registers;
        ctx.proc.num_registers += 1;
        try ctx.proc.instructions.append(ctx.program.allocator, .{ .opcode = .string_builder_to_string, .dest = result, .arg1 = builder_slot, .source_node = expr });
        try ctx.proc.instructions.append(ctx.program.allocator, .{ .opcode = .string_builder_free, .arg1 = builder_slot, .source_node = expr });
        return result;
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
                !(try typeTextIsEmbeddedStruct(ctx, return_text, diag));
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

    fn emitFloat(ctx: *GenContext, source_node: NodeIndex, value: f64) !Bytecode.Register {
        const reg = ctx.proc.num_registers;
        ctx.proc.num_registers += 1;
        const bits: u64 = @bitCast(value);
        try ctx.proc.instructions.append(ctx.program.allocator, .{ .opcode = .load_float, .dest = reg, .arg1 = @truncate(bits), .arg2 = @truncate(bits >> 32), .source_node = source_node });
        return reg;
    }

    fn evalFloatConstExpr(ctx: *GenContext, node: NodeIndex, diag: Diagnostic) !f64 {
        const ast = ctx.ast;
        if (ctx.typed) |typed| {
            if (typed.comptime_floats.get(node)) |value| return value;
            if (typed.comptime_ints.get(node)) |value| return @floatFromInt(value);
        }
        return switch (ast.tag(node)) {
            .float_literal => try std.fmt.parseFloat(f64, ast.tokenSlice(ast.mainToken(node))),
            .integer_literal => @floatFromInt(try evalIntegerConstExpr(ctx, node, diag)),
            .identifier => blk: {
                const name = ast.tokenSlice(ast.mainToken(node));
                if (std.mem.eql(u8, name, "PI")) break :blk std.math.pi;
                const decl = ctx.resolved.local_values.get(node) orelse return diag.failAt(ast.tokens[ast.mainToken(node)].start, "expected compile-time numeric value", .{});
                const init = if (ast.tag(decl) == .const_decl) ast.data(decl).lhs else if (ast.tag(decl) == .var_decl) ast.data(decl).rhs else @import("Ast.zig").null_node;
                if (init == @import("Ast.zig").null_node) return diag.failAt(ast.tokens[ast.mainToken(node)].start, "expected compile-time numeric value", .{});
                break :blk try ctx.evalFloatConstExpr(init, diag);
            },
            .binary_expr => blk: {
                const lhs = try ctx.evalFloatConstExpr(ast.data(node).lhs, diag);
                const rhs = try ctx.evalFloatConstExpr(ast.data(node).rhs, diag);
                break :blk switch (ast.tokens[ast.mainToken(node)].tag) {
                    .plus => lhs + rhs,
                    .minus => lhs - rhs,
                    .star => lhs * rhs,
                    .slash => lhs / rhs,
                    else => return diag.failAt(ast.tokens[ast.mainToken(node)].start, "expected compile-time numeric expression", .{}),
                };
            },
            else => return diag.failAt(ast.tokens[ast.mainToken(node)].start, "expected compile-time numeric expression", .{}),
        };
    }

    fn emitAllocatorValue(ctx: *GenContext, source_node: NodeIndex, proc_id: Bytecode.Register, data: Bytecode.Register) !Bytecode.Register {
        const reg = ctx.proc.num_registers;
        ctx.proc.num_registers += 1;
        try ctx.proc.instructions.append(ctx.program.allocator, .{ .opcode = .alloc_heap, .dest = reg, .arg1 = 16, .source_node = source_node });
        try ctx.proc.instructions.append(ctx.program.allocator, .{ .opcode = .store_ptr, .dest = reg, .arg1 = proc_id, .source_node = source_node });
        const data_addr = ctx.proc.num_registers;
        ctx.proc.num_registers += 1;
        try ctx.proc.instructions.append(ctx.program.allocator, .{ .opcode = .ptr_offset, .dest = data_addr, .arg1 = reg, .arg2 = 8, .source_node = source_node });
        try ctx.proc.instructions.append(ctx.program.allocator, .{ .opcode = .store_ptr, .dest = data_addr, .arg1 = data, .source_node = source_node });
        return reg;
    }

    fn emitDefaultAllocatorValue(ctx: *GenContext, source_node: NodeIndex) !Bytecode.Register {
        const proc_id = try ctx.emitInt(source_node, allocator_proc_default);
        const data = ctx.proc.num_registers;
        ctx.proc.num_registers += 1;
        try ctx.proc.instructions.append(ctx.program.allocator, .{ .opcode = .load_null_ptr, .dest = data, .source_node = source_node });
        return try ctx.emitAllocatorValue(source_node, proc_id, data);
    }

    fn emitString(ctx: *GenContext, source_node: NodeIndex, value: []const u8) !Bytecode.Register {
        const string_idx = try ctx.program.addString(value);
        const reg = ctx.proc.num_registers;
        ctx.proc.num_registers += 1;
        try ctx.proc.instructions.append(ctx.program.allocator, .{ .opcode = .load_string, .dest = reg, .arg1 = string_idx, .source_node = source_node });
        return reg;
    }

    fn emitSourceLocation(ctx: *GenContext, location_node: NodeIndex, source_node: NodeIndex, diag: Diagnostic) !Bytecode.Register {
        const target = if (location_node == @import("Ast.zig").null_node) source_node else location_node;
        const tok = ctx.ast.mainToken(target);
        const line = sourceLineNumber(ctx.ast.source, ctx.ast.tokens[tok].start);
        const path = try canonicalSourcePath(ctx.program.allocator, diag.file_path);
        defer ctx.program.allocator.free(path);
        const string_idx = try ctx.program.addString(path);
        const reg = ctx.proc.num_registers;
        ctx.proc.num_registers += 1;
        try ctx.proc.instructions.append(ctx.program.allocator, .{
            .opcode = .load_source_location,
            .dest = reg,
            .arg1 = string_idx,
            .arg2 = @intCast(@max(line, 0)),
            .source_node = source_node,
        });
        return reg;
    }

    fn locationTargetNode(ctx: *GenContext, node: NodeIndex) NodeIndex {
        const ast = ctx.ast;
        if (node == @import("Ast.zig").null_node) return node;
        if (ast.tag(node) != .identifier) return node;
        const decl = ctx.resolved.local_values.get(node) orelse blk: {
            const name = ast.tokenSlice(ast.mainToken(node));
            if (ctx.resolved.lookup(name)) |sym| switch (sym) {
                .const_value => |value| break :blk value,
                else => {},
            };
            return node;
        };
        if (decl == @import("Ast.zig").null_node) return node;
        const init = switch (ast.tag(decl)) {
            .const_decl => ast.data(decl).lhs,
            .var_decl => ast.data(decl).rhs,
            else => decl,
        };
        if (init == @import("Ast.zig").null_node) return node;
        return init;
    }

    fn genSyntheticBindingOptionField(ctx: *GenContext, name: []const u8, source_node: NodeIndex, diag: Diagnostic) !Bytecode.Register {
        if (ctx.binding_option_fields.get(name)) |reg| return reg;
        const reg = ctx.proc.num_registers;
        ctx.proc.num_registers += 1;
        if (isBindingOptionArrayField(name)) {
            try ctx.proc.instructions.append(ctx.program.allocator, .{ .opcode = .alloc_local_bytes, .dest = reg, .arg1 = 8, .source_node = source_node });
        } else if (std.mem.eql(u8, name, "header")) {
            const string_idx = try ctx.program.addString("");
            try ctx.proc.instructions.append(ctx.program.allocator, .{ .opcode = .load_string, .dest = reg, .arg1 = string_idx, .source_node = source_node });
        } else if (std.mem.eql(u8, name, "strip_flags")) {
            try ctx.proc.instructions.append(ctx.program.allocator, .{ .opcode = .load_int, .dest = reg, .arg1 = 0, .source_node = source_node });
        } else {
            return diag.failAt(ctx.ast.tokens[ctx.ast.mainToken(source_node)].start, "unknown Generate_Bindings_Options field '{s}'", .{name});
        }
        try ctx.binding_option_fields.put(ctx.program.allocator, name, reg);
        return reg;
    }

    fn emitStaticArrayElementAddress(ctx: *GenContext, base: NodeIndex, index: NodeIndex, base_ty: []const u8, source_node: NodeIndex, diag: Diagnostic) !Bytecode.Register {
        const elem_ty = staticArrayElementText(base_ty) orelse return ctx.genTypedPlaceholderValue(source_node, diag);
        const base_reg = try ctx.genExpr(base, diag);
        const index_reg = try ctx.genExpr(index, diag);
        const elem_size = try typeTextSize(ctx, elem_ty, diag);
        const scaled_index = if (elem_size == 1) index_reg else blk: {
            const size_reg = try ctx.emitInt(source_node, @intCast(elem_size));
            const reg = ctx.proc.num_registers;
            ctx.proc.num_registers += 1;
            try ctx.proc.instructions.append(ctx.program.allocator, .{ .opcode = .mul_int, .dest = reg, .arg1 = index_reg, .arg2 = size_reg, .source_node = source_node });
            break :blk reg;
        };
        const addr = ctx.proc.num_registers;
        ctx.proc.num_registers += 1;
        try ctx.proc.instructions.append(ctx.program.allocator, .{ .opcode = .ptr_offset_reg, .dest = addr, .arg1 = base_reg, .arg2 = scaled_index, .source_node = source_node });
        return addr;
    }

    fn emitGlobalAddress(ctx: *GenContext, decl: NodeIndex, source_node: NodeIndex, type_text: []const u8, diag: Diagnostic) !Bytecode.Register {
        const size = try typeTextSize(ctx, type_text, diag);
        const global_index = try ctx.program.addGlobal(decl, @intCast(@max(size, 1)));
        if (ctx.program.globals.items[global_index].initial_bytes == null and ctx.isTopLevelVarDecl(decl)) {
            if (try ctx.topLevelGlobalInitialBytes(decl, @intCast(@max(size, 1)), diag)) |bytes| {
                ctx.program.globals.items[global_index].initial_bytes = bytes;
            }
        }
        if (ctx.program.globals.items[global_index].initial_bytes == null and ctx.ast.isNoReset(decl)) {
            if (ctx.typed) |typed| {
                if (typed.comptime_bytes.get(decl)) |bytes| {
                    ctx.program.globals.items[global_index].initial_bytes = bytes;
                }
            }
        }
        const reg = ctx.proc.num_registers;
        ctx.proc.num_registers += 1;
        try ctx.proc.instructions.append(ctx.program.allocator, .{ .opcode = .global_addr, .dest = reg, .arg1 = global_index, .source_node = source_node });
        return reg;
    }

    fn topLevelGlobalInitialBytes(ctx: *GenContext, decl: NodeIndex, size: usize, diag: Diagnostic) !?[]const u8 {
        if (ctx.ast.tag(decl) != .var_decl) return null;
        const init = ctx.ast.data(decl).rhs;
        if (init == @import("Ast.zig").null_node or ctx.ast.tag(init) == .undefined_literal) return null;
        const bytes = try ctx.program.allocator.alloc(u8, size);
        errdefer ctx.program.allocator.free(bytes);
        @memset(bytes, 0);
        switch (ctx.ast.tag(init)) {
            .integer_literal, .unary_expr, .binary_expr, .identifier, .size_of_expr, .field_access => {
                const value = try evalIntegerConstExpr(ctx, init, diag);
                const write_len = @min(size, @sizeOf(i64));
                var buf: [8]u8 = undefined;
                std.mem.writeInt(u64, &buf, @bitCast(value), .little);
                @memcpy(bytes[0..write_len], buf[0..write_len]);
            },
            .bool_literal => {
                bytes[0] = if (std.mem.eql(u8, ctx.ast.tokenSlice(ctx.ast.mainToken(init)), "true")) 1 else 0;
            },
            else => {
                ctx.program.allocator.free(bytes);
                return null;
            },
        }
        try ctx.program.byte_arrays.append(ctx.program.allocator, bytes);
        return bytes;
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
        if (ctx.ast.tag(node) == .type_expr) return ctx.typeExprTokenSource(ctx.ast.mainToken(node));
        var start = ctx.ast.tokens[ctx.ast.mainToken(node)].start;
        var end = ctx.ast.tokens[ctx.ast.mainToken(node)].end;
        collectNodeStart(ctx.ast, node, &start);
        collectNodeEnd(ctx.ast, node, &end);
        return std.mem.trim(u8, ctx.ast.source[start..@min(end, ctx.ast.source.len)], " \t\r\n;");
    }

    fn typeExprTokenSource(ctx: *GenContext, tok: @import("Token.zig").Token.Index) []const u8 {
        var end_tok = tok;
        var scan = tok + 1;
        while (scan < ctx.ast.tokens.len) {
            switch (ctx.ast.tokens[scan].tag) {
                .dot => {
                    scan += 1;
                    if (scan < ctx.ast.tokens.len and ctx.ast.tokens[scan].tag == .identifier) {
                        end_tok = scan;
                        scan += 1;
                    }
                    continue;
                },
                .l_paren => {
                    var depth: usize = 1;
                    scan += 1;
                    while (scan < ctx.ast.tokens.len and depth != 0) : (scan += 1) {
                        switch (ctx.ast.tokens[scan].tag) {
                            .l_paren => depth += 1,
                            .r_paren => {
                                depth -= 1;
                                if (depth == 0) {
                                    end_tok = scan;
                                    scan += 1;
                                    break;
                                }
                            },
                            else => {},
                        }
                    }
                    continue;
                },
                else => break,
            }
        }
        return std.mem.trim(u8, ctx.ast.source[ctx.ast.tokens[tok].start..ctx.ast.tokens[end_tok].end], " \t\r\n;");
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

    fn isTopLevelVarDecl(ctx: *GenContext, decl: NodeIndex) bool {
        if (decl == @import("Ast.zig").null_node or ctx.ast.tag(decl) != .var_decl) return false;
        if (ctx.ast.root == @import("Ast.zig").null_node) return false;
        for (ctx.ast.extraSlice(ctx.ast.data(ctx.ast.root).lhs)) |root_decl| {
            if (@as(NodeIndex, @intCast(root_decl)) == decl) return true;
        }
        return false;
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
            const reg = ctx.proc.num_registers;
            ctx.proc.num_registers += 1;
            if (ast.data(type_expr).lhs == @import("Ast.zig").null_node) {
                try ctx.proc.instructions.append(ctx.program.allocator, .{ .opcode = .alloc_local_bytes, .dest = reg, .arg1 = 8, .source_node = source_node });
            } else {
                const count = try evalIntegerConstExpr(ctx, ast.data(type_expr).lhs, diag);
                const elem_size = try typeTextSize(ctx, ctx.nodeSource(ast.data(type_expr).rhs), diag);
                const size: u64 = @as(u64, @intCast(@max(count, 0))) * elem_size;
                try ctx.proc.instructions.append(ctx.program.allocator, .{ .opcode = .alloc_local_bytes, .dest = reg, .arg1 = @intCast(@max(size, 1)), .source_node = source_node });
            }
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
        if (ctx.polymorph_types.get(type_name)) |actual_type| return ctx.genDefaultValueFromText(actual_type, source_node, diag);
        if (std.mem.eql(u8, type_name, "Allocator")) return try ctx.emitDefaultAllocatorValue(source_node);
        const reg = ctx.proc.num_registers;
        ctx.proc.num_registers += 1;
        if (std.mem.eql(u8, type_name, "string")) {
            const string_idx = try ctx.program.addString("");
            try ctx.proc.instructions.append(ctx.program.allocator, .{ .opcode = .load_string, .dest = reg, .arg1 = string_idx, .source_node = source_node });
            const addr_reg = ctx.proc.num_registers;
            ctx.proc.num_registers += 1;
            try ctx.proc.instructions.append(ctx.program.allocator, .{ .opcode = .addr_of_local, .dest = addr_reg, .arg1 = reg, .source_node = source_node });
        } else if (std.mem.eql(u8, type_name, "bool")) {
            try ctx.proc.instructions.append(ctx.program.allocator, .{ .opcode = .load_bool, .dest = reg, .arg1 = 0, .source_node = source_node });
        } else if (std.mem.eql(u8, type_name, "float") or std.mem.eql(u8, type_name, "float32") or std.mem.eql(u8, type_name, "float64")) {
            const bits: u64 = @bitCast(@as(f64, 0.0));
            try ctx.proc.instructions.append(ctx.program.allocator, .{ .opcode = .load_float, .dest = reg, .arg1 = @truncate(bits), .arg2 = @truncate(bits >> 32), .source_node = source_node });
        } else if (std.mem.eql(u8, type_name, "void")) {
            try ctx.proc.instructions.append(ctx.program.allocator, .{ .opcode = .load_type, .dest = reg, .arg1 = 0, .source_node = source_node });
        } else if (try structSizeFromTypeText(ctx, ctx.nodeSource(type_expr), diag)) |size| {
            try ctx.proc.instructions.append(ctx.program.allocator, .{ .opcode = .alloc_heap, .dest = reg, .arg1 = @intCast(@max(size, 1)), .source_node = source_node });
            try ctx.emitContainerGeneratedInitializers(reg, ctx.nodeSource(type_expr), source_node, diag);
        } else if (std.mem.eql(u8, type_name, "Build_Options") or std.mem.eql(u8, type_name, "Generate_Bindings_Options")) {
            try ctx.proc.instructions.append(ctx.program.allocator, .{ .opcode = .alloc_heap, .dest = reg, .arg1 = 8, .source_node = source_node });
        } else {
            try ctx.proc.instructions.append(ctx.program.allocator, .{ .opcode = .load_int, .dest = reg, .arg1 = 0, .source_node = source_node });
        }
        return reg;
    }

    fn genDefaultValueFromText(ctx: *GenContext, raw_type: []const u8, source_node: NodeIndex, diag: Diagnostic) !Bytecode.Register {
        const type_text = std.mem.trim(u8, raw_type, " \t\r\n");
        if (std.mem.eql(u8, firstTypeWord(type_text), "Allocator")) return try ctx.emitDefaultAllocatorValue(source_node);
        const reg = ctx.proc.num_registers;
        ctx.proc.num_registers += 1;
        if (try typeTextIsEmbeddedStruct(ctx, type_text, diag)) {
            const size = try typeTextSize(ctx, type_text, diag);
            try ctx.proc.instructions.append(ctx.program.allocator, .{ .opcode = .alloc_heap, .dest = reg, .arg1 = @intCast(@max(size, 1)), .source_node = source_node });
            try ctx.emitContainerGeneratedInitializers(reg, type_text, source_node, diag);
        } else if (isDynamicArrayTypeText(type_text)) {
            try ctx.proc.instructions.append(ctx.program.allocator, .{ .opcode = .alloc_local_bytes, .dest = reg, .arg1 = 8, .source_node = source_node });
        } else if (isStaticArrayTypeText(type_text)) {
            const size = try typeTextSize(ctx, type_text, diag);
            try ctx.proc.instructions.append(ctx.program.allocator, .{ .opcode = .alloc_local_bytes, .dest = reg, .arg1 = @intCast(@max(size, 1)), .source_node = source_node });
        } else if (std.mem.eql(u8, firstTypeWord(type_text), "bool")) {
            try ctx.proc.instructions.append(ctx.program.allocator, .{ .opcode = .load_bool, .dest = reg, .arg1 = 0, .source_node = source_node });
        } else if (std.mem.eql(u8, firstTypeWord(type_text), "Build_Options")) {
            try ctx.proc.instructions.append(ctx.program.allocator, .{ .opcode = .load_build_options, .dest = reg, .arg1 = std.math.maxInt(u32), .source_node = source_node });
        } else if (std.mem.eql(u8, firstTypeWord(type_text), "Generate_Bindings_Options")) {
            try ctx.proc.instructions.append(ctx.program.allocator, .{ .opcode = .alloc_heap, .dest = reg, .arg1 = 8, .source_node = source_node });
        } else {
            try ctx.proc.instructions.append(ctx.program.allocator, .{ .opcode = .load_int, .dest = reg, .arg1 = 0, .source_node = source_node });
        }
        return reg;
    }

    fn emitDefaultBuildOptionsField(ctx: *GenContext, field_name: []const u8, source_node: NodeIndex, diag: Diagnostic) !?Bytecode.Register {
        _ = diag;
        if (std.mem.eql(u8, field_name, "compile_time_command_line") or std.mem.eql(u8, field_name, "import_path")) {
            const reg = ctx.proc.num_registers;
            ctx.proc.num_registers += 1;
            try ctx.proc.instructions.append(ctx.program.allocator, .{ .opcode = .new_array, .dest = reg, .arg1 = 0, .arg2 = 16, .arg3 = 8, .source_node = source_node });
            if (std.mem.eql(u8, field_name, "import_path")) {
                const item = try ctx.emitString(source_node, "modules");
                const append_reg = ctx.proc.num_registers;
                ctx.proc.num_registers += 1;
                try ctx.proc.instructions.append(ctx.program.allocator, .{ .opcode = .array_add, .dest = append_reg, .arg1 = reg, .arg2 = item, .arg3 = 16, .source_node = source_node });
            }
            return reg;
        }
        if (std.mem.eql(u8, field_name, "output_executable_name") or
            std.mem.eql(u8, field_name, "output_path"))
        {
            return try ctx.emitString(source_node, "");
        }
        return null;
    }

    fn genBuildOptionsFieldAssignmentValue(ctx: *GenContext, field_name: []const u8, rhs_node: NodeIndex, diag: Diagnostic) !Bytecode.Register {
        const ast = ctx.ast;
        _ = field_name;
        if (ast.tag(rhs_node) == .field_access and ast.data(rhs_node).lhs == @import("Ast.zig").null_node) {
            return try ctx.emitString(rhs_node, ast.tokenSlice(ast.data(rhs_node).rhs));
        }
        return try ctx.genExpr(rhs_node, diag);
    }
};

fn collectNodeEnd(ast: *const Ast, node: NodeIndex, end: *u32) void {
    if (node == @import("Ast.zig").null_node or node >= ast.node_tags.items.len) return;
    const tok = ast.mainToken(node);
    if (tok < ast.tokens.len) end.* = @max(end.*, ast.tokens[tok].end);
    const data = ast.data(node);
    switch (ast.tag(node)) {
        .block => {
            if (matchingDelimiterEnd(ast, tok, .l_brace, .r_brace)) |close_end| end.* = @max(end.*, close_end);
            if (data.lhs < ast.extra_data.items.len) {
                for (ast.extraSlice(data.lhs)) |child| collectNodeEnd(ast, @intCast(child), end);
            }
        },
        .root, .stmt_list, .aggregate_literal => {
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
            if (matchingDelimiterEnd(ast, tok, .l_paren, .r_paren)) |close_end| end.* = @max(end.*, close_end);
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
        .const_decl, .placeholder_decl, .expr_stmt, .return_stmt, .pointer_type, .type_of_expr, .size_of_expr, .run_expr, .is_constant_expr, .unary_expr, .defer_stmt => {
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

fn collectNodeStart(ast: *const Ast, node: NodeIndex, start: *u32) void {
    if (node == @import("Ast.zig").null_node or node >= ast.node_tags.items.len) return;
    const tok = ast.mainToken(node);
    if (tok < ast.tokens.len) start.* = @min(start.*, ast.tokens[tok].start);
    const data = ast.data(node);
    switch (ast.tag(node)) {
        .root, .stmt_list, .aggregate_literal => {
            if (data.lhs < ast.extra_data.items.len) {
                for (ast.extraSlice(data.lhs)) |child| collectNodeStart(ast, @intCast(child), start);
            }
        },
        .typed_aggregate_literal, .typed_array_literal => {
            if (data.lhs < ast.extra_data.items.len) {
                const payload = ast.extraSlice(data.lhs);
                if (payload.len >= 2) {
                    collectNodeStart(ast, @intCast(payload[0]), start);
                    for (ast.extraSlice(payload[1])) |child| collectNodeStart(ast, @intCast(child), start);
                }
            }
        },
        .call_expr => {
            collectNodeStart(ast, data.lhs, start);
            if (data.rhs < ast.extra_data.items.len) {
                for (ast.extraSlice(data.rhs)) |arg| collectNodeStart(ast, @intCast(arg), start);
            }
        },
        .if_stmt => {
            collectNodeStart(ast, data.lhs, start);
            if (data.rhs < ast.extra_data.items.len) {
                for (ast.extraSlice(data.rhs)) |child| collectNodeStart(ast, @intCast(child), start);
            }
        },
        .for_stmt => {
            if (data.lhs < ast.extra_data.items.len) {
                for (ast.extraSlice(data.lhs)) |operand| {
                    const clean = operand & 0x7fffffff;
                    if (clean < ast.node_tags.items.len) collectNodeStart(ast, @intCast(clean), start);
                }
            }
            collectNodeStart(ast, data.rhs, start);
        },
        .proc_type => {
            if (data.lhs < ast.extra_data.items.len) {
                for (ast.extraSlice(data.lhs)) |param_ty| collectNodeStart(ast, @intCast(param_ty), start);
            }
            collectNodeStart(ast, data.rhs, start);
        },
        .var_decl, .assign_stmt, .binary_expr, .index_expr, .array_type, .meta_expr, .meta_stmt, .field_access => {
            collectNodeStart(ast, data.lhs, start);
            collectNodeStart(ast, data.rhs, start);
        },
        .const_decl, .placeholder_decl, .expr_stmt, .return_stmt, .pointer_type, .type_of_expr, .size_of_expr, .run_expr, .is_constant_expr, .unary_expr, .defer_stmt => {
            collectNodeStart(ast, data.lhs, start);
        },
        .proc_decl => {
            collectNodeStart(ast, data.lhs, start);
            if (data.rhs < ast.extra_data.items.len) {
                for (ast.extraSlice(data.rhs)) |sig_part| {
                    if (sig_part < ast.node_tags.items.len) collectNodeStart(ast, @intCast(sig_part), start);
                }
            }
        },
        else => {},
    }
}

fn matchingDelimiterEnd(ast: *const Ast, open_tok: @import("Token.zig").Token.Index, open_tag: TokenTag, close_tag: TokenTag) ?u32 {
    if (open_tok >= ast.tokens.len or ast.tokens[open_tok].tag != open_tag) return null;
    var depth: usize = 0;
    var i = open_tok;
    while (i < ast.tokens.len) : (i += 1) {
        const tag = ast.tokens[i].tag;
        if (tag == open_tag) {
            depth += 1;
        } else if (tag == close_tag) {
            depth -= 1;
            if (depth == 0) return ast.tokens[i].end;
        } else if (tag == .eof) {
            return null;
        }
    }
    return null;
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
        .field_access => blk: {
            const field_name = ast.tokenSlice(ast.data(node).rhs);
            const base = ast.data(node).lhs;
            if (std.mem.eql(u8, field_name, "count") and base != @import("Ast.zig").null_node and ast.tag(base) == .string_literal) {
                const decoded = try decodeString(ctx.program.allocator, ast.stringTokenContents(ast.mainToken(base)), diag, ast.tokens[ast.mainToken(base)].start);
                defer ctx.program.allocator.free(decoded);
                break :blk @intCast(decoded.len);
            }
            return diag.failAt(ast.tokens[ast.mainToken(node)].start, "unsupported field access in integer constant option", .{});
        },
        .size_of_expr => @intCast(try phase3SizeOf(ctx, ast.data(node).lhs, diag)),
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

fn isCallerLocationExpr(ast: *const Ast, node: NodeIndex) bool {
    return node != @import("Ast.zig").null_node and
        ast.tag(node) == .meta_expr and
        ast.tokens[ast.mainToken(node)].tag == .directive_caller_location;
}

fn isCallerCodeExpr(ast: *const Ast, node: NodeIndex) bool {
    return node != @import("Ast.zig").null_node and
        ast.tag(node) == .meta_expr and
        ast.tokens[ast.mainToken(node)].tag == .directive_caller_code;
}

fn stmtInitOrAssignRhs(ast: *const Ast, stmt: NodeIndex) ?NodeIndex {
    const rhs = switch (ast.tag(stmt)) {
        .var_decl => ast.data(stmt).rhs,
        .const_decl => ast.data(stmt).lhs,
        .assign_stmt => ast.data(stmt).rhs,
        else => null,
    };
    if (rhs == @import("Ast.zig").null_node) return null;
    return rhs;
}

fn handleArgNode(ast: *const Ast, arg: NodeIndex) NodeIndex {
    if (ast.tag(arg) == .unary_expr and ast.tokens[ast.mainToken(arg)].tag == .star) return ast.data(arg).lhs;
    if (ast.tag(arg) == .assign_stmt) return ast.data(arg).rhs;
    if (ast.tag(arg) == .binary_expr and ast.tokens[ast.mainToken(arg)].tag == .equal and ast.tag(ast.data(arg).lhs) == .identifier) return ast.data(arg).rhs;
    return arg;
}

fn namedBoolArg(ctx: *GenContext, args: []const u32, option_name: []const u8, default_value: bool, diag: Diagnostic) !u32 {
    const ast = ctx.ast;
    for (args) |arg_idx| {
        const arg: NodeIndex = @intCast(arg_idx);
        const is_assign = ast.tag(arg) == .assign_stmt or (ast.tag(arg) == .binary_expr and ast.tokens[ast.mainToken(arg)].tag == .equal and ast.tag(ast.data(arg).lhs) == .identifier);
        if (!is_assign) {
            _ = try ctx.genExpr(arg, diag);
            continue;
        }
        const lhs = ast.data(arg).lhs;
        if (ast.tag(lhs) != .identifier or !std.mem.eql(u8, ast.tokenSlice(ast.mainToken(lhs)), option_name)) {
            _ = try ctx.genExpr(ast.data(arg).rhs, diag);
            continue;
        }
        const rhs = ast.data(arg).rhs;
        if (ast.tag(rhs) == .bool_literal) return if (std.mem.eql(u8, ast.tokenSlice(ast.mainToken(rhs)), "true")) 1 else 0;
        const reg = try ctx.genExpr(rhs, diag);
        _ = reg;
        return if (default_value) 1 else 0;
    }
    return if (default_value) 1 else 0;
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

const TypeArgRestore = struct {
    name: []const u8,
    had_old: bool,
    old: []const u8 = "",
};

fn genAddressOfLvalue(ctx: *GenContext, expr: NodeIndex, diag: Diagnostic) !Bytecode.Register {
    const ast = ctx.ast;
    const proc = ctx.proc;
    const program = ctx.program;
    switch (ast.tag(expr)) {
        .identifier => {
            if (ctx.resolved.local_values.get(expr)) |decl| {
                if (ctx.isTopLevelVarDecl(decl)) {
                    const type_node = ast.data(decl).lhs;
                    const type_text = if (type_node != @import("Ast.zig").null_node) ctx.nodeSource(type_node) else typeTextForExpr(ctx, expr, diag) orelse "int";
                    return try ctx.emitGlobalAddress(decl, expr, type_text, diag);
                }
            }
            const value = try ctx.genExpr(expr, diag);
            if (typeTextForExpr(ctx, expr, diag)) |ty| {
                const clean = stripPointerText(ty);
                if (isDynamicArrayTypeText(clean) or isStaticArrayTypeText(clean) or (try typeTextIsStruct(ctx, clean, diag))) return value;
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
            if (std.mem.eql(u8, firstTypeWord(base_ty), "string")) {
                const base_reg = try ctx.genExpr(base, diag);
                const index_reg = try ctx.genExpr(ast.data(expr).rhs, diag);
                const data_reg = proc.num_registers;
                proc.num_registers += 1;
                try proc.instructions.append(program.allocator, .{ .opcode = .string_data, .dest = data_reg, .arg1 = base_reg, .source_node = expr });
                const addr = proc.num_registers;
                proc.num_registers += 1;
                try proc.instructions.append(program.allocator, .{ .opcode = .ptr_offset_reg, .dest = addr, .arg1 = data_reg, .arg2 = index_reg, .source_node = expr });
                return addr;
            }
            if (staticArrayElementText(base_ty) != null) {
                return try ctx.emitStaticArrayElementAddress(base, ast.data(expr).rhs, base_ty, expr, diag);
            }
            if (std.mem.startsWith(u8, std.mem.trim(u8, base_ty, " \t\r\n"), "*")) {
                const elem_ty = stripPointerText(base_ty);
                const base_reg = try ctx.genExpr(base, diag);
                const index_reg = try ctx.genExpr(ast.data(expr).rhs, diag);
                const elem_size = try typeTextSize(ctx, elem_ty, diag);
                const byte_index = if (elem_size == 1) index_reg else blk: {
                    const size_reg = try ctx.emitInt(expr, @intCast(elem_size));
                    const scaled = proc.num_registers;
                    proc.num_registers += 1;
                    try proc.instructions.append(program.allocator, .{ .opcode = .mul_int, .dest = scaled, .arg1 = index_reg, .arg2 = size_reg, .source_node = expr });
                    break :blk scaled;
                };
                const addr = proc.num_registers;
                proc.num_registers += 1;
                try proc.instructions.append(program.allocator, .{ .opcode = .ptr_offset_reg, .dest = addr, .arg1 = base_reg, .arg2 = byte_index, .source_node = expr });
                return addr;
            }
            const elem_ty = dynamicArrayElementText(base_ty) orelse return ctx.genTypedPlaceholderValue(expr, diag);
            const base_reg = try ctx.genExpr(base, diag);
            const index_reg = try ctx.genExpr(ast.data(expr).rhs, diag);
            const elem_size = try typeTextSize(ctx, elem_ty, diag);
            const addr = proc.num_registers;
            proc.num_registers += 1;
            try proc.instructions.append(program.allocator, .{ .opcode = .array_index, .dest = addr, .arg1 = base_reg, .arg2 = index_reg, .arg3 = @intCast(elem_size), .arg4 = 1, .source_node = expr });
            return addr;
        },
        else => return ctx.genTypedPlaceholderValue(expr, diag),
    }
}

fn typeTextForExpr(ctx: *GenContext, expr: NodeIndex, diag: Diagnostic) ?[]const u8 {
    const ast = ctx.ast;
    if (expr == @import("Ast.zig").null_node or expr >= ast.node_tags.items.len) return null;
    if (ctx.typed) |typed| {
        if (typed.comptime_strings.contains(expr) or typed.comptime_bytes.contains(expr)) return "string";
    }
    switch (ast.tag(expr)) {
        .string_literal => return "string",
        .char_literal => return "u8",
        .integer_literal => return "int",
        .float_literal => return "float32",
        .binary_expr => {
            const lhs_ty = typeTextForExpr(ctx, ast.data(expr).lhs, diag);
            const rhs_ty = typeTextForExpr(ctx, ast.data(expr).rhs, diag);
            if (lhs_ty) |lhs| {
                const lhs_name = firstTypeWord(std.mem.trim(u8, lhs, " \t\r\n"));
                if (std.mem.eql(u8, lhs_name, "float64")) return lhs;
                if (std.mem.eql(u8, lhs_name, "float") or std.mem.eql(u8, lhs_name, "float32")) return "float32";
                if (!std.mem.eql(u8, lhs_name, "int") and !std.mem.eql(u8, lhs_name, "s64")) return lhs;
            }
            if (rhs_ty) |rhs| {
                const rhs_name = firstTypeWord(std.mem.trim(u8, rhs, " \t\r\n"));
                if (std.mem.eql(u8, rhs_name, "float64")) return rhs;
                if (std.mem.eql(u8, rhs_name, "float") or std.mem.eql(u8, rhs_name, "float32")) return "float32";
                if (!std.mem.eql(u8, rhs_name, "int") and !std.mem.eql(u8, rhs_name, "s64")) return rhs;
            }
            return lhs_ty orelse rhs_ty;
        },
        .identifier => {
            const ident_name = ast.tokenSlice(ast.mainToken(expr));
            if (ctx.polymorph_types.get(ident_name)) |actual_type| return actual_type;
            if (std.mem.eql(u8, ident_name, "GENERATOR_DEFAULT_SYSTEM_INCLUDE_PATH")) return "string";
            if (bindingOptionFieldType(ident_name)) |field_type| return field_type;
            const decl = ctx.resolved.local_values.get(expr) orelse {
                if (ctx.external_types.get(ident_name)) |actual_type| return actual_type;
                return null;
            };
            if (decl == @import("Ast.zig").null_node) {
                if (ctx.external_types.get(ident_name)) |actual_type| return actual_type;
                return null;
            }
            if (ast.tag(decl) == .for_stmt and ctx.isLoopIndexIdentifier(expr, decl)) return "int";
            if (ctx.type_overrides.get(decl)) |actual_type| return actual_type;
            if (ctx.typed) |typed| {
                if (typed.comptime_strings.contains(decl) or typed.comptime_bytes.contains(decl)) return "string";
            }
            if (ast.tag(decl) == .var_decl or ast.tag(decl) == .const_decl) {
                const type_node = if (ast.tag(decl) == .var_decl) ast.data(decl).lhs else ast.data(decl).rhs;
                if (type_node != @import("Ast.zig").null_node) return ctx.nodeSource(type_node);
                if (ast.tag(decl) == .var_decl and ast.data(decl).rhs != @import("Ast.zig").null_node) {
                    return typeTextForExpr(ctx, ast.data(decl).rhs, diag);
                }
                if (ast.tag(decl) == .const_decl and ast.data(decl).lhs != @import("Ast.zig").null_node) {
                    return typeTextForExpr(ctx, ast.data(decl).lhs, diag);
                }
            }
            return null;
        },
        .field_access => {
            const base_ty = typeTextForExpr(ctx, ast.data(expr).lhs, diag) orelse return null;
            const field_name = ast.tokenSlice(ast.data(expr).rhs);
            if (std.mem.eql(u8, firstTypeWord(base_ty), "Code")) {
                if (std.mem.eql(u8, field_name, "type")) return "Type";
            }
            if (std.mem.eql(u8, firstTypeWord(base_ty), "string")) {
                if (std.mem.eql(u8, field_name, "count")) return "int";
                if (std.mem.eql(u8, field_name, "data")) return "*u8";
            }
            if (isCodeNodeTypeText(base_ty)) {
                if (std.mem.eql(u8, field_name, "kind") or std.mem.eql(u8, field_name, "node_flags")) return "string";
                if (std.mem.eql(u8, field_name, "arguments_unsorted")) return "[] Code_Argument";
                if (std.mem.eql(u8, field_name, "value_type") or std.mem.eql(u8, field_name, "_s64")) return "int";
            }
            if (isCodeArgumentTypeText(base_ty)) {
                if (std.mem.eql(u8, field_name, "expression")) return "*Code_Node";
            }
            if (std.mem.eql(u8, firstTypeWord(base_ty), "Source_Code_Location")) {
                if (std.mem.eql(u8, field_name, "fully_pathed_filename")) return "string";
                if (std.mem.eql(u8, field_name, "line_number")) return "int";
            }
            if (std.mem.eql(u8, firstTypeWord(stripPointerText(base_ty)), "Type_Info_Struct")) {
                if (std.mem.eql(u8, field_name, "type")) return "int";
                if (std.mem.eql(u8, field_name, "name")) return "string";
                if (std.mem.eql(u8, field_name, "members")) return "[..] Type_Info_Struct_Member";
            }
            if (std.mem.eql(u8, firstTypeWord(stripPointerText(base_ty)), "Type_Info_Struct_Member")) {
                if (std.mem.eql(u8, field_name, "name")) return "string";
                if (std.mem.eql(u8, field_name, "type")) return "Type";
                if (std.mem.eql(u8, field_name, "flags") or std.mem.eql(u8, field_name, "offset_in_bytes")) return "int";
            }
            if (dynamicArrayElementText(base_ty) != null) {
                if (std.mem.eql(u8, field_name, "count")) return "int";
                if (std.mem.eql(u8, field_name, "data")) return "*u8";
            }
            if (std.mem.eql(u8, firstTypeWord(base_ty), "Build_Options")) {
                if (buildOptionsFieldType(field_name)) |field_ty| return field_ty;
            }
            if (std.mem.eql(u8, firstTypeWord(base_ty), "Build_Options_LLVM_Options")) {
                if (buildOptionsLlvmFieldType(field_name)) |field_ty| return field_ty;
            }
            if (staticArrayElementText(base_ty) != null) {
                if (std.mem.eql(u8, field_name, "count")) return "int";
                if (std.mem.eql(u8, field_name, "data")) return "*u8";
            }
            const info = fieldInfoFromTypeText(ctx, base_ty, field_name, diag) catch return null;
            return if (info) |actual| actual.type_text else null;
        },
        .index_expr => {
            const base_ty = typeTextForExpr(ctx, ast.data(expr).lhs, diag) orelse return null;
            if (std.mem.eql(u8, firstTypeWord(base_ty), "string")) return "u8";
            if (std.mem.startsWith(u8, std.mem.trim(u8, base_ty, " \t\r\n"), "*")) return stripPointerText(base_ty);
            return dynamicArrayElementText(base_ty) orelse staticArrayElementText(base_ty);
        },
        .unary_expr => {
            const op = ast.tokens[ast.mainToken(expr)].tag;
            if (op == .keyword_cast) {
                const target_ty: NodeIndex = @intCast(ast.data(expr).rhs & 0x7fffffff);
                if (target_ty != @import("Ast.zig").null_node and target_ty < ast.node_tags.items.len) return ctx.nodeSource(target_ty);
            }
            if (op == .star) {
                const operand_ty = typeTextForExpr(ctx, ast.data(expr).lhs, diag) orelse return null;
                return std.mem.trim(u8, stripPointerText(operand_ty), " \t\r\n");
            }
            return typeTextForExpr(ctx, ast.data(expr).lhs, diag);
        },
        .meta_expr => {
            const tag = ast.tokens[ast.mainToken(expr)].tag;
            if (tag == .directive_location or tag == .directive_caller_location) return "Source_Code_Location";
            if (tag == .directive_code) return "Code";
            return null;
        },
        .call_expr => {
            const callee = ast.data(expr).lhs;
            const args = if (ast.data(expr).rhs < ast.extra_data.items.len) ast.extraSlice(ast.data(expr).rhs) else &[_]u32{};
            if (ast.tag(callee) == .identifier) {
                const name = ast.tokenSlice(ast.mainToken(callee));
                if (std.mem.eql(u8, name, "compiler_arg") or
                    std.mem.eql(u8, name, "compiler_read_file") or
                    std.mem.eql(u8, name, "add_global_data") or
                    std.mem.eql(u8, name, "read_entire_file") or
                    std.mem.eql(u8, name, "string_slice") or
                    std.mem.eql(u8, name, "formatInt") or
                    std.mem.eql(u8, name, "formatFloat") or
                    std.mem.eql(u8, name, "calendar_to_string") or
                    std.mem.eql(u8, name, "builder_to_string") or
                    std.mem.eql(u8, name, "code_to_string") or
                    std.mem.eql(u8, name, "type_to_string") or
                    std.mem.eql(u8, name, "sprint") or
                    std.mem.eql(u8, name, "tprint") or
                    std.mem.eql(u8, name, "to_string") or
                    std.mem.eql(u8, name, "copy_string") or
                    std.mem.eql(u8, name, "trim") or
                    std.mem.eql(u8, name, "join") or
                    std.mem.eql(u8, name, "replace") or
                    std.mem.eql(u8, name, "slice"))
                {
                    return "string";
                }
                if (std.mem.eql(u8, name, "compiler_arg_count") or
                    std.mem.eql(u8, name, "read") or
                    std.mem.eql(u8, name, "GetStdHandle") or
                    std.mem.eql(u8, name, "file_length") or
                    std.mem.eql(u8, name, "array_count") or
                    std.mem.eql(u8, name, "write_string") or
                    std.mem.eql(u8, name, "write_strings") or
                    std.mem.eql(u8, name, "write_number") or
                    std.mem.eql(u8, name, "write_nonnegative_number") or
                    std.mem.eql(u8, name, "builder_string_length") or
                    std.mem.eql(u8, name, "compare") or
                    std.mem.eql(u8, name, "find_index_from_left") or
                    std.mem.eql(u8, name, "find_index_from_right") or
                    std.mem.eql(u8, name, "string_to_int") or
                    std.mem.eql(u8, name, "parse_int") or
                    std.mem.eql(u8, name, "to_integer") or
                    std.mem.eql(u8, name, "c_style_strlen") or
                    std.mem.eql(u8, name, "get_number_of_processors") or
                    std.mem.eql(u8, name, "max"))
                {
                    return "int";
                }
                if (std.mem.eql(u8, name, "thread_is_done") or
                    std.mem.eql(u8, name, "reset_temporary_storage") or
                    std.mem.eql(u8, name, "push_allocator") or
                    std.mem.eql(u8, name, "compiler_write_file") or
                    std.mem.eql(u8, name, "write_entire_file") or
                    std.mem.eql(u8, name, "copy_file") or
                    std.mem.eql(u8, name, "build_cpp") or
                    std.mem.eql(u8, name, "build_cpp_dynamic_lib") or
                    std.mem.eql(u8, name, "cpp_link_library") or
                    std.mem.eql(u8, name, "generate_bindings") or
                    std.mem.eql(u8, name, "check_feature") or
                    std.mem.eql(u8, name, "has_feature") or
                    std.mem.eql(u8, name, "make_directory_if_it_does_not_exist") or
                    std.mem.eql(u8, name, "delete_directory") or
                    std.mem.eql(u8, name, "file_exists") or
                    std.mem.eql(u8, name, "file_set_position") or
                    std.mem.eql(u8, name, "file_write") or
                    std.mem.eql(u8, name, "file_read") or
                    std.mem.eql(u8, name, "contains") or
                    std.mem.eql(u8, name, "begins_with") or
                    std.mem.eql(u8, name, "is_digit") or
                    std.mem.eql(u8, name, "is_alpha") or
                    std.mem.eql(u8, name, "is_alnum") or
                    std.mem.eql(u8, name, "is_space") or
                    std.mem.eql(u8, name, "is_any"))
                {
                    return "bool";
                }
                if (std.mem.eql(u8, name, "file_open")) return "*File";
                if (std.mem.eql(u8, name, "string_to_float") or std.mem.eql(u8, name, "sqrt") or std.mem.eql(u8, name, "cos")) return "float64";
                if (std.mem.eql(u8, name, "to_c_string")) return "*u8";
                if (std.mem.eql(u8, name, "make_vector2")) return "Vector2";
                if (std.mem.eql(u8, name, "make_vector3")) return "Vector3";
                if (std.mem.eql(u8, name, "compiler_get_nodes")) return "*Code_Node";
                if (std.mem.eql(u8, name, "compiler_get_code")) return "Code";
                if (std.mem.eql(u8, name, "get_build_options")) return "Build_Options";
                if (std.mem.eql(u8, name, "make_location")) return "Source_Code_Location";
                if (std.mem.eql(u8, name, "split")) return "[..] string";
                if (std.mem.eql(u8, name, "get_command_line_arguments")) return "[..] string";
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
        .run_expr => return typeTextForExpr(ctx, ast.data(expr).lhs, diag),
        .typed_aggregate_literal => {
            const payload = ast.extraSlice(ast.data(expr).lhs);
            if (payload.len >= 1) return ctx.nodeSource(@intCast(payload[0]));
            return null;
        },
        .typed_array_literal => return typedArrayLiteralTypeText(ctx, expr),
        else => return null,
    }
}

fn typeTextForDecl(ctx: *GenContext, decl: NodeIndex, diag: Diagnostic) ?[]const u8 {
    const ast = ctx.ast;
    if (decl == @import("Ast.zig").null_node or decl >= ast.node_tags.items.len) return null;
    if (ctx.type_overrides.get(decl)) |actual_type| return actual_type;
    return switch (ast.tag(decl)) {
        .var_decl => blk: {
            const type_node = ast.data(decl).lhs;
            if (type_node != @import("Ast.zig").null_node) break :blk ctx.nodeSource(type_node);
            const init = ast.data(decl).rhs;
            if (init != @import("Ast.zig").null_node) break :blk typeTextForExpr(ctx, init, diag);
            break :blk null;
        },
        .const_decl => blk: {
            const type_node = ast.data(decl).rhs;
            if (type_node != @import("Ast.zig").null_node) break :blk ctx.nodeSource(type_node);
            const init = ast.data(decl).lhs;
            if (init != @import("Ast.zig").null_node) break :blk typeTextForExpr(ctx, init, diag);
            break :blk null;
        },
        else => null,
    };
}

fn topLevelConstDeclByName(ast: *const Ast, name: []const u8) ?NodeIndex {
    if (ast.root == @import("Ast.zig").null_node) return null;
    const decls = ast.extraSlice(ast.data(ast.root).lhs);
    for (decls) |decl_idx| {
        const decl: NodeIndex = @intCast(decl_idx);
        if (decl >= ast.node_tags.items.len or ast.tag(decl) != .const_decl) continue;
        if (std.mem.eql(u8, ast.tokenSlice(ast.mainToken(decl)), name)) return decl;
    }
    return null;
}

fn stripPointerText(raw: []const u8) []const u8 {
    var ty = std.mem.trim(u8, raw, " \t\r\n");
    while (std.mem.startsWith(u8, ty, "*")) ty = std.mem.trim(u8, ty[1..], " \t\r\n");
    return ty;
}

fn isCodeNodeTypeText(raw: []const u8) bool {
    const clean = std.mem.trim(u8, stripPointerText(raw), " \t\r\n");
    return std.mem.eql(u8, firstTypeWord(clean), "Code_Node") or
        std.mem.eql(u8, firstTypeWord(clean), "Code_Literal") or
        std.mem.eql(u8, firstTypeWord(clean), "Code_Procedure_Call") or
        std.mem.eql(u8, firstTypeWord(clean), "Code_Declaration");
}

fn isCodeArgumentTypeText(raw: []const u8) bool {
    const clean = std.mem.trim(u8, stripPointerText(raw), " \t\r\n");
    return std.mem.eql(u8, firstTypeWord(clean), "Code_Argument");
}

fn isCodeNodeKindName(name: []const u8) bool {
    return std.mem.eql(u8, name, "IDENT") or
        std.mem.eql(u8, name, "TYPE_INSTANTIATION") or
        std.mem.eql(u8, name, "LITERAL") or
        std.mem.eql(u8, name, "DECLARATION") or
        std.mem.eql(u8, name, "PROCEDURE_CALL") or
        std.mem.eql(u8, name, "BINARY_OPERATOR") or
        std.mem.eql(u8, name, "UNARY_OPERATOR") or
        std.mem.eql(u8, name, "BLOCK") or
        std.mem.eql(u8, name, "STATEMENT");
}

fn isOsEnumName(name: []const u8) bool {
    return std.mem.eql(u8, name, "WINDOWS") or
        std.mem.eql(u8, name, "LINUX") or
        std.mem.eql(u8, name, "MACOS") or
        std.mem.eql(u8, name, "DARWIN");
}

fn hostOsName() []const u8 {
    return switch (@import("builtin").target.os.tag) {
        .windows => "WINDOWS",
        .linux => "LINUX",
        .macos => "MACOS",
        else => @tagName(@import("builtin").target.os.tag),
    };
}

fn isCodeNodeExpression(ctx: *GenContext, expr: NodeIndex, diag: Diagnostic) bool {
    const ast = ctx.ast;
    if (typeTextForExpr(ctx, expr, diag)) |text| return isCodeNodeTypeText(text);
    if (expr == @import("Ast.zig").null_node or expr >= ast.node_tags.items.len) return false;
    return switch (ast.tag(expr)) {
        .index_expr => blk: {
            const base_text = typeTextForExpr(ctx, ast.data(expr).lhs, diag) orelse break :blk true;
            const elem = dynamicArrayElementText(base_text) orelse staticArrayElementText(base_text) orelse break :blk false;
            break :blk isCodeNodeTypeText(elem);
        },
        .identifier => false,
        else => false,
    };
}

fn isCodeArgumentExpression(ctx: *GenContext, expr: NodeIndex, diag: Diagnostic) bool {
    if (typeTextForExpr(ctx, expr, diag)) |text| return isCodeArgumentTypeText(text);
    return false;
}

fn isCodeArgumentSyntax(ast: *const Ast, expr: NodeIndex) bool {
    if (expr == @import("Ast.zig").null_node or expr >= ast.node_tags.items.len) return false;
    if (ast.tag(expr) != .index_expr) return false;
    const base = ast.data(expr).lhs;
    if (base == @import("Ast.zig").null_node or base >= ast.node_tags.items.len or ast.tag(base) != .field_access) return false;
    return std.mem.eql(u8, ast.tokenSlice(ast.data(base).rhs), "arguments_unsorted");
}

fn staticArrayTypeNodeForExpr(ctx: *GenContext, expr: NodeIndex) ?NodeIndex {
    const ast = ctx.ast;
    if (expr == @import("Ast.zig").null_node or expr >= ast.node_tags.items.len) return null;
    if (ast.tag(expr) != .identifier) return null;
    const decl = ctx.resolved.local_values.get(expr) orelse return null;
    if (decl == @import("Ast.zig").null_node or decl >= ast.node_tags.items.len or ast.tag(decl) != .var_decl) return null;
    const type_node = ast.data(decl).lhs;
    if (type_node == @import("Ast.zig").null_node or ast.tag(type_node) != .array_type) return null;
    if (ast.data(type_node).lhs == @import("Ast.zig").null_node) return null;
    return type_node;
}

fn isDynamicArrayTypeText(raw: []const u8) bool {
    const ty = std.mem.trim(u8, raw, " \t\r\n");
    return std.mem.startsWith(u8, ty, "[..]") or std.mem.startsWith(u8, ty, "[]");
}

fn isStorageValueTypeText(raw: []const u8) bool {
    const ty = std.mem.trim(u8, stripPointerText(raw), " \t\r\n");
    return isDynamicArrayTypeText(ty) or isStaticArrayTypeText(ty);
}

fn isStaticArrayTypeText(raw: []const u8) bool {
    const ty = std.mem.trim(u8, stripPointerText(raw), " \t\r\n");
    return std.mem.startsWith(u8, ty, "[") and !std.mem.startsWith(u8, ty, "[..]") and !std.mem.startsWith(u8, ty, "[]");
}

fn dynamicArrayElementText(raw: []const u8) ?[]const u8 {
    const ty = std.mem.trim(u8, stripPointerText(raw), " \t\r\n");
    if (std.mem.startsWith(u8, ty, "[..]")) return std.mem.trim(u8, ty[4..], " \t\r\n");
    if (std.mem.startsWith(u8, ty, "[]")) return std.mem.trim(u8, ty[2..], " \t\r\n");
    return null;
}

fn isBindingOptionArrayField(name: []const u8) bool {
    return std.mem.eql(u8, name, "libpaths") or
        std.mem.eql(u8, name, "libnames") or
        std.mem.eql(u8, name, "include_paths") or
        std.mem.eql(u8, name, "source_files") or
        std.mem.eql(u8, name, "system_include_paths") or
        std.mem.eql(u8, name, "extra_clang_arguments");
}

fn bindingOptionFieldType(name: []const u8) ?[]const u8 {
    if (isBindingOptionArrayField(name)) return "[..] string";
    if (std.mem.eql(u8, name, "header")) return "string";
    if (std.mem.eql(u8, name, "strip_flags")) return "int";
    return null;
}

fn buildOptionsFieldType(name: []const u8) ?[]const u8 {
    if (std.mem.eql(u8, name, "import_path") or std.mem.eql(u8, name, "compile_time_command_line")) return "[..] string";
    if (std.mem.eql(u8, name, "llvm_options")) return "Build_Options_LLVM_Options";
    if (std.mem.eql(u8, name, "output_executable_name") or
        std.mem.eql(u8, name, "output_path") or
        std.mem.eql(u8, name, "intermediate_path") or
        std.mem.eql(u8, name, "output_type") or
        std.mem.eql(u8, name, "backend") or
        std.mem.eql(u8, name, "backtrace_on_crash") or
        std.mem.eql(u8, name, "array_bounds_check") or
        std.mem.eql(u8, name, "cast_bounds_check") or
        std.mem.eql(u8, name, "null_pointer_check"))
    {
        return "string";
    }
    if (std.mem.eql(u8, name, "write_added_strings") or
        std.mem.eql(u8, name, "stack_trace") or
        std.mem.eql(u8, name, "enable_bytecode_inliner") or
        std.mem.eql(u8, name, "runtime_storageless_type_info"))
    {
        return "bool";
    }
    return null;
}

fn buildOptionsLlvmFieldType(name: []const u8) ?[]const u8 {
    if (std.mem.eql(u8, name, "output_bitcode")) return "bool";
    return null;
}

fn isBuildOptionsValueType(type_text: []const u8) bool {
    const first = firstTypeWord(type_text);
    return std.mem.eql(u8, first, "Build_Options") or std.mem.eql(u8, first, "Build_Options_LLVM_Options");
}

fn isBindingOptionField(name: []const u8) bool {
    return bindingOptionFieldType(name) != null;
}

fn staticArrayElementText(raw: []const u8) ?[]const u8 {
    const ty = std.mem.trim(u8, stripPointerText(raw), " \t\r\n");
    if (!std.mem.startsWith(u8, ty, "[") or std.mem.startsWith(u8, ty, "[..]") or std.mem.startsWith(u8, ty, "[]")) return null;
    const close = std.mem.indexOfScalar(u8, ty, ']') orelse return null;
    return std.mem.trim(u8, ty[close + 1 ..], " \t\r\n");
}

fn sortKindForElementText(raw: []const u8) ?u32 {
    const elem_name = firstTypeWord(std.mem.trim(u8, raw, " \t\r\n"));
    if (std.mem.eql(u8, elem_name, "string")) return 2;
    if (std.mem.eql(u8, elem_name, "float") or std.mem.eql(u8, elem_name, "float64")) return 1;
    if (std.mem.eql(u8, elem_name, "int") or std.mem.eql(u8, elem_name, "s64") or std.mem.eql(u8, elem_name, "u64") or std.mem.eql(u8, elem_name, "s32") or std.mem.eql(u8, elem_name, "u32") or std.mem.eql(u8, elem_name, "u8") or std.mem.eql(u8, elem_name, "s8")) return 0;
    return null;
}

fn isArrayLiteralNode(ast: *const Ast, node: NodeIndex) bool {
    if (node == @import("Ast.zig").null_node or node >= ast.node_tags.items.len) return false;
    return ast.tag(node) == .aggregate_literal or ast.tag(node) == .typed_array_literal;
}

fn arrayLiteralElements(ast: *const Ast, node: NodeIndex) ?[]const u32 {
    if (node == @import("Ast.zig").null_node or node >= ast.node_tags.items.len) return null;
    return switch (ast.tag(node)) {
        .aggregate_literal => ast.extraSlice(ast.data(node).lhs),
        .typed_array_literal => blk: {
            const payload = ast.extraSlice(ast.data(node).lhs);
            if (payload.len < 2) break :blk null;
            break :blk ast.extraSlice(payload[1]);
        },
        else => null,
    };
}

fn typedArrayLiteralTypeText(ctx: *GenContext, node: NodeIndex) ?[]const u8 {
    const ast = ctx.ast;
    if (node == @import("Ast.zig").null_node or node >= ast.node_tags.items.len or ast.tag(node) != .typed_array_literal) return null;
    const payload = ast.extraSlice(ast.data(node).lhs);
    if (payload.len < 2) return null;
    const elem_type = ctx.nodeSource(@intCast(payload[0]));
    const elems = ast.extraSlice(payload[1]);
    const text = std.fmt.allocPrint(ctx.program.allocator, "[{d}] {s}", .{ elems.len, elem_type }) catch return null;
    ctx.owned_type_texts.append(ctx.program.allocator, text) catch {
        ctx.program.allocator.free(text);
        return null;
    };
    return text;
}

fn staticArrayCountFromText(ctx: *GenContext, raw: []const u8, diag: Diagnostic) !?u64 {
    const ty = std.mem.trim(u8, stripPointerText(raw), " \t\r\n");
    if (!std.mem.startsWith(u8, ty, "[") or std.mem.startsWith(u8, ty, "[..]")) return null;
    const close = std.mem.indexOfScalar(u8, ty, ']') orelse return null;
    const count_text = std.mem.trim(u8, ty[1..close], " \t\r\n");
    if (count_text.len == 0) return null;
    if (std.fmt.parseInt(u64, count_text, 10)) |count| return count else |_| {}
    if (evalIntegerTextExpr(ctx, count_text)) |count| {
        if (count >= 0) return @intCast(count);
    } else |_| {}
    const sym = ctx.resolved.lookup(count_text) orelse return null;
    const decl = switch (sym) {
        .const_value => |node| node,
        else => return null,
    };
    if (decl == @import("Ast.zig").null_node or decl >= ctx.ast.node_tags.items.len or ctx.ast.tag(decl) != .const_decl) return null;
    const value = try evalIntegerConstExpr(ctx, ctx.ast.data(decl).lhs, diag);
    if (value < 0) return null;
    return @intCast(value);
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
    if (std.mem.eql(u8, type_name, "Allocator")) {
        if (std.mem.eql(u8, field_name, "proc")) return .{ .offset = 0, .type_text = "s64" };
        if (std.mem.eql(u8, field_name, "data")) return .{ .offset = 8, .type_text = "*void" };
    }
    if (std.mem.eql(u8, type_name, "string")) {
        if (std.mem.eql(u8, field_name, "count")) return .{ .offset = 0, .type_text = "int" };
        if (std.mem.eql(u8, field_name, "data")) return .{ .offset = 8, .type_text = "*u8" };
    }
    const type_node = try structTypeNodeByName(ctx, type_name) orelse {
        if (ctx.type_context_parent) |parent| return try fieldInfoFromTypeText(parent, raw_type, field_name, diag);
        return null;
    };
    var restores = try bindContainerTypeArgs(ctx, raw_type, type_node);
    defer {
        restoreContainerTypeArgs(ctx, restores.items) catch {};
        restores.deinit(ctx.program.allocator);
    }
    return try containerFieldInfoFromSource(ctx, type_node, field_name, diag);
}

fn typeTextIsStruct(ctx: *GenContext, raw_type: []const u8, diag: Diagnostic) !bool {
    const type_name = firstTypeWord(stripPointerText(raw_type));
    if (type_name.len == 0) return false;
    if (std.mem.eql(u8, type_name, "Allocator") or std.mem.eql(u8, type_name, "Pool") or std.mem.eql(u8, type_name, "Flat_Pool")) return true;
    if (ctx.type_context_parent) |parent| {
        if (try typeTextIsStruct(parent, raw_type, diag)) return true;
    }
    return (try structTypeNodeByName(ctx, type_name)) != null;
}

fn typeTextIsEmbeddedStruct(ctx: *GenContext, raw_type: []const u8, diag: Diagnostic) !bool {
    var ty = std.mem.trim(u8, raw_type, " \t\r\n");
    while (std.mem.startsWith(u8, ty, "using")) ty = std.mem.trim(u8, ty[5..], " \t\r\n");
    if (ty.len == 0 or ty[0] == '*') return false;
    if (std.mem.startsWith(u8, ty, "[..]") or std.mem.indexOf(u8, ty, "->") != null) return false;
    return try typeTextIsStruct(ctx, ty, diag);
}

fn structTypeNodeByName(ctx: *GenContext, name: []const u8) !?NodeIndex {
    const ast = ctx.ast;
    if (ctx.local_type_decls.get(name)) |local_type_node| {
        if (local_type_node == @import("Ast.zig").null_node or local_type_node >= ast.node_tags.items.len) return null;
        if (ast.tag(local_type_node) == .identifier or ast.tag(local_type_node) == .type_expr) {
            const alias = ast.tokenSlice(ast.mainToken(local_type_node));
            if (!std.mem.eql(u8, alias, name)) return try structTypeNodeByName(ctx, alias);
            return null;
        }
        if (ast.tag(local_type_node) == .struct_type or ast.tag(local_type_node) == .union_type) return local_type_node;
        return null;
    }
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

fn typeIdFromTypeText(raw: []const u8) u32 {
    const clean = std.mem.trim(u8, raw, " \t\r\n");
    if (std.mem.startsWith(u8, clean, "*")) return 10;
    if (std.mem.startsWith(u8, clean, "[..]")) return 16;
    const name = firstTypeWord(clean);
    if (std.mem.eql(u8, name, "bool")) return 1;
    if (std.mem.eql(u8, name, "s32") or std.mem.eql(u8, name, "u32")) return 4;
    if (std.mem.eql(u8, name, "int") or std.mem.eql(u8, name, "s64") or std.mem.eql(u8, name, "u64")) return 5;
    if (std.mem.eql(u8, name, "u8") or std.mem.eql(u8, name, "s8")) return 7;
    if (std.mem.eql(u8, name, "u16") or std.mem.eql(u8, name, "s16")) return 8;
    if (std.mem.eql(u8, name, "float") or std.mem.eql(u8, name, "float32")) return 12;
    if (std.mem.eql(u8, name, "float64")) return 13;
    if (std.mem.eql(u8, name, "string")) return 14;
    if (std.mem.eql(u8, name, "Type")) return 15;
    return 16;
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

fn canonicalSourcePath(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    if (std.fs.path.isAbsolute(path)) return allocator.dupe(u8, path);
    var cwd_buf: [std.fs.max_path_bytes]u8 = undefined;
    _ = std.c.getcwd(&cwd_buf, cwd_buf.len) orelse return allocator.dupe(u8, path);
    const cwd_len = std.mem.indexOfScalar(u8, &cwd_buf, 0) orelse cwd_buf.len;
    return std.fs.path.join(allocator, &.{ cwd_buf[0..cwd_len], path });
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

fn collectReachableProcs(allocator: std.mem.Allocator, ast: *const Ast, resolved: *const Resolved, proc_node: NodeIndex, call_expr: NodeIndex) !std.AutoHashMapUnmanaged(NodeIndex, void) {
    var set: std.AutoHashMapUnmanaged(NodeIndex, void) = .empty;
    errdefer set.deinit(allocator);
    var seen: std.AutoHashMapUnmanaged(NodeIndex, void) = .empty;
    defer seen.deinit(allocator);
    try addReachableProc(allocator, ast, resolved, &set, &seen, proc_node);
    try scanReachableProcCalls(allocator, ast, resolved, &set, &seen, call_expr);
    return set;
}

fn addReachableProc(allocator: std.mem.Allocator, ast: *const Ast, resolved: *const Resolved, set: *std.AutoHashMapUnmanaged(NodeIndex, void), seen: *std.AutoHashMapUnmanaged(NodeIndex, void), proc_node: NodeIndex) !void {
    if (proc_node == @import("Ast.zig").null_node or proc_node >= ast.node_tags.items.len or ast.tag(proc_node) != .proc_decl) return;
    if (set.contains(proc_node)) return;
    try set.put(allocator, proc_node, {});
    try scanReachableProcCalls(allocator, ast, resolved, set, seen, ast.data(proc_node).lhs);
}

fn scanReachableProcCalls(allocator: std.mem.Allocator, ast: *const Ast, resolved: *const Resolved, set: *std.AutoHashMapUnmanaged(NodeIndex, void), seen: *std.AutoHashMapUnmanaged(NodeIndex, void), node: NodeIndex) anyerror!void {
    if (node == @import("Ast.zig").null_node or node >= ast.node_tags.items.len) return;
    if (seen.contains(node)) return;
    try seen.put(allocator, node, {});
    const data = ast.data(node);
    switch (ast.tag(node)) {
        .call_expr => {
            const args = if (data.rhs < ast.extra_data.items.len) ast.extraSlice(data.rhs) else &[_]u32{};
            if (resolveReachableCallTarget(ast, resolved, data.lhs, args.len)) |target| {
                try addReachableProc(allocator, ast, resolved, set, seen, target);
            }
            for (args) |arg| try scanReachableProcCalls(allocator, ast, resolved, set, seen, @intCast(arg));
        },
        .block, .stmt_list, .aggregate_literal => {
            if (data.lhs < ast.extra_data.items.len) {
                for (ast.extraSlice(data.lhs)) |child| try scanReachableProcCalls(allocator, ast, resolved, set, seen, @intCast(child));
            }
        },
        .typed_aggregate_literal, .typed_array_literal => {
            if (data.lhs < ast.extra_data.items.len) {
                const payload = ast.extraSlice(data.lhs);
                if (payload.len >= 1) try scanReachableProcCalls(allocator, ast, resolved, set, seen, @intCast(payload[0]));
                if (payload.len >= 2) {
                    for (ast.extraSlice(payload[1])) |child| try scanReachableProcCalls(allocator, ast, resolved, set, seen, @intCast(child));
                }
            }
        },
        .if_stmt => {
            try scanReachableProcCalls(allocator, ast, resolved, set, seen, data.lhs);
            if (data.rhs < ast.extra_data.items.len) {
                for (ast.extraSlice(data.rhs)) |child| try scanReachableProcCalls(allocator, ast, resolved, set, seen, @intCast(child));
            }
        },
        .for_stmt => {
            if (data.lhs < ast.extra_data.items.len) {
                for (ast.extraSlice(data.lhs)) |operand| {
                    if ((operand & 0x80000000) == 0 and operand < ast.node_tags.items.len) {
                        try scanReachableProcCalls(allocator, ast, resolved, set, seen, @intCast(operand));
                    }
                }
            }
            try scanReachableProcCalls(allocator, ast, resolved, set, seen, data.rhs);
        },
        .var_decl, .assign_stmt, .binary_expr, .index_expr, .array_type, .meta_expr, .field_access, .proc_type => {
            try scanReachableProcCalls(allocator, ast, resolved, set, seen, data.lhs);
            try scanReachableProcCalls(allocator, ast, resolved, set, seen, data.rhs);
        },
        .const_decl, .placeholder_decl, .expr_stmt, .return_stmt, .pointer_type, .type_of_expr, .size_of_expr, .run_expr, .is_constant_expr, .unary_expr, .defer_stmt => {
            try scanReachableProcCalls(allocator, ast, resolved, set, seen, data.lhs);
        },
        .proc_decl => try scanReachableProcCalls(allocator, ast, resolved, set, seen, data.lhs),
        else => {},
    }
}

fn resolveReachableCallTarget(ast: *const Ast, resolved: *const Resolved, callee: NodeIndex, arg_count: usize) ?NodeIndex {
    if (callee == @import("Ast.zig").null_node or callee >= ast.node_tags.items.len) return null;
    if (ast.tag(callee) == .proc_decl) return callee;
    if (ast.tag(callee) != .identifier) return null;
    if (resolved.local_values.get(callee)) |decl| {
        if (decl != @import("Ast.zig").null_node and decl < ast.node_tags.items.len and ast.tag(decl) == .proc_decl) return decl;
    }
    const name = ast.tokenSlice(ast.mainToken(callee));
    if (resolved.overloads(name)) |candidates| {
        for (candidates) |candidate| {
            const sig = procSignature(ast, candidate) orelse {
                if (arg_count == 0) return candidate;
                continue;
            };
            const params = ast.extraSlice(sig.params_extra);
            if (arg_count <= params.len) return candidate;
        }
    }
    if (resolved.lookup(name)) |sym| switch (sym) {
        .proc => |proc| return proc,
        else => {},
    };
    return null;
}

fn procHasExpandModifier(ast: *const Ast, proc: NodeIndex, next_decl: NodeIndex) bool {
    if (proc == @import("Ast.zig").null_node or ast.tag(proc) != .proc_decl) return false;
    const token_start = ast.tokens[ast.mainToken(proc)].start;
    const start = token_start - @min(token_start, 200);
    const end = if (next_decl != @import("Ast.zig").null_node and next_decl < ast.node_tags.items.len)
        ast.tokens[ast.mainToken(next_decl)].start
    else
        ast.source.len;
    if (end <= start or end > ast.source.len) return false;
    return std.mem.indexOf(u8, ast.source[start..end], "#expand") != null;
}

fn procHasExpandModifierLocal(ast: *const Ast, proc: NodeIndex) bool {
    if (proc == @import("Ast.zig").null_node or ast.tag(proc) != .proc_decl) return false;
    const token_start = ast.tokens[ast.mainToken(proc)].start;
    const body = ast.data(proc).lhs;
    const body_start = if (body != @import("Ast.zig").null_node and body < ast.node_tags.items.len) ast.tokens[ast.mainToken(body)].start else @min(ast.source.len, token_start + 256);
    const start = token_start - @min(token_start, 200);
    if (body_start <= start or body_start > ast.source.len) return false;
    return std.mem.indexOf(u8, ast.source[start..body_start], "#expand") != null;
}

fn procContainsCompileTimeOnlyCompilerApi(ast: *const Ast, proc: NodeIndex) bool {
    if (proc == @import("Ast.zig").null_node or ast.tag(proc) != .proc_decl) return false;
    var seen: std.AutoHashMapUnmanaged(NodeIndex, void) = .empty;
    defer seen.deinit(ast.allocator);
    return nodeContainsCompileTimeOnlyCompilerApi(ast, ast.data(proc).lhs, &seen);
}

fn procHasSourceLocationAbi(ast: *const Ast, proc: NodeIndex) bool {
    const sig = procSignature(ast, proc) orelse return false;
    if (sig.return_type != @import("Ast.zig").null_node and std.mem.eql(u8, firstTypeWord(nodeSourceText(ast, sig.return_type)), "Source_Code_Location")) return true;
    const params = ast.extraSlice(sig.params_extra);
    for (params) |param_idx| {
        const param: NodeIndex = @intCast(param_idx);
        const param_type = ast.data(param).lhs;
        if (param_type != @import("Ast.zig").null_node and std.mem.eql(u8, firstTypeWord(nodeSourceText(ast, param_type)), "Source_Code_Location")) return true;
        if (isCallerLocationExpr(ast, ast.data(param).rhs)) return true;
    }
    return false;
}

fn nodeSourceText(ast: *const Ast, node: NodeIndex) []const u8 {
    if (node == @import("Ast.zig").null_node or node >= ast.node_tags.items.len) return "";
    var start = ast.tokens[ast.mainToken(node)].start;
    var end = ast.tokens[ast.mainToken(node)].end;
    collectNodeStart(ast, node, &start);
    collectNodeEnd(ast, node, &end);
    return std.mem.trim(u8, ast.source[start..@min(end, ast.source.len)], " \t\r\n;");
}

fn nodeContainsCompileTimeOnlyCompilerApi(ast: *const Ast, node: NodeIndex, seen: *std.AutoHashMapUnmanaged(NodeIndex, void)) bool {
    if (node == @import("Ast.zig").null_node or node >= ast.node_tags.items.len) return false;
    if (seen.contains(node)) return false;
    seen.put(ast.allocator, node, {}) catch return false;
    const data = ast.data(node);
    switch (ast.tag(node)) {
        .call_expr => {
            const callee = data.lhs;
            if (ast.tag(callee) == .identifier) {
                const name = ast.tokenSlice(ast.mainToken(callee));
                if (std.mem.eql(u8, name, "compiler_get_nodes") or
                    std.mem.eql(u8, name, "compiler_get_code") or
                    std.mem.eql(u8, name, "print_expression") or
                    std.mem.eql(u8, name, "make_location") or
                    std.mem.eql(u8, name, "compiler_report"))
                {
                    return true;
                }
            }
            if (nodeContainsCompileTimeOnlyCompilerApi(ast, data.lhs, seen)) return true;
            if (validExtraSlice(ast, data.rhs)) |args| {
                for (args) |arg| {
                    if (nodeContainsCompileTimeOnlyCompilerApi(ast, @intCast(arg), seen)) return true;
                }
            }
            return false;
        },
        .meta_stmt => {
            if (ast.tokens[ast.mainToken(node)].tag == .directive_insert) return true;
            return nodeContainsCompileTimeOnlyCompilerApi(ast, data.lhs, seen) or nodeContainsCompileTimeOnlyCompilerApi(ast, data.rhs, seen);
        },
        .block, .stmt_list, .aggregate_literal => {
            if (validExtraSlice(ast, data.lhs)) |children| {
                for (children) |child| {
                    if (nodeContainsCompileTimeOnlyCompilerApi(ast, @intCast(child), seen)) return true;
                }
            }
            return false;
        },
        .typed_aggregate_literal, .typed_array_literal => {
            if (validExtraSlice(ast, data.lhs)) |payload| {
                if (payload.len >= 1 and nodeContainsCompileTimeOnlyCompilerApi(ast, @intCast(payload[0]), seen)) return true;
                if (payload.len >= 2) {
                    if (validExtraSlice(ast, payload[1])) |children| {
                        for (children) |child| {
                            if (nodeContainsCompileTimeOnlyCompilerApi(ast, @intCast(child), seen)) return true;
                        }
                    }
                }
            }
            return false;
        },
        .if_stmt => {
            if (nodeContainsCompileTimeOnlyCompilerApi(ast, data.lhs, seen)) return true;
            if (validExtraSlice(ast, data.rhs)) |blocks| {
                for (blocks) |child| {
                    const clean = child & 0x7fffffff;
                    if (clean != node and clean < ast.node_tags.items.len and nodeContainsCompileTimeOnlyCompilerApi(ast, @intCast(clean), seen)) return true;
                }
            }
            return false;
        },
        .for_stmt => {
            if (validExtraSlice(ast, data.lhs)) |operands| {
                for (operands) |operand| {
                    if ((operand & 0x80000000) != 0) continue;
                    if (operand == node) continue;
                    if (operand < ast.node_tags.items.len and nodeContainsCompileTimeOnlyCompilerApi(ast, @intCast(operand), seen)) return true;
                }
            }
            return nodeContainsCompileTimeOnlyCompilerApi(ast, data.rhs, seen);
        },
        .var_decl, .assign_stmt, .binary_expr, .index_expr, .array_type, .meta_expr, .field_access, .proc_type => {
            return nodeContainsCompileTimeOnlyCompilerApi(ast, data.lhs, seen) or nodeContainsCompileTimeOnlyCompilerApi(ast, data.rhs, seen);
        },
        .unary_expr => {
            if (ast.tokens[ast.mainToken(node)].tag == .keyword_cast and data.rhs != @import("Ast.zig").null_node) {
                const target: NodeIndex = @intCast(data.rhs & 0x7fffffff);
                const target_name = firstTypeWord(stripPointerText(nodeSourceText(ast, target)));
                if (std.mem.startsWith(u8, target_name, "Type_Info")) return true;
            }
            return nodeContainsCompileTimeOnlyCompilerApi(ast, data.lhs, seen);
        },
        .const_decl, .placeholder_decl, .expr_stmt, .return_stmt, .pointer_type, .type_of_expr, .size_of_expr, .run_expr, .is_constant_expr, .defer_stmt => {
            return nodeContainsCompileTimeOnlyCompilerApi(ast, data.lhs, seen);
        },
        .proc_decl => return nodeContainsCompileTimeOnlyCompilerApi(ast, data.lhs, seen),
        else => return false,
    }
}

fn validExtraSlice(ast: *const Ast, start: u32) ?[]const u32 {
    if (start >= ast.extra_data.items.len) return null;
    const len = ast.extra_data.items[start];
    if (start + 1 + len > ast.extra_data.items.len) return null;
    return ast.extra_data.items[start + 1 .. start + 1 + len];
}

fn typeIdFromToken(ast: *const Ast, token: u32, diag: Diagnostic) !u32 {
    const name = ast.tokenSlice(token);
    if (std.mem.eql(u8, name, "int") or std.mem.eql(u8, name, "s64")) return 5;
    if (std.mem.eql(u8, name, "Node_Index") or std.mem.eql(u8, name, "Token_Index") or std.mem.eql(u8, name, "Extra_Index")) return 5;
    if (std.mem.eql(u8, name, "Register") or std.mem.eql(u8, name, "String_Index") or std.mem.eql(u8, name, "Type_Id")) return 5;
    if (std.mem.eql(u8, name, "Token_Tag") or std.mem.eql(u8, name, "Ast_Node_Tag") or std.mem.eql(u8, name, "Compile_Result")) return 5;
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
    const operand_text = std.mem.trim(u8, ctx.nodeSource(operand), " \t\r\n");
    if (std.mem.startsWith(u8, operand_text, "type_of(") and std.mem.endsWith(u8, operand_text, ")")) {
        const inner = std.mem.trim(u8, operand_text["type_of(".len .. operand_text.len - 1], " \t\r\n");
        if (std.mem.indexOfScalar(u8, inner, '.')) |dot| {
            const type_name = std.mem.trim(u8, inner[0..dot], " \t\r\n");
            const field_name = std.mem.trim(u8, inner[dot + 1 ..], " \t\r\n");
            if (try structFieldSizeByName(ctx, type_name, field_name, diag)) |size| return size;
        }
    }
    if (ast.tag(operand) == .identifier or ast.tag(operand) == .type_expr) {
        var name = ast.tokenSlice(ast.mainToken(operand));
        if (std.mem.startsWith(u8, name, "$")) name = name[1..];
        if (ctx.polymorph_types.get(name)) |actual_type| return try typeTextSize(ctx, actual_type, diag);
        if (try structSizeByName(ctx, name, diag)) |size| return size;
        if (ast.tag(operand) == .identifier) {
            if (ctx.resolved.local_values.get(operand)) |decl| {
                if (decl != @import("Ast.zig").null_node and ast.tag(decl) == .const_decl) {
                    const value = ast.data(decl).lhs;
                    if (ast.tag(value) == .struct_type or ast.tag(value) == .union_type) return try containerSizeFromSource(ctx, value, diag);
                }
            }
        }
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
    if (try structTypeNodeByName(ctx, name)) |type_node| return try containerSizeFromSource(ctx, type_node, diag);
    if (ctx.type_context_parent) |parent| if (try structSizeByName(parent, name, diag)) |size| return size;
    if (containerBodySourceByName(ctx, name)) |body| return try containerSizeFromBody(ctx, body, diag);
    return null;
}

fn structSizeFromTypeText(ctx: *GenContext, raw_type: []const u8, diag: Diagnostic) anyerror!?u64 {
    const type_name = firstTypeWord(stripPointerText(raw_type));
    const type_node = try structTypeNodeByName(ctx, type_name) orelse {
        if (ctx.type_context_parent) |parent| return try structSizeFromTypeText(parent, raw_type, diag);
        return null;
    };
    var restores = try bindContainerTypeArgs(ctx, raw_type, type_node);
    defer {
        restoreContainerTypeArgs(ctx, restores.items) catch {};
        restores.deinit(ctx.program.allocator);
    }
    return try containerSizeFromSource(ctx, type_node, diag);
}

fn structFieldSizeFromAccess(ctx: *GenContext, access: NodeIndex, diag: Diagnostic) !?u64 {
    const ast = ctx.ast;
    const lhs = ast.data(access).lhs;
    if (ast.tag(lhs) != .identifier and ast.tag(lhs) != .type_expr) return null;
    const type_name = ast.tokenSlice(ast.mainToken(lhs));
    const field_name = ast.tokenSlice(ast.data(access).rhs);
    if (ast.tag(lhs) == .identifier) {
        if (ctx.resolved.local_values.get(lhs)) |decl| {
            if (decl != @import("Ast.zig").null_node and ast.tag(decl) == .const_decl) {
                const value = ast.data(decl).lhs;
                if (ast.tag(value) == .struct_type or ast.tag(value) == .union_type) return try containerFieldSizeFromSource(ctx, value, field_name, diag);
            }
        }
    }
    return try structFieldSizeByName(ctx, type_name, field_name, diag);
}

fn structFieldSizeByName(ctx: *GenContext, type_name: []const u8, field_name: []const u8, diag: Diagnostic) !?u64 {
    if (try structTypeNodeByName(ctx, type_name)) |type_node| return try containerFieldSizeFromSource(ctx, type_node, field_name, diag);
    if (containerBodySourceByName(ctx, type_name)) |body| return try containerFieldSizeFromBody(ctx, body, field_name, diag);
    return null;
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
    const type_node = try structTypeNodeByName(ctx, type_name) orelse return null;
    return try containerFieldOffsetFromSource(ctx, type_node, field_name, diag);
}

fn containerSizeFromSource(ctx: *GenContext, type_node: NodeIndex, diag: Diagnostic) anyerror!u64 {
    const body = containerBodySource(ctx.ast, type_node) orelse return 8;
    return try containerSizeFromBody(ctx, body, diag);
}

fn containerSizeFromBody(ctx: *GenContext, body: []const u8, diag: Diagnostic) anyerror!u64 {
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

fn bindContainerTypeArgs(ctx: *GenContext, raw_type: []const u8, type_node: NodeIndex) !std.ArrayList(TypeArgRestore) {
    var restores = std.ArrayList(TypeArgRestore).empty;
    errdefer restores.deinit(ctx.program.allocator);

    const clean = std.mem.trim(u8, stripPointerText(raw_type), " \t\r\n");
    const open = std.mem.indexOfScalar(u8, clean, '(') orelse return restores;
    const close = matchingParenIndex(clean, open) orelse return restores;
    const args_text = clean[open + 1 .. close];

    const params_text = containerTypeParameterText(ctx.ast, type_node) orelse return restores;
    var arg_it = std.mem.splitScalar(u8, args_text, ',');
    var param_it = std.mem.splitScalar(u8, params_text, ',');
    while (param_it.next()) |raw_param| {
        const raw_arg = arg_it.next() orelse break;
        const colon = std.mem.indexOfScalar(u8, raw_param, ':') orelse raw_param.len;
        const name = std.mem.trim(u8, raw_param[0..colon], " \t\r\n");
        const value = std.mem.trim(u8, raw_arg, " \t\r\n");
        if (name.len == 0 or value.len == 0) continue;
        try restores.append(ctx.program.allocator, .{
            .name = name,
            .had_old = ctx.polymorph_types.contains(name),
            .old = ctx.polymorph_types.get(name) orelse "",
        });
        try ctx.polymorph_types.put(ctx.program.allocator, name, value);
    }
    return restores;
}

fn restoreContainerTypeArgs(ctx: *GenContext, restores: []const TypeArgRestore) !void {
    var i = restores.len;
    while (i > 0) {
        i -= 1;
        const restore = restores[i];
        if (restore.had_old) {
            try ctx.polymorph_types.put(ctx.program.allocator, restore.name, restore.old);
        } else {
            _ = ctx.polymorph_types.remove(restore.name);
        }
    }
}

fn matchingParenIndex(text: []const u8, open: usize) ?usize {
    if (open >= text.len or text[open] != '(') return null;
    var depth: usize = 0;
    var i = open;
    while (i < text.len) : (i += 1) {
        switch (text[i]) {
            '(' => depth += 1,
            ')' => {
                depth -= 1;
                if (depth == 0) return i;
            },
            else => {},
        }
    }
    return null;
}

fn countCommaSeparatedArgs(text: []const u8) usize {
    if (std.mem.trim(u8, text, " \t\r\n").len == 0) return 0;
    var count: usize = 1;
    var depth: usize = 0;
    for (text) |c| {
        switch (c) {
            '(' => depth += 1,
            ')' => {
                if (depth > 0) depth -= 1;
            },
            ',' => {
                if (depth == 0) count += 1;
            },
            else => {},
        }
    }
    return count;
}

fn containerTypeParameterText(ast: *const Ast, type_node: NodeIndex) ?[]const u8 {
    const start_tok = ast.mainToken(type_node);
    var i = ast.tokens[start_tok].end;
    while (i < ast.source.len and std.ascii.isWhitespace(ast.source[i])) : (i += 1) {}
    if (i >= ast.source.len or ast.source[i] != '(') return null;
    const close = matchingParenIndex(ast.source, i) orelse return null;
    return ast.source[i + 1 .. close];
}

const IntegerTextParser = struct {
    ctx: *GenContext,
    text: []const u8,
    index: usize = 0,

    fn parse(p: *IntegerTextParser) anyerror!i64 {
        const value = try p.parseAddSub();
        p.skipWs();
        if (p.index != p.text.len) return error.InvalidIntegerTextExpression;
        return value;
    }

    fn parseAddSub(p: *IntegerTextParser) anyerror!i64 {
        var lhs = try p.parseMulDiv();
        while (true) {
            p.skipWs();
            if (p.match('+')) {
                lhs += try p.parseMulDiv();
            } else if (p.match('-')) {
                lhs -= try p.parseMulDiv();
            } else {
                return lhs;
            }
        }
    }

    fn parseMulDiv(p: *IntegerTextParser) anyerror!i64 {
        var lhs = try p.parseUnary();
        while (true) {
            p.skipWs();
            if (p.match('*')) {
                lhs *= try p.parseUnary();
            } else if (p.match('/')) {
                const rhs = try p.parseUnary();
                if (rhs == 0) return error.DivisionByZero;
                lhs = @divTrunc(lhs, rhs);
            } else if (p.match('%')) {
                const rhs = try p.parseUnary();
                if (rhs == 0) return error.DivisionByZero;
                lhs = @rem(lhs, rhs);
            } else {
                return lhs;
            }
        }
    }

    fn parseUnary(p: *IntegerTextParser) anyerror!i64 {
        p.skipWs();
        if (p.match('-')) return -(try p.parseUnary());
        if (p.match('+')) return try p.parseUnary();
        return try p.parsePrimary();
    }

    fn parsePrimary(p: *IntegerTextParser) anyerror!i64 {
        p.skipWs();
        if (p.match('(')) {
            const value = try p.parseAddSub();
            p.skipWs();
            if (!p.match(')')) return error.InvalidIntegerTextExpression;
            return value;
        }
        if (p.index >= p.text.len) return error.InvalidIntegerTextExpression;
        const start = p.index;
        if (std.ascii.isDigit(p.text[p.index])) {
            p.index += 1;
            while (p.index < p.text.len and std.ascii.isDigit(p.text[p.index])) p.index += 1;
            return try std.fmt.parseInt(i64, p.text[start..p.index], 10);
        }
        if (std.ascii.isAlphabetic(p.text[p.index]) or p.text[p.index] == '_') {
            p.index += 1;
            while (p.index < p.text.len and (std.ascii.isAlphanumeric(p.text[p.index]) or p.text[p.index] == '_')) p.index += 1;
            const name = p.text[start..p.index];
            const value_text = p.ctx.polymorph_types.get(name) orelse return error.UnknownIdentifier;
            return try std.fmt.parseInt(i64, std.mem.trim(u8, value_text, " \t\r\n"), 10);
        }
        return error.InvalidIntegerTextExpression;
    }

    fn skipWs(p: *IntegerTextParser) void {
        while (p.index < p.text.len and std.ascii.isWhitespace(p.text[p.index])) p.index += 1;
    }

    fn match(p: *IntegerTextParser, c: u8) bool {
        if (p.index < p.text.len and p.text[p.index] == c) {
            p.index += 1;
            return true;
        }
        return false;
    }
};

fn evalIntegerTextExpr(ctx: *GenContext, text: []const u8) !i64 {
    var parser = IntegerTextParser{ .ctx = ctx, .text = text };
    return try parser.parse();
}

fn containerFieldSizeFromSource(ctx: *GenContext, type_node: NodeIndex, field_name: []const u8, diag: Diagnostic) !?u64 {
    const body = containerBodySource(ctx.ast, type_node) orelse return null;
    return try containerFieldSizeFromBody(ctx, body, field_name, diag);
}

fn containerFieldSizeFromBody(ctx: *GenContext, body: []const u8, field_name: []const u8, diag: Diagnostic) !?u64 {
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

fn containerBodySourceByName(ctx: *GenContext, name: []const u8) ?[]const u8 {
    var search_start: usize = 0;
    while (std.mem.indexOfPos(u8, ctx.ast.source, search_start, name)) |pos| {
        search_start = pos + name.len;
        const before_ok = pos == 0 or !(std.ascii.isAlphanumeric(ctx.ast.source[pos - 1]) or ctx.ast.source[pos - 1] == '_');
        const after = pos + name.len;
        const after_ok = after >= ctx.ast.source.len or !(std.ascii.isAlphanumeric(ctx.ast.source[after]) or ctx.ast.source[after] == '_');
        if (!before_ok or !after_ok) continue;
        var i = after;
        while (i < ctx.ast.source.len and std.ascii.isWhitespace(ctx.ast.source[i])) : (i += 1) {}
        if (i + 1 >= ctx.ast.source.len or ctx.ast.source[i] != ':' or ctx.ast.source[i + 1] != ':') continue;
        i += 2;
        while (i < ctx.ast.source.len and std.ascii.isWhitespace(ctx.ast.source[i])) : (i += 1) {}
        if (!(std.mem.startsWith(u8, ctx.ast.source[i..], "struct") or std.mem.startsWith(u8, ctx.ast.source[i..], "union"))) continue;
        while (i < ctx.ast.source.len and ctx.ast.source[i] != '{') : (i += 1) {}
        if (i >= ctx.ast.source.len) continue;
        const body_start = i + 1;
        var depth: usize = 1;
        i += 1;
        while (i < ctx.ast.source.len) : (i += 1) {
            switch (ctx.ast.source[i]) {
                '{' => depth += 1,
                '}' => {
                    depth -= 1;
                    if (depth == 0) return ctx.ast.source[body_start..i];
                },
                else => {},
            }
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
    if (std.mem.eql(u8, field_name, "STARTUP")) return 0;
    if (std.mem.eql(u8, field_name, "ALLOCATE")) return 1;
    if (std.mem.eql(u8, field_name, "RESIZE")) return 2;
    if (std.mem.eql(u8, field_name, "FREE")) return 3;
    if (std.mem.eql(u8, field_name, "IS_THIS_YOURS")) return allocator_cap_is_this_yours;
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

fn allocatorProcIdByName(name: []const u8) ?u32 {
    if (std.mem.eql(u8, name, "pool_allocator_proc")) return allocator_proc_pool;
    if (std.mem.eql(u8, name, "flat_pool_allocator_proc")) return allocator_proc_flat_pool;
    if (std.mem.eql(u8, name, "rpmalloc_allocator_proc")) return allocator_proc_rpmalloc;
    return null;
}

fn x86FeatureFlagId(field_name: []const u8) u32 {
    if (std.mem.eql(u8, field_name, "MMX")) return 1;
    if (std.mem.eql(u8, field_name, "SSE")) return 2;
    if (std.mem.eql(u8, field_name, "SSE2")) return 3;
    if (std.mem.eql(u8, field_name, "SSE3")) return 4;
    if (std.mem.eql(u8, field_name, "SSSE3")) return 5;
    if (std.mem.eql(u8, field_name, "SSE4_1")) return 6;
    if (std.mem.eql(u8, field_name, "SSE4_2")) return 7;
    if (std.mem.eql(u8, field_name, "AVX")) return 8;
    if (std.mem.eql(u8, field_name, "AVX2")) return 9;
    if (std.mem.eql(u8, field_name, "AVX512F")) return 10;
    return 0;
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
    if (std.mem.startsWith(u8, ty, "[..]") or std.mem.startsWith(u8, ty, "[]")) return 8;
    if (ty[0] == '[') {
        const close = std.mem.indexOfScalar(u8, ty, ']') orelse return 8;
        const count_text = std.mem.trim(u8, ty[1..close], " \t\r\n");
        const count = std.fmt.parseInt(u64, count_text, 10) catch blk: {
            break :blk (try staticArrayCountFromText(ctx, ty, diag)) orelse 1;
        };
        return count * try typeTextSize(ctx, ty[close + 1 ..], diag);
    }
    const name = firstTypeWord(ty);
    if (ctx.polymorph_types.get(name)) |actual_type| return try typeTextSize(ctx, actual_type, diag);
    if (std.mem.eql(u8, name, "Allocator")) return 16;
    if (std.mem.eql(u8, name, "Generate_Bindings_Options")) return 8;
    if (std.mem.eql(u8, name, "Pool") or std.mem.eql(u8, name, "Flat_Pool")) return 8;
    if (std.mem.eql(u8, name, "float") or std.mem.eql(u8, name, "float32") or std.mem.eql(u8, name, "s32") or std.mem.eql(u8, name, "u32")) return 4;
    if (std.mem.eql(u8, name, "u8") or std.mem.eql(u8, name, "s8") or std.mem.eql(u8, name, "bool")) return 1;
    if (std.mem.eql(u8, name, "u16") or std.mem.eql(u8, name, "s16")) return 2;
    if (std.mem.eql(u8, name, "int") or std.mem.eql(u8, name, "s64") or std.mem.eql(u8, name, "u64") or std.mem.eql(u8, name, "float64") or std.mem.eql(u8, name, "Type") or std.mem.eql(u8, name, "string")) return 8;
    if (std.mem.eql(u8, name, "Any")) return 16;
    if (try structSizeFromTypeText(ctx, ty, diag)) |size| return size;
    return 8;
}

fn typeTextAlign(ctx: *GenContext, raw_type: []const u8, diag: Diagnostic) anyerror!u64 {
    var ty = std.mem.trim(u8, raw_type, " \t\r\n");
    while (std.mem.startsWith(u8, ty, "using")) ty = std.mem.trim(u8, ty[5..], " \t\r\n");
    if (ty.len == 0) return 1;
    if (ty[0] == '*' or std.mem.indexOf(u8, ty, "->") != null) return 8;
    if (std.mem.startsWith(u8, ty, "[..]") or std.mem.startsWith(u8, ty, "[]")) return 8;
    if (ty[0] == '[') {
        const close = std.mem.indexOfScalar(u8, ty, ']') orelse return 8;
        return try typeTextAlign(ctx, ty[close + 1 ..], diag);
    }
    const name = firstTypeWord(ty);
    if (std.mem.eql(u8, name, "u8") or std.mem.eql(u8, name, "s8") or std.mem.eql(u8, name, "bool")) return 1;
    if (std.mem.eql(u8, name, "u16") or std.mem.eql(u8, name, "s16")) return 2;
    if (std.mem.eql(u8, name, "float") or std.mem.eql(u8, name, "float32") or std.mem.eql(u8, name, "s32") or std.mem.eql(u8, name, "u32")) return 4;
    if (std.mem.eql(u8, name, "int") or std.mem.eql(u8, name, "s64") or std.mem.eql(u8, name, "u64") or std.mem.eql(u8, name, "float") or std.mem.eql(u8, name, "float64") or std.mem.eql(u8, name, "Type")) return 8;
    return try structAlignByName(ctx, name, diag) orelse 8;
}

fn structAlignByName(ctx: *GenContext, name: []const u8, diag: Diagnostic) anyerror!?u64 {
    const ast = ctx.ast;
    const type_node = try structTypeNodeByName(ctx, name) orelse return null;
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

fn isAddressableScalarTypeWord(name: []const u8) bool {
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
        std.mem.eql(u8, name, "float64") or
        std.mem.eql(u8, name, "string");
}

fn externalNameForSourceName(name: []const u8) []const u8 {
    if (std.mem.startsWith(u8, name, "`")) return name[1..];
    return name;
}

fn forStmtIteratorName(ast: *const Ast, range: []const u32) ?[]const u8 {
    if (range.len == 0) return null;

    // Explicit for-expansion form: for :expansion iterator, index: iterable
    if (range.len == 4 and (range[1] & 0x80000000) != 0) {
        const tok = range[2];
        if (tok == 0) return "it";
        return ast.tokenSlice(tok & 0x7fffffff);
    }

    // Iterable form: for iterator[, index]: iterable
    if ((range.len == 2 or range.len == 3) and (range[1] & 0x80000000) != 0) {
        return ast.tokenSlice(range[1] & 0x7fffffff);
    }

    // Range form: for iterator: first..last
    if (range.len == 4 and range[2] != 0 and (range[2] & 0x80000000) == 0) {
        return ast.tokenSlice(range[2]);
    }

    // Jai exposes implicit loop variables in ordinary iterable loops.
    if (range.len == 1) return "it";
    return null;
}

fn forStmtIndexName(ast: *const Ast, range: []const u32) ?[]const u8 {
    if (range.len == 0) return null;

    // Explicit for-expansion form: for :expansion iterator, index: iterable
    if (range.len == 4 and (range[1] & 0x80000000) != 0) {
        const tok = range[3];
        if (tok == 0) return "it_index";
        return ast.tokenSlice(tok & 0x7fffffff);
    }

    // Iterable form: for iterator, index: iterable
    if (range.len == 3 and (range[1] & 0x80000000) != 0) {
        return ast.tokenSlice(range[2] & 0x7fffffff);
    }

    // Jai exposes an implicit index alongside the implicit iterator.
    if (range.len == 1 or (range.len == 2 and (range[1] & 0x80000000) != 0)) return "it_index";
    return null;
}

fn isSimpleIdentifierText(text: []const u8) bool {
    if (text.len == 0) return false;
    if (!(std.ascii.isAlphabetic(text[0]) or text[0] == '_')) return false;
    for (text[1..]) |c| {
        if (!(std.ascii.isAlphanumeric(c) or c == '_')) return false;
    }
    return true;
}

fn tryExecuteSpecializedRunPrint(ctx: *GenContext, run_stmt: NodeIndex, diag: Diagnostic) anyerror!bool {
    const ast = ctx.ast;
    if (ast.tokens[ast.mainToken(run_stmt)].tag != .directive_run) return false;
    const call = ast.data(run_stmt).lhs;
    if (call == @import("Ast.zig").null_node or ast.tag(call) != .call_expr) return false;
    const callee = ast.data(call).lhs;
    if (callee == @import("Ast.zig").null_node or ast.tag(callee) != .identifier) return false;
    const name = ast.tokenSlice(ast.mainToken(callee));
    if (!std.mem.eql(u8, name, "print") and !std.mem.eql(u8, name, "log")) return false;
    const args = ast.extraSlice(ast.data(call).rhs);
    if (args.len == 0) return diag.failAt(ast.tokens[ast.mainToken(call)].start, "#run print expects at least one argument", .{});
    const fmt_node: NodeIndex = @intCast(args[0]);
    if (ast.tag(fmt_node) != .string_literal) return diag.failAt(ast.tokens[ast.mainToken(fmt_node)].start, "specialized #run print requires a string literal format", .{});

    const raw_fmt = ast.stringTokenContents(ast.mainToken(fmt_node));
    const fmt = try decodeString(ctx.program.allocator, raw_fmt, diag, ast.tokens[ast.mainToken(fmt_node)].start);
    defer ctx.program.allocator.free(fmt);

    var output = std.ArrayList(u8).empty;
    defer output.deinit(ctx.program.allocator);
    var start: usize = 0;
    var arg_index: usize = 0;
    var i: usize = 0;
    while (i < fmt.len) : (i += 1) {
        if (fmt[i] != '%') continue;
        if (i > 0 and fmt[i - 1] == '\\') {
            if (start < i - 1) try output.appendSlice(ctx.program.allocator, fmt[start .. i - 1]);
            try output.append(ctx.program.allocator, '%');
            start = i + 1;
            continue;
        }
        if (i + 1 < fmt.len and fmt[i + 1] == '%') {
            try output.appendSlice(ctx.program.allocator, fmt[start .. i + 1]);
            i += 1;
            start = i + 1;
            continue;
        }
        if (start < i) try output.appendSlice(ctx.program.allocator, fmt[start..i]);
        var selected_arg_index = arg_index;
        var next_start = i + 1;
        if (i + 1 < fmt.len and fmt[i + 1] >= '1' and fmt[i + 1] <= '9') {
            selected_arg_index = fmt[i + 1] - '1';
            next_start = i + 2;
        } else {
            arg_index += 1;
        }
        if (selected_arg_index + 1 >= args.len) return diag.failAt(ast.tokens[ast.mainToken(fmt_node)].start, "print format references argument index out of range", .{});
        try appendSpecializedRunPrintArg(ctx, &output, @intCast(args[selected_arg_index + 1]), diag);
        start = next_start;
    }
    if (start < fmt.len) try output.appendSlice(ctx.program.allocator, fmt[start..]);

    const key = try std.fmt.allocPrint(ctx.program.allocator, "{d}:{s}", .{ run_stmt, output.items });
    if (ctx.emitted_specialized_runs.contains(key)) {
        ctx.program.allocator.free(key);
        return true;
    }
    try ctx.emitted_specialized_runs.put(ctx.program.allocator, key, {});
    try ctx.owned_type_texts.append(ctx.program.allocator, key);
    std.debug.print("{s}", .{output.items});
    return true;
}

fn appendSpecializedRunPrintArg(ctx: *GenContext, output: *std.ArrayList(u8), arg_node: NodeIndex, diag: Diagnostic) anyerror!void {
    const ast = ctx.ast;
    switch (ast.tag(arg_node)) {
        .identifier => {
            const name = ast.tokenSlice(ast.mainToken(arg_node));
            if (ctx.polymorph_types.get(name)) |actual_type| {
                try output.appendSlice(ctx.program.allocator, displayTypeText(actual_type));
                return;
            }
        },
        .string_literal => {
            const decoded = try decodeString(ctx.program.allocator, ast.stringTokenContents(ast.mainToken(arg_node)), diag, ast.tokens[ast.mainToken(arg_node)].start);
            defer ctx.program.allocator.free(decoded);
            try output.appendSlice(ctx.program.allocator, decoded);
            return;
        },
        .integer_literal, .float_literal => {
            try output.appendSlice(ctx.program.allocator, ast.tokenSlice(ast.mainToken(arg_node)));
            return;
        },
        else => {},
    }
    return diag.failAt(ast.tokens[ast.mainToken(arg_node)].start, "unsupported specialized #run print argument", .{});
}

fn displayTypeText(raw: []const u8) []const u8 {
    const clean = std.mem.trim(u8, raw, " \t\r\n");
    const name = firstTypeWord(clean);
    if (std.mem.eql(u8, name, "float")) return "float32";
    return name;
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
        const arg_node: NodeIndex = @intCast(arg_nodes[selected_arg_index]);
        if (typeTextForExpr(ctx, arg_node, diag)) |arg_type| {
            if (try typeTextIsEmbeddedStruct(ctx, arg_type, diag)) {
                const arg_reg = try genCallArg(ctx, arg_node, diag);
                try emitFormattedValueForType(ctx, arg_reg, arg_type, arg_node, false, diag);
            } else if (staticArrayElementText(arg_type)) |elem_type| {
                const elem_name = firstTypeWord(elem_type);
                const count = try staticArrayCountFromText(ctx, arg_type, diag) orelse return diag.failAt(ast.tokens[ast.mainToken(arg_node)].start, "formatted static array output requires a known element count", .{});
                const arg_reg = try genCallArg(ctx, arg_node, diag);
                const opcode: Bytecode.Opcode = if (std.mem.eql(u8, elem_name, "int") or std.mem.eql(u8, elem_name, "s64"))
                    .format_static_int_array
                else if (std.mem.eql(u8, elem_name, "float") or std.mem.eql(u8, elem_name, "float64"))
                    .format_static_float_array
                else if (std.mem.eql(u8, elem_name, "string"))
                    .format_static_string_array
                else
                    return diag.failAt(ast.tokens[ast.mainToken(arg_node)].start, "formatted static array output does not support element type '{s}'", .{elem_type});
                try proc.instructions.append(program.allocator, .{ .opcode = opcode, .arg1 = arg_reg, .arg2 = @intCast(count), .source_node = arg_node });
            } else {
                const arg_reg = try genCallArg(ctx, arg_node, diag);
                try proc.instructions.append(program.allocator, .{ .opcode = .format_print, .arg1 = arg_reg, .source_node = arg_node });
            }
        } else {
            const arg_reg = try genCallArg(ctx, arg_node, diag);
            try proc.instructions.append(program.allocator, .{ .opcode = .format_print, .arg1 = arg_reg, .source_node = arg_node });
        }
        if (next_start + 1 < fmt.len and fmt[next_start] == ' ' and fmt[next_start + 1] == '\n') {
            start = next_start + 1;
        } else {
            start = next_start;
        }
    }
    if (start < fmt.len) try emitLiteralPrint(program, proc, fmt[start..], fmt_node);
    if (arg_index > arg_nodes.len) return diag.failAt(ast.tokens[ast.mainToken(fmt_node)].start, "print format consumed more arguments than provided", .{});
}

fn emitFormattedValueForType(ctx: *GenContext, value_reg: Bytecode.Register, raw_type: []const u8, source_node: NodeIndex, quote_strings: bool, diag: Diagnostic) anyerror!void {
    const clean_type = std.mem.trim(u8, raw_type, " \t\r\n");
    if (try typeTextIsEmbeddedStruct(ctx, clean_type, diag)) {
        try emitFormattedStructValue(ctx, value_reg, clean_type, source_node, diag);
        return;
    }
    if (std.mem.eql(u8, firstTypeWord(clean_type), "string") and quote_strings) {
        try emitLiteralPrint(ctx.program, ctx.proc, "\"", source_node);
        try ctx.proc.instructions.append(ctx.program.allocator, .{ .opcode = .format_print, .arg1 = value_reg, .source_node = source_node });
        try emitLiteralPrint(ctx.program, ctx.proc, "\"", source_node);
        return;
    }
    try ctx.proc.instructions.append(ctx.program.allocator, .{ .opcode = .format_print, .arg1 = value_reg, .source_node = source_node });
}

fn emitLoadFromAddressForType(ctx: *GenContext, addr: Bytecode.Register, raw_type: []const u8, source_node: NodeIndex, diag: Diagnostic) anyerror!Bytecode.Register {
    const clean_type = std.mem.trim(u8, raw_type, " \t\r\n");
    if (isDynamicArrayTypeText(clean_type) or isStaticArrayTypeText(clean_type) or try typeTextIsEmbeddedStruct(ctx, clean_type, diag)) return addr;
    const reg = ctx.proc.num_registers;
    ctx.proc.num_registers += 1;
    const opcode: Bytecode.Opcode = if (std.mem.eql(u8, firstTypeWord(clean_type), "string"))
        .load_ptr_string
    else if (std.mem.eql(u8, firstTypeWord(clean_type), "float") or std.mem.eql(u8, firstTypeWord(clean_type), "float32") or std.mem.eql(u8, firstTypeWord(clean_type), "float64"))
        .load_ptr_float
    else if ((try typeTextSize(ctx, clean_type, diag)) == 1)
        .load_ptr_byte
    else
        .load_ptr;
    try ctx.proc.instructions.append(ctx.program.allocator, .{ .opcode = opcode, .dest = reg, .arg1 = addr, .source_node = source_node });
    return reg;
}

fn emitFormattedStructValue(ctx: *GenContext, base_reg: Bytecode.Register, raw_type: []const u8, source_node: NodeIndex, diag: Diagnostic) anyerror!void {
    const type_name = firstTypeWord(stripPointerText(raw_type));
    const type_node = try structTypeNodeByName(ctx, type_name) orelse {
        if (ctx.type_context_parent) |parent| {
            try emitFormattedStructValue(parent, base_reg, raw_type, source_node, diag);
            return;
        }
        try ctx.proc.instructions.append(ctx.program.allocator, .{ .opcode = .format_print, .arg1 = base_reg, .source_node = source_node });
        return;
    };
    var restores = try bindContainerTypeArgs(ctx, raw_type, type_node);
    defer {
        restoreContainerTypeArgs(ctx, restores.items) catch {};
        restores.deinit(ctx.program.allocator);
    }
    const body = containerBodySource(ctx.ast, type_node) orelse {
        try ctx.proc.instructions.append(ctx.program.allocator, .{ .opcode = .format_print, .arg1 = base_reg, .source_node = source_node });
        return;
    };

    try emitLiteralPrint(ctx.program, ctx.proc, "{", source_node);
    var offset: u64 = 0;
    var printed_any = false;
    var fields = FieldSegmentIterator{ .source = body };
    while (fields.next()) |segment| {
        const parsed = parseFieldSegment(segment) orelse continue;
        const field_size = try typeTextSize(ctx, parsed.type_text, diag);
        const field_align = try typeTextAlign(ctx, parsed.type_text, diag);
        var split = std.mem.splitScalar(u8, parsed.names_text, ',');
        while (split.next()) |raw_name| {
            _ = lastWord(std.mem.trim(u8, raw_name, " \t\r\n"));
            offset = alignForward(offset, field_align);
            if (printed_any) try emitLiteralPrint(ctx.program, ctx.proc, ", ", source_node);
            printed_any = true;
            const field_addr = if (offset == 0) base_reg else blk: {
                const tmp = ctx.proc.num_registers;
                ctx.proc.num_registers += 1;
                try ctx.proc.instructions.append(ctx.program.allocator, .{ .opcode = .ptr_offset, .dest = tmp, .arg1 = base_reg, .arg2 = @intCast(offset), .source_node = source_node });
                break :blk tmp;
            };
            const field_value = try emitLoadFromAddressForType(ctx, field_addr, parsed.type_text, source_node, diag);
            try emitFormattedValueForType(ctx, field_value, parsed.type_text, source_node, true, diag);
            offset += field_size;
        }
    }
    try emitLiteralPrint(ctx.program, ctx.proc, "}", source_node);
}

fn builderSlotArg(ctx: *GenContext, arg: NodeIndex, diag: Diagnostic) !Bytecode.Register {
    const ast = ctx.ast;
    if (ast.tag(arg) == .unary_expr and ast.tokens[ast.mainToken(arg)].tag == .star) {
        return genAddressOfLvalue(ctx, ast.data(arg).lhs, diag);
    }
    return ctx.genExpr(arg, diag);
}

fn stringLiteralPayloadNode(ctx: *GenContext, node: NodeIndex) ?NodeIndex {
    const ast = ctx.ast;
    if (node == @import("Ast.zig").null_node) return null;
    if (ast.tag(node) == .string_literal) return node;
    if (ast.tag(node) != .identifier) return null;
    const name = ast.tokenSlice(ast.mainToken(node));
    if (ctx.resolved.lookup(name)) |sym| switch (sym) {
        .const_value => |value_node| {
            if (ast.tag(value_node) == .string_literal) return value_node;
            if (ast.tag(value_node) == .const_decl or ast.tag(value_node) == .var_decl) {
                const rhs = ast.data(value_node).rhs;
                if (rhs != @import("Ast.zig").null_node and ast.tag(rhs) == .string_literal) return rhs;
            }
        },
        else => {},
    };
    const decl = ctx.resolved.local_values.get(node) orelse return null;
    if (decl == @import("Ast.zig").null_node) return null;
    if (ast.tag(decl) == .string_literal) return decl;
    if (ast.tag(decl) == .const_decl or ast.tag(decl) == .var_decl) {
        const rhs = ast.data(decl).rhs;
        if (rhs != @import("Ast.zig").null_node and ast.tag(rhs) == .string_literal) return rhs;
    }
    return null;
}

fn emitFormattedBuilderAppend(ctx: *GenContext, builder_slot: Bytecode.Register, fmt_node: NodeIndex, arg_nodes: []const u32, diag: Diagnostic) anyerror!void {
    const ast = ctx.ast;
    const raw_fmt = ast.stringTokenContents(ast.mainToken(fmt_node));
    const fmt = try decodeString(ctx.program.allocator, raw_fmt, diag, ast.tokens[ast.mainToken(fmt_node)].start);
    defer ctx.program.allocator.free(fmt);
    var start: usize = 0;
    var arg_index: usize = 0;
    var i: usize = 0;
    while (i < fmt.len) : (i += 1) {
        if (fmt[i] != '%') continue;
        if (i > 0 and fmt[i - 1] == '\\') {
            if (start < i - 1) try emitLiteralBuilderAppend(ctx, builder_slot, fmt[start .. i - 1], fmt_node);
            try emitLiteralBuilderAppend(ctx, builder_slot, "%", fmt_node);
            start = i + 1;
            continue;
        }
        if (i + 1 < fmt.len and fmt[i + 1] == '%') {
            try emitLiteralBuilderAppend(ctx, builder_slot, fmt[start .. i + 1], fmt_node);
            i += 1;
            start = i + 1;
            continue;
        }
        if (start < i) try emitLiteralBuilderAppend(ctx, builder_slot, fmt[start..i], fmt_node);
        var selected_arg_index = arg_index;
        var next_start = i + 1;
        if (i + 1 < fmt.len and fmt[i + 1] >= '1' and fmt[i + 1] <= '9') {
            selected_arg_index = fmt[i + 1] - '1';
            next_start = i + 2;
        } else {
            arg_index += 1;
        }
        if (selected_arg_index >= arg_nodes.len) return diag.failAt(ast.tokens[ast.mainToken(fmt_node)].start, "format references argument index out of range", .{});
        const arg_node: NodeIndex = @intCast(arg_nodes[selected_arg_index]);
        const arg_reg = try genCallArg(ctx, arg_node, diag);
        try ctx.proc.instructions.append(ctx.program.allocator, .{ .opcode = .string_builder_append_string, .arg1 = builder_slot, .arg2 = arg_reg, .source_node = arg_node });
        if (next_start + 1 < fmt.len and fmt[next_start] == ' ' and fmt[next_start + 1] == '\n') {
            start = next_start + 1;
        } else {
            start = next_start;
        }
    }
    if (start < fmt.len) try emitLiteralBuilderAppend(ctx, builder_slot, fmt[start..], fmt_node);
}

fn emitLiteralBuilderAppend(ctx: *GenContext, builder_slot: Bytecode.Register, text: []const u8, source_node: NodeIndex) !void {
    if (text.len == 0) return;
    const text_reg = try ctx.emitString(source_node, text);
    try ctx.proc.instructions.append(ctx.program.allocator, .{ .opcode = .string_builder_append_string, .arg1 = builder_slot, .arg2 = text_reg, .source_node = source_node });
}

fn emitJoinAppend(ctx: *GenContext, builder_slot: Bytecode.Register, source_node: NodeIndex, raw_args: []const u32, diag: Diagnostic) !void {
    const ast = ctx.ast;
    var separator_node: NodeIndex = @import("Ast.zig").null_node;
    var before_first = false;
    var after_last = false;
    var saw_spread = false;
    var values = std.ArrayList(NodeIndex).empty;
    defer values.deinit(ctx.program.allocator);

    for (raw_args) |arg_idx| {
        const arg: NodeIndex = @intCast(arg_idx);
        if (ast.tag(arg) == .assign_stmt) {
            const lhs = ast.data(arg).lhs;
            const rhs = ast.data(arg).rhs;
            if (ast.tag(lhs) == .identifier and std.mem.eql(u8, ast.tokenSlice(ast.mainToken(lhs)), "separator")) {
                separator_node = rhs;
            } else if (ast.tag(lhs) == .identifier and std.mem.eql(u8, ast.tokenSlice(ast.mainToken(lhs)), "before_first")) {
                before_first = ast.tag(rhs) == .bool_literal and ast.data(rhs).lhs != 0;
            } else if (ast.tag(lhs) == .identifier and std.mem.eql(u8, ast.tokenSlice(ast.mainToken(lhs)), "after_last")) {
                after_last = ast.tag(rhs) == .bool_literal and ast.data(rhs).lhs != 0;
            } else {
                _ = try ctx.genExpr(rhs, diag);
            }
            continue;
        }
        if (ast.tag(arg) == .unary_expr and ast.tokens[ast.mainToken(arg)].tag == .dot_dot) {
            saw_spread = true;
            const operand = ast.data(arg).lhs;
            if (ast.tag(operand) == .aggregate_literal) {
                for (ast.extraSlice(ast.data(operand).lhs)[0..ast.data(operand).rhs]) |item| try values.append(ctx.program.allocator, @intCast(item));
            } else if (ast.tag(operand) == .typed_array_literal) {
                const payload = ast.extraSlice(ast.data(operand).lhs);
                const extra = payload[1];
                const count = payload[2];
                for (ast.extraSlice(extra)[0..count]) |item| try values.append(ctx.program.allocator, @intCast(item));
            } else {
                return diag.failAt(ast.tokens[ast.mainToken(arg)].start, "join spread currently requires a literal array", .{});
            }
            continue;
        }
        if (saw_spread and separator_node == @import("Ast.zig").null_node and values.items.len > 0 and ast.tag(arg) == .string_literal) {
            separator_node = arg;
        } else {
            try values.append(ctx.program.allocator, arg);
        }
    }
    const sep_reg: ?Bytecode.Register = if (separator_node != @import("Ast.zig").null_node) try ctx.genExpr(separator_node, diag) else null;
    if (before_first) {
        if (sep_reg) |reg| try ctx.proc.instructions.append(ctx.program.allocator, .{ .opcode = .string_builder_append_string, .arg1 = builder_slot, .arg2 = reg, .source_node = source_node });
    }
    for (values.items, 0..) |value_node, i| {
        if (i > 0) {
            if (sep_reg) |reg| try ctx.proc.instructions.append(ctx.program.allocator, .{ .opcode = .string_builder_append_string, .arg1 = builder_slot, .arg2 = reg, .source_node = value_node });
        }
        const value = try ctx.genExpr(value_node, diag);
        try ctx.proc.instructions.append(ctx.program.allocator, .{ .opcode = .string_builder_append_string, .arg1 = builder_slot, .arg2 = value, .source_node = value_node });
    }
    if (after_last) {
        if (sep_reg) |reg| try ctx.proc.instructions.append(ctx.program.allocator, .{ .opcode = .string_builder_append_string, .arg1 = builder_slot, .arg2 = reg, .source_node = source_node });
    }
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

test "compiler_write_file lowers to file write bytecode" {
    const lexer = @import("lexer.zig");
    const parser = @import("parser.zig");
    const resolve = @import("resolve.zig");
    const sema = @import("Sema.zig");

    const source = "#import \"Basic\";\nmain :: () {\n ok := compiler_write_file(\"out/tmp/write_probe.txt\", \"probe\\n\");\n if !ok exit(1);\n}\n";
    const diag = Diagnostic.init(std.testing.allocator, "write_probe.jai", source);

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
    var write_inst: ?Bytecode.Instruction = null;
    for (proc.instructions.items) |inst| {
        if (inst.opcode == .compiler_write_file) write_inst = inst;
    }
    const inst = write_inst orelse return error.MissingCompilerWriteFile;
    try std.testing.expect(inst.dest < proc.num_registers);
    try std.testing.expect(inst.arg1 < proc.num_registers);
    try std.testing.expect(inst.arg2 < proc.num_registers);
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
