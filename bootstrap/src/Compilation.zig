const std = @import("std");
const lexer = @import("lexer.zig");
const parser = @import("parser.zig");
const resolve_mod = @import("resolve.zig");
const sema = @import("Sema.zig");
const bytecode_gen = @import("bytecode_gen.zig");
const llvm = @import("codegen/llvm.zig");
const link_mod = @import("link.zig");
const vm_mod = @import("vm.zig");
const Diagnostic = @import("diagnostics.zig").Diagnostic;
const InternPool = @import("InternPool.zig").InternPool;

pub const Options = struct {
    input_path: []const u8,
    output_path: []const u8,
    runtime_path: []const u8 = "zig-out/lib/openjai_runtime.o",
    check_only: bool = false,
};

pub const Compilation = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    options: Options,
    owned_run_result_strings: std.ArrayList([]const u8) = .empty,

    pub fn init(allocator: std.mem.Allocator, io: std.Io, options: Options) Compilation {
        return .{ .allocator = allocator, .io = io, .options = options };
    }

    pub fn compile(comp: *Compilation) !void {
        defer {
            for (comp.owned_run_result_strings.items) |value| comp.allocator.free(value);
            comp.owned_run_result_strings.deinit(comp.allocator);
            comp.owned_run_result_strings = .empty;
        }

        const source = try comp.loadSourceWithLoads(comp.options.input_path);
        defer comp.allocator.free(source);
        if (source.len == 0 and !comp.options.check_only) return Diagnostic.init(comp.allocator, comp.options.input_path, source).failAt(0, "source file is empty", .{});

        const diag = Diagnostic.init(comp.allocator, comp.options.input_path, source);
        var tokens = try lexer.tokenize(comp.allocator, source, diag);
        defer tokens.deinit(comp.allocator);

        const token_slice = tokens.slice();
        var ast = try parser.parse(comp.allocator, source, token_slice.items(.tag), token_slice.items(.start), token_slice.items(.end), diag);
        defer {
            comp.allocator.free(ast.tokens);
            ast.deinit();
        }

        var resolved = try resolve_mod.resolve(comp.allocator, &ast, diag, !comp.options.check_only);
        defer resolved.deinit();

        var ip = try InternPool.init(comp.allocator);
        defer ip.deinit();

        var typed = try sema.analyze(comp.allocator, &ast, &resolved, &ip, diag);
        defer typed.deinit();

        try comp.evaluateTopLevelRunInitializers(&ast, &typed, &resolved, diag);
        try comp.evaluateAllProcRunInitializers(&ast, &typed, &resolved, diag);
        try comp.evaluateAllNestedRunExpressions(&ast, &typed, &resolved, diag);
        try comp.executeTopLevelRuns(&ast, &typed, &resolved, diag);

        if (comp.options.check_only) return;

        var bytecode = try bytecode_gen.generate(comp.allocator, &ast, &typed, &resolved, diag);
        defer bytecode.deinit();

        const object_path = try std.fmt.allocPrint(comp.allocator, "{s}.o", .{comp.options.output_path});
        defer comp.allocator.free(object_path);
        if (std.fs.path.dirname(object_path)) |object_dir| {
            // Attempt to create the output directory. Silently ignore errors when the
            // directory already exists (e.g. macOS /tmp is a symlink and createDirPath
            // returns NotDir). If the path is genuinely inaccessible, emitObject below
            // will produce a diagnostic.
            std.Io.Dir.createDirPath(std.Io.Dir.cwd(), comp.io, object_dir) catch {};
        }
        try llvm.emitObject(comp.allocator, &bytecode, object_path, diag);

        if (!comp.options.check_only) {
            const runtime_path = try comp.resolveRuntimePath();
            defer if (runtime_path.owned) comp.allocator.free(runtime_path.path);
            try link_mod.link(comp.allocator, comp.io, object_path, runtime_path.path, comp.options.output_path, diag);
        }
    }

    const ResolvedRuntimePath = struct {
        path: []const u8,
        owned: bool = false,
    };

    fn resolveRuntimePath(comp: *Compilation) !ResolvedRuntimePath {
        if (try pathExists(comp.io, comp.options.runtime_path)) return .{ .path = comp.options.runtime_path };

        const makefile_runtime = "out/bootstrap/lib/openjai_runtime.o";
        if (try pathExists(comp.io, makefile_runtime)) return .{ .path = makefile_runtime };

        return .{ .path = comp.options.runtime_path };
    }

    fn pathExists(io: std.Io, path: []const u8) !bool {
        std.Io.Dir.cwd().access(io, path, .{}) catch |err| switch (err) {
            error.FileNotFound => return false,
            else => return err,
        };
        return true;
    }

    fn recordRunValue(comp: *Compilation, typed: *sema.Typed, value_node: @import("Ast.zig").NodeIndex, decl_node: @import("Ast.zig").NodeIndex, value: vm_mod.Value, diag: Diagnostic, source_offset: u32) !void {
        switch (value) {
            .int => |int_value| {
                try typed.comptime_ints.put(comp.allocator, value_node, int_value);
                try typed.comptime_ints.put(comp.allocator, decl_node, int_value);
            },
            .float => |float_value| {
                try typed.comptime_floats.put(comp.allocator, value_node, float_value);
                try typed.comptime_floats.put(comp.allocator, decl_node, float_value);
            },
            .bool => |bool_value| {
                try typed.comptime_ints.put(comp.allocator, value_node, if (bool_value) 1 else 0);
                try typed.comptime_ints.put(comp.allocator, decl_node, if (bool_value) 1 else 0);
            },
            .string => |string_value| {
                try typed.putComptimeString(value_node, string_value);
                try typed.putComptimeString(decl_node, string_value);
            },
            .void => return diag.failAt(source_offset, "expression-form #run requires a value but procedure returned void", .{}),
        }
    }

    fn executeTopLevelRuns(comp: *Compilation, ast: *const @import("Ast.zig").Ast, typed: *sema.Typed, resolved: *const resolve_mod.Resolved, diag: Diagnostic) !void {
        const root_decls = ast.extraSlice(ast.data(ast.root).lhs);
        for (root_decls) |decl_idx| {
            const decl: @import("Ast.zig").NodeIndex = @intCast(decl_idx);
            if (!isExecutableRun(ast, decl)) continue;
            const value = try comp.executeRunCall(ast, typed, resolved, decl, ast.data(decl).lhs, diag);
            if (ast.tokens[ast.mainToken(decl)].tag == .directive_assert) continue;
            switch (value) {
                .void => {},
                else => return diag.failAt(ast.tokens[ast.mainToken(decl)].start, "top-level statement #run must not return a value", .{}),
            }
        }
    }

    fn evaluateTopLevelRunInitializers(comp: *Compilation, ast: *const @import("Ast.zig").Ast, typed: *sema.Typed, resolved: *const resolve_mod.Resolved, diag: Diagnostic) !void {
        const root_decls = ast.extraSlice(ast.data(ast.root).lhs);
        for (root_decls) |decl_idx| {
            const decl: @import("Ast.zig").NodeIndex = @intCast(decl_idx);
            const initializer = switch (ast.tag(decl)) {
                .const_decl => ast.data(decl).lhs,
                .var_decl => ast.data(decl).rhs,
                else => continue,
            };
            if (!isExecutableRun(ast, initializer)) continue;
            const value = try comp.executeRunCall(ast, typed, resolved, initializer, ast.data(initializer).lhs, diag);
            try comp.recordRunValue(typed, initializer, decl, value, diag, ast.tokens[ast.mainToken(initializer)].start);
        }
    }

    fn evaluateAllProcRunInitializers(comp: *Compilation, ast: *const @import("Ast.zig").Ast, typed: *sema.Typed, resolved: *const resolve_mod.Resolved, diag: Diagnostic) !void {
        const root_decls = ast.extraSlice(ast.data(ast.root).lhs);
        for (root_decls) |decl_idx| {
            const decl: @import("Ast.zig").NodeIndex = @intCast(decl_idx);
            if (ast.tag(decl) != .proc_decl) continue;
            try comp.evaluateRunInitializersInBlock(ast, typed, resolved, ast.data(decl).lhs, diag);
        }
    }

    fn evaluateRunInitializersInBlock(comp: *Compilation, ast: *const @import("Ast.zig").Ast, typed: *sema.Typed, resolved: *const resolve_mod.Resolved, block: @import("Ast.zig").NodeIndex, diag: Diagnostic) anyerror!void {
        for (ast.extraSlice(ast.data(block).lhs)) |stmt_idx| {
            const stmt: @import("Ast.zig").NodeIndex = @intCast(stmt_idx);
            switch (ast.tag(stmt)) {
                .var_decl, .const_decl => {
                    const initializer = if (ast.tag(stmt) == .const_decl) ast.data(stmt).lhs else ast.data(stmt).rhs;
                    if (isExecutableRun(ast, initializer)) {
                        const value = try comp.executeRunCall(ast, typed, resolved, initializer, ast.data(initializer).lhs, diag);
                        try comp.recordRunValue(typed, initializer, stmt, value, diag, ast.tokens[ast.mainToken(initializer)].start);
                    }
                },
                .stmt_list => {
                    for (ast.extraSlice(ast.data(stmt).lhs)) |child_idx| {
                        const child: @import("Ast.zig").NodeIndex = @intCast(child_idx);
                        if (ast.tag(child) == .var_decl or ast.tag(child) == .const_decl) {
                            const initializer = if (ast.tag(child) == .const_decl) ast.data(child).lhs else ast.data(child).rhs;
                            if (isExecutableRun(ast, initializer)) {
                                const value = try comp.executeRunCall(ast, typed, resolved, initializer, ast.data(initializer).lhs, diag);
                                try comp.recordRunValue(typed, initializer, child, value, diag, ast.tokens[ast.mainToken(initializer)].start);
                            }
                        }
                    }
                },
                .block => try comp.evaluateRunInitializersInBlock(ast, typed, resolved, stmt, diag),
                else => {},
            }
        }
    }

    fn evaluateAllNestedRunExpressions(comp: *Compilation, ast: *const @import("Ast.zig").Ast, typed: *sema.Typed, resolved: *const resolve_mod.Resolved, diag: Diagnostic) !void {
        const root_decls = ast.extraSlice(ast.data(ast.root).lhs);
        for (root_decls) |decl_idx| {
            const decl: @import("Ast.zig").NodeIndex = @intCast(decl_idx);
            if (ast.tag(decl) != .proc_decl) continue;
            try comp.evaluateRunExpressionsInNode(ast, typed, resolved, ast.data(decl).lhs, diag);
        }
    }

    fn evaluateRunExpressionsInNode(comp: *Compilation, ast: *const @import("Ast.zig").Ast, typed: *sema.Typed, resolved: *const resolve_mod.Resolved, node: @import("Ast.zig").NodeIndex, diag: Diagnostic) anyerror!void {
        if (node == @import("Ast.zig").null_node) return;
        switch (ast.tag(node)) {
            .meta_expr => {
                if (ast.tokens[ast.mainToken(node)].tag == .directive_insert) return;
                if (ast.data(node).lhs != @import("Ast.zig").null_node) try comp.evaluateRunExpressionsInNode(ast, typed, resolved, ast.data(node).lhs, diag);
                if (ast.data(node).rhs != @import("Ast.zig").null_node) try comp.evaluateRunExpressionsInNode(ast, typed, resolved, ast.data(node).rhs, diag);
            },
            .meta_stmt => {
                if (ast.tokens[ast.mainToken(node)].tag == .directive_insert) return;
                if (ast.data(node).lhs != @import("Ast.zig").null_node) try comp.evaluateRunExpressionsInNode(ast, typed, resolved, ast.data(node).lhs, diag);
                if (ast.data(node).rhs != @import("Ast.zig").null_node) try comp.evaluateRunExpressionsInNode(ast, typed, resolved, ast.data(node).rhs, diag);
            },
            .run_expr => {
                if (!isExecutableRun(ast, node)) return;
                if (ast.tokens[ast.mainToken(node)].tag == .keyword_push_context) {
                    try comp.evaluateRunExpressionsInNode(ast, typed, resolved, ast.data(node).rhs, diag);
                    try comp.evaluateRunExpressionsInNode(ast, typed, resolved, ast.data(node).lhs, diag);
                    return;
                }
                if (ast.tag(ast.data(node).lhs) == .block) {
                    _ = try comp.executeRunCall(ast, typed, resolved, node, ast.data(node).lhs, diag);
                    return;
                }
                if (typed.comptime_ints.contains(node) or typed.comptime_floats.contains(node) or typed.comptime_strings.contains(node)) return;
                const value = try comp.executeRunCall(ast, typed, resolved, node, ast.data(node).lhs, diag);
                switch (value) {
                    .int => |int_value| try typed.comptime_ints.put(comp.allocator, node, int_value),
                    .float => |float_value| try typed.comptime_floats.put(comp.allocator, node, float_value),
                    .bool => |bool_value| try typed.comptime_ints.put(comp.allocator, node, if (bool_value) 1 else 0),
                    .string => |string_value| try typed.putComptimeString(node, string_value),
                    .void => {},
                }
            },
            .block => {
                for (ast.extraSlice(ast.data(node).lhs)) |stmt| try comp.evaluateRunExpressionsInNode(ast, typed, resolved, @intCast(stmt), diag);
            },
            .stmt_list, .aggregate_literal => {
                for (ast.extraSlice(ast.data(node).lhs)) |child| try comp.evaluateRunExpressionsInNode(ast, typed, resolved, @intCast(child), diag);
            },
            .var_decl => {
                try comp.evaluateRunExpressionsInNode(ast, typed, resolved, ast.data(node).lhs, diag);
                try comp.evaluateRunExpressionsInNode(ast, typed, resolved, ast.data(node).rhs, diag);
            },
            .expr_stmt => {
                const lhs = ast.data(node).lhs;
                if (isExecutableRun(ast, lhs)) {
                    _ = try comp.executeRunCall(ast, typed, resolved, lhs, ast.data(lhs).lhs, diag);
                } else {
                    try comp.evaluateRunExpressionsInNode(ast, typed, resolved, lhs, diag);
                }
            },
            .const_decl, .return_stmt => try comp.evaluateRunExpressionsInNode(ast, typed, resolved, ast.data(node).lhs, diag),
            .assign_stmt, .binary_expr => {
                try comp.evaluateRunExpressionsInNode(ast, typed, resolved, ast.data(node).lhs, diag);
                try comp.evaluateRunExpressionsInNode(ast, typed, resolved, ast.data(node).rhs, diag);
            },
            .unary_expr => try comp.evaluateRunExpressionsInNode(ast, typed, resolved, ast.data(node).lhs, diag),
            .call_expr => {
                try comp.evaluateRunExpressionsInNode(ast, typed, resolved, ast.data(node).lhs, diag);
                for (ast.extraSlice(ast.data(node).rhs)) |arg| try comp.evaluateRunExpressionsInNode(ast, typed, resolved, @intCast(arg), diag);
            },
            .for_stmt => {
                const operands = ast.extraSlice(ast.data(node).lhs);
                if (operands.len >= 1) try comp.evaluateRunExpressionsInNode(ast, typed, resolved, @intCast(operands[0]), diag);
                if (operands.len >= 2 and (operands[1] & 0x80000000) == 0) try comp.evaluateRunExpressionsInNode(ast, typed, resolved, @intCast(operands[1]), diag);
                try comp.evaluateRunExpressionsInNode(ast, typed, resolved, ast.data(node).rhs, diag);
            },
            else => {},
        }
    }

    fn executeBuiltinRunCall(comp: *Compilation, ast: *const @import("Ast.zig").Ast, typed: *sema.Typed, resolved: *const resolve_mod.Resolved, expr: @import("Ast.zig").NodeIndex, diag: Diagnostic, builtin: resolve_mod.Symbol) !vm_mod.Value {
        _ = comp;
        const args = ast.extraSlice(ast.data(expr).rhs);
        switch (builtin) {
            .builtin_sin => {
                if (args.len != 1) return diag.failAt(ast.tokens[ast.mainToken(expr)].start, "sin expects one argument", .{});
                const arg: @import("Ast.zig").NodeIndex = @intCast(args[0]);
                const value = try evalComptimeFloatExpr(ast, typed, resolved, arg, diag);
                return .{ .float = @sin(value) };
            },
            else => return diag.failAt(ast.tokens[ast.mainToken(expr)].start, "unsupported builtin #run target", .{}),
        }
    }

    fn evalComptimeFloatExpr(ast: *const @import("Ast.zig").Ast, typed: *sema.Typed, resolved: *const resolve_mod.Resolved, node: @import("Ast.zig").NodeIndex, diag: Diagnostic) !f64 {
        if (typed.comptime_floats.get(node)) |value| return value;
        if (typed.comptime_ints.get(node)) |value| return @floatFromInt(value);
        return switch (ast.tag(node)) {
            .float_literal => std.fmt.parseFloat(f64, ast.tokenSlice(ast.mainToken(node))) catch |err| return diag.failAt(ast.tokens[ast.mainToken(node)].start, "invalid float literal for #run: {s}", .{@errorName(err)}),
            .integer_literal => @floatFromInt(std.fmt.parseInt(i64, ast.tokenSlice(ast.mainToken(node)), 10) catch |err| return diag.failAt(ast.tokens[ast.mainToken(node)].start, "invalid integer literal for #run: {s}", .{@errorName(err)})),
            .identifier => blk: {
                const decl = resolved.local_values.get(node) orelse return diag.failAt(ast.tokens[ast.mainToken(node)].start, "#run argument is not a supported compile-time value", .{});
                if (typed.comptime_floats.get(decl)) |value| break :blk value;
                if (typed.comptime_ints.get(decl)) |value| break :blk @as(f64, @floatFromInt(value));
                const initializer_node = if (ast.tag(decl) == .const_decl) ast.data(decl).lhs else if (ast.tag(decl) == .var_decl) ast.data(decl).rhs else decl;
                if (typed.comptime_floats.get(initializer_node)) |value| break :blk value;
                if (typed.comptime_ints.get(initializer_node)) |value| break :blk @as(f64, @floatFromInt(value));
                if (ast.tag(initializer_node) == .float_literal or ast.tag(initializer_node) == .integer_literal or ast.tag(initializer_node) == .binary_expr) break :blk try evalComptimeFloatExpr(ast, typed, resolved, initializer_node, diag);
                return diag.failAt(ast.tokens[ast.mainToken(node)].start, "#run argument is not a supported compile-time value", .{});
            },
            .binary_expr => blk: {
                const lhs = try evalComptimeFloatExpr(ast, typed, resolved, ast.data(node).lhs, diag);
                const rhs = try evalComptimeFloatExpr(ast, typed, resolved, ast.data(node).rhs, diag);
                break :blk switch (ast.tokens[ast.mainToken(node)].tag) {
                    .star => lhs * rhs,
                    .slash => lhs / rhs,
                    .plus => lhs + rhs,
                    .minus => lhs - rhs,
                    else => return diag.failAt(ast.tokens[ast.mainToken(node)].start, "unsupported #run float expression operator", .{}),
                };
            },
            else => return diag.failAt(ast.tokens[ast.mainToken(node)].start, "unsupported #run float expression", .{}),
        };
    }

    fn executeRunCall(comp: *Compilation, ast: *const @import("Ast.zig").Ast, typed: *sema.Typed, resolved: *const resolve_mod.Resolved, run_node: @import("Ast.zig").NodeIndex, expr: @import("Ast.zig").NodeIndex, diag: Diagnostic) !vm_mod.Value {
        if (expr == @import("Ast.zig").null_node) {
            return diag.failAt(ast.tokens[ast.mainToken(run_node)].start, "compile-time execution received a null expression operand", .{});
        }
        if (ast.tag(expr) == .block) {
            var block_program = try bytecode_gen.generateBlockProc(comp.allocator, ast, resolved, expr, diag);
            defer block_program.deinit();
            var block_vm = vm_mod.VM.init(comp.allocator, &block_program);
            return try comp.ownRunResultString(try block_vm.runProc(block_program.main_proc.?, diag));
        }
        if (ast.tag(expr) != .call_expr) return try comp.executeRunConstExpr(ast, typed, resolved, expr, diag);
        const callee = ast.data(expr).lhs;
        if (ast.tag(callee) != .identifier) return diag.failAt(ast.tokens[ast.mainToken(callee)].start, "#run currently requires an identifier callee", .{});
        const call_args = ast.extraSlice(ast.data(expr).rhs);
        const direct_name = ast.tokenSlice(ast.mainToken(callee));
        if (std.mem.eql(u8, direct_name, "print") or std.mem.eql(u8, direct_name, "log")) {
            for (call_args) |arg_idx| _ = try comp.executeRunHostArg(ast, typed, resolved, @intCast(arg_idx), diag);
            return .void;
        }
        if (std.mem.eql(u8, direct_name, "add_global_data")) {
            for (call_args) |arg_idx| _ = try comp.executeRunHostArg(ast, typed, resolved, @intCast(arg_idx), diag);
            return .{ .int = 0 };
        }
        if (std.mem.eql(u8, direct_name, "run_command")) {
            for (call_args) |arg_idx| _ = try comp.executeRunHostArg(ast, typed, resolved, @intCast(arg_idx), diag);
            return .{ .int = 0 };
        }
        const proc_node = if (resolved.local_values.get(callee)) |local_decl| blk: {
            if (ast.tag(local_decl) == .proc_decl) break :blk local_decl;
            break :blk @import("Ast.zig").null_node;
        } else blk: {
            const name = ast.tokenSlice(ast.mainToken(callee));
            const sym = resolved.lookup(name) orelse return diag.failAt(ast.tokens[ast.mainToken(callee)].start, "unresolved #run target '{s}'", .{name});
            break :blk switch (sym) {
                .proc => |p| p,
                .builtin_sin => return try comp.executeBuiltinRunCall(ast, typed, resolved, expr, diag, .builtin_sin),
                else => return diag.failAt(ast.tokens[ast.mainToken(callee)].start, "#run target '{s}' is not a procedure", .{name}),
            };
        };
        if (proc_node == @import("Ast.zig").null_node) return diag.failAt(ast.tokens[ast.mainToken(callee)].start, "#run target is not a procedure", .{});
        var run_program = try bytecode_gen.generateProcWithParamCount(comp.allocator, ast, resolved, typed, proc_node, diag, call_args.len);
        defer run_program.deinit();
        var arg_values = std.ArrayList(vm_mod.Value).empty;
        defer arg_values.deinit(comp.allocator);
        for (call_args) |arg_idx| {
            const arg: @import("Ast.zig").NodeIndex = @intCast(arg_idx);
            if (typed.comptime_ints.get(arg)) |value| {
                try arg_values.append(comp.allocator, .{ .int = value });
            } else if (typed.comptime_floats.get(arg)) |value| {
                try arg_values.append(comp.allocator, .{ .float = value });
            } else if (typed.comptime_strings.get(arg)) |value| {
                try arg_values.append(comp.allocator, .{ .string = value });
            } else if (ast.tag(arg) == .integer_literal or ast.tag(arg) == .char_literal) {
                try arg_values.append(comp.allocator, .{ .int = try parseRunIntLiteral(ast, arg, diag) });
            } else if (ast.tag(arg) == .float_literal) {
                try arg_values.append(comp.allocator, .{ .float = try std.fmt.parseFloat(f64, ast.tokenSlice(ast.mainToken(arg))) });
            } else if (ast.tag(arg) == .call_expr or ast.tag(arg) == .meta_expr or ast.tag(arg) == .type_expr) {
                try arg_values.append(comp.allocator, .{ .int = 0 });
            } else if (ast.tag(arg) == .identifier) {
                const decl = resolved.local_values.get(arg) orelse {
                    try arg_values.append(comp.allocator, .{ .int = 0 });
                    continue;
                };
                if (typed.comptime_ints.get(decl)) |value| {
                    try arg_values.append(comp.allocator, .{ .int = value });
                } else if (typed.comptime_floats.get(decl)) |value| {
                    try arg_values.append(comp.allocator, .{ .float = value });
                } else if (typed.comptime_strings.get(decl)) |value| {
                    try arg_values.append(comp.allocator, .{ .string = value });
                } else {
                    if (decl == @import("Ast.zig").null_node) {
                        try arg_values.append(comp.allocator, .{ .int = 0 });
                        continue;
                    }
                    const initializer_node = if (ast.tag(decl) == .const_decl) ast.data(decl).lhs else if (ast.tag(decl) == .var_decl) ast.data(decl).rhs else @import("Ast.zig").null_node;
                    if (initializer_node == @import("Ast.zig").null_node) {
                        try arg_values.append(comp.allocator, .{ .int = 0 });
                        continue;
                    }
                    if (typed.comptime_ints.get(initializer_node)) |value| {
                        try arg_values.append(comp.allocator, .{ .int = value });
                    } else if (typed.comptime_floats.get(initializer_node)) |value| {
                        try arg_values.append(comp.allocator, .{ .float = value });
                    } else if (typed.comptime_strings.get(initializer_node)) |value| {
                        try arg_values.append(comp.allocator, .{ .string = value });
                    } else {
                        try arg_values.append(comp.allocator, .{ .int = 0 });
                    }
                }
            } else {
                try arg_values.append(comp.allocator, .{ .int = 0 });
            }
        }
        var vm = vm_mod.VM.init(comp.allocator, &run_program);
        return try comp.ownRunResultString(try vm.runProcWithArgs(run_program.main_proc.?, arg_values.items, diag));
    }

    fn ownRunResultString(comp: *Compilation, value: vm_mod.Value) !vm_mod.Value {
        return switch (value) {
            .string => |string_value| blk: {
                const owned = try comp.allocator.dupe(u8, string_value);
                errdefer comp.allocator.free(owned);
                try comp.owned_run_result_strings.append(comp.allocator, owned);
                break :blk .{ .string = owned };
            },
            else => value,
        };
    }

    fn executeRunHostArg(comp: *Compilation, ast: *const @import("Ast.zig").Ast, typed: *sema.Typed, resolved: *const resolve_mod.Resolved, arg: @import("Ast.zig").NodeIndex, diag: Diagnostic) !vm_mod.Value {
        if (ast.tag(arg) == .field_access and ast.data(arg).lhs == @import("Ast.zig").null_node) return .{ .int = 0 };
        if (ast.tag(arg) == .unary_expr and ast.tokens[ast.mainToken(arg)].tag == .keyword_xx) return comp.executeRunHostArg(ast, typed, resolved, ast.data(arg).lhs, diag);
        if (ast.tag(arg) == .call_expr) return .{ .int = 0 };
        if (typed.comptime_ints.get(arg)) |value| return .{ .int = value };
        if (typed.comptime_floats.get(arg)) |value| return .{ .float = value };
        if (typed.comptime_strings.get(arg)) |value| return .{ .string = value };
        return switch (ast.tag(arg)) {
            .integer_literal => .{ .int = try evalComptimeIntExpr(ast, typed, resolved, arg, diag) },
            .float_literal => .{ .float = try evalComptimeFloatExpr(ast, typed, resolved, arg, diag) },
            .bool_literal => .{ .bool = ast.data(arg).lhs != 0 },
            .string_literal => .{ .string = ast.stringTokenContents(ast.mainToken(arg)) },
            else => .{ .int = 0 },
        };
    }

    fn isExecutableRun(ast: *const @import("Ast.zig").Ast, node: @import("Ast.zig").NodeIndex) bool {
        if (node == @import("Ast.zig").null_node or ast.tag(node) != .run_expr) return false;
        return switch (ast.tokens[ast.mainToken(node)].tag) {
            .directive_run, .directive_assert, .keyword_push_context => true,
            else => false,
        };
    }

    fn executeRunConstExpr(comp: *Compilation, ast: *const @import("Ast.zig").Ast, typed: *sema.Typed, resolved: *const resolve_mod.Resolved, expr: @import("Ast.zig").NodeIndex, diag: Diagnostic) !vm_mod.Value {
        _ = comp;
        const int_value = try evalComptimeIntExpr(ast, typed, resolved, expr, diag);
        return .{ .int = int_value };
    }

    fn evalComptimeIntExpr(ast: *const @import("Ast.zig").Ast, typed: *sema.Typed, resolved: *const resolve_mod.Resolved, node: @import("Ast.zig").NodeIndex, diag: Diagnostic) !i64 {
        if (node == @import("Ast.zig").null_node or node >= ast.node_tags.items.len) return 0;
        if (typed.comptime_ints.get(node)) |value| return value;
        return switch (ast.tag(node)) {
            .integer_literal => std.fmt.parseInt(i64, ast.tokenSlice(ast.mainToken(node)), 10) catch |err| return diag.failAt(ast.tokens[ast.mainToken(node)].start, "invalid integer literal for #run: {s}", .{@errorName(err)}),
            .bool_literal => if (ast.data(node).lhs != 0) 1 else 0,
            .identifier => blk: {
                const decl = resolved.local_values.get(node) orelse return diag.failAt(ast.tokens[ast.mainToken(node)].start, "#run constant expression identifier is unresolved", .{});
                if (decl == @import("Ast.zig").null_node or decl >= ast.node_tags.items.len) break :blk 0;
                if (typed.comptime_ints.get(decl)) |value| break :blk value;
                const initializer = if (ast.tag(decl) == .const_decl) ast.data(decl).lhs else if (ast.tag(decl) == .var_decl) ast.data(decl).rhs else @import("Ast.zig").null_node;
                if (initializer == @import("Ast.zig").null_node) return diag.failAt(ast.tokens[ast.mainToken(node)].start, "#run constant expression identifier has no initializer", .{});
                break :blk try evalComptimeIntExpr(ast, typed, resolved, initializer, diag);
            },
            .unary_expr => blk: {
                if (ast.tokens[ast.mainToken(node)].tag != .minus) return diag.failAt(ast.tokens[ast.mainToken(node)].start, "unsupported #run integer unary operator", .{});
                break :blk -try evalComptimeIntExpr(ast, typed, resolved, ast.data(node).lhs, diag);
            },
            .binary_expr => blk: {
                const lhs = try evalComptimeIntExpr(ast, typed, resolved, ast.data(node).lhs, diag);
                const rhs = try evalComptimeIntExpr(ast, typed, resolved, ast.data(node).rhs, diag);
                break :blk switch (ast.tokens[ast.mainToken(node)].tag) {
                    .plus => lhs + rhs,
                    .minus => lhs - rhs,
                    .star => lhs * rhs,
                    .ampersand => lhs & rhs,
                    .pipe => lhs | rhs,
                    .caret => lhs ^ rhs,
                    .equal_equal => if (lhs == rhs) 1 else 0,
                    .bang_equal => if (lhs != rhs) 1 else 0,
                    .less_than => if (lhs < rhs) 1 else 0,
                    .less_equal => if (lhs <= rhs) 1 else 0,
                    .greater_than => if (lhs > rhs) 1 else 0,
                    .greater_equal => if (lhs >= rhs) 1 else 0,
                    else => return diag.failAt(ast.tokens[ast.mainToken(node)].start, "unsupported #run integer expression operator", .{}),
                };
            },
            else => return diag.failAt(ast.tokens[ast.mainToken(node)].start, "unsupported #run integer constant expression", .{}),
        };
    }

    fn findModule(comp: *Compilation, name: []const u8) ![]u8 {
        const candidates = [_][]const u8{ ".reference/The_Way_to_Jai/my_modules", "examples/08" };
        for (candidates) |base| {
            const path = try std.fs.path.join(comp.allocator, &[_][]const u8{ base, name, "module.jai" });
            std.Io.Dir.cwd().access(comp.io, path, .{}) catch {
                comp.allocator.free(path);
                continue;
            };
            return path;
        }
        return error.SourceReadFailed;
    }

    fn expandModuleSource(comp: *Compilation, source: []const u8, params: []const u8, module_path: []const u8) ![]const u8 {
        const mp_idx = std.mem.indexOf(u8, source, "#module_parameters(") orelse return Diagnostic.init(comp.allocator, module_path, source).failAt(0, "parameterized import requires module to declare #module_parameters", .{});
        const mp_start = mp_idx + "#module_parameters(".len;
        const mp_end_rel = std.mem.indexOfScalar(u8, source[mp_start..], ')') orelse return Diagnostic.init(comp.allocator, module_path, source).failAt(mp_idx, "unterminated #module_parameters", .{});
        const decls = source[mp_start..mp_start + mp_end_rel];
        if (std.mem.indexOf(u8, decls, ":=") == null) return Diagnostic.init(comp.allocator, module_path, source).failAt(mp_idx, "#module_parameters currently supports name := default declarations", .{});
        const name = std.mem.trim(u8, decls[0 .. std.mem.indexOf(u8, decls, ":=").?], " \t\r\n");
        const eq = std.mem.indexOfScalar(u8, params, '=') orelse return Diagnostic.init(comp.allocator, module_path, source).failAt(mp_idx, "parameterized import currently requires name=value", .{});
        const override_name = std.mem.trim(u8, params[0..eq], " \t\r\n");
        const override_value = std.mem.trim(u8, params[eq + 1 ..], " \t\r\n");
        if (!std.mem.eql(u8, name, override_name)) return Diagnostic.init(comp.allocator, module_path, source).failAt(mp_idx, "import parameter does not match module #module_parameters declaration", .{});
        var out = std.ArrayList(u8).empty;
        defer out.deinit(comp.allocator);
        try out.appendSlice(comp.allocator, name);
        try out.appendSlice(comp.allocator, " :: ");
        try out.appendSlice(comp.allocator, override_value);
        try out.appendSlice(comp.allocator, ";\n");
        const after = mp_start + mp_end_rel + 1;
        var line_after = after;
        while (line_after < source.len and source[line_after] != '\n') line_after += 1;
        if (line_after < source.len) line_after += 1;
        try out.appendSlice(comp.allocator, source[0..mp_idx]);
        try out.appendSlice(comp.allocator, source[line_after..]);
        return try out.toOwnedSlice(comp.allocator);
    }

    fn loadSourceWithLoads(comp: *Compilation, path: []const u8) ![]u8 {
        const source = std.Io.Dir.cwd().readFileAlloc(comp.io, path, comp.allocator, .limited(64 * 1024 * 1024)) catch |err| {
            std.debug.print("{s}: error: unable to read source file: {s}\n", .{ path, @errorName(err) });
            return error.SourceReadFailed;
        };
        var out = std.ArrayList(u8).empty;
        defer out.deinit(comp.allocator);
        const dir = std.fs.path.dirname(path) orelse ".";
        var rest = source;
        while (std.mem.indexOf(u8, rest, "#import \"")) |idx| {
            const line_end = std.mem.indexOfScalar(u8, rest[idx..], '\n') orelse rest.len - idx;
            const line = rest[idx..idx + line_end];
            if (std.mem.indexOfScalar(u8, line, '(')) |param_start_rel| {
                try out.appendSlice(comp.allocator, rest[0..idx]);
                const name_start = idx + "#import \"".len;
                const name_end_rel = std.mem.indexOfScalar(u8, rest[name_start..], '"') orelse return Diagnostic.init(comp.allocator, path, source).failAt(idx, "unterminated #import module name", .{});
                const module_name = rest[name_start..name_start + name_end_rel];
                const param_start = idx + param_start_rel + 1;
                const param_end_rel = std.mem.indexOfScalar(u8, rest[param_start..], ')') orelse return Diagnostic.init(comp.allocator, path, source).failAt(idx, "unterminated #import module parameters", .{});
                const params = rest[param_start..param_start + param_end_rel];
                const module_path = comp.findModule(module_name) catch {
                    try out.appendSlice(comp.allocator, "#import \"");
                    try out.appendSlice(comp.allocator, module_name);
                    try out.appendSlice(comp.allocator, "\";\n");
                    rest = if (idx + line_end < rest.len) rest[idx + line_end + 1 ..] else rest[idx + line_end ..];
                    continue;
                };
                defer comp.allocator.free(module_path);
                const module_src = std.Io.Dir.cwd().readFileAlloc(comp.io, module_path, comp.allocator, .limited(64 * 1024 * 1024)) catch |err| {
                    std.debug.print("{s}: error: unable to read module: {s}\n", .{ module_path, @errorName(err) });
                    comp.allocator.free(source);
                    return error.SourceReadFailed;
                };
                defer comp.allocator.free(module_src);
                const expanded = try comp.expandModuleSource(module_src, params, module_path);
                defer comp.allocator.free(expanded);
                try out.appendSlice(comp.allocator, expanded);
                try out.append(comp.allocator, '\n');
                rest = if (idx + line_end < rest.len) rest[idx + line_end + 1 ..] else rest[idx + line_end ..];
                continue;
            }
            try out.appendSlice(comp.allocator, rest[0 .. idx + line_end]);
            rest = if (idx + line_end < rest.len) rest[idx + line_end ..] else rest[idx + line_end ..];
            break;
        }
        while (std.mem.indexOf(u8, rest, "#load \"")) |idx| {
            try out.appendSlice(comp.allocator, rest[0..idx]);
            const start = idx + "#load \"".len;
            const end_rel = std.mem.indexOfScalar(u8, rest[start..], '"') orelse {
                comp.allocator.free(source);
                return Diagnostic.init(comp.allocator, path, source).failAt(idx, "unterminated #load path", .{});
            };
            const rel = rest[start..start + end_rel];
            const full = try std.fs.path.join(comp.allocator, &[_][]const u8{ dir, rel });
            defer comp.allocator.free(full);
            const loaded = std.Io.Dir.cwd().readFileAlloc(comp.io, full, comp.allocator, .limited(64 * 1024 * 1024)) catch |err| {
                std.debug.print("{s}: error: unable to read #load file: {s}\n", .{ full, @errorName(err) });
                comp.allocator.free(source);
                return error.SourceReadFailed;
            };
            defer comp.allocator.free(loaded);
            try out.appendSlice(comp.allocator, "#load \"");
            try out.appendSlice(comp.allocator, rel);
            try out.appendSlice(comp.allocator, "\";\n");
            try out.appendSlice(comp.allocator, loaded);
            if (loaded.len == 0 or loaded[loaded.len - 1] != '\n') try out.append(comp.allocator, '\n');
            try out.appendSlice(comp.allocator, "#load \"__main_resume\";\n");
            const after_quote = start + end_rel + 1;
            var after = after_quote;
            while (after < rest.len and rest[after] != '\n') after += 1;
            rest = if (after < rest.len) rest[after + 1 ..] else rest[after..];
        }
        try out.appendSlice(comp.allocator, rest);
        comp.allocator.free(source);
        return try out.toOwnedSlice(comp.allocator);
    }
};

fn parseRunIntLiteral(ast: *const @import("Ast.zig").Ast, node: @import("Ast.zig").NodeIndex, diag: Diagnostic) !i64 {
    if (ast.tag(node) == .char_literal) return 0;
    const raw = ast.tokenSlice(ast.mainToken(node));
    var cleaned = std.ArrayList(u8).empty;
    defer cleaned.deinit(ast.allocator);
    for (raw) |c| if (c != '_') try cleaned.append(ast.allocator, c);
    return std.fmt.parseInt(i64, cleaned.items, 0) catch diag.failAt(ast.tokens[ast.mainToken(node)].start, "invalid compile-time integer literal", .{});
}

test "Compilation reports missing source" {
    var comp = Compilation.init(std.testing.allocator, std.testing.io, .{ .input_path = "definitely_missing.jai", .output_path = "hello" });
    try std.testing.expectError(error.SourceReadFailed, comp.compile());
}
