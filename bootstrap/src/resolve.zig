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
    builtin_free,
    builtin_exit,
    builtin_memcpy,
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
    builtin_format_int,
    builtin_format_float,
    builtin_get_type_table,
    builtin_alloc,
    builtin_array_add,
    builtin_array_free,
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
    local_values: std.AutoHashMapUnmanaged(NodeIndex, NodeIndex) = .empty,
    loop_value_types: std.AutoHashMapUnmanaged(NodeIndex, u32) = .empty,
    loop_indexes: std.AutoHashMapUnmanaged(NodeIndex, u32) = .empty,
    using_fallbacks: std.ArrayListUnmanaged(NodeIndex) = .empty,
    owned_names: std.ArrayList([]u8) = .empty,
    proc_overloads: std.StringHashMapUnmanaged(std.ArrayListUnmanaged(NodeIndex)) = .empty,
    imports_basic: bool = false,
    main_proc: ?NodeIndex = null,
    require_main: bool = true,

    pub fn deinit(r: *Resolved) void {
        var it = r.proc_overloads.iterator();
        while (it.next()) |entry| entry.value_ptr.deinit(r.allocator);
        r.proc_overloads.deinit(r.allocator);
        r.symbols.deinit(r.allocator);
        r.local_values.deinit(r.allocator);
        r.loop_value_types.deinit(r.allocator);
        r.loop_indexes.deinit(r.allocator);
        r.using_fallbacks.deinit(r.allocator);
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
        if (!r.symbols.contains(name)) try r.symbols.put(r.allocator, name, .{ .proc = proc });
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

fn putPlaceholder(r: *Resolved, allocator: std.mem.Allocator, name: []const u8) !void {
    if (!r.symbols.contains(name)) try r.symbols.put(allocator, name, .placeholder);
}

fn putPlaceholders(r: *Resolved, allocator: std.mem.Allocator, names: []const []const u8) !void {
    for (names) |name| try putPlaceholder(r, allocator, name);
}

pub fn resolve(allocator: std.mem.Allocator, ast: *const Ast, diag: Diagnostic, require_main: bool) !Resolved {
    var r = Resolved{ .allocator = allocator, .require_main = require_main };
    errdefer r.deinit();
    try r.symbols.put(allocator, "print", .builtin_print);
    try r.symbols.put(allocator, "write_string", .builtin_write_string);
    try r.symbols.put(allocator, "write_strings", .builtin_write_strings);
    try r.symbols.put(allocator, "write_number", .builtin_write_number);
    try r.symbols.put(allocator, "write_nonnegative_number", .builtin_write_nonnegative_number);
    try r.symbols.put(allocator, "New", .builtin_new);
    try r.symbols.put(allocator, "free", .builtin_free);
    try putPlaceholders(&r, allocator, &.{
        "context", "temp", "reset_temporary_storage",
        "push_allocator",
        "DrawTexturePro",
        "get_build_options", "set_build_options", "set_build_options_dc",
        "add_build_file", "add_build_string", "run_command", "get_current_workspace",
                        "compiler_create_workspace", "compiler_begin_intercept", "compiler_wait_for_message",
                        "compiler_end_intercept", "compiler_set_workspace_status", "compiler_report",
                        "make_location", "add_global_data", "Optimization_Type", "Message_Complete", "OS",
                        "compiler_get_version_info", "compiler_custom_link_command_is_complete",
                        "For_Flags",
                    });
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
            .const_decl, .var_decl, .proc_decl => {
                if (file_scope and !main_scope_started) {
                    const raw = try r.normalizedName(ast.tokenSlice(ast.mainToken(decl)));
                    const scoped = try r.scopedName(current_file, raw);
                        try r.owned_names.append(allocator, scoped);
                        if (ast.tag(decl) == .proc_decl) {
                            try r.addProc(scoped, decl);
                        } else {
                            try r.symbols.put(allocator, scoped, switch (ast.tag(decl)) {
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
                        try putPlaceholders(&r, allocator, &.{
                            "InitWindow", "CloseWindow", "SetTargetFPS", "WindowShouldClose",
                            "GetScreenWidth", "GetScreenHeight", "GetFrameTime",
                            "BeginDrawing", "EndDrawing", "ClearBackground", "DrawText",
                            "DrawRectangle", "DrawRectangleRec", "DrawCircle", "PI",
                        });
                    }
                    continue;
                }
                if (std.mem.eql(u8, module_name, "Basic")) {
                    r.imports_basic = true;
                    try r.symbols.put(allocator, "print", .builtin_print);
                    try r.symbols.put(allocator, "exit", .builtin_exit);
                    try r.symbols.put(allocator, "memcpy", .builtin_memcpy);
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
                    try r.symbols.put(allocator, "array_add", .builtin_array_add);
                    try r.symbols.put(allocator, "array_free", .builtin_array_free);
                    try r.symbols.put(allocator, "write_string", .builtin_write_string);
                    try r.symbols.put(allocator, "log", .builtin_log);
                    try r.symbols.put(allocator, "get_field", .builtin_get_field);
                    try r.symbols.put(allocator, "type_to_string", .builtin_type_to_string);
                    try r.symbols.put(allocator, "enum_range", .builtin_enum_range);
                    try r.symbols.put(allocator, "enum_values_as_s64", .builtin_enum_values_as_s64);
                    try r.symbols.put(allocator, "enum_names", .builtin_enum_names);
                    try putPlaceholders(&r, allocator, &.{
                        "append", "sprint", "to_c_string", "to_string",
                        "String_Builder", "free_buffers", "init_string_builder",
                        "print_to_builder", "builder_string_length", "builder_to_string",
                        "make_vector2", "make_vector3",
                        "get_command_line_arguments", "tprint", "NewArray", "compare", "split",
                        "read", "file_exists", "release", "start", "lock", "proc",
                    });
                } else if (std.mem.eql(u8, module_name, "String")) {
                    try r.symbols.put(allocator, "to_upper", .builtin_to_upper);
                    try r.symbols.put(allocator, "to_lower", .builtin_to_lower);
                    try r.symbols.put(allocator, "is_digit", .builtin_is_digit);
                    try r.symbols.put(allocator, "is_alpha", .builtin_is_alpha);
                    try r.symbols.put(allocator, "is_alnum", .builtin_is_alnum);
                    try r.symbols.put(allocator, "is_space", .builtin_is_space);
                    try r.symbols.put(allocator, "is_any", .builtin_is_any);
                    try putPlaceholders(&r, allocator, &.{ "append", "sprint", "to_c_string", "to_string", "tprint", "join", "copy_string", "equal", "compare", "split", "contains", "trim", "compare_strings" });
                } else if (std.mem.eql(u8, module_name, "Thread")) {
                    try r.symbols.put(allocator, "sleep_milliseconds", .builtin_sleep_milliseconds);
                    try putPlaceholders(&r, allocator, &.{ "init", "context", "start", "lock", "unlock" });
                } else if (std.mem.eql(u8, module_name, "Random")) {
                    try r.symbols.put(allocator, "random_seed", .builtin_random_seed);
                    try r.symbols.put(allocator, "random_get", .builtin_random_get);
                    try r.symbols.put(allocator, "random_get_zero_to_one", .builtin_random_get_zero_to_one);
                    try r.symbols.put(allocator, "random_get_within_range", .builtin_random_get_within_range);
                } else if (std.mem.eql(u8, module_name, "Math")) {
                    try r.symbols.put(allocator, "sin", .builtin_sin);
                    try r.symbols.put(allocator, "abs", .builtin_abs);
                    try r.symbols.put(allocator, "Vector3", .{ .const_value = @import("Ast.zig").null_node });
                    try putPlaceholders(&r, allocator, &.{ "PI", "make_vector2", "make_vector3", "sqrt", "cos" });
                } else if (std.mem.eql(u8, module_name, "TestModule_Params")) {
                    r.imports_basic = true;
                    try r.symbols.put(allocator, "print", .builtin_print);
                } else if (std.mem.eql(u8, module_name, "Compiler")) {
                    try r.symbols.put(allocator, "get_type_table", .builtin_get_type_table);
                    try putPlaceholders(&r, allocator, &.{
                        "compiler_create_workspace", "get_build_options", "set_build_options",
                        "set_build_options_dc", "compiler_begin_intercept", "compiler_wait_for_message",
                        "compiler_end_intercept", "add_build_file", "add_build_string", "run_command",
                        "set_optimization", "compiler_get_nodes", "compiler_get_code", "print_expression",
                        "get_current_workspace", "Optimization_Type", "Message_Complete",
                        "compiler_set_workspace_status", "compiler_report", "make_location",
                        "add_global_data", "code_to_string", "builder_to_string",
                        "compiler_get_version_info", "compiler_custom_link_command_is_complete",
                        "Message", "Message_File", "Message_Import", "Message_Phase",
                        "Message_Typechecked", "Message_Debug_Dump", "Workspace",
                        "Build_Options", "Code", "Code_Node", "Code_Literal",
                        "Code_Procedure_Call", "Code_Declaration", "Source_Code_Location",
                        "Version_Info",
                    });
                } else if (std.mem.eql(u8, module_name, "Metaprogram_Plugins")) {
                    try putPlaceholders(&r, allocator, &.{
                        "Metaprogram_Plugin", "Intercept_Flags",
                        "parse_plugin_arguments", "init_plugins",
                    });
                } else if (std.mem.eql(u8, module_name, "System") or
                    std.mem.eql(u8, module_name, "Windows") or
                    std.mem.eql(u8, module_name, "Process") or
                    std.mem.eql(u8, module_name, "Input") or
                    std.mem.eql(u8, module_name, "Window_Creation") or
                    std.mem.eql(u8, module_name, "Windows_Resources") or
                    std.mem.eql(u8, module_name, "Simp") or
                    std.mem.eql(u8, module_name, "GL") or
                    std.mem.eql(u8, module_name, "SDL") or
                    std.mem.eql(u8, module_name, "Mail") or
                    std.mem.eql(u8, module_name, "POSIX") or
                    std.mem.eql(u8, module_name, "Debug") or
                    std.mem.eql(u8, module_name, "Sort") or
                    std.mem.eql(u8, module_name, "Hash_Table") or
                    std.mem.eql(u8, module_name, "Pool") or
                    std.mem.eql(u8, module_name, "Flat_Pool") or
                    std.mem.eql(u8, module_name, "rpmalloc") or
                    std.mem.eql(u8, module_name, "Program_Print") or
                    std.mem.eql(u8, module_name, "File") or
                    std.mem.eql(u8, module_name, "File_Utilities") or
                    std.mem.eql(u8, module_name, "BuildCpp") or
                    std.mem.eql(u8, module_name, "GetRect") or
                    std.mem.eql(u8, module_name, "TestScope") or
                    std.mem.eql(u8, module_name, "Machine_X64") or
                    std.mem.eql(u8, module_name, "Check") or
                    std.mem.eql(u8, module_name, "Sound_Player") or
                    std.mem.eql(u8, module_name, "glfw") or
                    std.mem.eql(u8, module_name, "Bindings_Generator") or
                    std.mem.eql(u8, module_name, "Wav_File"))
                {
                    // Placeholder module acceptance until real module loading lands.
                    if (std.mem.eql(u8, module_name, "System")) {
                        try putPlaceholders(&r, allocator, &.{ "get_number_of_processors", "max" });
                    } else if (std.mem.eql(u8, module_name, "Windows")) {
                        try putPlaceholders(&r, allocator, &.{ "HANDLE", "GetStdHandle", "STD_INPUT_HANDLE", "STD_OUTPUT_HANDLE", "ReadConsoleA" });
                    } else if (std.mem.eql(u8, module_name, "Process")) {
                        try putPlaceholders(&r, allocator, &.{ "run_command", "read", "thread_is_done", "shutdown" });
                    } else if (std.mem.eql(u8, module_name, "File")) {
                        try putPlaceholders(&r, allocator, &.{
                            "make_directory_if_it_does_not_exist", "delete_directory", "file_exists",
                            "write_entire_file", "read_entire_file", "file_open", "file_close",
                            "file_length", "file_set_position", "file_write", "file_read",
                            "get_path_of_running_executable",
                        });
                    } else if (std.mem.eql(u8, module_name, "File_Utilities")) {
                        try putPlaceholders(&r, allocator, &.{ "delete_directory", "make_directory_if_it_does_not_exist" });
                    } else if (std.mem.eql(u8, module_name, "BuildCpp")) {
                        try putPlaceholders(&r, allocator, &.{ "build_cpp", "build_cpp_dynamic_lib", "cpp_link_library" });
                    } else if (std.mem.eql(u8, module_name, "Input")) {
                        try putPlaceholders(&r, allocator, &.{
                            "events_this_frame", "update_window_events",
                            "SDL_INIT_VIDEO", "SDL_Init", "SDL_GL_GetProcAddress",
                        });
                    } else if (std.mem.eql(u8, module_name, "Window_Creation")) {
                        try putPlaceholders(&r, allocator, &.{ "create_window" });
                    } else if (std.mem.eql(u8, module_name, "Windows_Resources")) {
                        try putPlaceholders(&r, allocator, &.{ "gl" });
                    } else if (std.mem.eql(u8, module_name, "Simp")) {
                        try putPlaceholders(&r, allocator, &.{
                            "get_font_at_size", "texture_load_from_file", "gl_load", "DrawTexturePro", "immediate_quad", "gl",
                        });
                    } else if (std.mem.eql(u8, module_name, "GL")) {
                        try putPlaceholders(&r, allocator, &.{ "gl", "gl_load", "glTexParameteri", "glGetString", "GL_VENDOR" });
                    } else if (std.mem.eql(u8, module_name, "GetRect")) {
                        try putPlaceholders(&r, allocator, &.{ "button", "slider", "dropdown", "draw_popups", "getrect_theme" });
                    } else if (std.mem.eql(u8, module_name, "Sort")) {
                        try putPlaceholders(&r, allocator, &.{ "compare_floats", "quick_sort", "bubble_sort", "compare", "compare_strings" });
                    } else if (std.mem.eql(u8, module_name, "Hash_Table")) {
                        try putPlaceholders(&r, allocator, &.{ "table_add" });
                    } else if (std.mem.eql(u8, module_name, "Pool") or std.mem.eql(u8, module_name, "Flat_Pool")) {
                        try putPlaceholders(&r, allocator, &.{ "get", "release", "reset", "pool_allocator_proc", "flat_pool_allocator_proc" });
                    } else if (std.mem.eql(u8, module_name, "Machine_X64")) {
                        try putPlaceholders(&r, allocator, &.{ "get_cpu_info", "has_feature", "check_feature", "Feature", "x86_Feature_Flag" });
                    } else if (std.mem.eql(u8, module_name, "Bindings_Generator")) {
                        try putPlaceholders(&r, allocator, &.{ "Generate_Bindings_Options", "GENERATOR_DEFAULT_SYSTEM_INCLUDE_PATH", "generate_bindings", "copy_file", "libpaths", "libnames", "include_paths", "source_files", "system_include_paths", "strip_flags", "header" });
                    } else if (std.mem.eql(u8, module_name, "Sound_Player")) {
                        try putPlaceholders(&r, allocator, &.{ "init_sound_player", "play_sound", "Sound_Player" });
                    } else if (std.mem.eql(u8, module_name, "Wav_File")) {
                        try putPlaceholders(&r, allocator, &.{ "load_wav_file", "Wav_File" });
                    } else if (std.mem.eql(u8, module_name, "glfw")) {
                        try putPlaceholders(&r, allocator, &.{ "glfwInit", "glfwTerminate", "glfwCreateWindow", "glfwMakeContextCurrent", "glfwWindowShouldClose", "glfwSwapBuffers", "glfwPollEvents", "glfwGetKey", "glfwWindowHint", "glfwSetWindowShouldClose", "GLFW_PRESS", "GLFW_TRUE", "GLFW_KEY_ESCAPE", "GLFW_CONTEXT_VERSION_MAJOR", "GLFW_CONTEXT_VERSION_MINOR" });
                    } else if (std.mem.eql(u8, module_name, "TestScope")) {
                        try r.symbols.put(allocator, "Struct1", .{ .const_value = @import("Ast.zig").null_node });
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
            .run_expr, .meta_stmt, .add_context_decl => {},
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
                try r.symbols.put(allocator, name, .{ .const_value = decl });
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
                    if (std.mem.eql(u8, name, "it") or std.mem.eql(u8, name, "it_index")) continue;
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
            if (std.mem.eql(u8, name, "it") or std.mem.eql(u8, name, "it_index")) continue;
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
                            if (std.mem.eql(u8, name, "it") or std.mem.eql(u8, name, "it_index")) {
                                try resolveNode(ast, r, child, file_id, diag);
                                continue;
                            }
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
                if (std.mem.eql(u8, name, "it") or std.mem.eql(u8, name, "it_index")) {
                    try resolveNode(ast, r, stmt, file_id, diag);
                    continue;
                }
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
        .string_literal, .integer_literal, .float_literal, .bool_literal, .null_literal, .char_literal, .undefined_literal, .type_expr, .struct_type, .union_type, .enum_type, .import_decl, .load_decl, .scope_decl => {},
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
            if (range.len == 1 or (range.len == 2 and (range[1] & 0x80000000) != 0) or range.len == 3) {
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
                    .const_value => |value_node| {
                        if (value_node == node and std.mem.eql(u8, name, "it_index")) try r.loop_indexes.put(r.allocator, node, 1);
                        if (value_node == node and std.mem.eql(u8, name, "it")) try r.loop_value_types.put(r.allocator, node, @import("InternPool.zig").InternPool.well_known.any_type);
                        try r.local_values.put(r.allocator, node, value_node);
                    },
                    .proc => |proc_node| try r.local_values.put(r.allocator, node, proc_node),
                    .placeholder => {},
                    .builtin_swap, .builtin_print, .builtin_write_string, .builtin_write_strings, .builtin_write_number, .builtin_write_nonnegative_number, .builtin_new, .builtin_free, .builtin_exit, .builtin_memcpy, .builtin_assert, .builtin_sin, .builtin_current_time_consensus, .builtin_current_time_monotonic, .builtin_to_calendar, .builtin_calendar_to_string, .builtin_random_seed, .builtin_random_get, .builtin_random_get_zero_to_one, .builtin_random_get_within_range, .builtin_format_int, .builtin_format_float, .builtin_get_type_table, .builtin_alloc, .builtin_array_add, .builtin_array_free, .builtin_get_time, .builtin_seconds_since_init, .builtin_sleep_milliseconds, .builtin_to_float64_seconds, .builtin_format_struct, .builtin_to_upper, .builtin_to_lower, .builtin_is_digit, .builtin_is_alpha, .builtin_is_alnum, .builtin_is_space, .builtin_is_any, .builtin_log, .builtin_get_field, .builtin_type_to_string, .builtin_enum_range, .builtin_enum_values_as_s64, .builtin_enum_names, .builtin_abs => {},
                }
            } else if (r.using_fallbacks.items.len != 0) {
                try r.local_values.put(r.allocator, node, r.using_fallbacks.items[r.using_fallbacks.items.len - 1]);
            } else if (isBuiltinTypeName(name)) {
                // Builtin type names can appear as first-class Type values in expressions,
                // e.g. type_of(n) == int. Leave them for Sema/codegen as identifiers.
            } else if (name.len != 0 and std.ascii.isUpper(name[0])) {
                try r.local_values.put(r.allocator, node, @import("Ast.zig").null_node);
            } else if (isMacroGeneratedIdentifier(name)) {
                try r.loop_value_types.put(r.allocator, node, @import("InternPool.zig").InternPool.well_known.any_type);
            } else {
                try r.local_values.put(r.allocator, node, @import("Ast.zig").null_node);
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

fn isBuiltinTypeName(name: []const u8) bool {
    return std.mem.eql(u8, name, "void") or std.mem.eql(u8, name, "bool") or std.mem.eql(u8, name, "string") or std.mem.eql(u8, name, "int") or std.mem.eql(u8, name, "s64") or std.mem.eql(u8, name, "float") or std.mem.eql(u8, name, "float32") or std.mem.eql(u8, name, "float64") or std.mem.eql(u8, name, "s32") or std.mem.eql(u8, name, "u8") or std.mem.eql(u8, name, "u16") or std.mem.eql(u8, name, "u32") or std.mem.eql(u8, name, "u64") or std.mem.eql(u8, name, "Vector2") or std.mem.eql(u8, name, "Vector3") or std.mem.eql(u8, name, "Type") or std.mem.eql(u8, name, "Any");
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

    var resolved = try resolve(std.testing.allocator, &ast, diag, true);
    defer resolved.deinit();

    try std.testing.expect(resolved.lookup("hidden") == null);
    try std.testing.expect(resolved.lookup("__file1_hidden") != null);
    try std.testing.expect(resolved.lookup("shown") != null);
}
