const std = @import("std");

pub const Register = u32;
pub const StringIndex = u32;

pub const Opcode = enum(u8) {
    load_int,
    load_float,
    load_string,
    load_code,
    load_source_location,
    load_calendar,
    load_bytes,
    load_bool,
    load_null_ptr,
    load_type,
    load_type_text,
    load_type_info_member,
    type_to_string,
    load_undef,
    global_addr,
    load_const_ref,
    neg_int,
    neg_float,
    not_bool,
    mul_int,
    mul_float,
    rem_int,
    add_int,
    add_float,
    sub_int,
    sub_float,
    div_int,
    div_float,
    format_print,
    format_static_int_array,
    format_static_float_array,
    format_static_string_array,
    format_int_value,
    format_float_value,
    call,
    call_foreign,
    call_proc0,
    call_extern,
    ret,
    ret_multi,
    ret_void,
    tuple_extract,
    alloc_local,
    load,
    store,
    load_ptr,
    load_ptr_byte,
    load_ptr_float,
    store_ptr,
    ptr_offset,
    ptr_offset_reg,
    store_ptr_byte,
    store_ptr_float,
    load_ptr_string,
    addr_of_local,
    proc_addr,
    alloc_heap,
    alloc_heap_reg,
    alloc_heap_owned,
    alloc_local_bytes,
    allocator_proc_call,
    allocator_owns,
    allocator_cap_flags,
    allocator_cap_name,
    pool_get,
    pool_release,
    pool_reset,
    pool_bytes_left,
    new_array,
    array_add,
    sort_array,
    array_free,
    array_pop,
    array_reset,
    array_reserve,
    array_ordered_remove_by_index,
    array_find,
    array_copy,
    array_count,
    array_data,
    array_index,
    compiler_get_nodes_root,
    compiler_get_nodes_exprs,
    code_node_field_kind,
    code_node_field_flags,
    code_node_field_expression,
    code_node_field_name,
    code_node_field_notes,
    code_node_field_type,
    code_node_field_subexpressions,
    code_node_field_enclosing_load,
    code_note_field_text,
    code_proc_call_arguments,
    code_argument_field_expression,
    code_literal_field_value_type,
    code_literal_field_s64,
    code_literal_set_s64,
    code_literal_field_string,
    code_literal_set_string,
    code_node_to_code,
    code_node_location,
    compiler_report,
    memcpy,
    memset,
    exit_process,
    free_heap,
    make_vector3,
    int_trunc_cast,
    bool_to_int_cast,
    int_to_bool_cast,
    float_cast,
    sin_float,
    sqrt_float,
    cos_float,
    current_time_consensus_low,
    current_time_monotonic_low,
    get_time_seconds,
    seconds_since_init,
    to_calendar,
    load_calendar_field,
    calendar_to_string,
    to_float64_seconds,
    random_seed,
    random_get,
    random_get_zero_to_one,
    random_get_within_range,
    compiler_arg_count,
    compiler_arg,
    compiler_read_file,
    read_entire_file,
    compiler_write_file,
    get_command_line_arguments,
    cpu_has_feature,
    sleep_milliseconds,
    make_directory,
    delete_directory,
    file_exists,
    set_working_directory,
    get_working_directory,
    get_path_of_running_executable,
    host_run_command,
    host_run_command_capture,
    host_copy_file,
    host_build_cpp_dynamic_lib,
    host_generate_bindings,
    host_add_build_string,
    host_add_build_file,
    host_compiler_create_workspace,
    host_get_current_workspace,
    host_compiler_begin_intercept,
    host_compiler_end_intercept,
    host_compiler_wait_for_message,
    message_get_field,
    load_build_options,
    host_set_build_options,
    host_set_optimization,
    host_set_workspace_status,
    host_custom_link_complete,
    build_options_get_field,
    build_options_set_field,
    type_info_field,
    type_info_member_field,
    source_location_get_field,
    file_open,
    file_close,
    file_length,
    file_set_position,
    file_write,
    file_read,
    posix_read,
    string_builder_init,
    string_builder_free,
    string_builder_append_string,
    string_builder_append_int,
    string_builder_append_float,
    string_builder_append_format,
    string_builder_to_string,
    string_builder_length,
    string_copy,
    string_to_c,
    string_from_c,
    string_from_parts,
    string_trim,
    string_compare,
    string_contains,
    string_begins_with,
    string_find,
    string_split,
    string_parse_int,
    string_parse_float,
    string_replace,
    string_len,
    string_data,
    string_slice,
    path_strip_filename,
    string_index,
    cmp_lt_int,
    cmp_le_int,
    cmp_gt_int,
    cmp_ge_int,
    cmp_eq,
    cmp_ne,
    bit_not,
    bit_and,
    bit_or,
    bit_xor,
    shl_int,
    shr_int,
    rotl_int,
    bool_and,
    bool_or,
    select_value,
    assert_true,
    jump,
    jump_if_false,
};

pub const ExternSymbol = enum(u32) {
    openjai_print,
};

pub const Instruction = struct {
    opcode: Opcode,
    dest: u32 = 0,
    arg1: u32 = 0,
    arg2: u32 = 0,
    arg3: u32 = 0,
    arg4: u32 = 0,
    arg5: u32 = 0,
    source_node: u32 = 0,
};

pub const TypeInfoMember = struct {
    name: []const u8,
    type_name: []const u8,
    flags: u32 = 0,
};

pub const TypeInfo = struct {
    name: []const u8,
    tag: u32,
    members: []TypeInfoMember,
};

pub const CodeLiteral = struct {
    text: []const u8,
    path: []const u8,
    line_number: i64,
};

pub const CalendarLiteral = struct {
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

pub const ProcBytecode = struct {
    name: []const u8,
    instructions: std.ArrayList(Instruction) = .empty,
    param_types: std.ArrayList(u32) = .empty,
    return_types: std.ArrayList(u32) = .empty,
    num_registers: u32 = 0,
    param_count: u32 = 0,
    return_type: u32 = 0,

    pub fn deinit(p: *ProcBytecode, allocator: std.mem.Allocator) void {
        p.param_types.deinit(allocator);
        p.return_types.deinit(allocator);
        p.instructions.deinit(allocator);
    }
};

pub const ForeignFunction = struct {
    name: []const u8,
    param_types: []const u32,
    return_type: u32 = 0,
};

pub const Global = struct {
    source_node: u32,
    size: u32,
    initial_bytes: ?[]const u8 = null,
};

pub const Program = struct {
    allocator: std.mem.Allocator,
    strings: std.ArrayList([]const u8) = .empty,
    code_literals: std.ArrayList(CodeLiteral) = .empty,
    calendar_literals: std.ArrayList(CalendarLiteral) = .empty,
    byte_arrays: std.ArrayList([]const u8) = .empty,
    type_info_members: std.ArrayList(TypeInfoMember) = .empty,
    globals: std.ArrayList(Global) = .empty,
    procs: std.ArrayList(ProcBytecode) = .empty,
    proc_nodes: std.ArrayList(u32) = .empty,
    foreign_functions: std.ArrayList(ForeignFunction) = .empty,
    type_infos: std.ArrayList(TypeInfo) = .empty,
    call_args: std.ArrayList(Register) = .empty,
    main_proc: ?u32 = null,

    pub fn init(allocator: std.mem.Allocator) Program {
        return .{ .allocator = allocator };
    }

    pub fn deinit(p: *Program) void {
        for (p.strings.items) |s| p.allocator.free(s);
        for (p.code_literals.items) |literal| {
            p.allocator.free(literal.text);
            p.allocator.free(literal.path);
        }
        for (p.byte_arrays.items) |b| p.allocator.free(b);
        for (p.type_info_members.items) |member| {
            p.allocator.free(member.name);
            p.allocator.free(member.type_name);
        }
        for (p.procs.items) |*proc| proc.deinit(p.allocator);
        for (p.foreign_functions.items) |foreign| {
            p.allocator.free(foreign.name);
            p.allocator.free(foreign.param_types);
        }
        for (p.type_infos.items) |info| {
            p.allocator.free(info.name);
            for (info.members) |member| {
                p.allocator.free(member.name);
                p.allocator.free(member.type_name);
            }
            p.allocator.free(info.members);
        }
        p.call_args.deinit(p.allocator);
        p.strings.deinit(p.allocator);
        p.code_literals.deinit(p.allocator);
        p.calendar_literals.deinit(p.allocator);
        p.byte_arrays.deinit(p.allocator);
        p.type_info_members.deinit(p.allocator);
        p.globals.deinit(p.allocator);
        p.procs.deinit(p.allocator);
        p.proc_nodes.deinit(p.allocator);
        p.foreign_functions.deinit(p.allocator);
        p.type_infos.deinit(p.allocator);
    }

    pub fn addProc(p: *Program, proc: ProcBytecode, source_node: u32) !u32 {
        const idx: u32 = @intCast(p.procs.items.len);
        try p.procs.append(p.allocator, proc);
        errdefer _ = p.procs.pop();
        try p.proc_nodes.append(p.allocator, source_node);
        return idx;
    }

    pub fn addForeignFunction(p: *Program, name: []const u8, param_types: []const u32, return_type: u32) !u32 {
        const owned_name = try p.allocator.dupe(u8, name);
        errdefer p.allocator.free(owned_name);
        const owned_params = try p.allocator.dupe(u32, param_types);
        errdefer p.allocator.free(owned_params);
        const idx: u32 = @intCast(p.foreign_functions.items.len);
        try p.foreign_functions.append(p.allocator, .{
            .name = owned_name,
            .param_types = owned_params,
            .return_type = return_type,
        });
        return idx;
    }

    pub fn addString(p: *Program, s: []const u8) !StringIndex {
        const owned = try p.allocator.dupe(u8, s);
        errdefer p.allocator.free(owned);
        const idx: StringIndex = @intCast(p.strings.items.len);
        try p.strings.append(p.allocator, owned);
        return idx;
    }

    pub fn addCodeLiteral(p: *Program, text: []const u8, path: []const u8, line_number: i64) !u32 {
        const owned_text = try p.allocator.dupe(u8, text);
        errdefer p.allocator.free(owned_text);
        const owned_path = try p.allocator.dupe(u8, path);
        errdefer p.allocator.free(owned_path);
        const idx: u32 = @intCast(p.code_literals.items.len);
        try p.code_literals.append(p.allocator, .{
            .text = owned_text,
            .path = owned_path,
            .line_number = line_number,
        });
        return idx;
    }

    pub fn addCalendarLiteral(p: *Program, calendar: CalendarLiteral) !u32 {
        const idx: u32 = @intCast(p.calendar_literals.items.len);
        try p.calendar_literals.append(p.allocator, calendar);
        return idx;
    }

    pub fn addByteArray(p: *Program, bytes: []const u8) !u32 {
        const owned = try p.allocator.dupe(u8, bytes);
        errdefer p.allocator.free(owned);
        const idx: u32 = @intCast(p.byte_arrays.items.len);
        try p.byte_arrays.append(p.allocator, owned);
        return idx;
    }

    pub fn addTypeInfoMemberLiteral(p: *Program, member: TypeInfoMember) !u32 {
        const owned_name = try p.allocator.dupe(u8, member.name);
        errdefer p.allocator.free(owned_name);
        const owned_type_name = try p.allocator.dupe(u8, member.type_name);
        errdefer p.allocator.free(owned_type_name);
        const idx: u32 = @intCast(p.type_info_members.items.len);
        try p.type_info_members.append(p.allocator, .{
            .name = owned_name,
            .type_name = owned_type_name,
            .flags = member.flags,
        });
        return idx;
    }

    pub fn typeInfoIndexByName(p: *const Program, name: []const u8) ?u32 {
        for (p.type_infos.items, 0..) |info, i| {
            if (std.mem.eql(u8, info.name, name)) return @intCast(i);
        }
        return null;
    }

    pub fn addTypeInfo(p: *Program, name: []const u8, tag: u32, members: []const TypeInfoMember) !u32 {
        if (p.typeInfoIndexByName(name)) |existing| return existing;
        const owned_name = try p.allocator.dupe(u8, name);
        errdefer p.allocator.free(owned_name);
        const owned_members = try p.allocator.alloc(TypeInfoMember, members.len);
        errdefer p.allocator.free(owned_members);
        var initialized: usize = 0;
        errdefer {
            for (owned_members[0..initialized]) |member| {
                p.allocator.free(member.name);
                p.allocator.free(member.type_name);
            }
        }
        for (members, 0..) |member, i| {
            owned_members[i] = .{
                .name = try p.allocator.dupe(u8, member.name),
                .type_name = try p.allocator.dupe(u8, member.type_name),
                .flags = member.flags,
            };
            initialized += 1;
        }
        const idx: u32 = @intCast(p.type_infos.items.len);
        try p.type_infos.append(p.allocator, .{ .name = owned_name, .tag = tag, .members = owned_members });
        return idx;
    }

    pub fn addGlobal(p: *Program, source_node: u32, size: u32) !u32 {
        for (p.globals.items, 0..) |global, i| {
            if (global.source_node == source_node) return @intCast(i);
        }
        const idx: u32 = @intCast(p.globals.items.len);
        try p.globals.append(p.allocator, .{ .source_node = source_node, .size = size });
        return idx;
    }

    pub fn addCallArgs(p: *Program, args: []const Register) !u32 {
        const start: u32 = @intCast(p.call_args.items.len);
        try p.call_args.appendSlice(p.allocator, args);
        return start;
    }
};
