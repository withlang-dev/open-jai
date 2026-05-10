const std = @import("std");

pub const Register = u32;
pub const StringIndex = u32;

pub const Opcode = enum(u8) {
    load_int,
    load_float,
    load_string,
    load_bytes,
    load_bool,
    load_null_ptr,
    load_type,
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
    format_int_value,
    format_float_value,
    call,
    call_proc0,
    call_extern,
    ret,
    ret_void,
    alloc_local,
    load,
    store,
    load_ptr,
    load_ptr_byte,
    store_ptr,
    ptr_offset,
    ptr_offset_reg,
    store_ptr_byte,
    load_ptr_string,
    addr_of_local,
    proc_addr,
    alloc_heap,
    alloc_local_bytes,
    new_array,
    array_add,
    array_free,
    array_count,
    array_data,
    array_index,
    compiler_get_nodes_root,
    compiler_get_nodes_exprs,
    code_node_field_kind,
    code_node_field_flags,
    memcpy,
    exit_process,
    free_heap,
    make_vector3,
    int_trunc_cast,
    bool_to_int_cast,
    int_to_bool_cast,
    float_cast,
    sin_float,
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
    compiler_write_file,
    get_command_line_arguments,
    sleep_milliseconds,
    make_directory,
    file_exists,
    file_open,
    file_close,
    file_length,
    file_set_position,
    file_write,
    file_read,
    string_builder_init,
    string_builder_free,
    string_builder_append_string,
    string_builder_append_int,
    string_builder_append_float,
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

pub const ProcBytecode = struct {
    name: []const u8,
    instructions: std.ArrayList(Instruction) = .empty,
    param_types: std.ArrayList(u32) = .empty,
    num_registers: u32 = 0,
    param_count: u32 = 0,
    return_type: u32 = 0,

    pub fn deinit(p: *ProcBytecode, allocator: std.mem.Allocator) void {
        p.param_types.deinit(allocator);
        p.instructions.deinit(allocator);
    }
};

pub const Global = struct {
    source_node: u32,
    size: u32,
    initial_bytes: ?[]const u8 = null,
};

pub const Program = struct {
    allocator: std.mem.Allocator,
    strings: std.ArrayList([]const u8) = .empty,
    byte_arrays: std.ArrayList([]const u8) = .empty,
    globals: std.ArrayList(Global) = .empty,
    procs: std.ArrayList(ProcBytecode) = .empty,
    call_args: std.ArrayList(Register) = .empty,
    main_proc: ?u32 = null,

    pub fn init(allocator: std.mem.Allocator) Program {
        return .{ .allocator = allocator };
    }

    pub fn deinit(p: *Program) void {
        for (p.strings.items) |s| p.allocator.free(s);
        for (p.byte_arrays.items) |b| p.allocator.free(b);
        for (p.procs.items) |*proc| proc.deinit(p.allocator);
        p.call_args.deinit(p.allocator);
        p.strings.deinit(p.allocator);
        p.byte_arrays.deinit(p.allocator);
        p.globals.deinit(p.allocator);
        p.procs.deinit(p.allocator);
    }

    pub fn addString(p: *Program, s: []const u8) !StringIndex {
        const owned = try p.allocator.dupe(u8, s);
        errdefer p.allocator.free(owned);
        const idx: StringIndex = @intCast(p.strings.items.len);
        try p.strings.append(p.allocator, owned);
        return idx;
    }

    pub fn addByteArray(p: *Program, bytes: []const u8) !u32 {
        const owned = try p.allocator.dupe(u8, bytes);
        errdefer p.allocator.free(owned);
        const idx: u32 = @intCast(p.byte_arrays.items.len);
        try p.byte_arrays.append(p.allocator, owned);
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
