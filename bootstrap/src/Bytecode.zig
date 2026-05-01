const std = @import("std");

pub const Register = u32;
pub const StringIndex = u32;

pub const Opcode = enum(u8) {
    load_int,
    load_float,
    load_string,
    load_bool,
    load_type,
    load_const_ref,
    mul_int,
    format_print,
    call,
    call_extern,
    ret,
    ret_void,
    alloc_local,
    load,
    store,
};

pub const ExternSymbol = enum(u32) {
    openjai_print,
};

pub const Instruction = struct {
    opcode: Opcode,
    dest: u32 = 0,
    arg1: u32 = 0,
    arg2: u32 = 0,
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
