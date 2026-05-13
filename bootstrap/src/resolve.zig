const std = @import("std");
const Ast = @import("Ast.zig").Ast;
const Node = @import("Ast.zig").Node;
const NodeIndex = @import("Ast.zig").NodeIndex;
const Diagnostic = @import("diagnostics.zig").Diagnostic;
const using_param_sentinel: u32 = 0xfffffffe;

pub const Symbol = union(enum) {
    proc: NodeIndex,
    placeholder,
    builtin_print,
    builtin_swap,
    builtin_write_string,
    builtin_write_strings,
    builtin_write_number,
    builtin_write_nonnegative_number,
    builtin_new,
    builtin_new_array,
    builtin_free,
    builtin_exit,
    builtin_memcpy,
    builtin_memset,
    builtin_assert,
    builtin_sin,
    builtin_current_time_consensus,
    builtin_current_time_monotonic,
    builtin_to_calendar,
    builtin_calendar_to_string,
    builtin_random_seed,
    builtin_random_get,
    builtin_random_get_zero_to_one,
    builtin_random_get_within_range,
    builtin_compiler_arg_count,
    builtin_compiler_arg,
    builtin_compiler_read_file,
    builtin_compiler_write_file,
    builtin_get_command_line_arguments,
    builtin_get_cpu_info,
    builtin_check_feature,
    builtin_make_directory_if_it_does_not_exist,
    builtin_delete_directory,
    builtin_file_exists,
    builtin_set_working_directory,
    builtin_get_working_directory,
    builtin_visit_files,
    builtin_get_path_of_running_executable,
    builtin_read_entire_file,
    builtin_write_entire_file,
    builtin_file_open,
    builtin_file_close,
    builtin_file_length,
    builtin_file_set_position,
    builtin_file_write,
    builtin_file_read,
    builtin_posix_read,
    builtin_get_std_handle,
    builtin_reset_temporary_storage,
    builtin_talloc_string,
    builtin_make_leak_report,
    builtin_log_leak_report,
    builtin_push_allocator,
    builtin_sprint,
    builtin_tprint,
    builtin_to_string,
    builtin_to_c_string,
    builtin_copy_string,
    builtin_string_builder_type,
    builtin_init_string_builder,
    builtin_free_buffers,
    builtin_append,
    builtin_print_to_builder,
    builtin_builder_string_length,
    builtin_builder_to_string,
    builtin_compare,
    builtin_contains,
    builtin_begins_with,
    builtin_split,
    builtin_trim,
    builtin_join,
    builtin_find_index_from_left,
    builtin_find_index_from_right,
    builtin_string_to_int,
    builtin_string_to_float,
    builtin_parse_int,
    builtin_to_integer,
    builtin_replace,
    builtin_slice,
    builtin_path_strip_filename,
    builtin_c_style_strlen,
    builtin_format_int,
    builtin_format_float,
    builtin_get_type_table,
    builtin_alloc,
    builtin_array_add,
    builtin_array_free,
    builtin_peek,
    builtin_pop,
    builtin_array_reset,
    builtin_array_reserve,
    builtin_array_ordered_remove_by_index,
    builtin_array_find,
    builtin_array_copy,
    builtin_get_time,
    builtin_seconds_since_init,
    builtin_sleep_milliseconds,
    builtin_to_float64_seconds,
    builtin_format_struct,
    builtin_to_upper,
    builtin_to_lower,
    builtin_is_digit,
    builtin_is_alpha,
    builtin_is_alnum,
    builtin_is_space,
    builtin_is_any,
    builtin_log,
    builtin_get_field,
    builtin_type_to_string,
    builtin_enum_range,
    builtin_enum_values_as_s64,
    builtin_enum_names,
    builtin_abs,
    const_value: NodeIndex,
};

pub const Resolved = struct {
    allocator: std.mem.Allocator,
    symbols: std.StringHashMapUnmanaged(Symbol) = .empty,
    explicit_placeholders: std.StringHashMapUnmanaged(void) = .empty,
    used_explicit_placeholders: std.StringHashMapUnmanaged(void) = .empty,
    implicit_placeholders: std.StringHashMapUnmanaged(void) = .empty,
    used_implicit_placeholders: std.StringHashMapUnmanaged(void) = .empty,
    local_values: std.AutoHashMapUnmanaged(NodeIndex, NodeIndex) = .empty,
    loop_value_types: std.AutoHashMapUnmanaged(NodeIndex, u32) = .empty,
    loop_indexes: std.AutoHashMapUnmanaged(NodeIndex, u32) = .empty,
    using_fallbacks: std.ArrayListUnmanaged(NodeIndex) = .empty,
    owned_names: std.ArrayList([]u8) = .empty,
    proc_overloads: std.StringHashMapUnmanaged(std.ArrayListUnmanaged(NodeIndex)) = .empty,
    external_names: std.StringHashMapUnmanaged(void) = .empty,
    imports_basic: bool = false,
    main_proc: ?NodeIndex = null,
    require_main: bool = true,

    pub fn deinit(r: *Resolved) void {
        var it = r.proc_overloads.iterator();
        while (it.next()) |entry| entry.value_ptr.deinit(r.allocator);
        r.proc_overloads.deinit(r.allocator);
        r.used_explicit_placeholders.deinit(r.allocator);
        r.explicit_placeholders.deinit(r.allocator);
        r.used_implicit_placeholders.deinit(r.allocator);
        r.implicit_placeholders.deinit(r.allocator);
        r.external_names.deinit(r.allocator);
        r.symbols.deinit(r.allocator);
        r.local_values.deinit(r.allocator);
        r.loop_value_types.deinit(r.allocator);
        r.loop_indexes.deinit(r.allocator);
        r.using_fallbacks.deinit(r.allocator);
        for (r.owned_names.items) |name| r.allocator.free(name);
        r.owned_names.deinit(r.allocator);
    }

    pub fn implicitPlaceholderCount(r: *const Resolved) u32 {
        return @intCast(r.implicit_placeholders.count());
    }

    pub fn usedImplicitPlaceholderCount(r: *const Resolved) u32 {
        return @intCast(r.used_implicit_placeholders.count());
    }

    pub fn explicitPlaceholderCount(r: *const Resolved) u32 {
        return @intCast(r.explicit_placeholders.count());
    }

    pub fn usedExplicitPlaceholderCount(r: *const Resolved) u32 {
        return @intCast(r.used_explicit_placeholders.count());
    }

    pub fn failIfImplicitPlaceholders(r: *const Resolved, diag: Diagnostic) !void {
        if (r.used_implicit_placeholders.count() == 0) return;

        var names = std.ArrayList([]const u8).empty;
        defer names.deinit(r.allocator);
        var it = r.used_implicit_placeholders.keyIterator();
        while (it.next()) |name| try names.append(r.allocator, name.*);
        std.mem.sort([]const u8, names.items, {}, struct {
            fn lessThan(_: void, lhs: []const u8, rhs: []const u8) bool {
                return std.mem.lessThan(u8, lhs, rhs);
            }
        }.lessThan);

        std.debug.print("implicit placeholder symbols:\n", .{});
        for (names.items) |name| std.debug.print("  {s}\n", .{name});
        return diag.failAt(0, "implicit placeholder symbols are disabled; first used placeholder is '{s}' ({d} used, {d} accepted)", .{ names.items[0], names.items.len, r.implicit_placeholders.count() });
    }

    pub fn failIfUsedExplicitPlaceholders(r: *const Resolved, diag: Diagnostic) !void {
        if (r.used_explicit_placeholders.count() == 0) return;

        var names = std.ArrayList([]const u8).empty;
        defer names.deinit(r.allocator);
        var it = r.used_explicit_placeholders.keyIterator();
        while (it.next()) |name| try names.append(r.allocator, name.*);
        std.mem.sort([]const u8, names.items, {}, struct {
            fn lessThan(_: void, lhs: []const u8, rhs: []const u8) bool {
                return std.mem.lessThan(u8, lhs, rhs);
            }
        }.lessThan);

        std.debug.print("unresolved explicit placeholder symbols:\n", .{});
        for (names.items) |name| std.debug.print("  {s}\n", .{name});
        return diag.failAt(0, "explicit placeholder '{s}' was used but never fulfilled by generated source", .{names.items[0]});
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

    pub fn overloads(r: *const Resolved, name: []const u8) ?[]const NodeIndex {
        if (r.proc_overloads.get(name)) |list| return list.items;
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
        if (r.proc_overloads.get(buf[0..len])) |list| return list.items;
        return null;
    }

    fn addProc(r: *Resolved, name: []const u8, proc: NodeIndex) !void {
        var entry = try r.proc_overloads.getOrPut(r.allocator, name);
        if (!entry.found_existing) entry.value_ptr.* = .empty;
        try entry.value_ptr.append(r.allocator, proc);
        if (r.symbols.get(name)) |sym| {
            if (sym == .placeholder) {
                _ = r.explicit_placeholders.remove(name);
                _ = r.used_explicit_placeholders.remove(name);
                _ = r.implicit_placeholders.remove(name);
                _ = r.used_implicit_placeholders.remove(name);
                try r.symbols.put(r.allocator, name, .{ .proc = proc });
            }
        } else try r.symbols.put(r.allocator, name, .{ .proc = proc });
    }

    fn putRealSymbol(r: *Resolved, name: []const u8, sym: Symbol) !void {
        if (r.symbols.get(name)) |existing| {
            if (existing != .placeholder) return;
            _ = r.explicit_placeholders.remove(name);
            _ = r.used_explicit_placeholders.remove(name);
            _ = r.implicit_placeholders.remove(name);
            _ = r.used_implicit_placeholders.remove(name);
        }
        try r.symbols.put(r.allocator, name, sym);
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

fn putExternalSymbols(r: *Resolved, names: []const []const u8) !void {
    for (names) |name| try r.putRealSymbol(name, .{ .const_value = @import("Ast.zig").null_node });
}

fn putExplicitPlaceholder(r: *Resolved, allocator: std.mem.Allocator, name: []const u8) !void {
    if (r.symbols.get(name)) |sym| {
        if (sym == .placeholder) {
            _ = r.implicit_placeholders.remove(name);
            _ = r.used_implicit_placeholders.remove(name);
            try r.explicit_placeholders.put(allocator, name, {});
        }
        return;
    }
    try r.symbols.put(allocator, name, .placeholder);
    try r.explicit_placeholders.put(allocator, name, {});
}

fn markImplicitPlaceholderUse(r: *Resolved, allocator: std.mem.Allocator, name: []const u8) !void {
    if (r.implicit_placeholders.contains(name)) try r.used_implicit_placeholders.put(allocator, name, {});
    if (r.explicit_placeholders.contains(name)) try r.used_explicit_placeholders.put(allocator, name, {});
}

fn putStringBuiltins(r: *Resolved) !void {
    try r.putRealSymbol("sprint", .builtin_sprint);
    try r.putRealSymbol("tprint", .builtin_tprint);
    try r.putRealSymbol("to_string", .builtin_to_string);
    try r.putRealSymbol("to_c_string", .builtin_to_c_string);
    try r.putRealSymbol("copy_string", .builtin_copy_string);
    try r.putRealSymbol("String_Builder", .builtin_string_builder_type);
    try r.putRealSymbol("init_string_builder", .builtin_init_string_builder);
    try r.putRealSymbol("free_buffers", .builtin_free_buffers);
    try r.putRealSymbol("append", .builtin_append);
    try r.putRealSymbol("print_to_builder", .builtin_print_to_builder);
    try r.putRealSymbol("builder_string_length", .builtin_builder_string_length);
    try r.putRealSymbol("builder_to_string", .builtin_builder_to_string);
    try r.putRealSymbol("compare", .builtin_compare);
    try r.putRealSymbol("contains", .builtin_contains);
    try r.putRealSymbol("split", .builtin_split);
    try r.putRealSymbol("trim", .builtin_trim);
    try r.putRealSymbol("join", .builtin_join);
    try r.putRealSymbol("string_to_int", .builtin_string_to_int);
    try r.putRealSymbol("string_to_float", .builtin_string_to_float);
    try r.putRealSymbol("parse_int", .builtin_parse_int);
    try r.putRealSymbol("to_integer", .builtin_to_integer);
    try r.putRealSymbol("replace", .builtin_replace);
    try r.putRealSymbol("slice", .builtin_slice);
    try r.putRealSymbol("path_strip_filename", .builtin_path_strip_filename);
    try r.putRealSymbol("c_style_strlen", .builtin_c_style_strlen);
}

fn putCompilerModuleSymbols(r: *Resolved) !void {
    try putStringBuiltins(r);
    for (&[_][]const u8{
        "compiler_create_workspace",
        "get_build_options",
        "set_build_options",
        "set_build_options_dc",
        "compiler_begin_intercept",
        "compiler_wait_for_message",
        "compiler_end_intercept",
        "add_build_file",
        "add_build_string",
        "run_command",
        "set_optimization",
        "compiler_get_nodes",
        "compiler_get_code",
        "print_expression",
        "is_subclass_of",
        "get_current_workspace",
        "Optimization_Type",
        "Message_Complete",
        "compiler_set_workspace_status",
        "compiler_custom_link_command_is_complete",
        "compiler_report",
        "make_location",
        "add_global_data",
        "code_to_string",
        "Message",
        "Message_File",
        "Message_Import",
        "Message_Phase",
        "Message_Typechecked",
        "Message_Debug_Dump",
        "Workspace",
        "Build_Options",
        "Code",
        "Code_Node",
        "Code_Literal",
        "Code_Argument",
        "Code_Procedure_Call",
        "Code_Declaration",
        "Source_Code_Location",
        "Type_Info_Pointer",
    }) |name| {
        try r.putRealSymbol(name, .{ .const_value = @import("Ast.zig").null_node });
    }
}

pub fn resolve(allocator: std.mem.Allocator, ast: *const Ast, diag: Diagnostic, require_main: bool, external_names: []const []const u8) !Resolved {
    var r = Resolved{ .allocator = allocator, .require_main = require_main };
    errdefer r.deinit();
    for (external_names) |name| try r.external_names.put(allocator, name, {});
    try r.symbols.put(allocator, "print", .builtin_print);
    try r.symbols.put(allocator, "write_string", .builtin_write_string);
    try r.symbols.put(allocator, "write_strings", .builtin_write_strings);
    try r.symbols.put(allocator, "write_number", .builtin_write_number);
    try r.symbols.put(allocator, "write_nonnegative_number", .builtin_write_nonnegative_number);
    try r.symbols.put(allocator, "New", .builtin_new);
    try r.symbols.put(allocator, "NewArray", .builtin_new_array);
    try r.symbols.put(allocator, "free", .builtin_free);
    try r.symbols.put(allocator, "compiler_arg_count", .builtin_compiler_arg_count);
    try r.symbols.put(allocator, "compiler_arg", .builtin_compiler_arg);
    try r.symbols.put(allocator, "compiler_read_file", .builtin_compiler_read_file);
    try r.symbols.put(allocator, "compiler_write_file", .builtin_compiler_write_file);
    try r.symbols.put(allocator, "read_entire_file", .builtin_read_entire_file);
    try r.symbols.put(allocator, "write_entire_file", .builtin_write_entire_file);
    try r.putRealSymbol("context", .{ .const_value = @import("Ast.zig").null_node });
    try r.symbols.put(allocator, "reset_temporary_storage", .builtin_reset_temporary_storage);
    try r.symbols.put(allocator, "push_allocator", .builtin_push_allocator);
    try r.putRealSymbol("For_Flags", .{ .const_value = @import("Ast.zig").null_node });
    try r.putRealSymbol("temp", .{ .const_value = @import("Ast.zig").null_node });
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
                switch (ast.tokens[ast.mainToken(decl)].tag) {
                    .directive_scope_file => {
                        file_scope = true;
                    },
                    .directive_scope_export, .directive_scope_module => file_scope = false,
                    else => return diag.failAt(ast.tokens[ast.mainToken(decl)].start, "unsupported scope directive", .{}),
                }
            },
            .const_decl, .var_decl, .proc_decl, .placeholder_decl => {
                if (file_scope) {
                    const raw = try r.normalizedName(ast.tokenSlice(ast.mainToken(decl)));
                    const scoped = try r.scopedName(current_file, raw);
                    try r.owned_names.append(allocator, scoped);
                    if (ast.tag(decl) == .proc_decl) {
                        try r.addProc(scoped, decl);
                    } else if (ast.tag(decl) == .placeholder_decl) {
                        try putExplicitPlaceholder(&r, allocator, scoped);
                    } else {
                        try r.putRealSymbol(scoped, switch (ast.tag(decl)) {
                            .var_decl => .{ .const_value = decl },
                            else => .{ .const_value = ast.data(decl).lhs },
                        });
                    }
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
                if (ast.data(decl).rhs != 0) {
                    if (std.mem.eql(u8, module_name, "raylib")) {
                        try putExternalSymbols(&r, &.{
                            "InitWindow",       "CloseWindow",     "SetTargetFPS", "WindowShouldClose",
                            "GetScreenWidth",   "GetScreenHeight", "GetFrameTime", "BeginDrawing",
                            "EndDrawing",       "ClearBackground", "DrawText",     "DrawRectangle",
                            "DrawRectangleRec", "DrawCircle",      "PI",
                        });
                    } else if (std.mem.eql(u8, module_name, "Basic")) {
                        r.imports_basic = true;
                        try r.symbols.put(allocator, "memcpy", .builtin_memcpy);
                        try r.symbols.put(allocator, "memset", .builtin_memset);
                    }
                    continue;
                }
                if (std.mem.eql(u8, module_name, "Basic")) {
                    r.imports_basic = true;
                    try r.symbols.put(allocator, "print", .builtin_print);
                    try r.symbols.put(allocator, "exit", .builtin_exit);
                    try r.symbols.put(allocator, "memcpy", .builtin_memcpy);
                    try r.symbols.put(allocator, "memset", .builtin_memset);
                    try r.symbols.put(allocator, "assert", .builtin_assert);
                    try r.symbols.put(allocator, "swap", .builtin_swap);
                    try r.symbols.put(allocator, "formatInt", .builtin_format_int);
                    try r.symbols.put(allocator, "formatFloat", .builtin_format_float);
                    try r.symbols.put(allocator, "current_time_consensus", .builtin_current_time_consensus);
                    try r.symbols.put(allocator, "current_time_monotonic", .builtin_current_time_monotonic);
                    try r.symbols.put(allocator, "to_calendar", .builtin_to_calendar);
                    try r.symbols.put(allocator, "calendar_to_string", .builtin_calendar_to_string);
                    try r.symbols.put(allocator, "get_time", .builtin_get_time);
                    try r.symbols.put(allocator, "seconds_since_init", .builtin_seconds_since_init);
                    try r.symbols.put(allocator, "sleep_milliseconds", .builtin_sleep_milliseconds);
                    try r.symbols.put(allocator, "to_float64_seconds", .builtin_to_float64_seconds);
                    try r.symbols.put(allocator, "formatStruct", .builtin_format_struct);
                    try r.symbols.put(allocator, "alloc", .builtin_alloc);
                    try r.symbols.put(allocator, "NewArray", .builtin_new_array);
                    try r.symbols.put(allocator, "array_add", .builtin_array_add);
                    try r.symbols.put(allocator, "array_free", .builtin_array_free);
                    try r.symbols.put(allocator, "peek", .builtin_peek);
                    try r.symbols.put(allocator, "pop", .builtin_pop);
                    try r.symbols.put(allocator, "array_reset", .builtin_array_reset);
                    try r.symbols.put(allocator, "array_reserve", .builtin_array_reserve);
                    try r.symbols.put(allocator, "array_ordered_remove_by_index", .builtin_array_ordered_remove_by_index);
                    try r.symbols.put(allocator, "array_find", .builtin_array_find);
                    try r.symbols.put(allocator, "array_copy", .builtin_array_copy);
                    try r.symbols.put(allocator, "talloc_string", .builtin_talloc_string);
                    try r.symbols.put(allocator, "make_leak_report", .builtin_make_leak_report);
                    try r.symbols.put(allocator, "log_leak_report", .builtin_log_leak_report);
                    try r.symbols.put(allocator, "write_string", .builtin_write_string);
                    try r.symbols.put(allocator, "log", .builtin_log);
                    try r.symbols.put(allocator, "get_field", .builtin_get_field);
                    try r.symbols.put(allocator, "type_to_string", .builtin_type_to_string);
                    try r.symbols.put(allocator, "enum_range", .builtin_enum_range);
                    try r.symbols.put(allocator, "enum_values_as_s64", .builtin_enum_values_as_s64);
                    try r.symbols.put(allocator, "enum_names", .builtin_enum_names);
                    try r.putRealSymbol("advance", .{ .const_value = @import("Ast.zig").null_node });
                    try r.putRealSymbol("log_error", .{ .const_value = @import("Ast.zig").null_node });
                    try putExternalSymbols(&r, &.{"get_mouse_pointer_position"});
                    try r.symbols.put(allocator, "equal", .builtin_compare);
                    for (&[_][]const u8{ "make_vector2", "make_vector3", "make_vector4", "PI", "sqrt", "cos", "min", "max", "clamp", "get_number_of_processors" }) |name| {
                        try r.putRealSymbol(name, .{ .const_value = @import("Ast.zig").null_node });
                    }
                    try putStringBuiltins(&r);
                    try r.symbols.put(allocator, "get_command_line_arguments", .builtin_get_command_line_arguments);
                    try r.symbols.put(allocator, "file_exists", .builtin_file_exists);
                } else if (std.mem.eql(u8, module_name, "String")) {
                    try r.symbols.put(allocator, "to_upper", .builtin_to_upper);
                    try r.symbols.put(allocator, "to_lower", .builtin_to_lower);
                    try r.symbols.put(allocator, "is_digit", .builtin_is_digit);
                    try r.symbols.put(allocator, "is_alpha", .builtin_is_alpha);
                    try r.symbols.put(allocator, "is_alnum", .builtin_is_alnum);
                    try r.symbols.put(allocator, "is_space", .builtin_is_space);
                    try r.symbols.put(allocator, "is_any", .builtin_is_any);
                    try putStringBuiltins(&r);
                    try r.symbols.put(allocator, "begins_with", .builtin_begins_with);
                    try r.symbols.put(allocator, "find_index_from_left", .builtin_find_index_from_left);
                    try r.symbols.put(allocator, "find_index_from_right", .builtin_find_index_from_right);
                    try r.symbols.put(allocator, "equal", .builtin_compare);
                    try r.putRealSymbol("compare_strings", .{ .const_value = @import("Ast.zig").null_node });
                } else if (std.mem.eql(u8, module_name, "Thread")) {
                    try r.symbols.put(allocator, "sleep_milliseconds", .builtin_sleep_milliseconds);
                    for (&[_][]const u8{
                        "Thread",
                        "Thread_Group",
                        "Thread_Continue_Status",
                        "Mutex",
                        "init",
                        "start",
                        "add_work",
                        "get_completed_work",
                        "shutdown",
                        "lock",
                        "unlock",
                        "thread_init",
                        "thread_start",
                        "thread_deinit",
                        "thread_destroy",
                        "thread_is_done",
                    }) |name| {
                        try r.putRealSymbol(name, .{ .const_value = @import("Ast.zig").null_node });
                    }
                } else if (std.mem.eql(u8, module_name, "Random")) {
                    try r.symbols.put(allocator, "random_seed", .builtin_random_seed);
                    try r.symbols.put(allocator, "random_get", .builtin_random_get);
                    try r.symbols.put(allocator, "random_get_zero_to_one", .builtin_random_get_zero_to_one);
                    try r.symbols.put(allocator, "random_get_within_range", .builtin_random_get_within_range);
                    try r.symbols.put(allocator, "compiler_arg_count", .builtin_compiler_arg_count);
                    try r.symbols.put(allocator, "compiler_arg", .builtin_compiler_arg);
                    try r.symbols.put(allocator, "compiler_read_file", .builtin_compiler_read_file);
                    try r.symbols.put(allocator, "compiler_write_file", .builtin_compiler_write_file);
                } else if (std.mem.eql(u8, module_name, "Math")) {
                    try r.symbols.put(allocator, "sin", .builtin_sin);
                    try r.symbols.put(allocator, "abs", .builtin_abs);
                    try r.symbols.put(allocator, "Vector3", .{ .const_value = @import("Ast.zig").null_node });
                    try r.symbols.put(allocator, "Vector4", .{ .const_value = @import("Ast.zig").null_node });
                    for (&[_][]const u8{ "PI", "make_vector2", "make_vector3", "make_vector4", "sqrt", "cos", "min", "max", "clamp" }) |name| {
                        try r.putRealSymbol(name, .{ .const_value = @import("Ast.zig").null_node });
                    }
                } else if (std.mem.eql(u8, module_name, "TestModule_Params")) {
                    r.imports_basic = true;
                    try r.symbols.put(allocator, "print", .builtin_print);
                } else if (std.mem.eql(u8, module_name, "Compiler")) {
                    try r.symbols.put(allocator, "get_type_table", .builtin_get_type_table);
                    try putCompilerModuleSymbols(&r);
                } else if (std.mem.eql(u8, module_name, "Input") or
                    std.mem.eql(u8, module_name, "Window_Creation") or
                    std.mem.eql(u8, module_name, "Simp") or
                    std.mem.eql(u8, module_name, "GL") or
                    std.mem.eql(u8, module_name, "SDL") or
                    std.mem.eql(u8, module_name, "Hash_Table") or
                    std.mem.eql(u8, module_name, "Pool") or
                    std.mem.eql(u8, module_name, "Flat_Pool") or
                    std.mem.eql(u8, module_name, "rpmalloc") or
                    std.mem.eql(u8, module_name, "GetRect") or
                    std.mem.eql(u8, module_name, "Sound_Player") or
                    std.mem.eql(u8, module_name, "glfw") or
                    std.mem.eql(u8, module_name, "Bindings_Generator") or
                    std.mem.eql(u8, module_name, "Wav_File"))
                {
                    // Placeholder module acceptance until real module loading lands.
                    if (std.mem.eql(u8, module_name, "Input")) {
                        try putExternalSymbols(&r, &.{
                            "events_this_frame",          "update_window_events",
                            "SDL_INIT_VIDEO",             "SDL_Init",
                            "SDL_GL_GetProcAddress",      "get_window_resizes",
                            "get_mouse_pointer_position",
                        });
                    } else if (std.mem.eql(u8, module_name, "Window_Creation")) {
                        try putExternalSymbols(&r, &.{ "create_window", "get_render_dimensions" });
                    } else if (std.mem.eql(u8, module_name, "Simp")) {
                        try putExternalSymbols(&r, &.{
                            "get_font_at_size",  "texture_load_from_file", "gl_load",               "DrawTexturePro",  "immediate_quad",  "gl",
                            "set_render_target", "set_shader_for_color",   "clear_render_target",   "swap_buffers",    "update_window",   "immediate_triangle",
                            "load_font",         "draw_text",              "set_shader_for_images", "immediate_begin", "immediate_flush",
                        });
                    } else if (std.mem.eql(u8, module_name, "GL")) {
                        try putExternalSymbols(&r, &.{
                            "gl",
                            "gl_load",
                            "glTexParameteri",
                            "glGetString",
                            "glViewport",
                            "glClearColor",
                            "glClear",
                            "GL_VENDOR",
                            "GL_COLOR_BUFFER_BIT",
                        });
                    } else if (std.mem.eql(u8, module_name, "GetRect")) {
                        try putExternalSymbols(&r, &.{
                            "ui_init",
                            "ui_per_frame_update",
                            "getrect_handle_event",
                            "get_rect",
                            "button",
                            "slider",
                            "dropdown",
                            "draw_popups",
                            "set_default_theme",
                            "default_theme_procs",
                            "getrect_theme",
                        });
                    } else if (std.mem.eql(u8, module_name, "Hash_Table")) {
                        for (&[_][]const u8{ "Table", "table_add", "table_find", "table_remove" }) |name| {
                            try r.putRealSymbol(name, .{ .const_value = @import("Ast.zig").null_node });
                        }
                    } else if (std.mem.eql(u8, module_name, "Pool")) {
                        try r.putRealSymbol("Pool", .{ .const_value = @import("Ast.zig").null_node });
                        try r.putRealSymbol("get", .{ .const_value = @import("Ast.zig").null_node });
                        try r.putRealSymbol("release", .{ .const_value = @import("Ast.zig").null_node });
                        try r.putRealSymbol("reset", .{ .const_value = @import("Ast.zig").null_node });
                        try r.putRealSymbol("set_allocators", .{ .const_value = @import("Ast.zig").null_node });
                        try r.putRealSymbol("pool_allocator_proc", .{ .const_value = @import("Ast.zig").null_node });
                        try r.putRealSymbol("get_capabilities", .{ .const_value = @import("Ast.zig").null_node });
                    } else if (std.mem.eql(u8, module_name, "Flat_Pool")) {
                        try r.putRealSymbol("Flat_Pool", .{ .const_value = @import("Ast.zig").null_node });
                        try r.putRealSymbol("get", .{ .const_value = @import("Ast.zig").null_node });
                        try r.putRealSymbol("reset", .{ .const_value = @import("Ast.zig").null_node });
                        try r.putRealSymbol("fini", .{ .const_value = @import("Ast.zig").null_node });
                        try r.putRealSymbol("flat_pool_allocator_proc", .{ .const_value = @import("Ast.zig").null_node });
                        try r.putRealSymbol("get_capabilities", .{ .const_value = @import("Ast.zig").null_node });
                    } else if (std.mem.eql(u8, module_name, "rpmalloc")) {
                        try r.putRealSymbol("rpmalloc_allocator_proc", .{ .const_value = @import("Ast.zig").null_node });
                        try r.putRealSymbol("get_capabilities", .{ .const_value = @import("Ast.zig").null_node });
                    } else if (std.mem.eql(u8, module_name, "Bindings_Generator")) {
                        for (&[_][]const u8{
                            "Generate_Bindings_Options",
                            "GENERATOR_DEFAULT_SYSTEM_INCLUDE_PATH",
                            "generate_bindings",
                            "copy_file",
                            "libpaths",
                            "libnames",
                            "include_paths",
                            "source_files",
                            "system_include_paths",
                            "extra_clang_arguments",
                            "strip_flags",
                            "header",
                        }) |name| {
                            try r.putRealSymbol(name, .{ .const_value = @import("Ast.zig").null_node });
                        }
                    } else if (std.mem.eql(u8, module_name, "Sound_Player")) {
                        try putExternalSymbols(&r, &.{
                            "init_sound_player",
                            "play_sound",
                            "Sound_Player",
                            "Mixer_Sound_Data",
                            "Sound_Stream",
                            "init",
                            "make_stream",
                            "pre_entity_update",
                            "post_entity_update",
                        });
                    } else if (std.mem.eql(u8, module_name, "Wav_File")) {
                        try putExternalSymbols(&r, &.{ "load_wav_file", "get_wav_header", "Wav_File", "WAVE_FORMAT_PCM", "WAVE_FORMAT_DVI_ADPCM" });
                    } else if (std.mem.eql(u8, module_name, "glfw")) {
                        try putExternalSymbols(&r, &.{
                            "glfwInit",
                            "glfwTerminate",
                            "glfwCreateWindow",
                            "glfwDestroyWindow",
                            "glfwMakeContextCurrent",
                            "glfwWindowShouldClose",
                            "glfwSetWindowShouldClose",
                            "glfwSwapBuffers",
                            "glfwSwapInterval",
                            "glfwPollEvents",
                            "glfwGetKey",
                            "glfwWindowHint",
                            "glfwSetErrorCallback",
                            "glfwSetKeyCallback",
                            "glfwGetFramebufferSize",
                            "glfwGetProcAddress",
                            "glfwGetTime",
                            "GLFW_PRESS",
                            "GLFW_TRUE",
                            "GLFW_KEY_ESCAPE",
                            "GLFW_CONTEXT_VERSION_MAJOR",
                            "GLFW_CONTEXT_VERSION_MINOR",
                            "GLFWwindow",
                            "GLFWmonitor",
                            "GLFWerrorfun",
                            "GLFWkeyfun",
                        });
                    }
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
            .scope_decl => switch (ast.tokens[ast.mainToken(decl)].tag) {
                .directive_scope_file => file_scope = true,
                .directive_scope_export, .directive_scope_module => file_scope = false,
                else => return diag.failAt(ast.tokens[ast.mainToken(decl)].start, "unsupported scope directive", .{}),
            },
            .proc_decl => {
                if (file_scope and !global_main_scope_started) continue;
                const name = try r.normalizedName(ast.tokenSlice(ast.mainToken(decl)));
                try r.addProc(name, decl);
                if (std.mem.eql(u8, name, "main")) r.main_proc = decl;
            },
            .placeholder_decl => {
                if (file_scope and !global_main_scope_started) continue;
                const name = try r.normalizedName(ast.tokenSlice(ast.mainToken(decl)));
                try putExplicitPlaceholder(&r, allocator, name);
            },
            .run_expr, .meta_stmt, .add_context_decl => {},
            .const_decl => {
                const is_import_const = ast.data(decl).lhs != @import("Ast.zig").null_node and ast.tag(ast.data(decl).lhs) == .import_decl;
                if (file_scope and !global_main_scope_started and !is_import_const) continue;
                const name = try r.normalizedName(ast.tokenSlice(ast.mainToken(decl)));
                try r.putRealSymbol(name, .{ .const_value = ast.data(decl).lhs });
                if (is_import_const) {
                    try resolveNode(ast, &r, ast.data(decl).lhs, current_file, diag);
                }
            },
            .var_decl => {
                if (file_scope and !global_main_scope_started) continue;
                const name = try r.normalizedName(ast.tokenSlice(ast.mainToken(decl)));
                try r.putRealSymbol(name, .{ .const_value = decl });
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
            .scope_decl, .add_context_decl, .placeholder_decl => {},
            .proc_decl => {
                try proc_files.put(decl, current_file);
            },
            else => {},
        }
    }
    for (root_decls) |decl_idx| {
        const decl: NodeIndex = @intCast(decl_idx);
        if (ast.tag(decl) == .proc_decl) try resolveProc(ast, &r, decl, proc_files.get(decl) orelse 0, diag);
        if (ast.tag(decl) == .run_expr or ast.tag(decl) == .meta_stmt) try resolveNode(ast, &r, decl, 0, diag);
    }
    if (r.require_main and r.main_proc == null) return diag.failAt(0, "No program entry point was found. (The designated entry point name is 'main'.)", .{});
    return r;
}

fn resolveProc(ast: *const Ast, r: *Resolved, proc: NodeIndex, file_id: u32, diag: Diagnostic) anyerror!void {
    var declared = std.ArrayList([]const u8).empty;
    defer declared.deinit(r.allocator);
    var restores = std.ArrayList(BindingRestore).empty;
    defer restores.deinit(r.allocator);
    const old_this = try r.symbols.fetchPut(r.allocator, "#this", .{ .proc = proc });
    try restores.append(r.allocator, .{ .name = "#this", .old = if (old_this) |entry| entry.value else undefined, .had_old = old_this != null });
    const sig = procSignature(ast, proc);
    if (sig) |s| {
        for (ast.extraSlice(s.params_extra)) |param_idx| {
            const param: NodeIndex = @intCast(param_idx);
            const name = try r.normalizedName(ast.tokenSlice(ast.mainToken(param)));
            if (containsName(declared.items, name)) return diag.failAt(ast.tokens[ast.mainToken(param)].start, "duplicate parameter declaration '{s}'", .{name});
            const old = try r.symbols.fetchPut(r.allocator, name, .{ .const_value = param });
            try restores.append(r.allocator, .{ .name = name, .old = if (old) |entry| entry.value else undefined, .had_old = old != null });
            try declared.append(r.allocator, name);
            if (ast.data(param).lhs != @import("Ast.zig").null_node and ast.tag(ast.data(param).lhs) == .type_expr) {
                const ty_name = ast.tokenSlice(ast.mainToken(ast.data(param).lhs));
                if (ty_name.len != 0 and std.ascii.isUpper(ty_name[0]) and r.lookup(ty_name) == null) {
                    const old_ty = try r.symbols.fetchPut(r.allocator, ty_name, .{ .const_value = @import("Ast.zig").null_node });
                    try restores.append(r.allocator, .{ .name = ty_name, .old = if (old_ty) |entry| entry.value else undefined, .had_old = old_ty != null });
                }
            }
            if (ast.data(param).lhs != @import("Ast.zig").null_node) try resolveNode(ast, r, ast.data(param).lhs, file_id, diag);
            if (ast.data(param).rhs == using_param_sentinel) try r.using_fallbacks.append(r.allocator, param);
        }
    }
    try resolveBlock(ast, r, ast.data(proc).lhs, file_id, diag);
    restoreBindings(r, restores.items);
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
    const using_base = r.using_fallbacks.items.len;
    defer r.using_fallbacks.shrinkRetainingCapacity(using_base);
    var declared = std.ArrayList([]const u8).empty;
    defer declared.deinit(r.allocator);
    var restores = std.ArrayList(BindingRestore).empty;
    defer restores.deinit(r.allocator);
    var predeclared_nodes = std.AutoHashMap(NodeIndex, void).init(r.allocator);
    defer predeclared_nodes.deinit();

    for (stmts) |stmt_idx| {
        const stmt: NodeIndex = @intCast(stmt_idx);
        if (ast.tag(stmt) == .proc_decl or (ast.tag(stmt) == .var_decl and ast.data(stmt).lhs == @import("Ast.zig").null_node and ast.data(stmt).rhs != @import("Ast.zig").null_node and ast.tag(ast.data(stmt).rhs) == .proc_decl)) {
            const name = try r.normalizedName(ast.tokenSlice(ast.mainToken(stmt)));
            if (std.mem.eql(u8, name, "it") or std.mem.eql(u8, name, "it_index")) continue;
            const already_declared = containsName(declared.items, name);
            const sym: Symbol = if (ast.tag(stmt) == .proc_decl) .{ .proc = stmt } else .{ .const_value = stmt };
            const old = try r.symbols.fetchPut(r.allocator, name, sym);
            try restores.append(r.allocator, .{ .name = name, .old = if (old) |entry| entry.value else undefined, .had_old = old != null });
            if (!already_declared) try declared.append(r.allocator, name);
            try predeclared_nodes.put(stmt, {});
        } else if (ast.tag(stmt) == .stmt_list) {
            for (ast.extraSlice(ast.data(stmt).lhs)) |child_idx| {
                const child: NodeIndex = @intCast(child_idx);
                if (ast.tag(child) == .proc_decl or (ast.tag(child) == .var_decl and ast.data(child).lhs == @import("Ast.zig").null_node and ast.data(child).rhs != @import("Ast.zig").null_node and ast.tag(ast.data(child).rhs) == .proc_decl)) {
                    const name = try r.normalizedName(ast.tokenSlice(ast.mainToken(child)));
                    if (std.mem.eql(u8, name, "it") or std.mem.eql(u8, name, "it_index")) continue;
                    const already_declared = containsName(declared.items, name);
                    const sym: Symbol = if (ast.tag(child) == .proc_decl) .{ .proc = child } else .{ .const_value = child };
                    const old = try r.symbols.fetchPut(r.allocator, name, sym);
                    try restores.append(r.allocator, .{ .name = name, .old = if (old) |entry| entry.value else undefined, .had_old = old != null });
                    if (!already_declared) try declared.append(r.allocator, name);
                    try predeclared_nodes.put(child, {});
                } else if (ast.tag(child) == .var_decl or ast.tag(child) == .const_decl) {
                    const name = try r.normalizedName(ast.tokenSlice(ast.mainToken(child)));
                    const already_declared = containsName(declared.items, name);
                    const sym: Symbol = if (ast.tag(child) == .var_decl) .{ .const_value = child } else .{ .const_value = ast.data(child).lhs };
                    const old = try r.symbols.fetchPut(r.allocator, name, sym);
                    try restores.append(r.allocator, .{ .name = name, .old = if (old) |entry| entry.value else undefined, .had_old = old != null });
                    if (!already_declared) try declared.append(r.allocator, name);
                    try predeclared_nodes.put(child, {});
                }
            }
        } else if (ast.tag(stmt) == .var_decl or ast.tag(stmt) == .const_decl) {
            const name = try r.normalizedName(ast.tokenSlice(ast.mainToken(stmt)));
            const already_declared = containsName(declared.items, name);
            const sym: Symbol = if (ast.tag(stmt) == .var_decl) .{ .const_value = stmt } else .{ .const_value = ast.data(stmt).lhs };
            const old = try r.symbols.fetchPut(r.allocator, name, sym);
            try restores.append(r.allocator, .{ .name = name, .old = if (old) |entry| entry.value else undefined, .had_old = old != null });
            if (!already_declared) try declared.append(r.allocator, name);
            try predeclared_nodes.put(stmt, {});
        }
    }

    for (stmts) |stmt_idx| {
        const stmt: NodeIndex = @intCast(stmt_idx);
        switch (ast.tag(stmt)) {
            .expr_stmt => {
                try resolveNode(ast, r, stmt, file_id, diag);
                if (ast.mainToken(stmt) < ast.tokens.len and ast.tokens[ast.mainToken(stmt)].tag == .keyword_using) {
                    const operand = ast.data(stmt).lhs;
                    if (ast.tag(operand) == .identifier) {
                        if (r.local_values.get(operand)) |decl| try r.using_fallbacks.append(r.allocator, decl);
                    }
                }
            },
            .stmt_list => {
                for (ast.extraSlice(ast.data(stmt).lhs)) |child_idx| {
                    const child: NodeIndex = @intCast(child_idx);
                    switch (ast.tag(child)) {
                        .var_decl, .const_decl => {
                            const name = try r.normalizedName(ast.tokenSlice(ast.mainToken(child)));
                            if (predeclared_nodes.contains(child)) {
                                if (ast.tag(child) == .var_decl) {
                                    if (ast.data(child).lhs != @import("Ast.zig").null_node) try resolveNode(ast, r, ast.data(child).lhs, file_id, diag);
                                    if (ast.data(child).rhs != @import("Ast.zig").null_node) try resolveNode(ast, r, ast.data(child).rhs, file_id, diag);
                                } else {
                                    try resolveNode(ast, r, ast.data(child).lhs, file_id, diag);
                                }
                                continue;
                            }
                            if (containsName(declared.items, name)) {
                                if (ast.data(child).lhs == @import("Ast.zig").null_node and ast.data(child).rhs != @import("Ast.zig").null_node and ast.tag(ast.data(child).rhs) == .proc_decl) {
                                    try resolveNode(ast, r, ast.data(child).rhs, file_id, diag);
                                    continue;
                                }
                                if (canReuseNamedReturnBinding(ast, r, name, child)) {
                                    if (ast.data(child).rhs != @import("Ast.zig").null_node) try resolveNode(ast, r, ast.data(child).rhs, file_id, diag);
                                    continue;
                                }
                                return diag.failAt(ast.tokens[ast.mainToken(child)].start, "duplicate local declaration '{s}'", .{name});
                            }
                            if (ast.tag(child) == .var_decl) {
                                if (ast.data(child).lhs != @import("Ast.zig").null_node) try resolveNode(ast, r, ast.data(child).lhs, file_id, diag);
                                if (ast.data(child).rhs != @import("Ast.zig").null_node) try resolveNode(ast, r, ast.data(child).rhs, file_id, diag);
                            } else {
                                try resolveNode(ast, r, ast.data(child).lhs, file_id, diag);
                            }
                            const old = try r.symbols.fetchPut(r.allocator, name, .{ .const_value = if (ast.tag(child) == .var_decl) child else ast.data(child).lhs });
                            try restores.append(r.allocator, .{ .name = name, .old = if (old) |entry| entry.value else undefined, .had_old = old != null });
                            try declared.append(r.allocator, name);
                        },
                        .proc_decl => try resolveProc(ast, r, child, file_id, diag),
                        else => try resolveNode(ast, r, child, file_id, diag),
                    }
                }
            },
            .var_decl, .const_decl => {
                const name = try r.normalizedName(ast.tokenSlice(ast.mainToken(stmt)));
                if (predeclared_nodes.contains(stmt)) {
                    if (ast.tag(stmt) == .var_decl) {
                        if (ast.data(stmt).lhs != @import("Ast.zig").null_node) try resolveNode(ast, r, ast.data(stmt).lhs, file_id, diag);
                        if (ast.data(stmt).rhs != @import("Ast.zig").null_node) try resolveNode(ast, r, ast.data(stmt).rhs, file_id, diag);
                    } else {
                        try resolveNode(ast, r, ast.data(stmt).lhs, file_id, diag);
                    }
                    continue;
                }
                if (containsName(declared.items, name)) {
                    if (ast.data(stmt).lhs == @import("Ast.zig").null_node and ast.data(stmt).rhs != @import("Ast.zig").null_node and ast.tag(ast.data(stmt).rhs) == .proc_decl) {
                        try resolveNode(ast, r, ast.data(stmt).rhs, file_id, diag);
                        continue;
                    }
                    if (canReuseNamedReturnBinding(ast, r, name, stmt)) {
                        if (ast.data(stmt).rhs != @import("Ast.zig").null_node) try resolveNode(ast, r, ast.data(stmt).rhs, file_id, diag);
                        continue;
                    }
                    return diag.failAt(ast.tokens[ast.mainToken(stmt)].start, "duplicate local declaration '{s}'", .{name});
                }
                if (ast.tag(stmt) == .var_decl) {
                    if (ast.data(stmt).lhs != @import("Ast.zig").null_node) try resolveNode(ast, r, ast.data(stmt).lhs, file_id, diag);
                    if (ast.data(stmt).rhs != @import("Ast.zig").null_node) try resolveNode(ast, r, ast.data(stmt).rhs, file_id, diag);
                } else {
                    try resolveNode(ast, r, ast.data(stmt).lhs, file_id, diag);
                }
                const old = try r.symbols.fetchPut(r.allocator, name, .{ .const_value = if (ast.tag(stmt) == .var_decl) stmt else ast.data(stmt).lhs });
                try restores.append(r.allocator, .{ .name = name, .old = if (old) |entry| entry.value else undefined, .had_old = old != null });
                try declared.append(r.allocator, name);
            },
            .proc_decl => try resolveProc(ast, r, stmt, file_id, diag),
            else => try resolveNode(ast, r, stmt, file_id, diag),
        }
    }
    restoreBindings(r, restores.items);
}

const BindingRestore = struct {
    name: []const u8,
    old: Symbol,
    had_old: bool,
};

fn containsName(names: []const []const u8, needle: []const u8) bool {
    for (names) |name| if (std.mem.eql(u8, name, needle)) return true;
    return false;
}

fn restoreBindings(r: *Resolved, restores: []const BindingRestore) void {
    var i = restores.len;
    while (i > 0) {
        i -= 1;
        const restore = restores[i];
        if (restore.had_old)
            r.symbols.put(r.allocator, restore.name, restore.old) catch unreachable
        else
            _ = r.symbols.remove(restore.name);
    }
}

fn canReuseNamedReturnBinding(ast: *const Ast, r: *const Resolved, name: []const u8, stmt: NodeIndex) bool {
    if (ast.tag(stmt) != .var_decl) return false;
    if (ast.data(stmt).lhs != @import("Ast.zig").null_node) return false;
    const existing = r.lookup(name) orelse return false;
    return switch (existing) {
        .const_value => |node| ast.tag(node) == .var_decl and ast.data(node).lhs != @import("Ast.zig").null_node,
        else => false,
    };
}

fn resolveNode(ast: *const Ast, r: *Resolved, node: NodeIndex, file_id: u32, diag: Diagnostic) anyerror!void {
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
        .import_decl => {
            const module_name = ast.stringTokenContents(ast.data(node).lhs);
            if (std.mem.eql(u8, module_name, "Basic")) {
                r.imports_basic = true;
                try r.symbols.put(r.allocator, "memcpy", .builtin_memcpy);
                try r.symbols.put(r.allocator, "memset", .builtin_memset);
            } else if (std.mem.eql(u8, module_name, "Compiler")) {
                try r.symbols.put(r.allocator, "get_type_table", .builtin_get_type_table);
                try putCompilerModuleSymbols(r);
            } else if (std.mem.eql(u8, module_name, "GL")) {
                try putExternalSymbols(r, &.{
                    "gl",
                    "gl_load",
                    "glTexParameteri",
                    "glGetString",
                    "glViewport",
                    "glClearColor",
                    "glClear",
                    "GL_VENDOR",
                    "GL_COLOR_BUFFER_BIT",
                });
            } else if (std.mem.eql(u8, module_name, "String")) {
                try r.symbols.put(r.allocator, "to_upper", .builtin_to_upper);
                try r.symbols.put(r.allocator, "to_lower", .builtin_to_lower);
                try r.symbols.put(r.allocator, "is_digit", .builtin_is_digit);
                try r.symbols.put(r.allocator, "is_alpha", .builtin_is_alpha);
                try r.symbols.put(r.allocator, "is_alnum", .builtin_is_alnum);
                try r.symbols.put(r.allocator, "is_space", .builtin_is_space);
                try r.symbols.put(r.allocator, "is_any", .builtin_is_any);
                try putStringBuiltins(r);
                try r.symbols.put(r.allocator, "begins_with", .builtin_begins_with);
                try r.symbols.put(r.allocator, "find_index_from_left", .builtin_find_index_from_left);
                try r.symbols.put(r.allocator, "find_index_from_right", .builtin_find_index_from_right);
            }
        },
        .string_literal, .integer_literal, .float_literal, .bool_literal, .null_literal, .char_literal, .undefined_literal, .type_expr, .struct_type, .union_type, .enum_type, .load_decl, .scope_decl => {},
        .proc_decl => try resolveProc(ast, r, node, file_id, diag),
        .pointer_type => try resolveNode(ast, r, ast.data(node).lhs, file_id, diag),
        .array_type => {
            if (ast.data(node).lhs != @import("Ast.zig").null_node) try resolveNode(ast, r, ast.data(node).lhs, file_id, diag);
            try resolveNode(ast, r, ast.data(node).rhs, file_id, diag);
        },
        .proc_type => {
            for (ast.extraSlice(ast.data(node).lhs)) |param_ty| try resolveNode(ast, r, @intCast(param_ty), file_id, diag);
            try resolveNode(ast, r, ast.data(node).rhs, file_id, diag);
        },
        .type_of_expr => try resolveNode(ast, r, ast.data(node).lhs, file_id, diag),
        .is_constant_expr => try resolveNode(ast, r, ast.data(node).lhs, file_id, diag),
        .size_of_expr => try resolveNode(ast, r, ast.data(node).lhs, file_id, diag),
        .meta_stmt => {
            if (ast.data(node).lhs != @import("Ast.zig").null_node and ast.tag(ast.data(node).lhs) == .block)
                try resolveBlock(ast, r, ast.data(node).lhs, file_id, diag)
            else if (ast.data(node).lhs != @import("Ast.zig").null_node)
                try resolveNode(ast, r, ast.data(node).lhs, file_id, diag);
            if (ast.data(node).rhs != @import("Ast.zig").null_node)
                try resolveNode(ast, r, ast.data(node).rhs, file_id, diag);
        },
        .meta_expr => {
            if (ast.data(node).lhs != @import("Ast.zig").null_node and ast.tag(ast.data(node).lhs) == .block)
                try resolveBlock(ast, r, ast.data(node).lhs, file_id, diag)
            else if (ast.data(node).lhs != @import("Ast.zig").null_node)
                try resolveNode(ast, r, ast.data(node).lhs, file_id, diag);
            if (ast.data(node).rhs != @import("Ast.zig").null_node)
                try resolveNode(ast, r, ast.data(node).rhs, file_id, diag);
        },
        .run_expr => if (ast.tokens[ast.mainToken(node)].tag == .keyword_push_context) {
            try resolveNode(ast, r, ast.data(node).rhs, file_id, diag);
            try resolveBlock(ast, r, ast.data(node).lhs, file_id, diag);
        } else if (ast.tag(ast.data(node).lhs) == .block) try resolveBlock(ast, r, ast.data(node).lhs, file_id, diag) else try resolveNode(ast, r, ast.data(node).lhs, file_id, diag),
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
        .while_stmt => {
            const cond_node = ast.data(node).lhs;
            if (ast.tag(cond_node) == .var_decl) {
                // Named while: "while name := expr { }" — resolve the init, bind name for body.
                if (ast.data(cond_node).rhs != @import("Ast.zig").null_node)
                    try resolveNode(ast, r, ast.data(cond_node).rhs, file_id, diag);
                const name = ast.tokenSlice(ast.mainToken(cond_node));
                const old = r.symbols.fetchPut(r.allocator, name, .{ .const_value = cond_node }) catch |err| return err;
                defer {
                    if (old) |entry| r.symbols.put(r.allocator, name, entry.value) catch unreachable else _ = r.symbols.remove(name);
                }
                try resolveBlock(ast, r, ast.data(node).rhs, file_id, diag);
            } else {
                try resolveNode(ast, r, cond_node, file_id, diag);
                try resolveBlock(ast, r, ast.data(node).rhs, file_id, diag);
            }
        },
        .defer_stmt => try resolveNode(ast, r, ast.data(node).lhs, file_id, diag),
        .break_stmt, .continue_stmt => {},
        .for_stmt => {
            const range = ast.extraSlice(ast.data(node).lhs);
            if (range.len == 4 and (range[1] & 0x80000000) != 0) {
                try resolveNode(ast, r, @intCast(range[0]), file_id, diag);
                try r.loop_value_types.put(r.allocator, node, @import("InternPool.zig").InternPool.well_known.any_type);
                const old_it_index = r.symbols.fetchPut(r.allocator, "it_index", .{ .const_value = node }) catch |err| return err;
                const old_it = r.symbols.fetchPut(r.allocator, "it", .{ .const_value = node }) catch |err| return err;
                const iter_name = if (range[2] != 0 and (range[2] & 0x80000000) != 0) ast.tokenSlice(range[2] & 0x7fffffff) else "";
                const old_iter = if (iter_name.len != 0) r.symbols.fetchPut(r.allocator, iter_name, .{ .const_value = node }) catch |err| return err else null;
                const index_name = if (range[3] != 0) ast.tokenSlice(range[3]) else "";
                const old_index = if (range[3] != 0) r.symbols.fetchPut(r.allocator, index_name, .{ .const_value = node }) catch |err| return err else null;
                defer {
                    if (old_it_index) |entry| r.symbols.put(r.allocator, "it_index", entry.value) catch unreachable else _ = r.symbols.remove("it_index");
                    if (old_it) |entry| r.symbols.put(r.allocator, "it", entry.value) catch unreachable else _ = r.symbols.remove("it");
                    if (iter_name.len != 0) {
                        if (old_iter) |entry| r.symbols.put(r.allocator, iter_name, entry.value) catch unreachable else _ = r.symbols.remove(iter_name);
                    }
                    if (range[3] != 0) {
                        if (old_index) |entry| r.symbols.put(r.allocator, index_name, entry.value) catch unreachable else _ = r.symbols.remove(index_name);
                    }
                }
                try resolveBlock(ast, r, ast.data(node).rhs, file_id, diag);
            } else if (range.len == 1 or (range.len == 2 and (range[1] & 0x80000000) != 0) or range.len == 3) {
                try resolveNode(ast, r, @intCast(range[0]), file_id, diag);
                try r.loop_value_types.put(r.allocator, node, @import("InternPool.zig").InternPool.well_known.any_type);
                const old_it_index = r.symbols.fetchPut(r.allocator, "it_index", .{ .const_value = node }) catch |err| return err;
                const old_it = r.symbols.fetchPut(r.allocator, "it", .{ .const_value = node }) catch |err| return err;
                const iter_name = if (range.len >= 2 and (range[1] & 0x80000000) != 0) ast.tokenSlice(range[1] & 0x7fffffff) else "";
                const old_iter = if (iter_name.len != 0) r.symbols.fetchPut(r.allocator, iter_name, .{ .const_value = node }) catch |err| return err else null;
                const index_name = if (range.len == 3) ast.tokenSlice(range[2]) else "";
                const old_index = if (range.len == 3) r.symbols.fetchPut(r.allocator, index_name, .{ .const_value = node }) catch |err| return err else null;
                defer {
                    if (old_it_index) |entry| r.symbols.put(r.allocator, "it_index", entry.value) catch unreachable else _ = r.symbols.remove("it_index");
                    if (old_it) |entry| r.symbols.put(r.allocator, "it", entry.value) catch unreachable else _ = r.symbols.remove("it");
                    if (iter_name.len != 0) {
                        if (old_iter) |entry| r.symbols.put(r.allocator, iter_name, entry.value) catch unreachable else _ = r.symbols.remove(iter_name);
                    }
                    if (range.len == 3) {
                        if (old_index) |entry| r.symbols.put(r.allocator, index_name, entry.value) catch unreachable else _ = r.symbols.remove(index_name);
                    }
                }
                try resolveBlock(ast, r, ast.data(node).rhs, file_id, diag);
            } else if (range.len == 4 or range.len == 2) {
                // Range for: [start, end] or [start, end, iterator_tok, is_reverse]
                try resolveNode(ast, r, @intCast(range[0]), file_id, diag);
                try resolveNode(ast, r, @intCast(range[1]), file_id, diag);
                if (range.len == 4 and range[2] != 0) {
                    // Named iterator: bind it in scope for the body.
                    const iter_name = ast.tokenSlice(range[2]);
                    const old_iter = r.symbols.fetchPut(r.allocator, iter_name, .{ .const_value = node }) catch |err| return err;
                    // Also bind "it" as an alias.
                    const old_it = r.symbols.fetchPut(r.allocator, "it", .{ .const_value = node }) catch |err| return err;
                    defer {
                        if (old_iter) |entry| r.symbols.put(r.allocator, iter_name, entry.value) catch unreachable else _ = r.symbols.remove(iter_name);
                        if (old_it) |entry| r.symbols.put(r.allocator, "it", entry.value) catch unreachable else _ = r.symbols.remove("it");
                    }
                    try r.loop_indexes.put(r.allocator, node, 1);
                    try resolveBlock(ast, r, ast.data(node).rhs, file_id, diag);
                } else {
                    // No named iterator: bind 'it' and 'it_index' as the loop index.
                    try r.loop_indexes.put(r.allocator, node, 1);
                    const old_it = r.symbols.fetchPut(r.allocator, "it", .{ .const_value = node }) catch |err| return err;
                    const old_it_index = r.symbols.fetchPut(r.allocator, "it_index", .{ .const_value = node }) catch |err| return err;
                    defer {
                        if (old_it) |entry| r.symbols.put(r.allocator, "it", entry.value) catch unreachable else _ = r.symbols.remove("it");
                        if (old_it_index) |entry| r.symbols.put(r.allocator, "it_index", entry.value) catch unreachable else _ = r.symbols.remove("it_index");
                    }
                    try resolveBlock(ast, r, ast.data(node).rhs, file_id, diag);
                }
            } else return diag.failAt(ast.tokens[ast.mainToken(node)].start, "internal error: for statement has invalid operand count", .{});
        },
        .aggregate_literal => {
            for (ast.extraSlice(ast.data(node).lhs)) |elem_idx| {
                const elem: NodeIndex = @intCast(elem_idx);
                if (ast.tag(elem) == .assign_stmt)
                    try resolveNode(ast, r, ast.data(elem).rhs, file_id, diag)
                else
                    try resolveNode(ast, r, elem, file_id, diag);
            }
        },
        .typed_aggregate_literal => {
            const payload = ast.extraSlice(ast.data(node).lhs);
            try resolveNode(ast, r, @intCast(payload[0]), file_id, diag);
            const fields = ast.extraSlice(payload[1]);
            for (fields) |field_idx| {
                const field: NodeIndex = @intCast(field_idx);
                if (ast.tag(field) == .assign_stmt)
                    try resolveNode(ast, r, ast.data(field).rhs, file_id, diag)
                else
                    try resolveNode(ast, r, field, file_id, diag);
            }
        },
        .typed_array_literal => {
            const payload = ast.extraSlice(ast.data(node).lhs);
            try resolveNode(ast, r, @intCast(payload[0]), file_id, diag);
            const elems = ast.extraSlice(payload[1]);
            for (elems) |elem| try resolveNode(ast, r, @intCast(elem), file_id, diag);
        },
        .field_access => {
            if (ast.data(node).lhs == @import("Ast.zig").null_node) return;
            if (ast.tag(ast.data(node).lhs) == .identifier and std.mem.eql(u8, ast.tokenSlice(ast.mainToken(ast.data(node).lhs)), "Type_Info_Tag")) return;
            try resolveNode(ast, r, ast.data(node).lhs, file_id, diag);
        },
        .index_expr => {
            try resolveNode(ast, r, ast.data(node).lhs, file_id, diag);
            try resolveNode(ast, r, ast.data(node).rhs, file_id, diag);
        },
        .call_expr => {
            if (ast.tag(ast.data(node).lhs) == .identifier) {
                const callee_name = ast.tokenSlice(ast.mainToken(ast.data(node).lhs));
                if (r.lookup(callee_name) == null) {
                    try resolveNode(ast, r, ast.data(node).lhs, file_id, diag);
                } else try resolveNode(ast, r, ast.data(node).lhs, file_id, diag);
            } else try resolveNode(ast, r, ast.data(node).lhs, file_id, diag);
            for (ast.extraSlice(ast.data(node).rhs)) |arg_idx| {
                const arg: NodeIndex = @intCast(arg_idx);
                if (ast.tag(arg) == .assign_stmt) {
                    try resolveNode(ast, r, ast.data(arg).rhs, file_id, diag);
                } else if (ast.tag(arg) == .binary_expr and ast.tokens[ast.mainToken(arg)].tag == .equal and ast.tag(ast.data(arg).lhs) == .identifier) {
                    try resolveNode(ast, r, ast.data(arg).rhs, file_id, diag);
                } else try resolveNode(ast, r, arg, file_id, diag);
            }
        },
        .identifier => {
            const name = ast.tokenSlice(ast.mainToken(node));
            const sym_opt = blk: {
                const scoped = try r.scopedName(file_id, name);
                defer r.allocator.free(scoped);
                break :blk r.lookup(scoped) orelse r.lookup(name);
            };
            if (sym_opt) |sym| {
                switch (sym) {
                    .const_value => |value_node| {
                        if (value_node == node and std.mem.eql(u8, name, "it_index")) try r.loop_indexes.put(r.allocator, node, 1);
                        if (value_node == node and std.mem.eql(u8, name, "it")) try r.loop_value_types.put(r.allocator, node, @import("InternPool.zig").InternPool.well_known.any_type);
                        try r.local_values.put(r.allocator, node, value_node);
                    },
                    .proc => |proc_node| try r.local_values.put(r.allocator, node, proc_node),
                    .placeholder => try markImplicitPlaceholderUse(r, r.allocator, name),
                    .builtin_swap, .builtin_print, .builtin_write_string, .builtin_write_strings, .builtin_write_number, .builtin_write_nonnegative_number, .builtin_new, .builtin_new_array, .builtin_free, .builtin_exit, .builtin_memcpy, .builtin_memset, .builtin_assert, .builtin_sin, .builtin_current_time_consensus, .builtin_current_time_monotonic, .builtin_to_calendar, .builtin_calendar_to_string, .builtin_random_seed, .builtin_random_get, .builtin_random_get_zero_to_one, .builtin_random_get_within_range, .builtin_compiler_arg_count, .builtin_compiler_arg, .builtin_compiler_read_file, .builtin_compiler_write_file, .builtin_get_command_line_arguments, .builtin_get_cpu_info, .builtin_check_feature, .builtin_make_directory_if_it_does_not_exist, .builtin_delete_directory, .builtin_file_exists, .builtin_set_working_directory, .builtin_get_working_directory, .builtin_visit_files, .builtin_get_path_of_running_executable, .builtin_read_entire_file, .builtin_write_entire_file, .builtin_file_open, .builtin_file_close, .builtin_file_length, .builtin_file_set_position, .builtin_file_write, .builtin_file_read, .builtin_posix_read, .builtin_get_std_handle, .builtin_reset_temporary_storage, .builtin_talloc_string, .builtin_make_leak_report, .builtin_log_leak_report, .builtin_push_allocator, .builtin_sprint, .builtin_tprint, .builtin_to_string, .builtin_to_c_string, .builtin_copy_string, .builtin_string_builder_type, .builtin_init_string_builder, .builtin_free_buffers, .builtin_append, .builtin_print_to_builder, .builtin_builder_string_length, .builtin_builder_to_string, .builtin_compare, .builtin_contains, .builtin_begins_with, .builtin_split, .builtin_trim, .builtin_join, .builtin_find_index_from_left, .builtin_find_index_from_right, .builtin_string_to_int, .builtin_string_to_float, .builtin_parse_int, .builtin_to_integer, .builtin_replace, .builtin_slice, .builtin_path_strip_filename, .builtin_c_style_strlen, .builtin_format_int, .builtin_format_float, .builtin_get_type_table, .builtin_alloc, .builtin_array_add, .builtin_array_free, .builtin_peek, .builtin_pop, .builtin_array_reset, .builtin_array_reserve, .builtin_array_ordered_remove_by_index, .builtin_array_find, .builtin_array_copy, .builtin_get_time, .builtin_seconds_since_init, .builtin_sleep_milliseconds, .builtin_to_float64_seconds, .builtin_format_struct, .builtin_to_upper, .builtin_to_lower, .builtin_is_digit, .builtin_is_alpha, .builtin_is_alnum, .builtin_is_space, .builtin_is_any, .builtin_log, .builtin_get_field, .builtin_type_to_string, .builtin_enum_range, .builtin_enum_values_as_s64, .builtin_enum_names, .builtin_abs => {},
                }
            } else if (r.using_fallbacks.items.len != 0) {
                try r.local_values.put(r.allocator, node, r.using_fallbacks.items[r.using_fallbacks.items.len - 1]);
            } else if (std.mem.eql(u8, name, "OS")) {
                // OS is a compiler-provided value, not an implicit placeholder.
                // Leave it unresolved here so sema and lowering can give it a
                // real host-target value.
            } else if (isBuiltinTypeName(name)) {
                // Builtin type names can appear as first-class Type values in expressions,
                // e.g. type_of(n) == int. Leave them for Sema/codegen as identifiers.
            } else if (name.len != 0 and std.ascii.isUpper(name[0])) {
                try r.local_values.put(r.allocator, node, @import("Ast.zig").null_node);
            } else if (isBacktickedIdentifier(ast, node) or isMacroGeneratedIdentifier(name)) {
                try r.loop_value_types.put(r.allocator, node, @import("InternPool.zig").InternPool.well_known.any_type);
            } else if (r.external_names.contains(name)) {
                try r.local_values.put(r.allocator, node, @import("Ast.zig").null_node);
            } else if (isOperatorIdentifierName(name)) {
                // Expression-form `operator +(a, b)` parses the operator token
                // as an identifier callee. It is resolved by sema/codegen using
                // the same operator table as infix expressions.
            } else {
                return diag.failAt(ast.tokens[ast.mainToken(node)].start, "unresolved identifier '{s}'", .{name});
            }
        },
        // Bare block: anonymous scope — resolve all statements inside.
        .block => try resolveBlock(ast, r, node, file_id, diag),
        else => return diag.failAt(ast.tokens[ast.mainToken(node)].start, "unsupported AST node in resolver", .{}),
    }
}

fn isMacroGeneratedIdentifier(name: []const u8) bool {
    return std.mem.eql(u8, name, "it") or
        std.mem.eql(u8, name, "it_index") or
        std.mem.eql(u8, name, "a") or
        std.mem.eql(u8, name, "b") or
        std.mem.eql(u8, name, "c");
}

fn isBacktickedIdentifier(ast: *const Ast, node: NodeIndex) bool {
    if (ast.tag(node) != .identifier) return false;
    const tok = ast.mainToken(node);
    const start = ast.tokens[tok].start;
    return start > 0 and ast.source[start - 1] == '`';
}

fn isBuiltinTypeName(name: []const u8) bool {
    return std.mem.eql(u8, name, "void") or std.mem.eql(u8, name, "bool") or std.mem.eql(u8, name, "string") or std.mem.eql(u8, name, "int") or std.mem.eql(u8, name, "s64") or std.mem.eql(u8, name, "float") or std.mem.eql(u8, name, "float32") or std.mem.eql(u8, name, "float64") or std.mem.eql(u8, name, "s32") or std.mem.eql(u8, name, "u8") or std.mem.eql(u8, name, "u16") or std.mem.eql(u8, name, "u32") or std.mem.eql(u8, name, "u64") or std.mem.eql(u8, name, "Vector2") or std.mem.eql(u8, name, "Vector3") or std.mem.eql(u8, name, "Vector4") or std.mem.eql(u8, name, "Type") or std.mem.eql(u8, name, "Any");
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

test "scope_export restores non-file visibility after #scope_file" {
    const lexer = @import("lexer.zig");
    const parser = @import("parser.zig");

    const source =
        "#import \"Basic\";\n" ++
        "#load \"alpha.jai\";\n" ++
        "#scope_file;\n" ++
        "hidden :: 1;\n" ++
        "#scope_export;\n" ++
        "shown :: 2;\n" ++
        "#load \"__main_resume\";\n" ++
        "main :: () { print(\"%\", shown); }\n";
    const diag = Diagnostic.init(std.testing.allocator, "scope_export.jai", source);

    var tokens = try lexer.tokenize(std.testing.allocator, source, diag);
    defer tokens.deinit(std.testing.allocator);

    const slice = tokens.slice();
    var ast = try parser.parse(std.testing.allocator, source, slice.items(.tag), slice.items(.start), slice.items(.end), diag);
    defer {
        std.testing.allocator.free(ast.tokens);
        ast.deinit();
    }

    var resolved = try resolve(std.testing.allocator, &ast, diag, true, &.{});
    defer resolved.deinit();

    try std.testing.expect(resolved.lookup("hidden") == null);
    try std.testing.expect(resolved.lookup("__file1_hidden") != null);
    try std.testing.expect(resolved.lookup("shown") != null);
}

test "resolver treats loaded Process declarations as real symbols" {
    const lexer = @import("lexer.zig");
    const parser = @import("parser.zig");

    const source =
        "#load \"modules/Process/module.jai\";\n" ++
        "#scope_export;\n" ++
        "shutdown :: () {}\n" ++
        "#load \"__main_resume\";\n" ++
        "main :: () { shutdown(); }\n";
    const diag = Diagnostic.init(std.testing.allocator, "loaded_process_shutdown.jai", source);

    var tokens = try lexer.tokenize(std.testing.allocator, source, diag);
    defer tokens.deinit(std.testing.allocator);

    const slice = tokens.slice();
    var ast = try parser.parse(std.testing.allocator, source, slice.items(.tag), slice.items(.start), slice.items(.end), diag);
    defer {
        std.testing.allocator.free(ast.tokens);
        ast.deinit();
    }

    var resolved = try resolve(std.testing.allocator, &ast, diag, true, &.{});
    defer resolved.deinit();

    const shutdown = resolved.lookup("shutdown") orelse return error.TestUnexpectedResult;
    try std.testing.expect(shutdown != .placeholder);
    try std.testing.expectEqual(@as(u32, 0), resolved.usedImplicitPlaceholderCount());
    try resolved.failIfImplicitPlaceholders(diag);
}

test "resolver allows explicit placeholder declarations under strict gate" {
    const lexer = @import("lexer.zig");
    const parser = @import("parser.zig");

    const source =
        "#placeholder TRUTH;\n" ++
        "main :: () { print(\"%\", TRUTH); }\n";
    const diag = Diagnostic.init(std.testing.allocator, "explicit_placeholder.jai", source);

    var tokens = try lexer.tokenize(std.testing.allocator, source, diag);
    defer tokens.deinit(std.testing.allocator);

    const slice = tokens.slice();
    var ast = try parser.parse(std.testing.allocator, source, slice.items(.tag), slice.items(.start), slice.items(.end), diag);
    defer {
        std.testing.allocator.free(ast.tokens);
        ast.deinit();
    }

    var resolved = try resolve(std.testing.allocator, &ast, diag, true, &.{});
    defer resolved.deinit();

    try std.testing.expectEqual(@as(u32, 0), resolved.usedImplicitPlaceholderCount());
    try std.testing.expectEqual(@as(u32, 1), resolved.explicitPlaceholderCount());
    try std.testing.expectEqual(@as(u32, 1), resolved.usedExplicitPlaceholderCount());
    try resolved.failIfImplicitPlaceholders(diag);
}

test "resolver lets real declarations replace implicit placeholders" {
    const lexer = @import("lexer.zig");
    const parser = @import("parser.zig");

    const source =
        "#import \"Basic\";\n" ++
        "proc :: () {}\n" ++
        "main :: () { proc(); }\n";
    const diag = Diagnostic.init(std.testing.allocator, "placeholder_replacement.jai", source);

    var tokens = try lexer.tokenize(std.testing.allocator, source, diag);
    defer tokens.deinit(std.testing.allocator);

    const slice = tokens.slice();
    var ast = try parser.parse(std.testing.allocator, source, slice.items(.tag), slice.items(.start), slice.items(.end), diag);
    defer {
        std.testing.allocator.free(ast.tokens);
        ast.deinit();
    }

    var resolved = try resolve(std.testing.allocator, &ast, diag, true, &.{});
    defer resolved.deinit();

    try std.testing.expectEqual(@as(u32, 0), resolved.usedImplicitPlaceholderCount());
    try std.testing.expect(resolved.lookup("proc").? == .proc);
    try resolved.failIfImplicitPlaceholders(diag);
}

test "resolver does not globally seed compiler APIs as placeholders" {
    const lexer = @import("lexer.zig");
    const parser = @import("parser.zig");

    const source =
        "#import \"Basic\";\n" ++
        "for_expansion :: (body: Code, flags: For_Flags) #expand {}\n" ++
        "main :: () {}\n";
    const diag = Diagnostic.init(std.testing.allocator, "no_global_compiler_placeholders.jai", source);

    var tokens = try lexer.tokenize(std.testing.allocator, source, diag);
    defer tokens.deinit(std.testing.allocator);

    const slice = tokens.slice();
    var ast = try parser.parse(std.testing.allocator, source, slice.items(.tag), slice.items(.start), slice.items(.end), diag);
    defer {
        std.testing.allocator.free(ast.tokens);
        ast.deinit();
    }

    var resolved = try resolve(std.testing.allocator, &ast, diag, true, &.{});
    defer resolved.deinit();

    try std.testing.expect(resolved.lookup("compiler_create_workspace") == null);
    try std.testing.expect(!resolved.implicit_placeholders.contains("compiler_create_workspace"));
    try std.testing.expect(resolved.lookup("For_Flags") != null);
    try std.testing.expect(!resolved.implicit_placeholders.contains("For_Flags"));
    try resolved.failIfImplicitPlaceholders(diag);
}

test "implemented module imports do not create implicit placeholders" {
    const lexer = @import("lexer.zig");
    const parser = @import("parser.zig");

    const source =
        "#import \"Basic\";\n" ++
        "#import \"Compiler\";\n" ++
        "main :: () { print(\"ok\\n\"); }\n";
    const diag = Diagnostic.init(std.testing.allocator, "implemented_imports_no_placeholders.jai", source);

    var tokens = try lexer.tokenize(std.testing.allocator, source, diag);
    defer tokens.deinit(std.testing.allocator);

    const slice = tokens.slice();
    var ast = try parser.parse(std.testing.allocator, source, slice.items(.tag), slice.items(.start), slice.items(.end), diag);
    defer {
        std.testing.allocator.free(ast.tokens);
        ast.deinit();
    }

    var resolved = try resolve(std.testing.allocator, &ast, diag, true, &.{});
    defer resolved.deinit();

    try std.testing.expectEqual(@as(u32, 0), resolved.implicitPlaceholderCount());
    try std.testing.expectEqual(@as(u32, 0), resolved.usedImplicitPlaceholderCount());
    try resolved.failIfImplicitPlaceholders(diag);
}

test "resolver treats OS as a real compiler-provided value" {
    const lexer = @import("lexer.zig");
    const parser = @import("parser.zig");

    const source =
        "#import \"Basic\";\n" ++
        "main :: () { print(\"%\\n\", OS); }\n";
    const diag = Diagnostic.init(std.testing.allocator, "os_builtin.jai", source);

    var tokens = try lexer.tokenize(std.testing.allocator, source, diag);
    defer tokens.deinit(std.testing.allocator);

    const slice = tokens.slice();
    var ast = try parser.parse(std.testing.allocator, source, slice.items(.tag), slice.items(.start), slice.items(.end), diag);
    defer {
        std.testing.allocator.free(ast.tokens);
        ast.deinit();
    }

    var resolved = try resolve(std.testing.allocator, &ast, diag, true, &.{});
    defer resolved.deinit();

    try std.testing.expect(!resolved.implicit_placeholders.contains("OS"));
    try std.testing.expectEqual(@as(u32, 0), resolved.usedImplicitPlaceholderCount());
    try resolved.failIfImplicitPlaceholders(diag);
}
