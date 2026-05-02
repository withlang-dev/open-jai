const std = @import("std");

pub const Register = u32;
pub const StringIndex = u32;

pub const Opcode = enum(u8) {
    load_int,
    load_float,
    load_string,
    load_bool,
    load_null_ptr,
    load_type,
    load_undef,
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
    div_float,
    format_print,
    call,
    call_proc0,
    call_extern,
    ret,
    ret_void,
    alloc_local,
    load,
    store,
    load_ptr,
    store_ptr,
    addr_of_local,
    proc_addr,
    alloc_heap,
    memcpy,
    exit_process,
    free_heap,
    make_vector3,
    int_trunc_cast,
    float_cast,
    sin_float,
    cmp_lt_int,
    cmp_eq,
    cmp_ne,
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
    source_node: u32 = 0,
};

pub const ProcBytecode = struct {
    name: []const u8,
    instructions: std.ArrayList(Instruction) = .empty,
    num_registers: u32 = 0,
    param_count: u32 = 0,
    return_type: u32 = 0,

    pub fn deinit(p: *ProcBytecode, allocator: std.mem.Allocator) void {
        p.instructions.deinit(allocator);
    }
};

pub const Program = struct {
    allocator: std.mem.Allocator,
    strings: std.ArrayList([]const u8) = .empty,
    procs: std.ArrayList(ProcBytecode) = .empty,
    main_proc: u32 = 0,

    pub fn init(allocator: std.mem.Allocator) Program { return .{ .allocator = allocator }; }

    pub fn deinit(p: *Program) void {
        for (p.strings.items) |s| p.allocator.free(s);
        for (p.procs.items) |*proc| proc.deinit(p.allocator);
        p.strings.deinit(p.allocator);
        p.procs.deinit(p.allocator);
    }

    pub fn addString(p: *Program, s: []const u8) !StringIndex {
        const owned = try p.allocator.dupe(u8, s);
        errdefer p.allocator.free(owned);
        const idx: StringIndex = @intCast(p.strings.items.len);
        try p.strings.append(p.allocator, owned);
        return idx;
    }
};
