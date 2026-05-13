const std = @import("std");
const lexer = @import("lexer.zig");
const parser = @import("parser.zig");
const resolve_mod = @import("resolve.zig");
const sema = @import("Sema.zig");
const bytecode_gen = @import("bytecode_gen.zig");
const Bytecode = @import("Bytecode.zig");
const llvm = @import("codegen/llvm.zig");
const link_mod = @import("link.zig");
const vm_mod = @import("vm.zig");
const Diagnostic = @import("diagnostics.zig").Diagnostic;
const InternPool = @import("InternPool.zig").InternPool;
const Tag = @import("Token.zig").Tag;
const using_param_sentinel: u32 = 0xfffffffe;

pub const Options = struct {
    input_path: []const u8,
    output_path: []const u8,
    runtime_path: []const u8 = "zig-out/lib/openjai_runtime.manifest",
    check_only: bool = false,
    command_line: []const []const u8 = &.{},
};

pub const Compilation = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    options: Options,
    owned_run_result_strings: std.ArrayList([]const u8) = .empty,
    owned_run_result_bytes: std.ArrayList([]const u8) = .empty,
    pending_current_workspace_sources: std.ArrayList([]const u8) = .empty,
    workspace_sources: std.ArrayList(vm_mod.WorkspaceSourceSnapshot) = .empty,
    workspace_build_options: std.AutoHashMapUnmanaged(i64, vm_mod.BuildOptionsSnapshot) = .empty,
    loaded_module_paths: std.StringHashMapUnmanaged(void) = .empty,
    next_workspace_id: i64 = 3,

    pub fn init(allocator: std.mem.Allocator, io: std.Io, options: Options) Compilation {
        return .{ .allocator = allocator, .io = io, .options = options };
    }

    fn sourceBaseDir(comp: *Compilation) []const u8 {
        return std.fs.path.dirname(comp.options.input_path) orelse ".";
    }

    fn clearPendingCurrentWorkspaceSources(comp: *Compilation) void {
        for (comp.pending_current_workspace_sources.items) |value| comp.allocator.free(value);
        comp.pending_current_workspace_sources.clearRetainingCapacity();
    }

    fn clearWorkspaceBuildState(comp: *Compilation) void {
        for (comp.workspace_sources.items) |source| vm_mod.VM.freeWorkspaceSourceSnapshot(comp.allocator, source);
        comp.workspace_sources.clearRetainingCapacity();
        var it = comp.workspace_build_options.iterator();
        while (it.next()) |entry| vm_mod.VM.freeBuildOptionsSnapshot(comp.allocator, entry.value_ptr.*);
        comp.workspace_build_options.clearRetainingCapacity();
    }

    fn clearLoadedModules(comp: *Compilation) void {
        var it = comp.loaded_module_paths.keyIterator();
        while (it.next()) |key| comp.allocator.free(key.*);
        comp.loaded_module_paths.clearRetainingCapacity();
    }

    fn captureVMWorkspaceState(comp: *Compilation, vm: *vm_mod.VM) !void {
        try vm.exportWorkspaceBuildState(comp.allocator, &comp.workspace_sources, &comp.workspace_build_options);
    }

    fn hasAppliedCurrentWorkspaceSource(applied: []const []const u8, source: []const u8) bool {
        for (applied) |existing| {
            if (std.mem.eql(u8, existing, source)) return true;
        }
        return false;
    }

    fn applyPendingCurrentWorkspaceSources(comp: *Compilation, source: *[]u8, applied: *std.ArrayList([]const u8)) !bool {
        defer comp.clearPendingCurrentWorkspaceSources();

        var new_sources = std.ArrayList([]const u8).empty;
        defer new_sources.deinit(comp.allocator);

        for (comp.pending_current_workspace_sources.items) |pending| {
            if (hasAppliedCurrentWorkspaceSource(applied.items, pending)) continue;
            try new_sources.append(comp.allocator, pending);
            const owned = try comp.allocator.dupe(u8, pending);
            applied.append(comp.allocator, owned) catch |err| {
                comp.allocator.free(owned);
                return err;
            };
        }
        if (new_sources.items.len == 0) return false;

        var out = std.ArrayList(u8).empty;
        errdefer out.deinit(comp.allocator);
        try out.appendSlice(comp.allocator, source.*);
        if (out.items.len != 0 and out.items[out.items.len - 1] != '\n') try out.append(comp.allocator, '\n');
        for (new_sources.items) |generated_source| {
            try out.appendSlice(comp.allocator, "\n// Added by compile-time add_build_string to the current workspace.\n");
            try out.appendSlice(comp.allocator, generated_source);
            if (generated_source.len == 0 or generated_source[generated_source.len - 1] != '\n') try out.append(comp.allocator, '\n');
        }

        const expanded = try out.toOwnedSlice(comp.allocator);
        comp.allocator.free(source.*);
        source.* = expanded;
        return true;
    }

    fn currentWorkspaceOutputDisabled(comp: *Compilation) bool {
        const options = comp.workspace_build_options.get(2) orelse return false;
        return std.mem.eql(u8, options.output_type, "NO_OUTPUT");
    }

    fn compileTargetWorkspaces(comp: *Compilation, diag: Diagnostic) anyerror!void {
        var seen = std.AutoHashMapUnmanaged(i64, void){};
        defer seen.deinit(comp.allocator);
        for (comp.workspace_sources.items) |source| {
            if (source.workspace <= 2) continue;
            const entry = try seen.getOrPut(comp.allocator, source.workspace);
            if (entry.found_existing) continue;
            try comp.compileTargetWorkspace(source.workspace, diag);
        }
    }

    fn compileTargetWorkspace(comp: *Compilation, workspace: i64, parent_diag: Diagnostic) anyerror!void {
        const options = comp.workspace_build_options.get(workspace) orelse return;
        if (std.mem.eql(u8, options.output_type, "NO_OUTPUT")) return;

        var combined = std.ArrayList(u8).empty;
        defer combined.deinit(comp.allocator);
        var first_path: ?[]const u8 = null;
        for (comp.workspace_sources.items) |source| {
            if (source.workspace != workspace) continue;
            if (first_path == null) first_path = source.path;
            if (combined.items.len != 0 and combined.items[combined.items.len - 1] != '\n') try combined.append(comp.allocator, '\n');
            try combined.print(comp.allocator, "\n// Added to workspace {d} from {s}.\n", .{ workspace, source.path });
            try combined.appendSlice(comp.allocator, source.source);
            if (source.source.len == 0 or source.source[source.source.len - 1] != '\n') try combined.append(comp.allocator, '\n');
        }
        if (combined.items.len == 0) return;

        const workspace_dir = try std.fmt.allocPrint(comp.allocator, "out/workspaces/{d}", .{workspace});
        defer comp.allocator.free(workspace_dir);
        std.Io.Dir.createDirPath(std.Io.Dir.cwd(), comp.io, workspace_dir) catch |err| {
            return parent_diag.failAt(0, "failed creating workspace build directory '{s}': {s}", .{ workspace_dir, @errorName(err) });
        };

        const source_path = try std.fmt.allocPrint(comp.allocator, "{s}/workspace.jai", .{workspace_dir});
        defer comp.allocator.free(source_path);
        std.Io.Dir.cwd().writeFile(comp.io, .{ .sub_path = source_path, .data = combined.items }) catch |err| {
            return parent_diag.failAt(0, "failed writing generated workspace source '{s}': {s}", .{ source_path, @errorName(err) });
        };

        const output_path = try comp.outputPathForWorkspace(workspace, options);
        defer comp.allocator.free(output_path);
        var nested = Compilation.init(comp.allocator, comp.io, .{
            .input_path = source_path,
            .output_path = output_path,
            .runtime_path = comp.options.runtime_path,
            .check_only = comp.options.check_only,
            .command_line = comp.options.command_line,
        });
        nested.compile() catch |err| {
            return parent_diag.failAt(0, "workspace {d} build failed from '{s}': {s}", .{ workspace, first_path orelse source_path, @errorName(err) });
        };
    }

    fn outputPathForWorkspace(comp: *Compilation, workspace: i64, options: vm_mod.BuildOptionsSnapshot) ![]u8 {
        const executable_name = if (options.output_executable_name.len != 0)
            options.output_executable_name
        else
            try std.fmt.allocPrint(comp.allocator, "workspace_{d}", .{workspace});
        defer if (options.output_executable_name.len == 0) comp.allocator.free(executable_name);
        if (options.output_path.len == 0) {
            return try std.fs.path.join(comp.allocator, &.{ "out", executable_name });
        }
        return try std.fs.path.join(comp.allocator, &.{ options.output_path, executable_name });
    }

    pub fn compile(comp: *Compilation) !void {
        defer {
            for (comp.owned_run_result_strings.items) |value| comp.allocator.free(value);
            comp.owned_run_result_strings.deinit(comp.allocator);
            comp.owned_run_result_strings = .empty;
            for (comp.owned_run_result_bytes.items) |value| comp.allocator.free(value);
            comp.owned_run_result_bytes.deinit(comp.allocator);
            comp.owned_run_result_bytes = .empty;
            for (comp.pending_current_workspace_sources.items) |value| comp.allocator.free(value);
            comp.pending_current_workspace_sources.deinit(comp.allocator);
            comp.pending_current_workspace_sources = .empty;
            comp.clearWorkspaceBuildState();
            comp.workspace_sources.deinit(comp.allocator);
            comp.workspace_build_options.deinit(comp.allocator);
            comp.clearLoadedModules();
            comp.loaded_module_paths.deinit(comp.allocator);
        }

        var source = try comp.loadSourceWithLoads(comp.options.input_path);
        defer comp.allocator.free(source);
        var applied_current_workspace_sources = std.ArrayList([]const u8).empty;
        defer {
            for (applied_current_workspace_sources.items) |value| comp.allocator.free(value);
            applied_current_workspace_sources.deinit(comp.allocator);
        }

        var pass: usize = 0;
        while (true) {
            pass += 1;
            const diag = Diagnostic.init(comp.allocator, comp.options.input_path, source);
            if (pass > 16) return diag.failAt(0, "compile-time add_build_string did not reach a fixed point after {d} passes", .{pass - 1});
            if (source.len == 0 and !comp.options.check_only) return diag.failAt(0, "source file is empty", .{});

            var tokens = try lexer.tokenize(comp.allocator, source, diag);
            defer tokens.deinit(comp.allocator);

            const token_slice = tokens.slice();
            var ast = try parser.parse(comp.allocator, source, token_slice.items(.tag), token_slice.items(.start), token_slice.items(.end), diag);
            defer {
                comp.allocator.free(ast.tokens);
                ast.deinit();
            }

            const require_main = !comp.options.check_only and !hasTopLevelExecutableRun(&ast);
            var resolved = try resolve_mod.resolve(comp.allocator, &ast, diag, require_main, &.{});
            defer resolved.deinit();
            try resolved.failIfImplicitPlaceholders(diag);

            var ip = try InternPool.init(comp.allocator);
            defer ip.deinit();

            var typed = try sema.analyze(comp.allocator, &ast, &resolved, &ip, diag);
            defer typed.deinit();

            comp.next_workspace_id = 3;
            comp.clearPendingCurrentWorkspaceSources();
            comp.clearWorkspaceBuildState();
            try comp.evaluateTopLevelRunInitializers(&ast, &typed, &resolved, diag);
            try comp.evaluateAllProcRunInitializers(&ast, &typed, &resolved, diag);
            try comp.evaluateAllNestedRunExpressions(&ast, &typed, &resolved, diag);
            try comp.executeTopLevelRuns(&ast, &typed, &resolved, diag);
            if (try comp.applyPendingCurrentWorkspaceSources(&source, &applied_current_workspace_sources)) continue;
            try resolved.failIfUsedExplicitPlaceholders(diag);

            try comp.compileTargetWorkspaces(diag);
            if (comp.options.check_only) return;
            if (comp.currentWorkspaceOutputDisabled()) return;
            if (resolved.main_proc == null) return;

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

            const runtime_path = try comp.resolveRuntimePath();
            defer if (runtime_path.owned) comp.allocator.free(runtime_path.path);
            try link_mod.link(comp.allocator, comp.io, object_path, runtime_path.path, comp.options.output_path, diag);
            return;
        }
    }

    const ResolvedRuntimePath = struct {
        path: []const u8,
        owned: bool = false,
    };

    fn resolveRuntimePath(comp: *Compilation) !ResolvedRuntimePath {
        if (try pathExists(comp.io, comp.options.runtime_path)) return .{ .path = comp.options.runtime_path };

        const makefile_runtime = "out/bootstrap/lib/openjai_runtime.manifest";
        if (try pathExists(comp.io, makefile_runtime)) return .{ .path = makefile_runtime };

        const makefile_runtime_object = "out/bootstrap/lib/openjai_runtime.o";
        if (try pathExists(comp.io, makefile_runtime_object)) return .{ .path = makefile_runtime_object };

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
            .bytes => |bytes_value| {
                try typed.putComptimeBytes(value_node, bytes_value);
                try typed.putComptimeBytes(decl_node, bytes_value);
            },
            .code => |code_value| {
                try typed.putComptimeString(value_node, code_value.text);
                try typed.putComptimeString(decl_node, code_value.text);
            },
            .type_text => return diag.failAt(source_offset, "expression-form #run cannot materialize a Type value as a runtime constant", .{}),
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
            _ = value;
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
        for (root_decls, 0..) |decl_idx, i| {
            const decl: @import("Ast.zig").NodeIndex = @intCast(decl_idx);
            if (ast.tag(decl) != .proc_decl) continue;
            const next_decl: @import("Ast.zig").NodeIndex = if (i + 1 < root_decls.len) @intCast(root_decls[i + 1]) else @import("Ast.zig").null_node;
            if (procHasExpandModifier(ast, decl, next_decl)) continue;
            if (procHasPolymorphicParams(ast, decl)) continue;
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
        for (root_decls, 0..) |decl_idx, i| {
            const decl: @import("Ast.zig").NodeIndex = @intCast(decl_idx);
            if (ast.tag(decl) != .proc_decl) continue;
            const next_decl: @import("Ast.zig").NodeIndex = if (i + 1 < root_decls.len) @intCast(root_decls[i + 1]) else @import("Ast.zig").null_node;
            if (procHasExpandModifier(ast, decl, next_decl)) continue;
            if (procHasPolymorphicParams(ast, decl)) continue;
            try comp.evaluateRunExpressionsInNode(ast, typed, resolved, ast.data(decl).lhs, diag);
        }
    }

    fn evaluateRunExpressionsInNode(comp: *Compilation, ast: *const @import("Ast.zig").Ast, typed: *sema.Typed, resolved: *const resolve_mod.Resolved, node: @import("Ast.zig").NodeIndex, diag: Diagnostic) anyerror!void {
        if (node == @import("Ast.zig").null_node or node == using_param_sentinel or node >= ast.node_tags.items.len) return;
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
                if (typed.comptime_ints.contains(node) or typed.comptime_floats.contains(node) or typed.comptime_strings.contains(node) or typed.comptime_bytes.contains(node)) return;
                const value = try comp.executeRunCall(ast, typed, resolved, node, ast.data(node).lhs, diag);
                switch (value) {
                    .int => |int_value| try typed.comptime_ints.put(comp.allocator, node, int_value),
                    .float => |float_value| try typed.comptime_floats.put(comp.allocator, node, float_value),
                    .bool => |bool_value| try typed.comptime_ints.put(comp.allocator, node, if (bool_value) 1 else 0),
                    .string => |string_value| try typed.putComptimeString(node, string_value),
                    .bytes => |bytes_value| try typed.putComptimeBytes(node, bytes_value),
                    .code => |code_value| try typed.putComptimeString(node, code_value.text),
                    .type_text => {},
                    .void => {},
                }
            },
            .block => {
                if (blockContainsDirectiveInsert(ast, node)) return;
                for (ast.extraSlice(ast.data(node).lhs)) |stmt| try comp.evaluateRunExpressionsInNode(ast, typed, resolved, @intCast(stmt), diag);
            },
            .stmt_list, .aggregate_literal => {
                for (ast.extraSlice(ast.data(node).lhs)) |child| try comp.evaluateRunExpressionsInNode(ast, typed, resolved, @intCast(child), diag);
            },
            .var_decl => {
                try comp.evaluateRunExpressionsInNode(ast, typed, resolved, ast.data(node).lhs, diag);
                if (ast.data(node).rhs != using_param_sentinel) try comp.evaluateRunExpressionsInNode(ast, typed, resolved, ast.data(node).rhs, diag);
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
                const decl = resolved.local_values.get(node) orelse blk_decl: {
                    const name = ast.tokenSlice(ast.mainToken(node));
                    if (resolved.lookup(name)) |sym| switch (sym) {
                        .const_value => |value_node| break :blk_decl value_node,
                        else => {},
                    };
                    return diag.failAt(ast.tokens[ast.mainToken(node)].start, "#run argument is not a supported compile-time value", .{});
                };
                if (decl == @import("Ast.zig").null_node or decl >= ast.node_tags.items.len) return diag.failAt(ast.tokens[ast.mainToken(node)].start, "#run argument is not a supported compile-time value", .{});
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

    fn executeRunCall(comp: *Compilation, ast: *const @import("Ast.zig").Ast, typed: *sema.Typed, resolved: *const resolve_mod.Resolved, run_node: @import("Ast.zig").NodeIndex, expr: @import("Ast.zig").NodeIndex, diag: Diagnostic) anyerror!vm_mod.Value {
        if (expr == @import("Ast.zig").null_node) {
            return diag.failAt(ast.tokens[ast.mainToken(run_node)].start, "compile-time execution received a null expression operand", .{});
        }
        if (ast.tag(expr) == .block) {
            var block_program = try bytecode_gen.generateBlockProc(comp.allocator, ast, resolved, expr, diag);
            defer block_program.deinit();
            var block_vm = vm_mod.VM.initWithContext(comp.allocator, &block_program, comp.io, comp.sourceBaseDir());
            block_vm.current_workspace_build_strings = &comp.pending_current_workspace_sources;
            block_vm.next_workspace_id = &comp.next_workspace_id;
            block_vm.command_line = comp.options.command_line;
            defer block_vm.deinit();
            const result = try comp.ownRunResult(try block_vm.runProc(block_program.main_proc.?, diag));
            try comp.captureVMWorkspaceState(&block_vm);
            try comp.recordNoResetGlobals(ast, typed, &block_program, &block_vm, diag);
            return result;
        }
        if (ast.tag(expr) != .call_expr) return try comp.executeRunConstExpr(ast, typed, resolved, expr, diag);
        const callee = ast.data(expr).lhs;
        if (ast.tag(callee) != .identifier) return diag.failAt(ast.tokens[ast.mainToken(callee)].start, "#run currently requires an identifier callee", .{});
        const call_args = ast.extraSlice(ast.data(expr).rhs);
        const direct_name = ast.tokenSlice(ast.mainToken(callee));
        if (std.mem.eql(u8, direct_name, "print") or std.mem.eql(u8, direct_name, "log")) {
            try comp.executeRunPrint(ast, typed, resolved, callee, call_args, diag);
            return .void;
        }
        if (std.mem.eql(u8, direct_name, "add_global_data")) {
            if (call_args.len == 0) return diag.failAt(ast.tokens[ast.mainToken(callee)].start, "add_global_data expects at least one data argument", .{});
            const data = try comp.executeRunHostArg(ast, typed, resolved, @intCast(call_args[0]), diag);
            for (call_args[1..]) |arg_idx| _ = try comp.executeRunHostArg(ast, typed, resolved, @intCast(arg_idx), diag);
            return switch (data) {
                .string => |text| .{ .bytes = text },
                .bytes => |bytes| .{ .bytes = bytes },
                else => diag.failAt(ast.tokens[ast.mainToken(@as(@import("Ast.zig").NodeIndex, @intCast(call_args[0])))].start, "add_global_data data argument must be bytes or string", .{}),
            };
        }
        if (std.mem.eql(u8, direct_name, "run_command")) {
            return try comp.executeRunCommand(ast, typed, resolved, call_args, diag);
        }
        if (std.mem.eql(u8, direct_name, "sin") or std.mem.eql(u8, direct_name, "sqrt") or std.mem.eql(u8, direct_name, "cos")) {
            if (call_args.len != 1) return diag.failAt(ast.tokens[ast.mainToken(callee)].start, "{s} expects one argument", .{direct_name});
            const arg = try evalComptimeFloatExpr(ast, typed, resolved, @intCast(call_args[0]), diag);
            const result = if (std.mem.eql(u8, direct_name, "sin"))
                @sin(arg)
            else if (std.mem.eql(u8, direct_name, "sqrt"))
                std.math.sqrt(arg)
            else
                std.math.cos(arg);
            return .{ .float = result };
        }
        if (std.mem.eql(u8, direct_name, "join")) {
            var out = std.ArrayList(u8).empty;
            defer out.deinit(comp.allocator);
            for (call_args) |arg_idx| {
                const value = try comp.executeRunHostArg(ast, typed, resolved, @intCast(arg_idx), diag);
                switch (value) {
                    .string => |text| try out.appendSlice(comp.allocator, text),
                    .bytes => |bytes| try out.appendSlice(comp.allocator, bytes),
                    else => return diag.failAt(ast.tokens[ast.mainToken(@as(@import("Ast.zig").NodeIndex, @intCast(arg_idx)))].start, "join arguments in #run must be strings", .{}),
                }
            }
            return .{ .string = try comp.ownRunString(out.items) };
        }
        if (std.mem.eql(u8, direct_name, "read_entire_file")) {
            if (call_args.len != 1) return diag.failAt(ast.tokens[ast.mainToken(callee)].start, "read_entire_file expects one path", .{});
            const path_value = try comp.executeRunHostArg(ast, typed, resolved, @intCast(call_args[0]), diag);
            const path = switch (path_value) {
                .string => |text| text,
                .bytes => |bytes| bytes,
                else => return diag.failAt(ast.tokens[ast.mainToken(@as(@import("Ast.zig").NodeIndex, @intCast(call_args[0])))].start, "read_entire_file path must be a string", .{}),
            };
            const full = if (std.fs.path.isAbsolute(path))
                try comp.allocator.dupe(u8, path)
            else
                try std.fs.path.join(comp.allocator, &.{ comp.sourceBaseDir(), path });
            defer comp.allocator.free(full);
            const contents = std.Io.Dir.cwd().readFileAlloc(comp.io, full, comp.allocator, .limited(64 * 1024 * 1024)) catch |err| {
                return diag.failAt(ast.tokens[ast.mainToken(callee)].start, "read_entire_file failed for '{s}': {s}", .{ full, @errorName(err) });
            };
            errdefer comp.allocator.free(contents);
            try comp.owned_run_result_bytes.append(comp.allocator, contents);
            return .{ .bytes = contents };
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
        const target_is_expand = procHasExpandModifierLocal(ast, proc_node);
        var run_program = try bytecode_gen.generateProcForCall(comp.allocator, ast, resolved, typed, proc_node, expr, diag);
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
            } else if (typed.comptime_bytes.get(arg)) |value| {
                try arg_values.append(comp.allocator, .{ .bytes = value });
            } else if (ast.tag(arg) == .integer_literal or ast.tag(arg) == .char_literal) {
                try arg_values.append(comp.allocator, .{ .int = try parseRunIntLiteral(ast, arg, diag) });
            } else if (ast.tag(arg) == .float_literal) {
                try arg_values.append(comp.allocator, .{ .float = try std.fmt.parseFloat(f64, ast.tokenSlice(ast.mainToken(arg))) });
            } else if (ast.tag(arg) == .call_expr) {
                try arg_values.append(comp.allocator, try comp.executeRunCall(ast, typed, resolved, arg, arg, diag));
            } else if (ast.tag(arg) == .binary_expr or ast.tag(arg) == .unary_expr) {
                if (evalComptimeFloatExpr(ast, typed, resolved, arg, diag)) |value| {
                    try arg_values.append(comp.allocator, .{ .float = value });
                } else |_| {
                    try arg_values.append(comp.allocator, .{ .int = try evalComptimeIntExpr(ast, typed, resolved, arg, diag) });
                }
            } else if (ast.tag(arg) == .meta_expr or ast.tag(arg) == .type_expr) {
                return diag.failAt(ast.tokens[ast.mainToken(arg)].start, "unsupported compile-time procedure argument kind {s}", .{@tagName(ast.tag(arg))});
            } else if (ast.tag(arg) == .identifier) {
                const decl = resolved.local_values.get(arg) orelse blk: {
                    const name = ast.tokenSlice(ast.mainToken(arg));
                    if (resolved.lookup(name)) |sym| switch (sym) {
                        .const_value => |node| break :blk node,
                        else => {},
                    };
                    return diag.failAt(ast.tokens[ast.mainToken(arg)].start, "unresolved compile-time procedure argument", .{});
                };
                if (typed.comptime_ints.get(decl)) |value| {
                    try arg_values.append(comp.allocator, .{ .int = value });
                } else if (typed.comptime_floats.get(decl)) |value| {
                    try arg_values.append(comp.allocator, .{ .float = value });
                } else if (typed.comptime_strings.get(decl)) |value| {
                    try arg_values.append(comp.allocator, .{ .string = value });
                } else if (typed.comptime_bytes.get(decl)) |value| {
                    try arg_values.append(comp.allocator, .{ .bytes = value });
                } else {
                    if (decl == @import("Ast.zig").null_node) {
                        return diag.failAt(ast.tokens[ast.mainToken(arg)].start, "unsupported compile-time procedure argument", .{});
                    }
                    const initializer_node = if (ast.tag(decl) == .const_decl) ast.data(decl).lhs else if (ast.tag(decl) == .var_decl) ast.data(decl).rhs else @import("Ast.zig").null_node;
                    if (initializer_node == @import("Ast.zig").null_node) {
                        if (target_is_expand) {
                            try arg_values.append(comp.allocator, .{ .int = 0 });
                            continue;
                        }
                        return diag.failAt(ast.tokens[ast.mainToken(arg)].start, "compile-time procedure argument has no initializer", .{});
                    }
                    if (typed.comptime_ints.get(initializer_node)) |value| {
                        try arg_values.append(comp.allocator, .{ .int = value });
                    } else if (typed.comptime_floats.get(initializer_node)) |value| {
                        try arg_values.append(comp.allocator, .{ .float = value });
                    } else if (typed.comptime_strings.get(initializer_node)) |value| {
                        try arg_values.append(comp.allocator, .{ .string = value });
                    } else if (typed.comptime_bytes.get(initializer_node)) |value| {
                        try arg_values.append(comp.allocator, .{ .bytes = value });
                    } else {
                        const value = comp.executeRunConstExpr(ast, typed, resolved, initializer_node, diag) catch |err| {
                            if (target_is_expand) {
                                try arg_values.append(comp.allocator, .{ .int = 0 });
                                continue;
                            }
                            return err;
                        };
                        try arg_values.append(comp.allocator, value);
                    }
                }
            } else {
                return diag.failAt(ast.tokens[ast.mainToken(arg)].start, "unsupported compile-time procedure argument expression", .{});
            }
        }
        if (procParams(ast, proc_node)) |params| {
            if (arg_values.items.len < params.len) {
                var i = arg_values.items.len;
                while (i < params.len) : (i += 1) {
                    const param: @import("Ast.zig").NodeIndex = @intCast(params[i]);
                    const default_value = ast.data(param).rhs;
                    if (default_value == @import("Ast.zig").null_node) {
                        return diag.failAt(ast.tokens[ast.mainToken(param)].start, "#run argument count does not match procedure parameters", .{});
                    }
                    if (isCallerCodeExpr(ast, default_value)) {
                        try arg_values.append(comp.allocator, .{ .string = callSource(ast, expr) });
                    } else {
                        try arg_values.append(comp.allocator, try comp.executeRunHostArg(ast, typed, resolved, default_value, diag));
                    }
                }
            }
        }
        var vm = vm_mod.VM.initWithContext(comp.allocator, &run_program, comp.io, comp.sourceBaseDir());
        vm.current_workspace_build_strings = &comp.pending_current_workspace_sources;
        vm.next_workspace_id = &comp.next_workspace_id;
        vm.command_line = comp.options.command_line;
        defer vm.deinit();
        const result = try comp.ownRunResult(try vm.runProcWithArgs(run_program.main_proc.?, arg_values.items, diag));
        try comp.captureVMWorkspaceState(&vm);
        return result;
    }

    fn executeRunCommand(comp: *Compilation, ast: *const @import("Ast.zig").Ast, typed: *sema.Typed, resolved: *const resolve_mod.Resolved, args: []const u32, diag: Diagnostic) !vm_mod.Value {
        if (args.len == 0) return diag.failAt(0, "run_command expects at least one string argument", .{});

        var command_args = std.ArrayList([]const u8).empty;
        defer command_args.deinit(comp.allocator);
        for (args) |arg_idx| {
            const value = try comp.executeRunHostArg(ast, typed, resolved, @intCast(arg_idx), diag);
            switch (value) {
                .string => |text| try command_args.append(comp.allocator, text),
                else => return diag.failAt(ast.tokens[ast.mainToken(@as(@import("Ast.zig").NodeIndex, @intCast(arg_idx)))].start, "run_command arguments must be strings", .{}),
            }
        }

        var argv = std.ArrayList([]const u8).empty;
        defer argv.deinit(comp.allocator);
        if (command_args.items.len == 1) {
            try argv.appendSlice(comp.allocator, &.{ "/bin/sh", "-c", command_args.items[0] });
        } else {
            try argv.appendSlice(comp.allocator, command_args.items);
        }

        const result = std.process.run(comp.allocator, comp.io, .{
            .argv = argv.items,
            .stderr_limit = .limited(64 * 1024),
            .stdout_limit = .limited(64 * 1024),
        }) catch |err| {
            return diag.failAt(0, "run_command failed to start: {s}", .{@errorName(err)});
        };
        defer comp.allocator.free(result.stdout);
        defer comp.allocator.free(result.stderr);
        if (result.stdout.len != 0) std.debug.print("{s}", .{result.stdout});
        if (result.stderr.len != 0) std.debug.print("{s}", .{result.stderr});
        return .{ .int = switch (result.term) {
            .exited => |code| code,
            else => 1,
        } };
    }

    fn executeRunPrint(comp: *Compilation, ast: *const @import("Ast.zig").Ast, typed: *sema.Typed, resolved: *const resolve_mod.Resolved, callee: @import("Ast.zig").NodeIndex, args: []const u32, diag: Diagnostic) !void {
        if (args.len == 0) return diag.failAt(ast.tokens[ast.mainToken(callee)].start, "print expects at least one argument", .{});
        const first: @import("Ast.zig").NodeIndex = @intCast(args[0]);
        if (ast.tag(first) == .string_literal and args.len > 1) {
            const raw_fmt = ast.stringTokenContents(ast.mainToken(first));
            const fmt = try decodeRunString(comp.allocator, raw_fmt, diag, ast.tokens[ast.mainToken(first)].start);
            defer comp.allocator.free(fmt);
            var arg_index: usize = 0;
            var start: usize = 0;
            var i: usize = 0;
            while (i < fmt.len) : (i += 1) {
                if (fmt[i] != '%') continue;
                if (i + 1 < fmt.len and fmt[i + 1] == '%') {
                    std.debug.print("{s}%", .{fmt[start..i]});
                    i += 1;
                    start = i + 1;
                    continue;
                }
                std.debug.print("{s}", .{fmt[start..i]});
                var selected = arg_index;
                var next_start = i + 1;
                if (i + 1 < fmt.len and fmt[i + 1] >= '1' and fmt[i + 1] <= '9') {
                    selected = fmt[i + 1] - '1';
                    next_start = i + 2;
                } else {
                    arg_index += 1;
                }
                if (selected >= args.len - 1) return diag.failAt(ast.tokens[ast.mainToken(first)].start, "print format references argument index out of range", .{});
                const value = try comp.executeRunHostArg(ast, typed, resolved, @intCast(args[selected + 1]), diag);
                printRunValue(value);
                start = next_start;
            }
            if (start < fmt.len) std.debug.print("{s}", .{fmt[start..]});
            return;
        }
        for (args) |arg_idx| {
            const value = try comp.executeRunHostArg(ast, typed, resolved, @intCast(arg_idx), diag);
            printRunValue(value);
        }
    }

    fn printRunValue(value: vm_mod.Value) void {
        switch (value) {
            .void => {},
            .int => |v| std.debug.print("{d}", .{v}),
            .float => |v| std.debug.print("{d}", .{v}),
            .bool => |v| std.debug.print("{s}", .{if (v) "true" else "false"}),
            .string => |v| std.debug.print("{s}", .{v}),
            .bytes => |v| std.debug.print("{s}", .{v}),
            .code => |v| std.debug.print("{s}", .{v.text}),
            .type_text => |v| std.debug.print("{s}", .{v}),
        }
    }

    fn decodeRunString(allocator: std.mem.Allocator, raw: []const u8, diag: Diagnostic, source_offset: u32) ![]const u8 {
        var out = std.ArrayList(u8).empty;
        errdefer out.deinit(allocator);
        var i: usize = 0;
        while (i < raw.len) : (i += 1) {
            if (raw[i] != '\\') {
                try out.append(allocator, raw[i]);
                continue;
            }
            i += 1;
            if (i >= raw.len) return diag.failAt(source_offset, "unterminated escape in #run print format string", .{});
            try out.append(allocator, switch (raw[i]) {
                'n' => '\n',
                'r' => '\r',
                't' => '\t',
                '\\' => '\\',
                '"' => '"',
                '%' => '%',
                'x' => blk: {
                    if (i + 2 >= raw.len) return diag.failAt(source_offset, "short hex escape in #run string", .{});
                    const value = (try hexNibble(raw[i + 1], diag, source_offset) << 4) | try hexNibble(raw[i + 2], diag, source_offset);
                    i += 2;
                    break :blk value;
                },
                else => raw[i],
            });
        }
        return try out.toOwnedSlice(allocator);
    }

    fn hexNibble(ch: u8, diag: Diagnostic, source_offset: u32) !u8 {
        return switch (ch) {
            '0'...'9' => ch - '0',
            'a'...'f' => ch - 'a' + 10,
            'A'...'F' => ch - 'A' + 10,
            else => diag.failAt(source_offset, "invalid hex escape digit in #run string", .{}),
        };
    }

    fn recordNoResetGlobals(comp: *Compilation, ast: *const @import("Ast.zig").Ast, typed: *sema.Typed, program: *const Bytecode.Program, vm: *vm_mod.VM, diag: Diagnostic) !void {
        for (program.globals.items, 0..) |global, i| {
            const decl: @import("Ast.zig").NodeIndex = @intCast(global.source_node);
            if (!ast.isNoReset(decl)) continue;
            const bytes = (try vm.globalBytes(i, diag)) orelse continue;
            try typed.putComptimeBytes(decl, bytes);
        }
        _ = comp;
    }

    fn ownRunResult(comp: *Compilation, value: vm_mod.Value) !vm_mod.Value {
        return switch (value) {
            .string => |string_value| blk: {
                const owned = try comp.allocator.dupe(u8, string_value);
                errdefer comp.allocator.free(owned);
                try comp.owned_run_result_strings.append(comp.allocator, owned);
                break :blk .{ .string = owned };
            },
            .bytes => |bytes_value| blk: {
                const owned = try comp.allocator.dupe(u8, bytes_value);
                errdefer comp.allocator.free(owned);
                try comp.owned_run_result_bytes.append(comp.allocator, owned);
                break :blk .{ .bytes = owned };
            },
            .code => |code_value| blk: {
                const owned_text = try comp.ownRunString(code_value.text);
                const owned_path = try comp.ownRunString(code_value.path);
                break :blk .{ .code = .{ .text = owned_text, .path = owned_path, .line_number = code_value.line_number } };
            },
            else => value,
        };
    }

    fn executeRunHostArg(comp: *Compilation, ast: *const @import("Ast.zig").Ast, typed: *sema.Typed, resolved: *const resolve_mod.Resolved, arg: @import("Ast.zig").NodeIndex, diag: Diagnostic) anyerror!vm_mod.Value {
        if (ast.tag(arg) == .field_access and ast.data(arg).lhs == @import("Ast.zig").null_node) return .{ .int = 0 };
        if (ast.tag(arg) == .unary_expr and ast.tokens[ast.mainToken(arg)].tag == .keyword_xx) return comp.executeRunHostArg(ast, typed, resolved, ast.data(arg).lhs, diag);
        if (ast.tag(arg) == .call_expr) return try comp.executeRunCall(ast, typed, resolved, arg, arg, diag);
        if (typed.comptime_ints.get(arg)) |value| return .{ .int = value };
        if (typed.comptime_floats.get(arg)) |value| return .{ .float = value };
        if (typed.comptime_strings.get(arg)) |value| return .{ .string = value };
        if (typed.comptime_bytes.get(arg)) |value| return .{ .bytes = value };
        return switch (ast.tag(arg)) {
            .integer_literal => .{ .int = try evalComptimeIntExpr(ast, typed, resolved, arg, diag) },
            .float_literal => .{ .float = try evalComptimeFloatExpr(ast, typed, resolved, arg, diag) },
            .bool_literal => .{ .bool = ast.data(arg).lhs != 0 },
            .string_literal => blk: {
                const decoded = if (isDirectiveStringLiteral(ast, arg))
                    try comp.allocator.dupe(u8, ast.stringTokenContents(ast.mainToken(arg)))
                else
                    try decodeRunString(comp.allocator, ast.stringTokenContents(ast.mainToken(arg)), diag, ast.tokens[ast.mainToken(arg)].start);
                errdefer comp.allocator.free(decoded);
                try comp.owned_run_result_strings.append(comp.allocator, decoded);
                break :blk .{ .string = decoded };
            },
            .identifier => .{ .string = ast.tokenSlice(ast.mainToken(arg)) },
            else => return diag.failAt(ast.tokens[ast.mainToken(arg)].start, "unsupported compile-time host argument expression {s}", .{@tagName(ast.tag(arg))}),
        };
    }

    fn ownRunString(comp: *Compilation, value: []const u8) ![]const u8 {
        const owned = try comp.allocator.dupe(u8, value);
        errdefer comp.allocator.free(owned);
        try comp.owned_run_result_strings.append(comp.allocator, owned);
        return owned;
    }

    fn isDirectiveStringLiteral(ast: *const @import("Ast.zig").Ast, node: @import("Ast.zig").NodeIndex) bool {
        return ast.tag(node) == .string_literal and
            ast.data(node).lhs != @import("Ast.zig").null_node and
            ast.tokens[ast.data(node).lhs].tag == .directive_string;
    }

    fn procParams(ast: *const @import("Ast.zig").Ast, proc_node: @import("Ast.zig").NodeIndex) ?[]const u32 {
        if (proc_node == @import("Ast.zig").null_node or proc_node >= ast.node_tags.items.len or ast.tag(proc_node) != .proc_decl) return null;
        const sig_extra = ast.data(proc_node).rhs;
        if (sig_extra >= ast.extra_data.items.len) return null;
        const sig = ast.extraSlice(sig_extra);
        if (sig.len < 1) return null;
        if (sig[0] >= ast.extra_data.items.len) return null;
        return ast.extraSlice(sig[0]);
    }

    fn isCallerCodeExpr(ast: *const @import("Ast.zig").Ast, node: @import("Ast.zig").NodeIndex) bool {
        return node != @import("Ast.zig").null_node and
            node < ast.node_tags.items.len and
            ast.tag(node) == .meta_expr and
            ast.tokens[ast.mainToken(node)].tag == .directive_caller_code;
    }

    fn procHasExpandModifierLocal(ast: *const @import("Ast.zig").Ast, proc: @import("Ast.zig").NodeIndex) bool {
        if (proc == @import("Ast.zig").null_node or proc >= ast.node_tags.items.len or ast.tag(proc) != .proc_decl) return false;
        const token_start = ast.tokens[ast.mainToken(proc)].start;
        const body = ast.data(proc).lhs;
        const body_start = if (body != @import("Ast.zig").null_node and body < ast.node_tags.items.len) ast.tokens[ast.mainToken(body)].start else @min(ast.source.len, token_start + 256);
        const start = token_start - @min(token_start, 200);
        if (body_start <= start or body_start > ast.source.len) return false;
        return std.mem.indexOf(u8, ast.source[start..body_start], "#expand") != null;
    }

    fn callSource(ast: *const @import("Ast.zig").Ast, call: @import("Ast.zig").NodeIndex) []const u8 {
        if (call == @import("Ast.zig").null_node or call >= ast.node_tags.items.len) return "";
        var start = ast.tokens[ast.mainToken(call)].start;
        var end = ast.tokens[ast.mainToken(call)].end;
        if (ast.tag(call) == .call_expr) {
            const callee = ast.data(call).lhs;
            if (callee < ast.node_tags.items.len) start = @min(start, ast.tokens[ast.mainToken(callee)].start);
            if (matchingCallClose(ast, ast.mainToken(call))) |close_end| end = @max(end, close_end);
        }
        return std.mem.trim(u8, ast.source[start..@min(end, ast.source.len)], " \t\r\n;");
    }

    fn matchingCallClose(ast: *const @import("Ast.zig").Ast, open_tok: @import("Token.zig").Token.Index) ?u32 {
        if (open_tok >= ast.tokens.len or ast.tokens[open_tok].tag != .l_paren) return null;
        var depth: usize = 0;
        var i = open_tok;
        while (i < ast.tokens.len) : (i += 1) {
            switch (ast.tokens[i].tag) {
                .l_paren => depth += 1,
                .r_paren => {
                    if (depth == 0) return null;
                    depth -= 1;
                    if (depth == 0) return ast.tokens[i].end;
                },
                .eof => return null,
                else => {},
            }
        }
        return null;
    }

    fn isExecutableRun(ast: *const @import("Ast.zig").Ast, node: @import("Ast.zig").NodeIndex) bool {
        if (node == @import("Ast.zig").null_node or node == using_param_sentinel or node >= ast.node_tags.items.len or ast.tag(node) != .run_expr) return false;
        return switch (ast.tokens[ast.mainToken(node)].tag) {
            .directive_run, .directive_assert, .keyword_push_context => true,
            else => false,
        };
    }

    fn hasTopLevelExecutableRun(ast: *const @import("Ast.zig").Ast) bool {
        if (ast.root == @import("Ast.zig").null_node) return false;
        for (ast.extraSlice(ast.data(ast.root).lhs)) |decl_idx| {
            if (isExecutableRun(ast, @intCast(decl_idx))) return true;
        }
        return false;
    }

    fn procHasExpandModifier(ast: *const @import("Ast.zig").Ast, proc: @import("Ast.zig").NodeIndex, next_decl: @import("Ast.zig").NodeIndex) bool {
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

    const ProcSig = struct { params_extra: u32, return_type: @import("Ast.zig").NodeIndex };
    fn procSignature(ast: *const @import("Ast.zig").Ast, proc: @import("Ast.zig").NodeIndex) ?ProcSig {
        if (ast.data(proc).rhs == @import("Ast.zig").null_node) return null;
        const sig = ast.extraSlice(ast.data(proc).rhs);
        if (sig.len < 2) return null;
        return .{ .params_extra = sig[0], .return_type = sig[1] };
    }

    fn procHasPolymorphicParams(ast: *const @import("Ast.zig").Ast, proc: @import("Ast.zig").NodeIndex) bool {
        const sig = procSignature(ast, proc) orelse return false;
        for (ast.extraSlice(sig.params_extra)) |param_idx| {
            const param: @import("Ast.zig").NodeIndex = @intCast(param_idx);
            const type_node = ast.data(param).lhs;
            if (type_node == @import("Ast.zig").null_node) continue;
            if (nodeTypeTextIncludesDollar(ast, type_node)) return true;
        }
        return false;
    }

    fn nodeTypeTextIncludesDollar(ast: *const @import("Ast.zig").Ast, node: @import("Ast.zig").NodeIndex) bool {
        if (node == @import("Ast.zig").null_node or node >= ast.node_tags.items.len) return false;
        const tok = ast.mainToken(node);
        var start = ast.tokens[tok].start;
        const end = ast.tokens[tok].end;
        while (start > 0 and (ast.source[start - 1] == ' ' or ast.source[start - 1] == '\t')) start -= 1;
        if (start > 0 and ast.source[start - 1] == '$') return true;
        return std.mem.indexOfScalar(u8, ast.source[start..@min(end, ast.source.len)], '$') != null;
    }

    fn blockContainsDirectiveInsert(ast: *const @import("Ast.zig").Ast, block: @import("Ast.zig").NodeIndex) bool {
        if (block == @import("Ast.zig").null_node or ast.tag(block) != .block) return false;
        for (ast.extraSlice(ast.data(block).lhs)) |stmt_idx| {
            if (nodeContainsDirectiveInsert(ast, @intCast(stmt_idx))) return true;
        }
        return false;
    }

    fn nodeContainsDirectiveInsert(ast: *const @import("Ast.zig").Ast, node: @import("Ast.zig").NodeIndex) bool {
        if (node == @import("Ast.zig").null_node or node >= ast.node_tags.items.len) return false;
        if ((ast.tag(node) == .meta_stmt or ast.tag(node) == .meta_expr) and ast.tokens[ast.mainToken(node)].tag == .directive_insert) return true;
        const data = ast.data(node);
        return switch (ast.tag(node)) {
            .expr_stmt, .const_decl, .return_stmt, .unary_expr, .run_expr => nodeContainsDirectiveInsert(ast, data.lhs),
            .var_decl, .assign_stmt, .binary_expr, .meta_expr, .meta_stmt => nodeContainsDirectiveInsert(ast, data.lhs) or nodeContainsDirectiveInsert(ast, data.rhs),
            .stmt_list, .block, .aggregate_literal => blk: {
                if (data.lhs >= ast.extra_data.items.len) break :blk false;
                for (ast.extraSlice(data.lhs)) |child| if (nodeContainsDirectiveInsert(ast, @intCast(child))) break :blk true;
                break :blk false;
            },
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
                const decl = resolved.local_values.get(node) orelse blk_decl: {
                    const name = ast.tokenSlice(ast.mainToken(node));
                    if (resolved.lookup(name)) |sym| switch (sym) {
                        .const_value => |value_node| break :blk_decl value_node,
                        else => {},
                    };
                    return diag.failAt(ast.tokens[ast.mainToken(node)].start, "#run constant expression identifier is unresolved", .{});
                };
                if (decl == @import("Ast.zig").null_node or decl >= ast.node_tags.items.len) break :blk 0;
                if (typed.comptime_ints.get(decl)) |value| break :blk value;
                const initializer = if (ast.tag(decl) == .const_decl) ast.data(decl).lhs else if (ast.tag(decl) == .var_decl) ast.data(decl).rhs else decl;
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

    fn findModule(comp: *Compilation, name: []const u8, from_path: []const u8) ![]u8 {
        const from_dir = std.fs.path.dirname(from_path) orelse ".";
        var maybe_base: ?[]const u8 = from_dir;
        while (maybe_base) |base| {
            const module_path = try std.fs.path.join(comp.allocator, &.{ base, name, "module.jai" });
            if (std.Io.Dir.cwd().access(comp.io, module_path, .{})) {
                return module_path;
            } else |_| {
                comp.allocator.free(module_path);
            }

            const flat_name = try std.fmt.allocPrint(comp.allocator, "{s}.jai", .{name});
            defer comp.allocator.free(flat_name);
            const flat_path = try std.fs.path.join(comp.allocator, &.{ base, flat_name });
            std.Io.Dir.cwd().access(comp.io, flat_path, .{}) catch {
                comp.allocator.free(flat_path);
                const enclosing_name = std.fs.path.basename(base);
                if (std.mem.eql(u8, enclosing_name, name)) {
                    const enclosing_module_path = try std.fs.path.join(comp.allocator, &.{ base, "module.jai" });
                    if (std.Io.Dir.cwd().access(comp.io, enclosing_module_path, .{})) {
                        return enclosing_module_path;
                    } else |_| {
                        comp.allocator.free(enclosing_module_path);
                    }
                }
                maybe_base = std.fs.path.dirname(base);
                continue;
            };
            return flat_path;
        }
        const module_path = try std.fs.path.join(comp.allocator, &.{ "modules", name, "module.jai" });
        if (std.Io.Dir.cwd().access(comp.io, module_path, .{})) {
            return module_path;
        } else |_| {
            comp.allocator.free(module_path);
        }

        const flat_name = try std.fmt.allocPrint(comp.allocator, "{s}.jai", .{name});
        defer comp.allocator.free(flat_name);
        const flat_path = try std.fs.path.join(comp.allocator, &.{ "modules", flat_name });
        std.Io.Dir.cwd().access(comp.io, flat_path, .{}) catch {
            comp.allocator.free(flat_path);
            return error.SourceReadFailed;
        };
        return flat_path;
    }

    fn expandModuleSource(comp: *Compilation, source: []const u8, params: []const u8, module_path: []const u8) ![]const u8 {
        if (std.mem.trim(u8, params, " \t\r\n").len == 0) return try comp.stripModuleParameters(source);
        const mp_idx = std.mem.indexOf(u8, source, "#module_parameters(") orelse return Diagnostic.init(comp.allocator, module_path, source).failAt(0, "parameterized import requires module to declare #module_parameters", .{});
        const mp_start = mp_idx + "#module_parameters(".len;
        const mp_end_rel = std.mem.indexOfScalar(u8, source[mp_start..], ')') orelse return Diagnostic.init(comp.allocator, module_path, source).failAt(mp_idx, "unterminated #module_parameters", .{});
        const decls = source[mp_start .. mp_start + mp_end_rel];
        if (std.mem.indexOf(u8, decls, ":=") == null) return Diagnostic.init(comp.allocator, module_path, source).failAt(mp_idx, "#module_parameters currently supports name := default declarations", .{});
        const name = std.mem.trim(u8, decls[0..std.mem.indexOf(u8, decls, ":=").?], " \t\r\n");
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

    fn stripModuleParameters(comp: *Compilation, source: []const u8) ![]const u8 {
        const mp_idx = std.mem.indexOf(u8, source, "#module_parameters(") orelse return try comp.allocator.dupe(u8, source);
        const mp_start = mp_idx + "#module_parameters(".len;
        const mp_end_rel = std.mem.indexOfScalar(u8, source[mp_start..], ')') orelse return try comp.allocator.dupe(u8, source);
        const after = mp_start + mp_end_rel + 1;
        var line_after = after;
        while (line_after < source.len and source[line_after] != '\n') line_after += 1;
        if (line_after < source.len) line_after += 1;
        var out = std.ArrayList(u8).empty;
        defer out.deinit(comp.allocator);
        try out.appendSlice(comp.allocator, source[0..mp_idx]);
        try out.appendSlice(comp.allocator, source[line_after..]);
        return try out.toOwnedSlice(comp.allocator);
    }

    fn appendLoadedModule(comp: *Compilation, out: *std.ArrayList(u8), module_path: []const u8, source_path: []const u8) anyerror!void {
        if (comp.loaded_module_paths.contains(module_path)) return;
        const owned_module_path = try comp.allocator.dupe(u8, module_path);
        errdefer comp.allocator.free(owned_module_path);
        try comp.loaded_module_paths.put(comp.allocator, owned_module_path, {});
        const loaded_raw = try comp.loadSourceWithLoads(module_path);
        defer comp.allocator.free(loaded_raw);
        const loaded = try comp.stripModuleParameters(loaded_raw);
        defer comp.allocator.free(loaded);
        try out.appendSlice(comp.allocator, "#load \"");
        try out.appendSlice(comp.allocator, module_path);
        try out.appendSlice(comp.allocator, "\";\n");
        try out.appendSlice(comp.allocator, loaded);
        if (loaded.len == 0 or loaded[loaded.len - 1] != '\n') try out.append(comp.allocator, '\n');
        try out.appendSlice(comp.allocator, "#load \"__main_resume\";\n");
        _ = source_path;
    }

    fn isTopLevelImportPosition(source: []const u8, offset: usize) bool {
        var depth: usize = 0;
        var i: usize = 0;
        while (i < offset and i < source.len) {
            const c = source[i];
            if (c == '/' and i + 1 < offset and source[i + 1] == '/') {
                i += 2;
                while (i < offset and source[i] != '\n') i += 1;
                continue;
            }
            if (c == '/' and i + 1 < offset and source[i + 1] == '*') {
                i += 2;
                while (i + 1 < offset and !(source[i] == '*' and source[i + 1] == '/')) i += 1;
                if (i + 1 < offset) i += 2;
                continue;
            }
            if (c == '"') {
                i += 1;
                while (i < offset) : (i += 1) {
                    if (source[i] == '\\') {
                        if (i + 1 < offset) i += 1;
                        continue;
                    }
                    if (source[i] == '"') {
                        i += 1;
                        break;
                    }
                }
                continue;
            }
            if (c == '\'') {
                i += 1;
                while (i < offset) : (i += 1) {
                    if (source[i] == '\\') {
                        if (i + 1 < offset) i += 1;
                        continue;
                    }
                    if (source[i] == '\'') {
                        i += 1;
                        break;
                    }
                }
                continue;
            }
            if (c == '{') depth += 1 else if (c == '}') {
                if (depth > 0) depth -= 1;
            }
            i += 1;
        }
        return depth == 0;
    }

    fn loadSourceWithLoads(comp: *Compilation, path: []const u8) anyerror![]u8 {
        const raw_source = std.Io.Dir.cwd().readFileAlloc(comp.io, path, comp.allocator, .limited(64 * 1024 * 1024)) catch |err| {
            std.debug.print("{s}: error: unable to read source file: {s}\n", .{ path, @errorName(err) });
            return error.SourceReadFailed;
        };
        defer comp.allocator.free(raw_source);
        return try comp.processSourceWithLoads(path, raw_source);
    }

    fn processSourceWithLoads(comp: *Compilation, path: []const u8, raw_source: []const u8) anyerror![]u8 {
        const source = try comp.normalizeSpacedDirectives(raw_source);
        defer comp.allocator.free(source);
        var module_prelude = std.ArrayList(u8).empty;
        defer module_prelude.deinit(comp.allocator);
        var module_postlude = std.ArrayList(u8).empty;
        defer module_postlude.deinit(comp.allocator);
        var out = std.ArrayList(u8).empty;
        defer out.deinit(comp.allocator);
        const dir = std.fs.path.dirname(path) orelse ".";
        var rest = source;
        while (try comp.nextDirectiveIndex(path, rest, .directive_import)) |idx| {
            const absolute_idx = source.len - rest.len + idx;
            const line_end = std.mem.indexOfScalar(u8, rest[idx..], '\n') orelse rest.len - idx;
            const line = rest[idx .. idx + line_end];
            const directive_end = idx + "#import".len;
            const quote_rel = std.mem.indexOfScalar(u8, rest[directive_end .. idx + line_end], '"') orelse return Diagnostic.init(comp.allocator, path, source).failAt(idx, "expected module string after #import", .{});
            const name_start = directive_end + quote_rel + 1;
            const name_end_rel = std.mem.indexOfScalar(u8, rest[name_start..], '"') orelse return Diagnostic.init(comp.allocator, path, source).failAt(idx, "unterminated #import module name", .{});
            const module_name = rest[name_start .. name_start + name_end_rel];
            const after_name = name_start + name_end_rel + 1;
            const line_start = if (std.mem.lastIndexOfScalar(u8, rest[0..idx], '\n')) |newline| newline + 1 else 0;
            const import_prefix = std.mem.trim(u8, rest[line_start..idx], " \t\r\n");
            const assigned_import = import_prefix.len != 0;
            const comment_start = std.mem.indexOf(u8, line, "//") orelse line.len;
            const import_syntax_end = idx + comment_start;
            var param_start: ?usize = null;
            var scan = after_name;
            while (scan < import_syntax_end and std.ascii.isWhitespace(rest[scan])) : (scan += 1) {}
            if (scan < import_syntax_end and rest[scan] == '(') param_start = scan + 1;
            if (param_start) |param_start_value| {
                try out.appendSlice(comp.allocator, rest[0..idx]);
                if (assigned_import) {
                    try out.appendSlice(comp.allocator, rest[idx .. idx + line_end]);
                    if (idx + line_end < rest.len) try out.append(comp.allocator, '\n');
                    rest = if (idx + line_end < rest.len) rest[idx + line_end + 1 ..] else rest[idx + line_end ..];
                    continue;
                }
                const param_end_rel = std.mem.indexOfScalar(u8, rest[param_start_value..], ')') orelse return Diagnostic.init(comp.allocator, path, source).failAt(idx, "unterminated #import module parameters", .{});
                const params = rest[param_start_value .. param_start_value + param_end_rel];
                const module_path = comp.findModule(module_name, path) catch {
                    try out.appendSlice(comp.allocator, "#import \"");
                    try out.appendSlice(comp.allocator, module_name);
                    try out.appendSlice(comp.allocator, "\";\n");
                    rest = if (idx + line_end < rest.len) rest[idx + line_end + 1 ..] else rest[idx + line_end ..];
                    continue;
                };
                defer comp.allocator.free(module_path);
                const module_src = std.Io.Dir.cwd().readFileAlloc(comp.io, module_path, comp.allocator, .limited(64 * 1024 * 1024)) catch |err| {
                    std.debug.print("{s}: error: unable to read module: {s}\n", .{ module_path, @errorName(err) });
                    return error.SourceReadFailed;
                };
                defer comp.allocator.free(module_src);
                const expanded = try comp.expandModuleSource(module_src, params, module_path);
                defer comp.allocator.free(expanded);
                const loaded_expanded = try comp.processSourceWithLoads(module_path, expanded);
                defer comp.allocator.free(loaded_expanded);
                try out.appendSlice(comp.allocator, loaded_expanded);
                try out.append(comp.allocator, '\n');
                rest = if (idx + line_end < rest.len) rest[idx + line_end + 1 ..] else rest[idx + line_end ..];
                continue;
            }
            if (assigned_import) {
                try out.appendSlice(comp.allocator, rest[0 .. idx + line_end]);
                if (idx + line_end < rest.len) try out.append(comp.allocator, '\n');
                if (comp.findModule(module_name, path)) |module_path| {
                    defer comp.allocator.free(module_path);
                    if (isTopLevelImportPosition(source, absolute_idx))
                        try comp.appendLoadedModule(&module_postlude, module_path, path)
                    else
                        try comp.appendLoadedModule(&module_prelude, module_path, path);
                } else |_| {}
                rest = if (idx + line_end < rest.len) rest[idx + line_end + 1 ..] else rest[idx + line_end ..];
                continue;
            }
            if (comp.findModule(module_name, path)) |module_path| {
                defer comp.allocator.free(module_path);
                if (isTopLevelImportPosition(source, absolute_idx)) {
                    try out.appendSlice(comp.allocator, rest[0..idx]);
                    try out.appendSlice(comp.allocator, "// ");
                    try out.appendSlice(comp.allocator, rest[idx .. idx + line_end]);
                    if (idx + line_end < rest.len) try out.append(comp.allocator, '\n');
                    try comp.appendLoadedModule(&module_postlude, module_path, path);
                } else {
                    try out.appendSlice(comp.allocator, rest[0 .. idx + line_end]);
                    if (idx + line_end < rest.len) try out.append(comp.allocator, '\n');
                    try comp.appendLoadedModule(&module_prelude, module_path, path);
                }
                rest = if (idx + line_end < rest.len) rest[idx + line_end + 1 ..] else rest[idx + line_end ..];
            } else |_| {
                try out.appendSlice(comp.allocator, rest[0 .. idx + line_end]);
                if (idx + line_end < rest.len) try out.append(comp.allocator, '\n');
                rest = if (idx + line_end < rest.len) rest[idx + line_end + 1 ..] else rest[idx + line_end ..];
                continue;
            }
        }
        while (try comp.nextDirectiveIndex(path, rest, .directive_load)) |idx| {
            try out.appendSlice(comp.allocator, rest[0..idx]);
            const start = idx + "#load \"".len;
            const end_rel = std.mem.indexOfScalar(u8, rest[start..], '"') orelse {
                return Diagnostic.init(comp.allocator, path, source).failAt(idx, "unterminated #load path", .{});
            };
            const rel = rest[start .. start + end_rel];
            const full = try std.fs.path.join(comp.allocator, &[_][]const u8{ dir, rel });
            defer comp.allocator.free(full);
            const loaded = comp.loadSourceWithLoads(full) catch |err| {
                std.debug.print("{s}: error: unable to load #load file: {s}\n", .{ full, @errorName(err) });
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
        if (module_prelude.items.len == 0 and module_postlude.items.len == 0) return try out.toOwnedSlice(comp.allocator);
        var combined = std.ArrayList(u8).empty;
        defer combined.deinit(comp.allocator);
        if (module_prelude.items.len != 0) {
            try combined.appendSlice(comp.allocator, module_prelude.items);
            if (combined.items.len != 0 and combined.items[combined.items.len - 1] != '\n') try combined.append(comp.allocator, '\n');
        }
        try combined.appendSlice(comp.allocator, out.items);
        if (module_postlude.items.len != 0) {
            if (combined.items.len != 0 and combined.items[combined.items.len - 1] != '\n') try combined.append(comp.allocator, '\n');
            try combined.appendSlice(comp.allocator, module_postlude.items);
        }
        return try combined.toOwnedSlice(comp.allocator);
    }

    fn nextDirectiveIndex(comp: *Compilation, path: []const u8, source: []const u8, tag: Tag) !?usize {
        const diag = Diagnostic.init(comp.allocator, path, source);
        var tokens = try lexer.tokenize(comp.allocator, source, diag);
        defer tokens.deinit(comp.allocator);
        for (tokens.items(.tag), tokens.items(.start)) |token_tag, start| {
            if (token_tag == tag) return start;
        }
        return null;
    }

    fn normalizeSpacedDirectives(comp: *Compilation, source: []const u8) ![]u8 {
        var out = std.ArrayList(u8).empty;
        errdefer out.deinit(comp.allocator);
        var i: usize = 0;
        while (i < source.len) {
            if (source[i] == '#') {
                var cursor = i + 1;
                while (cursor < source.len and (source[cursor] == ' ' or source[cursor] == '\t')) cursor += 1;
                if (cursor > i + 1 and cursor < source.len and (std.ascii.isAlphabetic(source[cursor]) or source[cursor] == '_')) {
                    try out.append(comp.allocator, '#');
                    i = cursor;
                    continue;
                }
            }
            try out.append(comp.allocator, source[i]);
            i += 1;
        }
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
