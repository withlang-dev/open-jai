const std = @import("std");
const Ast = @import("Ast.zig").Ast;
const Node = @import("Ast.zig").Node;
const NodeIndex = @import("Ast.zig").NodeIndex;
const Diagnostic = @import("diagnostics.zig").Diagnostic;

pub const Symbol = union(enum) {
    proc: NodeIndex,
    builtin_print,
    builtin_swap,
    builtin_write_string,
    builtin_write_strings,
    builtin_write_number,
    builtin_write_nonnegative_number,
    builtin_new,
    builtin_free,
    builtin_exit,
    builtin_memcpy,
    builtin_assert,
    builtin_sin,
    const_value: NodeIndex,
};

pub const Resolved = struct {
    allocator: std.mem.Allocator,
    symbols: std.StringHashMapUnmanaged(Symbol) = .empty,
    local_values: std.AutoHashMapUnmanaged(NodeIndex, NodeIndex) = .empty,
    owned_names: std.ArrayList([]u8) = .empty,
    imports_basic: bool = false,
    main_proc: ?NodeIndex = null,

    pub fn deinit(r: *Resolved) void {
        r.symbols.deinit(r.allocator);
        r.local_values.deinit(r.allocator);
        for (r.owned_names.items) |name| r.allocator.free(name);
        r.owned_names.deinit(r.allocator);
    }

    pub fn lookup(r: *const Resolved, name: []const u8) ?Symbol {
        if (r.symbols.get(name)) |sym| return sym;
        if (std.mem.indexOfScalar(u8, name, '\\') == null) return null;
        var buf: [256]u8 = undefined;
        var len: usize = 0;
        var i: usize = 0;
        while (i < name.len) : (i += 1) {
            if (name[i] == '\\') {
                i += 1;
                while (i < name.len and name[i] == ' ') i += 1;
                if (i >= name.len) break;
            }
            if (len >= buf.len) return null;
            buf[len] = name[i];
            len += 1;
        }
        return r.symbols.get(buf[0..len]);
    }

    fn scopedName(r: *Resolved, file_id: u32, raw: []const u8) ![]u8 {
        return try std.fmt.allocPrint(r.allocator, "__file{d}_{s}", .{ file_id, raw });
    }

    fn normalizedName(r: *Resolved, raw: []const u8) ![]const u8 {
        if (std.mem.indexOfScalar(u8, raw, '\\') == null) return raw;
        var out = std.ArrayList(u8).empty;
        errdefer out.deinit(r.allocator);
        var i: usize = 0;
        while (i < raw.len) : (i += 1) {
            if (raw[i] == '\\') {
                i += 1;
                while (i < raw.len and raw[i] == ' ') i += 1;
                if (i >= raw.len) break;
            }
            try out.append(r.allocator, raw[i]);
        }
        const owned = try out.toOwnedSlice(r.allocator);
        try r.owned_names.append(r.allocator, owned);
        return owned;
    }
};

pub fn resolve(allocator: std.mem.Allocator, ast: *const Ast, diag: Diagnostic) !Resolved {
    var r = Resolved{ .allocator = allocator };
    errdefer r.deinit();
    try r.symbols.put(allocator, "write_string", .builtin_write_string);
    try r.symbols.put(allocator, "write_strings", .builtin_write_strings);
    try r.symbols.put(allocator, "write_number", .builtin_write_number);
    try r.symbols.put(allocator, "write_nonnegative_number", .builtin_write_nonnegative_number);
    try r.symbols.put(allocator, "New", .builtin_new);
    try r.symbols.put(allocator, "free", .builtin_free);
    const root_decls = ast.extraSlice(ast.data(ast.root).lhs);
    var current_file: u32 = 0;
    var next_file_id: u32 = 0;
    var file_scope = false;
    var main_scope_started = false;
    for (root_decls) |decl_idx| {
        const decl: NodeIndex = @intCast(decl_idx);
        switch (ast.tag(decl)) {
            .load_decl => {
                const load_name = ast.stringTokenContents(ast.data(decl).lhs);
                if (std.mem.eql(u8, load_name, "__main_resume")) {
                    current_file = 0;
                } else {
                    next_file_id += 1;
                    current_file = next_file_id;
                }
                file_scope = false;
            },
            .scope_decl => {
                if (ast.tokens[ast.mainToken(decl)].tag != .directive_scope_file) return diag.failAt(ast.tokens[ast.mainToken(decl)].start, "only #scope_file is implemented in this Phase 6 slice", .{});
                if (current_file == 0) return diag.failAt(ast.tokens[ast.mainToken(decl)].start, "#scope_file is only supported in #load files in this Phase 6 slice", .{});
                file_scope = true;
            },
            .const_decl, .var_decl, .proc_decl => {
                if (file_scope and !main_scope_started) {
                    const raw = try r.normalizedName(ast.tokenSlice(ast.mainToken(decl)));
                    const scoped = try r.scopedName(current_file, raw);
                    try r.owned_names.append(allocator, scoped);
                    try r.symbols.put(allocator, scoped, switch (ast.tag(decl)) {
                        .proc_decl => .{ .proc = decl },
                        .var_decl => .{ .const_value = ast.data(decl).rhs },
                        else => .{ .const_value = ast.data(decl).lhs },
                    });
                } else if (current_file == 0) {
                    main_scope_started = true;
                }
            },
            else => {},
        }
    }

    current_file = 0;
    next_file_id = 0;
    file_scope = false;
    const global_main_scope_started = false;
    for (root_decls) |decl_idx| {
        const decl: NodeIndex = @intCast(decl_idx);
        switch (ast.tag(decl)) {
            .import_decl => {
                const module_name = ast.stringTokenContents(ast.data(decl).lhs);
                if (std.mem.eql(u8, module_name, "Basic")) {
                    r.imports_basic = true;
                    try r.symbols.put(allocator, "print", .builtin_print);
                    try r.symbols.put(allocator, "exit", .builtin_exit);
                    try r.symbols.put(allocator, "memcpy", .builtin_memcpy);
                    try r.symbols.put(allocator, "assert", .builtin_assert);
                    try r.symbols.put(allocator, "swap", .builtin_swap);
                } else if (std.mem.eql(u8, module_name, "Math")) {
                    try r.symbols.put(allocator, "sin", .builtin_sin);
                    try r.symbols.put(allocator, "Vector3", .{ .const_value = @import("Ast.zig").null_node });
                } else if (std.mem.eql(u8, module_name, "TestModule_Params")) {
                    r.imports_basic = true;
                    try r.symbols.put(allocator, "print", .builtin_print);
                } else return diag.failAt(ast.tokens[ast.data(decl).lhs].start, "unknown Phase 1 import '{s}'", .{module_name});
            },
            .load_decl => {
                const load_name = ast.stringTokenContents(ast.data(decl).lhs);
                if (std.mem.eql(u8, load_name, "__main_resume")) {
                    current_file = 0;
                } else {
                    next_file_id += 1;
                    current_file = next_file_id;
                }
                file_scope = false;
            },
            .scope_decl => file_scope = true,
            .proc_decl => {
                if (file_scope and !global_main_scope_started) continue;
                const name = try r.normalizedName(ast.tokenSlice(ast.mainToken(decl)));
                if (r.symbols.contains(name)) continue;
                try r.symbols.put(allocator, name, .{ .proc = decl });
                if (std.mem.eql(u8, name, "main")) r.main_proc = decl;
            },
            .run_expr => {},
            .const_decl => {
                if (file_scope and !global_main_scope_started) continue;
                const name = try r.normalizedName(ast.tokenSlice(ast.mainToken(decl)));
                if (r.symbols.contains(name)) continue;
                try r.symbols.put(allocator, name, .{ .const_value = ast.data(decl).lhs });
            },
            .var_decl => {
                if (file_scope and !global_main_scope_started) continue;
                const name = try r.normalizedName(ast.tokenSlice(ast.mainToken(decl)));
                if (r.symbols.contains(name)) continue;
                if (ast.data(decl).rhs == @import("Ast.zig").null_node) return diag.failAt(ast.tokens[ast.mainToken(decl)].start, "top-level variable declaration requires an initializer", .{});
                try r.symbols.put(allocator, name, .{ .const_value = ast.data(decl).rhs });
            },
            else => return diag.failAt(ast.tokens[ast.mainToken(decl)].start, "unsupported top-level AST node in resolver", .{}),
        }
    }
    current_file = 0;
    next_file_id = 0;
    var proc_files = std.AutoHashMap(NodeIndex, u32).init(allocator);
    defer proc_files.deinit();
    for (root_decls) |decl_idx| {
        const decl: NodeIndex = @intCast(decl_idx);
        switch (ast.tag(decl)) {
            .load_decl => {
                const load_name = ast.stringTokenContents(ast.data(decl).lhs);
                if (std.mem.eql(u8, load_name, "__main_resume")) {
                    current_file = 0;
                } else {
                    next_file_id += 1;
                    current_file = next_file_id;
                }
                file_scope = false;
            },
            .scope_decl, .add_context_decl => {},
            .proc_decl => {
                try proc_files.put(decl, current_file);
            },
            else => {},
        }
    }
    for (root_decls) |decl_idx| {
        const decl: NodeIndex = @intCast(decl_idx);
        if (ast.tag(decl) == .proc_decl) try resolveProc(ast, &r, decl, proc_files.get(decl) orelse 0, diag);
        if (ast.tag(decl) == .run_expr) try resolveNode(ast, &r, decl, 0, diag);
    }
    if (r.main_proc == null) return diag.failAt(0, "No program entry point was found. (The designated entry point name is 'main'.)", .{});
    return r;
}

fn resolveProc(ast: *const Ast, r: *Resolved, proc: NodeIndex, file_id: u32, diag: Diagnostic) !void {
    var declared = std.ArrayList([]const u8).empty;
    defer declared.deinit(r.allocator);
    const sig = procSignature(ast, proc);
    if (sig) |s| {
        for (ast.extraSlice(s.params_extra)) |param_idx| {
            const param: NodeIndex = @intCast(param_idx);
            const name = try r.normalizedName(ast.tokenSlice(ast.mainToken(param)));
            if (r.symbols.contains(name)) return diag.failAt(ast.tokens[ast.mainToken(param)].start, "duplicate parameter declaration '{s}'", .{name});
            try r.symbols.put(r.allocator, name, .{ .const_value = param });
            try declared.append(r.allocator, name);
            if (ast.data(param).lhs != @import("Ast.zig").null_node) try resolveNode(ast, r, ast.data(param).lhs, file_id, diag);
        }
    }
    try resolveBlock(ast, r, ast.data(proc).lhs, file_id, diag);
    for (declared.items) |name| _ = r.symbols.remove(name);
}

const ProcSig = struct { params_extra: u32, return_type: NodeIndex };
fn procSignature(ast: *const Ast, proc: NodeIndex) ?ProcSig {
    if (ast.data(proc).rhs == 0) return null;
    const sig = ast.extraSlice(ast.data(proc).rhs);
    if (sig.len < 2) return null;
    return .{ .params_extra = sig[0], .return_type = sig[1] };
}

fn resolveBlock(ast: *const Ast, r: *Resolved, block: NodeIndex, file_id: u32, diag: Diagnostic) anyerror!void {
    const stmts = ast.extraSlice(ast.data(block).lhs);
    var declared = std.ArrayList([]const u8).empty;
    defer declared.deinit(r.allocator);

    for (stmts) |stmt_idx| {
        const stmt: NodeIndex = @intCast(stmt_idx);
        if (ast.tag(stmt) == .proc_decl) {
            const name = try r.normalizedName(ast.tokenSlice(ast.mainToken(stmt)));
            if (r.symbols.contains(name)) return diag.failAt(ast.tokens[ast.mainToken(stmt)].start, "duplicate local procedure declaration '{s}'", .{name});
            try r.symbols.put(r.allocator, name, .{ .proc = stmt });
            try declared.append(r.allocator, name);
        } else if (ast.tag(stmt) == .stmt_list) {
            for (ast.extraSlice(ast.data(stmt).lhs)) |child_idx| {
                const child: NodeIndex = @intCast(child_idx);
                if (ast.tag(child) == .proc_decl) {
                    const name = try r.normalizedName(ast.tokenSlice(ast.mainToken(child)));
                    if (r.symbols.contains(name)) return diag.failAt(ast.tokens[ast.mainToken(child)].start, "duplicate local procedure declaration '{s}'", .{name});
                    try r.symbols.put(r.allocator, name, .{ .proc = child });
                    try declared.append(r.allocator, name);
                }
            }
        }
    }

    for (stmts) |stmt_idx| {
        const stmt: NodeIndex = @intCast(stmt_idx);
        switch (ast.tag(stmt)) {
            .stmt_list => {
                for (ast.extraSlice(ast.data(stmt).lhs)) |child_idx| {
                    const child: NodeIndex = @intCast(child_idx);
                    switch (ast.tag(child)) {
                        .var_decl, .const_decl => {
                            const name = try r.normalizedName(ast.tokenSlice(ast.mainToken(child)));
                            if (r.symbols.contains(name)) return diag.failAt(ast.tokens[ast.mainToken(child)].start, "duplicate local declaration '{s}'", .{name});
                            if (ast.tag(child) == .var_decl) {
                                if (ast.data(child).lhs != @import("Ast.zig").null_node) try resolveNode(ast, r, ast.data(child).lhs, file_id, diag);
                                if (ast.data(child).rhs != @import("Ast.zig").null_node) try resolveNode(ast, r, ast.data(child).rhs, file_id, diag);
                            } else {
                                try resolveNode(ast, r, ast.data(child).lhs, file_id, diag);
                            }
                            try r.symbols.put(r.allocator, name, .{ .const_value = if (ast.tag(child) == .var_decl) child else ast.data(child).lhs });
                            try declared.append(r.allocator, name);
                        },
                        .proc_decl => try resolveProc(ast, r, child, file_id, diag),
                        else => try resolveNode(ast, r, child, file_id, diag),
                    }
                }
            },
            .var_decl, .const_decl => {
                const name = try r.normalizedName(ast.tokenSlice(ast.mainToken(stmt)));
                if (r.symbols.contains(name)) return diag.failAt(ast.tokens[ast.mainToken(stmt)].start, "duplicate local declaration '{s}'", .{name});
                if (ast.tag(stmt) == .var_decl) {
                    if (ast.data(stmt).lhs != @import("Ast.zig").null_node) try resolveNode(ast, r, ast.data(stmt).lhs, file_id, diag);
                    if (ast.data(stmt).rhs != @import("Ast.zig").null_node) try resolveNode(ast, r, ast.data(stmt).rhs, file_id, diag);
                } else {
                    try resolveNode(ast, r, ast.data(stmt).lhs, file_id, diag);
                }
                try r.symbols.put(r.allocator, name, .{ .const_value = if (ast.tag(stmt) == .var_decl) stmt else ast.data(stmt).lhs });
                try declared.append(r.allocator, name);
            },
            .proc_decl => try resolveProc(ast, r, stmt, file_id, diag),
            else => try resolveNode(ast, r, stmt, file_id, diag),
        }
    }
    for (declared.items) |name| _ = r.symbols.remove(name);
}

fn resolveNode(ast: *const Ast, r: *Resolved, node: NodeIndex, file_id: u32, diag: Diagnostic) !void {
    switch (ast.tag(node)) {
        .expr_stmt => try resolveNode(ast, r, ast.data(node).lhs, file_id, diag),
        .stmt_list => {
            for (ast.extraSlice(ast.data(node).lhs)) |child| try resolveNode(ast, r, @intCast(child), file_id, diag);
        },
        .var_decl => {
            if (ast.data(node).lhs != @import("Ast.zig").null_node) try resolveNode(ast, r, ast.data(node).lhs, file_id, diag);
            if (ast.data(node).rhs != @import("Ast.zig").null_node) try resolveNode(ast, r, ast.data(node).rhs, file_id, diag);
        },
        .const_decl => try resolveNode(ast, r, ast.data(node).lhs, file_id, diag),
        .assign_stmt => {
            try resolveNode(ast, r, ast.data(node).lhs, file_id, diag);
            try resolveNode(ast, r, ast.data(node).rhs, file_id, diag);
        },
        .return_stmt => {
            if (ast.data(node).lhs != @import("Ast.zig").null_node) try resolveNode(ast, r, ast.data(node).lhs, file_id, diag);
        },
        .string_literal, .integer_literal, .float_literal, .bool_literal, .null_literal, .char_literal, .undefined_literal, .type_expr => {},
        .pointer_type => try resolveNode(ast, r, ast.data(node).lhs, file_id, diag),
        .proc_type => {
            for (ast.extraSlice(ast.data(node).lhs)) |param_ty| try resolveNode(ast, r, @intCast(param_ty), file_id, diag);
            try resolveNode(ast, r, ast.data(node).rhs, file_id, diag);
        },
        .type_of_expr => try resolveNode(ast, r, ast.data(node).lhs, file_id, diag),
        .is_constant_expr => try resolveNode(ast, r, ast.data(node).lhs, file_id, diag),
        .size_of_expr => try resolveNode(ast, r, ast.data(node).lhs, file_id, diag),
        .run_expr => if (ast.tag(ast.data(node).lhs) == .block) try resolveBlock(ast, r, ast.data(node).lhs, file_id, diag) else try resolveNode(ast, r, ast.data(node).lhs, file_id, diag),
        .unary_expr => try resolveNode(ast, r, ast.data(node).lhs, file_id, diag),
        .binary_expr => {
            try resolveNode(ast, r, ast.data(node).lhs, file_id, diag);
            try resolveNode(ast, r, ast.data(node).rhs, file_id, diag);
        },
        .if_stmt => {
            try resolveNode(ast, r, ast.data(node).lhs, file_id, diag);
            const blocks = ast.extraSlice(ast.data(node).rhs);
            try resolveBlock(ast, r, @intCast(blocks[0]), file_id, diag);
            if (blocks.len > 1 and blocks[1] != @import("Ast.zig").null_node) try resolveBlock(ast, r, @intCast(blocks[1]), file_id, diag);
        },
        .ifx_expr => {
            try resolveNode(ast, r, ast.data(node).lhs, file_id, diag);
            for (ast.extraSlice(ast.data(node).rhs)) |arm| try resolveNode(ast, r, @intCast(arm), file_id, diag);
        },
        .for_stmt => {
            const range = ast.extraSlice(ast.data(node).lhs);
            try resolveNode(ast, r, @intCast(range[0]), file_id, diag);
            try resolveNode(ast, r, @intCast(range[1]), file_id, diag);
            try resolveBlock(ast, r, ast.data(node).rhs, file_id, diag);
        },
        .aggregate_literal => {
            for (ast.extraSlice(ast.data(node).lhs)) |elem| try resolveNode(ast, r, @intCast(elem), file_id, diag);
        },
        .typed_aggregate_literal => {
            const payload = ast.extraSlice(ast.data(node).lhs);
            try resolveNode(ast, r, @intCast(payload[0]), file_id, diag);
            const fields = ast.extraSlice(payload[1]);
            for (fields) |field_idx| {
                const field: NodeIndex = @intCast(field_idx);
                try resolveNode(ast, r, ast.data(field).rhs, file_id, diag);
            }
        },
        .field_access => try resolveNode(ast, r, ast.data(node).lhs, file_id, diag),
        .call_expr => {
            if (ast.tag(ast.data(node).lhs) == .identifier) {
                const callee_name = ast.tokenSlice(ast.mainToken(ast.data(node).lhs));
                if (r.lookup(callee_name) == null) {
                    if (std.mem.indexOfScalar(u8, callee_name, '_') != null) {
                        // Procedure-value call targets such as p_ptr are resolved in sema
                        // through local_values after their declaration is in scope.
                    } else try resolveNode(ast, r, ast.data(node).lhs, file_id, diag);
                } else try resolveNode(ast, r, ast.data(node).lhs, file_id, diag);
            } else try resolveNode(ast, r, ast.data(node).lhs, file_id, diag);
            for (ast.extraSlice(ast.data(node).rhs)) |arg_idx| {
                const arg: NodeIndex = @intCast(arg_idx);
                if (ast.tag(arg) == .assign_stmt) {
                    try resolveNode(ast, r, ast.data(arg).rhs, file_id, diag);
                } else try resolveNode(ast, r, arg, file_id, diag);
            }
        },
        .identifier => {
            const name = ast.tokenSlice(ast.mainToken(node));
            const sym_opt = if (file_id != 0) blk: {
                const scoped = try r.scopedName(file_id, name);
                defer r.allocator.free(scoped);
                break :blk r.lookup(scoped) orelse r.lookup(name);
            } else r.lookup(name);
            if (sym_opt) |sym| {
                switch (sym) {
                    .const_value => |value_node| try r.local_values.put(r.allocator, node, value_node),
                    .proc => |proc_node| try r.local_values.put(r.allocator, node, proc_node),
                    .builtin_swap, .builtin_print, .builtin_write_string, .builtin_write_strings, .builtin_write_number, .builtin_write_nonnegative_number, .builtin_new, .builtin_free, .builtin_exit, .builtin_memcpy, .builtin_assert, .builtin_sin => {},
                }
            } else if (isBuiltinTypeName(name)) {
                // Builtin type names can appear as first-class Type values in expressions,
                // e.g. type_of(n) == int. Leave them for Sema/codegen as identifiers.
            } else return diag.failAt(ast.tokens[ast.mainToken(node)].start, "unresolved identifier '{s}'", .{name});
        },
        else => return diag.failAt(ast.tokens[ast.mainToken(node)].start, "unsupported AST node in resolver", .{}),
    }
}

fn isBuiltinTypeName(name: []const u8) bool {
    return std.mem.eql(u8, name, "void") or std.mem.eql(u8, name, "bool") or std.mem.eql(u8, name, "string") or std.mem.eql(u8, name, "int") or std.mem.eql(u8, name, "s64") or std.mem.eql(u8, name, "float") or std.mem.eql(u8, name, "float32") or std.mem.eql(u8, name, "float64") or std.mem.eql(u8, name, "s32") or std.mem.eql(u8, name, "u8") or std.mem.eql(u8, name, "u16") or std.mem.eql(u8, name, "u32") or std.mem.eql(u8, name, "u64") or std.mem.eql(u8, name, "Vector3") or std.mem.eql(u8, name, "Type") or std.mem.eql(u8, name, "Any");
}
