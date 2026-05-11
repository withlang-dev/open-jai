const std = @import("std");
const Bytecode = @import("Bytecode.zig");
const Diagnostic = @import("diagnostics.zig").Diagnostic;

pub const Value = union(enum) {
    void,
    int: i64,
    float: f64,
    bool: bool,
    string: []const u8,
    bytes: []const u8,
};

const Pointer = struct {
    block: u32,
    offset: usize,
};

const CodeNode = struct {
    tree: u32 = std.math.maxInt(u32),
    index: u32 = std.math.maxInt(u32),
    kind: []const u8,
    flags: []const u8,
    text: []const u8,
    start: usize = 0,
    end: usize = 0,
    s64: ?i64 = null,
};

const CodeTree = struct {
    source: []const u8,
    nodes: []CodeNode,
};

const RegisterValue = union(enum) {
    empty,
    string: []const u8,
    bytes: []const u8,
    code_node: CodeNode,
    code_nodes: []const CodeNode,
    type_id: u32,
    ptr: Pointer,
    int: i64,
    float: f64,
    bool: bool,
};

const DynamicArray = struct {
    header: ?Pointer = null,
    slot: ?Pointer = null,
    data: ?Pointer = null,
    elem_size: usize = 1,
    elems: std.ArrayList(RegisterValue) = .empty,
};

pub const VM = struct {
    allocator: std.mem.Allocator,
    program: *const Bytecode.Program,
    memory_blocks: std.ArrayList([]u8) = .empty,
    global_ptrs: std.ArrayList(?Pointer) = .empty,
    string_builders: std.AutoHashMapUnmanaged(u64, std.ArrayList(u8)) = .empty,
    dynamic_arrays: std.ArrayList(DynamicArray) = .empty,
    dynamic_array_refs: std.AutoHashMapUnmanaged(u64, usize) = .empty,
    code_trees: std.ArrayList(CodeTree) = .empty,
    rendered_code_strings: std.ArrayList([]const u8) = .empty,

    pub fn init(allocator: std.mem.Allocator, program: *const Bytecode.Program) VM {
        return .{ .allocator = allocator, .program = program };
    }

    pub fn deinit(vm: *VM) void {
        for (vm.memory_blocks.items) |block| vm.allocator.free(block);
        vm.memory_blocks.deinit(vm.allocator);
        vm.global_ptrs.deinit(vm.allocator);
        var builder_it = vm.string_builders.iterator();
        while (builder_it.next()) |entry| entry.value_ptr.deinit(vm.allocator);
        vm.string_builders.deinit(vm.allocator);
        for (vm.dynamic_arrays.items) |*array| array.elems.deinit(vm.allocator);
        vm.dynamic_arrays.deinit(vm.allocator);
        vm.dynamic_array_refs.deinit(vm.allocator);
        for (vm.code_trees.items) |tree| vm.allocator.free(tree.nodes);
        vm.code_trees.deinit(vm.allocator);
        for (vm.rendered_code_strings.items) |text| vm.allocator.free(text);
        vm.rendered_code_strings.deinit(vm.allocator);
    }

    pub fn runProc(vm: *VM, proc_index: u32, diag: Diagnostic) !Value {
        return vm.runProcWithArgs(proc_index, &.{}, diag);
    }

    pub fn runProcWithArgs(vm: *VM, proc_index: u32, args: []const Value, diag: Diagnostic) !Value {
        if (proc_index >= vm.program.procs.items.len) return diag.failAt(0, "#run target procedure index out of range", .{});
        const proc = &vm.program.procs.items[proc_index];
        var regs = try vm.allocator.alloc(RegisterValue, proc.num_registers);
        defer vm.allocator.free(regs);
        @memset(regs, .empty);
        var local_ptrs = try vm.allocator.alloc(?Pointer, proc.num_registers);
        defer vm.allocator.free(local_ptrs);
        @memset(local_ptrs, null);
        if (args.len > regs.len) return diag.failAt(0, "VM #run argument count exceeds register file", .{});
        for (args, 0..) |arg, i| {
            regs[i] = switch (arg) {
                .int => |v| .{ .int = v },
                .float => |v| .{ .float = v },
                .bool => |v| .{ .bool = v },
                .string => |v| .{ .string = v },
                .bytes => |v| .{ .bytes = v },
                .void => return diag.failAt(0, "VM #run arguments cannot be void", .{}),
            };
        }
        var ip: usize = 0;
        while (ip < proc.instructions.items.len) {
            const inst = proc.instructions.items[ip];
            ip += 1;
            switch (inst.opcode) {
                .load_string => {
                    if (inst.dest >= regs.len or inst.arg1 >= vm.program.strings.items.len) return diag.failAt(0, "VM load_string register/string index out of range", .{});
                    regs[inst.dest] = .{ .string = vm.program.strings.items[inst.arg1] };
                },
                .load_bytes => {
                    if (inst.dest >= regs.len or inst.arg1 >= vm.program.byte_arrays.items.len) return diag.failAt(0, "VM load_bytes register/byte-array index out of range", .{});
                    regs[inst.dest] = .{ .bytes = vm.program.byte_arrays.items[inst.arg1] };
                },
                .load_int => {
                    if (inst.dest >= regs.len) return diag.failAt(0, "VM load_int register out of range", .{});
                    regs[inst.dest] = .{ .int = @intCast(inst.arg1) };
                },
                .load_float => {
                    if (inst.dest >= regs.len) return diag.failAt(0, "VM load_float register out of range", .{});
                    const bits = (@as(u64, inst.arg2) << 32) | inst.arg1;
                    regs[inst.dest] = .{ .float = @bitCast(bits) };
                },
                .load_bool => {
                    if (inst.dest >= regs.len) return diag.failAt(0, "VM load_bool register out of range", .{});
                    regs[inst.dest] = .{ .bool = inst.arg1 != 0 };
                },
                .load_type => {
                    if (inst.dest >= regs.len) return diag.failAt(0, "VM load_type register out of range", .{});
                    regs[inst.dest] = .{ .type_id = inst.arg1 };
                },
                .load_null_ptr, .load_const_ref => {
                    if (inst.dest >= regs.len) return diag.failAt(0, "VM placeholder/reference load register out of range", .{});
                    regs[inst.dest] = .{ .int = @intCast(inst.arg1) };
                },
                .global_addr => {
                    if (inst.dest >= regs.len or inst.arg1 >= vm.program.globals.items.len) return diag.failAt(0, "VM global_addr register/global index out of range", .{});
                    regs[inst.dest] = .{ .ptr = try vm.globalPtr(inst.arg1) };
                },
                .load_undef => {
                    if (inst.dest >= regs.len) return diag.failAt(0, "VM undefined load register out of range", .{});
                    regs[inst.dest] = .{ .int = 0 };
                },
                .string_len => {
                    if (inst.dest >= regs.len or inst.arg1 >= regs.len) return diag.failAt(0, "VM string_len register out of range", .{});
                    regs[inst.dest] = .{ .int = @intCast(switch (regs[inst.arg1]) {
                        .string => |v| v.len,
                        else => return diag.failAt(0, "VM string_len requires string operand", .{}),
                    }) };
                },
                .string_data => {
                    if (inst.dest >= regs.len or inst.arg1 >= regs.len) return diag.failAt(0, "VM string_data register out of range", .{});
                    _ = switch (regs[inst.arg1]) {
                        .string => |v| v,
                        else => return diag.failAt(0, "VM string_data requires string operand", .{}),
                    };
                    regs[inst.dest] = .{ .int = 0 };
                },
                .string_index => {
                    if (inst.dest >= regs.len or inst.arg1 >= regs.len or inst.arg2 >= regs.len) return diag.failAt(0, "VM string_index register out of range", .{});
                    const bytes = switch (regs[inst.arg1]) {
                        .string => |v| v,
                        else => return diag.failAt(0, "VM string_index requires string operand", .{}),
                    };
                    const index = switch (regs[inst.arg2]) {
                        .int => |v| v,
                        else => return diag.failAt(0, "VM string_index requires integer index", .{}),
                    };
                    if (index < 0 or index >= bytes.len) return diag.failAt(0, "VM string index out of bounds", .{});
                    regs[inst.dest] = .{ .int = bytes[@intCast(index)] };
                },
                .cmp_lt_int => {
                    if (inst.dest >= regs.len or inst.arg1 >= regs.len or inst.arg2 >= regs.len) return diag.failAt(0, "VM cmp_lt_int register out of range", .{});
                    const lhs = switch (regs[inst.arg1]) {
                        .int => |v| v,
                        else => return diag.failAt(0, "VM cmp_lt_int requires integer lhs", .{}),
                    };
                    const rhs = switch (regs[inst.arg2]) {
                        .int => |v| v,
                        else => return diag.failAt(0, "VM cmp_lt_int requires integer rhs", .{}),
                    };
                    regs[inst.dest] = .{ .bool = lhs < rhs };
                },
                .cmp_le_int, .cmp_gt_int, .cmp_ge_int => {
                    if (inst.dest >= regs.len or inst.arg1 >= regs.len or inst.arg2 >= regs.len) return diag.failAt(0, "VM integer comparison register out of range", .{});
                    const lhs = try numericAsFloatOrInt(regs[inst.arg1], diag, "integer comparison lhs");
                    const rhs = try numericAsFloatOrInt(regs[inst.arg2], diag, "integer comparison rhs");
                    regs[inst.dest] = .{ .bool = switch (inst.opcode) {
                        .cmp_le_int => lhs <= rhs,
                        .cmp_gt_int => lhs > rhs,
                        .cmp_ge_int => lhs >= rhs,
                        else => unreachable,
                    } };
                },
                .cmp_eq, .cmp_ne => {
                    if (inst.dest >= regs.len or inst.arg1 >= regs.len or inst.arg2 >= regs.len) return diag.failAt(0, "VM equality comparison register out of range", .{});
                    const equal = registerValuesEqual(regs[inst.arg1], regs[inst.arg2]);
                    regs[inst.dest] = .{ .bool = if (inst.opcode == .cmp_eq) equal else !equal };
                },
                .jump => {
                    if (inst.arg1 >= proc.instructions.items.len) return diag.failAt(0, "VM jump target out of range", .{});
                    ip = inst.arg1;
                },
                .jump_if_false => {
                    if (inst.arg1 >= regs.len or inst.arg2 > proc.instructions.items.len) return diag.failAt(0, "VM conditional jump out of range", .{});
                    const cond = try registerTruthy(regs[inst.arg1], diag, "conditional jump");
                    if (!cond) ip = inst.arg2;
                },
                .neg_int => {
                    if (inst.dest >= regs.len or inst.arg1 >= regs.len) return diag.failAt(0, "VM neg_int register out of range", .{});
                    regs[inst.dest] = .{ .int = -switch (regs[inst.arg1]) {
                        .int => |v| v,
                        else => return diag.failAt(0, "VM neg_int requires integer operand", .{}),
                    } };
                },
                .neg_float => {
                    if (inst.dest >= regs.len or inst.arg1 >= regs.len) return diag.failAt(0, "VM neg_float register out of range", .{});
                    regs[inst.dest] = .{ .float = -switch (regs[inst.arg1]) {
                        .float => |v| v,
                        .int => |v| @as(f64, @floatFromInt(v)),
                        else => return diag.failAt(0, "VM neg_float requires numeric operand", .{}),
                    } };
                },
                .not_bool => {
                    if (inst.dest >= regs.len or inst.arg1 >= regs.len) return diag.failAt(0, "VM not_bool register out of range", .{});
                    const value = try registerTruthy(regs[inst.arg1], diag, "not operand");
                    regs[inst.dest] = .{ .bool = !value };
                },
                .bool_to_int_cast => {
                    if (inst.dest >= regs.len or inst.arg1 >= regs.len) return diag.failAt(0, "VM bool_to_int_cast register out of range", .{});
                    const value = switch (regs[inst.arg1]) {
                        .bool => |v| v,
                        else => return diag.failAt(0, "VM bool_to_int_cast requires bool operand", .{}),
                    };
                    regs[inst.dest] = .{ .int = if (value) 1 else 0 };
                },
                .int_to_bool_cast => {
                    if (inst.dest >= regs.len or inst.arg1 >= regs.len) return diag.failAt(0, "VM int_to_bool_cast register out of range", .{});
                    regs[inst.dest] = .{ .bool = switch (regs[inst.arg1]) {
                        .int => |v| v != 0,
                        .float => |v| v != 0,
                        .bool => |v| v,
                        else => return diag.failAt(0, "VM int_to_bool_cast requires numeric or bool operand", .{}),
                    } };
                },
                .float_cast => {
                    if (inst.dest >= regs.len or inst.arg1 >= regs.len) return diag.failAt(0, "VM float_cast register out of range", .{});
                    regs[inst.dest] = .{ .float = switch (regs[inst.arg1]) {
                        .float => |v| v,
                        .int => |v| @as(f64, @floatFromInt(v)),
                        .bool => |v| if (v) 1 else 0,
                        else => return diag.failAt(0, "VM float_cast requires numeric or bool operand", .{}),
                    } };
                },
                .bit_not => {
                    if (inst.dest >= regs.len or inst.arg1 >= regs.len) return diag.failAt(0, "VM bit_not register out of range", .{});
                    const value = switch (regs[inst.arg1]) {
                        .int => |v| v,
                        else => return diag.failAt(0, "VM bit_not requires integer operand", .{}),
                    };
                    regs[inst.dest] = .{ .int = ~value };
                },
                .mul_int, .rem_int, .add_int, .sub_int, .div_int, .bit_and, .bit_or, .bit_xor, .shl_int, .shr_int, .rotl_int => {
                    if (inst.dest >= regs.len or inst.arg1 >= regs.len or inst.arg2 >= regs.len) return diag.failAt(0, "VM integer arithmetic register out of range", .{});
                    const lhs = switch (regs[inst.arg1]) {
                        .int => |v| v,
                        else => return diag.failAt(0, "VM {s} requires integer lhs, got {s}", .{ @tagName(inst.opcode), @tagName(regs[inst.arg1]) }),
                    };
                    const rhs = switch (regs[inst.arg2]) {
                        .int => |v| v,
                        else => return diag.failAt(0, "VM {s} requires integer rhs, got {s}", .{ @tagName(inst.opcode), @tagName(regs[inst.arg2]) }),
                    };
                    regs[inst.dest] = .{ .int = switch (inst.opcode) {
                        .mul_int => lhs * rhs,
                        .rem_int => @rem(lhs, rhs),
                        .add_int => lhs + rhs,
                        .sub_int => lhs - rhs,
                        .div_int => @divTrunc(lhs, rhs),
                        .bit_and => lhs & rhs,
                        .bit_or => lhs | rhs,
                        .bit_xor => lhs ^ rhs,
                        .shl_int, .rotl_int => lhs << @intCast(@mod(rhs, @as(i64, @bitSizeOf(i64)))),
                        .shr_int => lhs >> @intCast(@mod(rhs, @as(i64, @bitSizeOf(i64)))),
                        else => unreachable,
                    } };
                },
                .bool_and, .bool_or => {
                    if (inst.dest >= regs.len or inst.arg1 >= regs.len or inst.arg2 >= regs.len) return diag.failAt(0, "VM boolean operator register out of range", .{});
                    const lhs = try registerTruthy(regs[inst.arg1], diag, "boolean lhs");
                    const rhs = try registerTruthy(regs[inst.arg2], diag, "boolean rhs");
                    regs[inst.dest] = .{ .bool = if (inst.opcode == .bool_and) lhs and rhs else lhs or rhs };
                },
                .select_value => {
                    if (inst.dest >= regs.len or inst.arg1 >= regs.len or inst.arg2 >= regs.len or inst.arg3 >= regs.len) return diag.failAt(0, "VM select register out of range", .{});
                    const cond = try registerTruthy(regs[inst.arg1], diag, "select condition");
                    regs[inst.dest] = if (cond) regs[inst.arg2] else regs[inst.arg3];
                },
                .mul_float, .add_float, .sub_float, .div_float => {
                    if (inst.dest >= regs.len or inst.arg1 >= regs.len or inst.arg2 >= regs.len) return diag.failAt(0, "VM float arithmetic register out of range", .{});
                    const lhs = switch (regs[inst.arg1]) {
                        .float => |v| v,
                        .int => |v| @as(f64, @floatFromInt(v)),
                        else => return diag.failAt(0, "VM float arithmetic requires numeric lhs", .{}),
                    };
                    const rhs = switch (regs[inst.arg2]) {
                        .float => |v| v,
                        .int => |v| @as(f64, @floatFromInt(v)),
                        else => return diag.failAt(0, "VM float arithmetic requires numeric rhs", .{}),
                    };
                    regs[inst.dest] = .{ .float = switch (inst.opcode) {
                        .mul_float => lhs * rhs,
                        .add_float => lhs + rhs,
                        .sub_float => lhs - rhs,
                        .div_float => lhs / rhs,
                        else => unreachable,
                    } };
                },
                .load => {
                    if (inst.dest >= regs.len or inst.arg1 >= regs.len) return diag.failAt(0, "VM load register out of range", .{});
                    regs[inst.dest] = regs[inst.arg1];
                },
                .store => {
                    if (inst.dest >= regs.len or inst.arg1 >= regs.len) return diag.failAt(0, "VM store register out of range", .{});
                    regs[inst.dest] = regs[inst.arg1];
                },
                .addr_of_local => {
                    if (inst.dest >= regs.len or inst.arg1 >= regs.len) return diag.failAt(0, "VM addr_of_local register out of range", .{});
                    const ptr = local_ptrs[inst.arg1] orelse blk: {
                        const allocated = try vm.materializeRegister(regs[inst.arg1], diag);
                        local_ptrs[inst.arg1] = allocated;
                        break :blk allocated;
                    };
                    regs[inst.dest] = .{ .ptr = ptr };
                },
                .proc_addr => {
                    if (inst.dest >= regs.len) return diag.failAt(0, "VM proc_addr register out of range", .{});
                    regs[inst.dest] = .{ .int = 1 };
                },
                .call_extern => {
                    if (inst.dest != @intFromEnum(Bytecode.ExternSymbol.openjai_print)) return diag.failAt(0, "VM only supports compile-time print extern calls", .{});
                    if (inst.arg1 >= regs.len) return diag.failAt(0, "VM print argument register out of range", .{});
                    try vm.printValue(regs[inst.arg1], diag, "compile-time print");
                },
                .call => {
                    if (inst.arg1 >= vm.program.procs.items.len) return diag.failAt(0, "VM call target procedure index out of range", .{});
                    if (inst.arg3 + inst.arg2 > vm.program.call_args.items.len) return diag.failAt(0, "VM call argument table out of range", .{});
                    const call_args = try vm.allocator.alloc(Value, inst.arg2);
                    defer vm.allocator.free(call_args);
                    for (call_args, 0..) |*arg, arg_index| {
                        const reg_index = vm.program.call_args.items[inst.arg3 + arg_index];
                        if (reg_index >= regs.len) return diag.failAt(0, "VM call argument register out of range", .{});
                        arg.* = try registerValueToValue(regs[reg_index], diag);
                    }
                    const result = try vm.runProcWithArgs(inst.arg1, call_args, diag);
                    if (result != .void) {
                        if (inst.dest >= regs.len) return diag.failAt(0, "VM call result register out of range", .{});
                        regs[inst.dest] = registerValueFromValue(result);
                    }
                },
                .format_print => {
                    if (inst.arg1 >= regs.len) return diag.failAt(0, "VM format_print register out of range", .{});
                    try vm.printValue(regs[inst.arg1], diag, "format_print");
                },
                .current_time_consensus_low, .current_time_monotonic_low => {
                    if (inst.dest >= regs.len) return diag.failAt(0, "VM time destination register out of range", .{});
                    regs[inst.dest] = .{ .int = 0 };
                },
                .get_time_seconds, .seconds_since_init, .to_float64_seconds => {
                    if (inst.dest >= regs.len) return diag.failAt(0, "VM time float destination register out of range", .{});
                    regs[inst.dest] = .{ .float = 0 };
                },
                .to_calendar => {
                    if (inst.dest >= regs.len or inst.arg1 >= regs.len) return diag.failAt(0, "VM to_calendar register out of range", .{});
                    regs[inst.dest] = regs[inst.arg1];
                },
                .calendar_to_string => {
                    if (inst.dest >= regs.len or inst.arg1 >= regs.len) return diag.failAt(0, "VM calendar_to_string register out of range", .{});
                    regs[inst.dest] = .{ .string = "" };
                },
                .ret => {
                    if (inst.arg1 >= regs.len) return diag.failAt(0, "VM return register out of range", .{});
                    return switch (regs[inst.arg1]) {
                        .int => |value| .{ .int = value },
                        .float => |value| .{ .float = value },
                        .bool => |value| .{ .bool = value },
                        .string => |value| .{ .string = value },
                        .bytes => |value| .{ .bytes = value },
                        .ptr => |ptr| .{ .bytes = try vm.readRemainingBytes(ptr, diag) },
                        else => diag.failAt(0, "VM #run return register was not initialized", .{}),
                    };
                },
                .assert_true => {
                    if (inst.arg1 >= regs.len) return diag.failAt(0, "VM assert register out of range", .{});
                    if (!try registerTruthy(regs[inst.arg1], diag, "assert condition")) {
                        return diag.failAt(inst.source_node, "compile-time assert failed", .{});
                    }
                },
                .ret_void => return .void,
                .exit_process => return .void,
                .alloc_heap => {
                    if (inst.dest >= regs.len) return diag.failAt(0, "VM alloc_heap destination register out of range", .{});
                    regs[inst.dest] = .{ .ptr = try vm.allocBlock(@max(inst.arg1, 1)) };
                },
                .alloc_heap_reg, .alloc_heap_owned => {
                    if (inst.dest >= regs.len or inst.arg1 >= regs.len) return diag.failAt(0, "VM allocator allocation register out of range", .{});
                    const size = try registerInt(regs[inst.arg1], diag, "allocation size");
                    regs[inst.dest] = .{ .ptr = try vm.allocBlock(@intCast(@max(size, 1))) };
                },
                .allocator_proc_call => {
                    if (inst.dest >= regs.len) return diag.failAt(0, "VM allocator_proc_call destination register out of range", .{});
                    regs[inst.dest] = .{ .int = 0 };
                },
                .allocator_owns => {
                    if (inst.dest >= regs.len) return diag.failAt(0, "VM allocator_owns destination register out of range", .{});
                    regs[inst.dest] = .{ .bool = false };
                },
                .allocator_cap_flags => {
                    if (inst.dest >= regs.len) return diag.failAt(0, "VM allocator_cap_flags destination register out of range", .{});
                    regs[inst.dest] = .{ .int = 8 };
                },
                .allocator_cap_name => {
                    if (inst.dest >= regs.len) return diag.failAt(0, "VM allocator_cap_name destination register out of range", .{});
                    regs[inst.dest] = .{ .string = "OpenJai allocator" };
                },
                .pool_get => {
                    if (inst.dest >= regs.len or inst.arg2 >= regs.len) return diag.failAt(0, "VM pool_get register out of range", .{});
                    const size = try registerInt(regs[inst.arg2], diag, "pool allocation size");
                    regs[inst.dest] = .{ .ptr = try vm.allocBlock(@intCast(@max(size, 1))) };
                },
                .pool_release, .pool_reset => {},
                .pool_bytes_left => {
                    if (inst.dest >= regs.len) return diag.failAt(0, "VM pool_bytes_left destination register out of range", .{});
                    regs[inst.dest] = .{ .int = 0 };
                },
                .load_ptr, .load_ptr_byte, .load_ptr_float => {
                    if (inst.dest >= regs.len or inst.arg1 >= regs.len) return diag.failAt(0, "VM load_ptr register out of range", .{});
                    const ptr = try registerPointer(regs[inst.arg1], diag, "load_ptr");
                    regs[inst.dest] = if (inst.opcode == .load_ptr_byte)
                        .{ .int = try vm.loadByte(ptr, diag) }
                    else if (inst.opcode == .load_ptr_float)
                        .{ .float = @bitCast(try vm.loadU64(ptr, diag)) }
                    else
                        .{ .int = @bitCast(try vm.loadU64(ptr, diag)) };
                },
                .ptr_offset => {
                    if (inst.dest >= regs.len or inst.arg1 >= regs.len) return diag.failAt(0, "VM ptr_offset register out of range", .{});
                    var ptr = try registerPointer(regs[inst.arg1], diag, "ptr_offset");
                    ptr.offset += inst.arg2;
                    regs[inst.dest] = .{ .ptr = ptr };
                },
                .ptr_offset_reg => {
                    if (inst.dest >= regs.len or inst.arg1 >= regs.len or inst.arg2 >= regs.len) return diag.failAt(0, "VM ptr_offset_reg register out of range", .{});
                    var ptr = try registerPointer(regs[inst.arg1], diag, "ptr_offset_reg");
                    const offset = switch (regs[inst.arg2]) {
                        .int => |v| v,
                        else => return diag.failAt(0, "VM ptr_offset_reg requires integer offset", .{}),
                    };
                    if (offset < 0) return diag.failAt(0, "VM ptr_offset_reg does not support negative offsets yet", .{});
                    ptr.offset += @intCast(offset);
                    regs[inst.dest] = .{ .ptr = ptr };
                },
                .alloc_local_bytes => {
                    if (inst.dest >= regs.len) return diag.failAt(0, "VM pointer/array destination register out of range", .{});
                    regs[inst.dest] = .{ .ptr = try vm.allocBlock(@max(inst.arg1, 1)) };
                },
                .new_array => {
                    if (inst.dest >= regs.len) return diag.failAt(0, "VM new_array destination register out of range", .{});
                    regs[inst.dest] = .{ .ptr = try vm.newDynamicArray(@intCast(inst.arg1), @intCast(@max(inst.arg2, 1)), diag) };
                },
                .array_add => {
                    if (inst.dest >= regs.len or inst.arg1 >= regs.len or inst.arg2 >= regs.len) return diag.failAt(0, "VM array_add register out of range", .{});
                    const slot = try registerPointer(regs[inst.arg1], diag, "array_add slot");
                    regs[inst.dest] = .{ .ptr = try vm.dynamicArrayAdd(slot, regs[inst.arg2], @intCast(@max(inst.arg3, 1)), diag) };
                },
                .sort_array => {
                    if (inst.dest >= regs.len or inst.arg1 >= regs.len) return diag.failAt(0, "VM sort_array register out of range", .{});
                    const array_ptr = try registerPointer(regs[inst.arg1], diag, "sort_array");
                    try vm.sortDynamicArray(array_ptr, inst.arg4, diag);
                    regs[inst.dest] = regs[inst.arg1];
                },
                .array_count => {
                    if (inst.dest >= regs.len or inst.arg1 >= regs.len) return diag.failAt(0, "VM array_count register out of range", .{});
                    regs[inst.dest] = .{ .int = @intCast(try vm.arrayCount(regs[inst.arg1], diag)) };
                },
                .array_data => {
                    if (inst.dest >= regs.len or inst.arg1 >= regs.len) return diag.failAt(0, "VM array_data register out of range", .{});
                    regs[inst.dest] = switch (regs[inst.arg1]) {
                        .bytes => |bytes| .{ .ptr = try vm.materializeRegister(.{ .bytes = bytes }, diag) },
                        .ptr => |ptr| .{ .ptr = try vm.dynamicArrayData(ptr, diag) orelse ptr },
                        else => return diag.failAt(0, "VM array_data requires array-compatible value", .{}),
                    };
                },
                .array_index => {
                    if (inst.dest >= regs.len or inst.arg1 >= regs.len or inst.arg2 >= regs.len) return diag.failAt(0, "VM array_index register out of range", .{});
                    const index = switch (regs[inst.arg2]) {
                        .int => |v| v,
                        else => return diag.failAt(0, "VM array_index requires integer index", .{}),
                    };
                    if (index < 0) return diag.failAt(0, "VM array_index does not support negative indices", .{});
                    const elem_size: usize = @intCast(@max(inst.arg3, 1));
                    switch (regs[inst.arg1]) {
                        .bytes => |bytes| {
                            const offset = @as(usize, @intCast(index)) * elem_size;
                            if (offset + elem_size > bytes.len) return diag.failAt(0, "VM array_index out of bounds", .{});
                            regs[inst.dest] = if (inst.arg4 == 1)
                                .{ .bytes = bytes[offset .. offset + elem_size] }
                            else if (elem_size == 1)
                                .{ .int = bytes[offset] }
                            else
                                .{ .int = readIntLittle(bytes[offset .. offset + @min(elem_size, 8)]) };
                        },
                        .ptr => |ptr| {
                            if (try vm.dynamicArrayIndex(ptr, @intCast(index), elem_size, inst.arg4, diag)) |item_value| {
                                regs[inst.dest] = item_value;
                                continue;
                            }
                            var item = ptr;
                            item.offset += @as(usize, @intCast(index)) * elem_size;
                            regs[inst.dest] = if (inst.arg4 == 1)
                                .{ .ptr = item }
                            else if (inst.arg4 == 2)
                                return diag.failAt(0, "VM array_index cannot load string elements from an untracked raw pointer", .{})
                            else if (elem_size == 1)
                                .{ .int = try vm.loadByte(item, diag) }
                            else
                                .{ .int = @bitCast(try vm.loadU64(item, diag)) };
                        },
                        .code_nodes => |nodes| {
                            if (index >= nodes.len) return diag.failAt(0, "VM Code_Node array index out of bounds", .{});
                            regs[inst.dest] = .{ .code_node = nodes[@intCast(index)] };
                        },
                        else => return diag.failAt(0, "VM array_index requires array or pointer value", .{}),
                    }
                },
                .compiler_get_nodes_root => {
                    if (inst.dest >= regs.len or inst.arg1 >= regs.len) return diag.failAt(0, "VM compiler_get_nodes root register out of range", .{});
                    const text = try registerCodeText(regs[inst.arg1], diag, "compiler_get_nodes");
                    const tree = try vm.ensureCodeTree(text);
                    regs[inst.dest] = .{ .code_node = .{ .tree = tree, .kind = "ROOT", .flags = "0", .text = text } };
                },
                .compiler_get_nodes_exprs => {
                    if (inst.dest >= regs.len or inst.arg1 >= regs.len) return diag.failAt(0, "VM compiler_get_nodes expressions register out of range", .{});
                    const text = try registerCodeText(regs[inst.arg1], diag, "compiler_get_nodes");
                    const tree = try vm.ensureCodeTree(text);
                    regs[inst.dest] = .{ .code_nodes = vm.code_trees.items[tree].nodes };
                },
                .code_node_field_kind => {
                    if (inst.dest >= regs.len or inst.arg1 >= regs.len) return diag.failAt(0, "VM Code_Node.kind register out of range", .{});
                    const node = switch (regs[inst.arg1]) {
                        .code_node => |v| v,
                        else => return diag.failAt(0, "VM Code_Node.kind requires a Code_Node value", .{}),
                    };
                    regs[inst.dest] = .{ .string = node.kind };
                },
                .code_node_field_flags => {
                    if (inst.dest >= regs.len or inst.arg1 >= regs.len) return diag.failAt(0, "VM Code_Node.node_flags register out of range", .{});
                    const node = switch (regs[inst.arg1]) {
                        .code_node => |v| v,
                        else => return diag.failAt(0, "VM Code_Node.node_flags requires a Code_Node value", .{}),
                    };
                    regs[inst.dest] = .{ .string = node.flags };
                },
                .code_literal_field_value_type => {
                    if (inst.dest >= regs.len or inst.arg1 >= regs.len) return diag.failAt(0, "VM Code_Literal.value_type register out of range", .{});
                    const node = switch (regs[inst.arg1]) {
                        .code_node => |v| v,
                        else => return diag.failAt(0, "VM Code_Literal.value_type requires a Code_Node value", .{}),
                    };
                    regs[inst.dest] = .{ .int = if (node.s64 != null) 0 else 1 };
                },
                .code_literal_field_s64 => {
                    if (inst.dest >= regs.len or inst.arg1 >= regs.len) return diag.failAt(0, "VM Code_Literal._s64 register out of range", .{});
                    const node = try vm.currentCodeNode(regs[inst.arg1], diag, "Code_Literal._s64");
                    regs[inst.dest] = .{ .int = node.s64 orelse return diag.failAt(0, "VM Code_Literal._s64 requires a numeric literal node", .{}) };
                },
                .code_literal_set_s64 => {
                    if (inst.arg1 >= regs.len or inst.arg2 >= regs.len) return diag.failAt(0, "VM Code_Literal._s64 setter register out of range", .{});
                    const value = switch (regs[inst.arg2]) {
                        .int => |v| v,
                        else => return diag.failAt(0, "VM Code_Literal._s64 setter requires integer source", .{}),
                    };
                    try vm.updateCodeLiteralS64(regs[inst.arg1], value, diag);
                    if (inst.dest < regs.len) regs[inst.dest] = .{ .int = value };
                },
                .code_node_to_code => {
                    if (inst.dest >= regs.len or inst.arg1 >= regs.len) return diag.failAt(0, "VM compiler_get_code register out of range", .{});
                    const node = switch (regs[inst.arg1]) {
                        .code_node => |v| v,
                        else => return diag.failAt(0, "VM compiler_get_code requires a Code_Node value", .{}),
                    };
                    regs[inst.dest] = .{ .string = try vm.renderCodeNode(node, diag) };
                },
                .cpu_has_feature => {
                    if (inst.dest >= regs.len) return diag.failAt(0, "VM cpu_has_feature destination register out of range", .{});
                    regs[inst.dest] = .{ .bool = false };
                },
                .load_ptr_string, .string_slice => {
                    if (inst.dest >= regs.len) return diag.failAt(0, "VM pointer/array destination register out of range", .{});
                    return diag.failAt(0, "VM does not support opcode {s} in #run yet", .{@tagName(inst.opcode)});
                },
                .format_static_int_array, .format_static_float_array, .format_static_string_array => {
                    return diag.failAt(0, "VM does not support static array formatted output in #run yet", .{});
                },
                .sleep_milliseconds => {
                    return diag.failAt(0, "VM does not support sleep_milliseconds in #run yet", .{});
                },
                .get_command_line_arguments, .file_open => {
                    if (inst.dest >= regs.len) return diag.failAt(0, "VM runtime API destination register out of range", .{});
                    return diag.failAt(0, "VM does not support runtime API opcode {s} in #run yet", .{@tagName(inst.opcode)});
                },
                .make_directory, .delete_directory, .file_exists, .file_close, .file_length, .file_set_position, .file_write, .file_read, .posix_read => {
                    return diag.failAt(0, "VM does not support runtime file opcode {s} in #run yet", .{@tagName(inst.opcode)});
                },
                .string_builder_init => {
                    if (inst.arg1 >= regs.len) return diag.failAt(0, "VM string_builder_init register out of range", .{});
                    try vm.builderInit(try registerPointer(regs[inst.arg1], diag, "string_builder_init slot"));
                },
                .string_builder_free => {
                    if (inst.arg1 >= regs.len) return diag.failAt(0, "VM string_builder_free register out of range", .{});
                    try vm.builderFree(try registerPointer(regs[inst.arg1], diag, "string_builder_free slot"));
                },
                .string_builder_append_string, .string_builder_append_int, .string_builder_append_float => {
                    if (inst.arg1 >= regs.len or inst.arg2 >= regs.len) return diag.failAt(0, "VM string_builder_append register out of range", .{});
                    try vm.builderAppendValue(try registerPointer(regs[inst.arg1], diag, "string_builder_append slot"), regs[inst.arg2], diag);
                },
                .string_builder_to_string => {
                    if (inst.dest >= regs.len or inst.arg1 >= regs.len) return diag.failAt(0, "VM string_builder_to_string register out of range", .{});
                    regs[inst.dest] = .{ .string = try vm.builderString(try registerPointer(regs[inst.arg1], diag, "string_builder_to_string slot")) };
                },
                .string_builder_length => {
                    if (inst.dest >= regs.len or inst.arg1 >= regs.len) return diag.failAt(0, "VM string_builder_length register out of range", .{});
                    regs[inst.dest] = .{ .int = @intCast((try vm.builderString(try registerPointer(regs[inst.arg1], diag, "string_builder_length slot"))).len) };
                },
                .store_ptr => {
                    if (inst.dest >= regs.len or inst.arg1 >= regs.len) return diag.failAt(0, "VM store_ptr register out of range", .{});
                    try vm.storeRegister(try registerPointer(regs[inst.dest], diag, "store_ptr destination"), regs[inst.arg1], diag);
                },
                .store_ptr_byte => {
                    if (inst.dest >= regs.len or inst.arg1 >= regs.len) return diag.failAt(0, "VM store_ptr_byte register out of range", .{});
                    const value = switch (regs[inst.arg1]) {
                        .int => |v| v,
                        else => return diag.failAt(0, "VM store_ptr_byte requires integer source", .{}),
                    };
                    try vm.storeByte(try registerPointer(regs[inst.dest], diag, "store_ptr_byte destination"), @intCast(value & 0xff), diag);
                },
                .store_ptr_float => {
                    if (inst.dest >= regs.len or inst.arg1 >= regs.len) return diag.failAt(0, "VM store_ptr_float register out of range", .{});
                    const value = switch (regs[inst.arg1]) {
                        .float => |v| v,
                        .int => |v| @as(f64, @floatFromInt(v)),
                        else => return diag.failAt(0, "VM store_ptr_float requires numeric source", .{}),
                    };
                    try vm.storeRegister(try registerPointer(regs[inst.dest], diag, "store_ptr_float destination"), .{ .float = value }, diag);
                },
                .memcpy => {
                    if (inst.dest >= regs.len or inst.arg1 >= regs.len or inst.arg2 >= regs.len) return diag.failAt(0, "VM memcpy register out of range", .{});
                    const count = switch (regs[inst.arg2]) {
                        .int => |v| v,
                        else => return diag.failAt(0, "VM memcpy byte count must be an integer", .{}),
                    };
                    if (count < 0) return diag.failAt(0, "VM memcpy byte count cannot be negative", .{});
                    try vm.copyBytes(try registerPointer(regs[inst.dest], diag, "memcpy destination"), regs[inst.arg1], @intCast(count), diag);
                },
                .free_heap, .array_free => {},
                else => return diag.failAt(0, "VM does not support opcode {s} in #run yet", .{@tagName(inst.opcode)}),
            }
        }
        return .void;
    }

    fn allocBlock(vm: *VM, size: usize) !Pointer {
        const block = try vm.allocator.alloc(u8, size);
        @memset(block, 0);
        const index: u32 = @intCast(vm.memory_blocks.items.len);
        try vm.memory_blocks.append(vm.allocator, block);
        return .{ .block = index, .offset = 0 };
    }

    fn globalPtr(vm: *VM, index: usize) !Pointer {
        while (vm.global_ptrs.items.len <= index) try vm.global_ptrs.append(vm.allocator, null);
        if (vm.global_ptrs.items[index]) |ptr| return ptr;
        const global = vm.program.globals.items[index];
        const ptr = try vm.allocBlock(@max(global.size, 1));
        if (global.initial_bytes) |initial| {
            const copy_len = @min(initial.len, global.size);
            if (copy_len != 0) @memcpy(vm.memory_blocks.items[ptr.block][0..copy_len], initial[0..copy_len]);
        }
        vm.global_ptrs.items[index] = ptr;
        return ptr;
    }

    pub fn globalBytes(vm: *VM, index: usize, diag: Diagnostic) !?[]const u8 {
        if (index >= vm.global_ptrs.items.len) return null;
        const ptr = vm.global_ptrs.items[index] orelse return null;
        const global = vm.program.globals.items[index];
        return try vm.blockSlice(ptr, global.size, diag);
    }

    fn materializeRegister(vm: *VM, value: RegisterValue, diag: Diagnostic) !Pointer {
        switch (value) {
            .ptr => |ptr| return ptr,
            .bytes => |bytes| {
                const ptr = try vm.allocBlock(@max(bytes.len, 1));
                if (bytes.len != 0) @memcpy(try vm.blockSlice(ptr, bytes.len, diag), bytes);
                return ptr;
            },
            .string => |text| {
                const ptr = try vm.allocBlock(@max(text.len, 1));
                if (text.len != 0) @memcpy(try vm.blockSlice(ptr, text.len, diag), text);
                return ptr;
            },
            .int => |int_value| {
                const ptr = try vm.allocBlock(8);
                std.mem.writeInt(u64, try vm.blockArray8(ptr, diag), @bitCast(int_value), .little);
                return ptr;
            },
            .float => |float_value| {
                const ptr = try vm.allocBlock(8);
                std.mem.writeInt(u64, try vm.blockArray8(ptr, diag), @bitCast(float_value), .little);
                return ptr;
            },
            .bool => |bool_value| {
                const ptr = try vm.allocBlock(1);
                try vm.storeByte(ptr, if (bool_value) 1 else 0, diag);
                return ptr;
            },
            .type_id => |type_id| {
                const ptr = try vm.allocBlock(8);
                std.mem.writeInt(u64, try vm.blockArray8(ptr, diag), type_id, .little);
                return ptr;
            },
            .code_node, .code_nodes => return diag.failAt(0, "VM cannot materialize compiler Code_Node values as raw bytes", .{}),
            .empty => return diag.failAt(0, "VM cannot take address of an uninitialized register", .{}),
        }
    }

    fn blockSlice(vm: *VM, ptr: Pointer, len: usize, diag: Diagnostic) ![]u8 {
        if (ptr.block >= vm.memory_blocks.items.len) return diag.failAt(0, "VM pointer block out of range", .{});
        const block = vm.memory_blocks.items[ptr.block];
        if (ptr.offset > block.len or len > block.len - ptr.offset) return diag.failAt(0, "VM pointer access out of bounds: block={d} block_len={d} offset={d} len={d}", .{ ptr.block, block.len, ptr.offset, len });
        return block[ptr.offset .. ptr.offset + len];
    }

    fn blockArray8(vm: *VM, ptr: Pointer, diag: Diagnostic) !*[8]u8 {
        const slice = try vm.blockSlice(ptr, 8, diag);
        return slice[0..8];
    }

    fn readRemainingBytes(vm: *VM, ptr: Pointer, diag: Diagnostic) ![]const u8 {
        if (ptr.block >= vm.memory_blocks.items.len) return diag.failAt(0, "VM pointer block out of range", .{});
        const block = vm.memory_blocks.items[ptr.block];
        if (ptr.offset > block.len) return diag.failAt(0, "VM pointer access out of bounds", .{});
        return block[ptr.offset..];
    }

    fn loadByte(vm: *VM, ptr: Pointer, diag: Diagnostic) !i64 {
        return (try vm.blockSlice(ptr, 1, diag))[0];
    }

    fn loadU64(vm: *VM, ptr: Pointer, diag: Diagnostic) !u64 {
        return std.mem.readInt(u64, try vm.blockArray8(ptr, diag), .little);
    }

    fn storeByte(vm: *VM, ptr: Pointer, value: u8, diag: Diagnostic) !void {
        (try vm.blockSlice(ptr, 1, diag))[0] = value;
    }

    fn storeRegister(vm: *VM, ptr: Pointer, value: RegisterValue, diag: Diagnostic) !void {
        switch (value) {
            .int => |int_value| std.mem.writeInt(u64, try vm.blockArray8(ptr, diag), @bitCast(int_value), .little),
            .float => |float_value| std.mem.writeInt(u64, try vm.blockArray8(ptr, diag), @bitCast(float_value), .little),
            .bool => |bool_value| try vm.storeByte(ptr, if (bool_value) 1 else 0, diag),
            .bytes => |bytes| if (bytes.len != 0) @memcpy(try vm.blockSlice(ptr, bytes.len, diag), bytes),
            .type_id => |type_id| std.mem.writeInt(u64, try vm.blockArray8(ptr, diag), type_id, .little),
            .ptr => |source_ptr| {
                const source = try vm.readRemainingBytes(source_ptr, diag);
                if (source.len != 0) @memcpy(try vm.blockSlice(ptr, source.len, diag), source);
            },
            .string => |text| if (text.len != 0) @memcpy(try vm.blockSlice(ptr, text.len, diag), text),
            .code_node, .code_nodes => return diag.failAt(0, "VM cannot store compiler Code_Node values into raw memory", .{}),
            .empty => return diag.failAt(0, "VM cannot store an uninitialized register", .{}),
        }
    }

    fn copyBytes(vm: *VM, dest: Pointer, source: RegisterValue, count: usize, diag: Diagnostic) !void {
        const dest_slice = try vm.blockSlice(dest, count, diag);
        switch (source) {
            .ptr => |ptr| @memcpy(dest_slice, try vm.blockSlice(ptr, count, diag)),
            .bytes => |bytes| {
                if (count > bytes.len) return diag.failAt(0, "VM memcpy source byte array is too small", .{});
                if (count != 0) @memcpy(dest_slice, bytes[0..count]);
            },
            else => {
                const ptr = try vm.materializeRegister(source, diag);
                @memcpy(dest_slice, try vm.blockSlice(ptr, count, diag));
            },
        }
    }

    fn arrayCount(vm: *VM, value: RegisterValue, diag: Diagnostic) !usize {
        return switch (value) {
            .bytes => |bytes| bytes.len,
            .ptr => |ptr| if (vm.dynamicArrayIndexForPointer(ptr)) |array_index|
                vm.dynamic_arrays.items[array_index].elems.items.len
            else
                (try vm.readRemainingBytes(ptr, diag)).len,
            .code_nodes => |nodes| nodes.len,
            else => diag.failAt(0, "VM array_count requires array-compatible value", .{}),
        };
    }

    fn newDynamicArray(vm: *VM, count: usize, elem_size: usize, diag: Diagnostic) !Pointer {
        const header = try vm.allocBlock(24);
        var array = DynamicArray{ .header = header, .elem_size = elem_size };
        errdefer array.elems.deinit(vm.allocator);
        if (count != 0) {
            const data = try vm.allocBlock(count * elem_size);
            array.data = data;
            try array.elems.ensureTotalCapacity(vm.allocator, count);
            var i: usize = 0;
            while (i < count) : (i += 1) array.elems.appendAssumeCapacity(.{ .int = 0 });
        }
        const index = try vm.addDynamicArray(array);
        try vm.writeDynamicArrayHeader(index, diag);
        return header;
    }

    fn dynamicArrayAdd(vm: *VM, array_ptr: Pointer, item: RegisterValue, elem_size: usize, diag: Diagnostic) !Pointer {
        const array_index = try vm.ensureDynamicArrayForPointer(array_ptr, elem_size, diag);
        var array = &vm.dynamic_arrays.items[array_index];
        if (array.elem_size != elem_size) {
            if (array.elems.items.len != 0) return diag.failAt(0, "VM array_add element size changed from {d} to {d}", .{ array.elem_size, elem_size });
            array.elem_size = elem_size;
        }
        try array.elems.append(vm.allocator, item);
        try vm.ensureDynamicArrayData(array_index, array.elems.items.len, diag);
        const item_ptr = vm.dynamicArrayItemPointer(array_index, array.elems.items.len - 1, diag) catch |err| return err;
        try vm.storeDynamicArrayElementBytes(item_ptr, item, elem_size, diag);
        try vm.writeDynamicArrayHeader(array_index, diag);
        return item_ptr;
    }

    fn sortDynamicArray(vm: *VM, array_ptr: Pointer, kind: u32, diag: Diagnostic) !void {
        const array_index = vm.dynamicArrayIndexForPointer(array_ptr) orelse return diag.failAt(0, "VM sort_array requires a dynamic array pointer", .{});
        const array = &vm.dynamic_arrays.items[array_index];
        var i: usize = 1;
        while (i < array.elems.items.len) : (i += 1) {
            var j = i;
            while (j > 0 and try compareSortValues(array.elems.items[j - 1], array.elems.items[j], kind, diag) > 0) : (j -= 1) {
                std.mem.swap(RegisterValue, &array.elems.items[j - 1], &array.elems.items[j]);
            }
        }
        try vm.ensureDynamicArrayData(array_index, array.elems.items.len, diag);
        for (array.elems.items, 0..) |item, index| {
            const item_ptr = try vm.dynamicArrayItemPointer(array_index, index, diag);
            try vm.storeDynamicArrayElementBytes(item_ptr, item, array.elem_size, diag);
        }
        try vm.writeDynamicArrayHeader(array_index, diag);
    }

    fn dynamicArrayData(vm: *VM, ptr: Pointer, diag: Diagnostic) !?Pointer {
        const array_index = vm.dynamicArrayIndexForPointer(ptr) orelse return null;
        try vm.ensureDynamicArrayData(array_index, vm.dynamic_arrays.items[array_index].elems.items.len, diag);
        return vm.dynamic_arrays.items[array_index].data;
    }

    fn dynamicArrayIndex(vm: *VM, ptr: Pointer, index: usize, elem_size: usize, elem_kind: u32, diag: Diagnostic) !?RegisterValue {
        const array_index = vm.dynamicArrayIndexForPointer(ptr) orelse return null;
        const array = &vm.dynamic_arrays.items[array_index];
        if (index >= array.elems.items.len) return diag.failAt(0, "VM dynamic array index out of bounds", .{});
        if (elem_kind == 1) return .{ .ptr = try vm.dynamicArrayItemPointer(array_index, index, diag) };
        const value = array.elems.items[index];
        if (elem_kind == 2) {
            return switch (value) {
                .string => |text| .{ .string = text },
                .bytes => |bytes| .{ .string = bytes },
                else => diag.failAt(0, "VM dynamic array string index found {s} element", .{@tagName(value)}),
            };
        }
        return switch (value) {
            .int, .float, .bool, .string, .bytes, .ptr, .type_id => value,
            .empty => if (elem_size == 1)
                .{ .int = try vm.loadByte(try vm.dynamicArrayItemPointer(array_index, index, diag), diag) }
            else
                .{ .int = @bitCast(try vm.loadU64(try vm.dynamicArrayItemPointer(array_index, index, diag), diag)) },
            .code_node, .code_nodes => diag.failAt(0, "VM dynamic arrays cannot index compiler Code_Node values as runtime data", .{}),
        };
    }

    fn addDynamicArray(vm: *VM, array: DynamicArray) !usize {
        const index = vm.dynamic_arrays.items.len;
        try vm.dynamic_arrays.append(vm.allocator, array);
        if (array.header) |header| try vm.dynamic_array_refs.put(vm.allocator, pointerKey(header), index);
        if (array.slot) |slot| try vm.dynamic_array_refs.put(vm.allocator, pointerKey(slot), index);
        if (array.data) |data| try vm.dynamic_array_refs.put(vm.allocator, pointerKey(data), index);
        return index;
    }

    fn ensureDynamicArrayForPointer(vm: *VM, ptr: Pointer, elem_size: usize, diag: Diagnostic) !usize {
        if (vm.dynamicArrayIndexForPointer(ptr)) |index| return index;
        var array = DynamicArray{ .slot = ptr, .elem_size = elem_size };
        errdefer array.elems.deinit(vm.allocator);
        const index = try vm.addDynamicArray(array);
        try vm.writeDynamicArrayHeader(index, diag);
        return index;
    }

    fn dynamicArrayIndexForPointer(vm: *VM, ptr: Pointer) ?usize {
        if (vm.dynamic_array_refs.get(pointerKey(ptr))) |index| return index;
        return null;
    }

    fn ensureDynamicArrayData(vm: *VM, array_index: usize, count: usize, diag: Diagnostic) !void {
        const array = &vm.dynamic_arrays.items[array_index];
        const byte_count = @max(count * array.elem_size, 1);
        if (array.data) |data| {
            const block = vm.memory_blocks.items[data.block];
            if (block.len >= byte_count) return;
            _ = vm.dynamic_array_refs.remove(pointerKey(data));
        }
        const old_data = array.data;
        const new_data = try vm.allocBlock(byte_count);
        if (old_data) |old| {
            const old_bytes = try vm.readRemainingBytes(old, diag);
            const copy_len = @min(old_bytes.len, byte_count);
            if (copy_len != 0) @memcpy((try vm.blockSlice(new_data, copy_len, diag)), old_bytes[0..copy_len]);
        }
        array.data = new_data;
        try vm.dynamic_array_refs.put(vm.allocator, pointerKey(new_data), array_index);
    }

    fn dynamicArrayItemPointer(vm: *VM, array_index: usize, index: usize, diag: Diagnostic) !Pointer {
        try vm.ensureDynamicArrayData(array_index, vm.dynamic_arrays.items[array_index].elems.items.len, diag);
        const data = vm.dynamic_arrays.items[array_index].data orelse return diag.failAt(0, "VM dynamic array has no data block", .{});
        return .{ .block = data.block, .offset = data.offset + index * vm.dynamic_arrays.items[array_index].elem_size };
    }

    fn storeDynamicArrayElementBytes(vm: *VM, dest: Pointer, value: RegisterValue, elem_size: usize, diag: Diagnostic) !void {
        switch (value) {
            .ptr => |ptr| {
                const src = try vm.blockSlice(ptr, elem_size, diag);
                if (elem_size != 0) @memcpy(try vm.blockSlice(dest, elem_size, diag), src);
            },
            .string => {},
            .bytes => |bytes| {
                const copy_len = @min(bytes.len, elem_size);
                if (copy_len != 0) @memcpy(try vm.blockSlice(dest, copy_len, diag), bytes[0..copy_len]);
            },
            else => try vm.storeRegister(dest, value, diag),
        }
    }

    fn writeDynamicArrayHeader(vm: *VM, array_index: usize, diag: Diagnostic) !void {
        const array = &vm.dynamic_arrays.items[array_index];
        const count = array.elems.items.len;
        if (array.header) |header| {
            std.mem.writeInt(u64, try vm.blockArray8(header, diag), @intCast(count), .little);
            std.mem.writeInt(u64, try vm.blockArray8(.{ .block = header.block, .offset = header.offset + 8 }, diag), @intCast(count), .little);
        }
        if (array.slot) |slot| {
            std.mem.writeInt(u64, try vm.blockArray8(slot, diag), @intCast(count), .little);
        }
    }

    fn printValue(vm: *VM, value: RegisterValue, diag: Diagnostic, context: []const u8) anyerror!void {
        switch (value) {
            .string => |text| std.debug.print("{s}", .{text}),
            .bytes => |bytes| std.debug.print("{s}", .{bytes}),
            .int => |int_value| std.debug.print("{d}", .{int_value}),
            .float => |float_value| std.debug.print("{d}", .{float_value}),
            .bool => |bool_value| std.debug.print("{s}", .{if (bool_value) "true" else "false"}),
            .type_id => |type_id| std.debug.print("{s}", .{typeName(type_id)}),
            .ptr => |ptr| {
                if (vm.dynamicArrayIndexForPointer(ptr)) |array_index| {
                    try vm.printDynamicArray(array_index, diag);
                } else {
                    std.debug.print("*0x{x}:0x{x}", .{ ptr.block, ptr.offset });
                }
            },
            .code_node => |node| std.debug.print("{s}", .{node.text}),
            .code_nodes => |nodes| {
                std.debug.print("[", .{});
                for (nodes, 0..) |node, i| {
                    if (i != 0) std.debug.print(", ", .{});
                    std.debug.print("{s}", .{node.text});
                }
                std.debug.print("]", .{});
            },
            .empty => return diag.failAt(0, "VM {s} cannot print an uninitialized value", .{context}),
        }
    }

    fn printDynamicArray(vm: *VM, array_index: usize, diag: Diagnostic) anyerror!void {
        std.debug.print("[", .{});
        for (vm.dynamic_arrays.items[array_index].elems.items, 0..) |item, i| {
            if (i != 0) std.debug.print(", ", .{});
            try vm.printValue(item, diag, "dynamic array print");
        }
        std.debug.print("]", .{});
    }

    fn ensureCodeTree(vm: *VM, code: []const u8) !u32 {
        for (vm.code_trees.items, 0..) |tree, i| {
            if (std.mem.eql(u8, tree.source, code)) return @intCast(i);
        }
        const nodes = try vm.buildCodeNodes(@intCast(vm.code_trees.items.len), code);
        errdefer vm.allocator.free(nodes);
        const index: u32 = @intCast(vm.code_trees.items.len);
        try vm.code_trees.append(vm.allocator, .{ .source = code, .nodes = nodes });
        return index;
    }

    fn buildCodeNodes(vm: *VM, tree_index: u32, code: []const u8) ![]CodeNode {
        var nodes = std.ArrayList(CodeNode).empty;
        errdefer nodes.deinit(vm.allocator);

        var i: usize = 0;
        var saw_decl = false;
        while (i < code.len) {
            const ch = code[i];
            if (std.ascii.isWhitespace(ch) or ch == ',' or ch == ';' or ch == '(' or ch == ')' or ch == '{' or ch == '}') {
                i += 1;
                continue;
            }
            if (ch == ':' and i + 1 < code.len and (code[i + 1] == '=' or code[i + 1] == ':')) {
                saw_decl = true;
                i += 2;
                continue;
            }
            if (std.ascii.isAlphabetic(ch) or ch == '_') {
                const start = i;
                i += 1;
                while (i < code.len and (std.ascii.isAlphanumeric(code[i]) or code[i] == '_')) : (i += 1) {}
                var scan = i;
                while (scan < code.len and std.ascii.isWhitespace(code[scan])) : (scan += 1) {}
                if (scan + 1 < code.len and code[scan] == '.' and code[scan + 1] == '{') {
                    try nodes.append(vm.allocator, .{ .tree = tree_index, .index = @intCast(nodes.items.len), .kind = "TYPE_INSTANTIATION", .flags = "0", .text = code[start..i], .start = start, .end = i });
                    try nodes.append(vm.allocator, .{ .tree = tree_index, .index = @intCast(nodes.items.len), .kind = "LITERAL", .flags = "0", .text = code[scan .. scan + 2], .start = scan, .end = scan + 2 });
                } else {
                    try nodes.append(vm.allocator, .{ .tree = tree_index, .index = @intCast(nodes.items.len), .kind = "IDENT", .flags = "0", .text = code[start..i], .start = start, .end = i });
                }
                continue;
            }
            if (std.ascii.isDigit(ch)) {
                const start = i;
                i += 1;
                while (i < code.len and (std.ascii.isAlphanumeric(code[i]) or code[i] == '.' or code[i] == '_')) : (i += 1) {}
                const literal_value = std.fmt.parseInt(i64, code[start..i], 10) catch null;
                try nodes.append(vm.allocator, .{ .tree = tree_index, .index = @intCast(nodes.items.len), .kind = "LITERAL", .flags = "0", .text = code[start..i], .start = start, .end = i, .s64 = literal_value });
                continue;
            }
            if (ch == '"' or ch == '\'') {
                const quote = ch;
                const start = i;
                i += 1;
                while (i < code.len) : (i += 1) {
                    if (code[i] == '\\' and i + 1 < code.len) {
                        i += 1;
                        continue;
                    }
                    if (code[i] == quote) {
                        i += 1;
                        break;
                    }
                }
                try nodes.append(vm.allocator, .{ .tree = tree_index, .index = @intCast(nodes.items.len), .kind = "LITERAL", .flags = "0", .text = code[start..@min(i, code.len)], .start = start, .end = @min(i, code.len) });
                continue;
            }
            i += 1;
        }
        if (saw_decl) try nodes.append(vm.allocator, .{ .tree = tree_index, .index = @intCast(nodes.items.len), .kind = "DECLARATION", .flags = "ALLOWED_BY_CONTEXT", .text = code, .start = 0, .end = code.len });

        const owned = try nodes.toOwnedSlice(vm.allocator);
        return owned;
    }

    fn currentCodeNode(vm: *VM, value: RegisterValue, diag: Diagnostic, context: []const u8) !CodeNode {
        const node = switch (value) {
            .code_node => |v| v,
            else => return diag.failAt(0, "VM {s} requires a Code_Node value", .{context}),
        };
        if (node.tree >= vm.code_trees.items.len or node.index >= vm.code_trees.items[node.tree].nodes.len) return node;
        return vm.code_trees.items[node.tree].nodes[node.index];
    }

    fn updateCodeLiteralS64(vm: *VM, value: RegisterValue, new_value: i64, diag: Diagnostic) !void {
        const node = switch (value) {
            .code_node => |v| v,
            else => return diag.failAt(0, "VM Code_Literal._s64 setter requires a Code_Node value", .{}),
        };
        if (node.tree >= vm.code_trees.items.len or node.index >= vm.code_trees.items[node.tree].nodes.len) return diag.failAt(0, "VM Code_Literal._s64 setter got a detached Code_Node", .{});
        if (vm.code_trees.items[node.tree].nodes[node.index].s64 == null) return diag.failAt(0, "VM Code_Literal._s64 setter requires a numeric literal node", .{});
        vm.code_trees.items[node.tree].nodes[node.index].s64 = new_value;
    }

    fn renderCodeNode(vm: *VM, node: CodeNode, diag: Diagnostic) ![]const u8 {
        if (node.tree >= vm.code_trees.items.len) return node.text;
        const tree = vm.code_trees.items[node.tree];
        var out = std.ArrayList(u8).empty;
        errdefer out.deinit(vm.allocator);
        var cursor: usize = 0;
        for (tree.nodes) |literal| {
            if (!std.mem.eql(u8, literal.kind, "LITERAL") or literal.s64 == null) continue;
            if (literal.start < cursor or literal.end > tree.source.len) continue;
            try out.appendSlice(vm.allocator, tree.source[cursor..literal.start]);
            const text = try std.fmt.allocPrint(vm.allocator, "{d}", .{literal.s64.?});
            defer vm.allocator.free(text);
            try out.appendSlice(vm.allocator, text);
            cursor = literal.end;
        }
        try out.appendSlice(vm.allocator, tree.source[cursor..]);
        _ = diag;
        const rendered = try out.toOwnedSlice(vm.allocator);
        errdefer vm.allocator.free(rendered);
        try vm.rendered_code_strings.append(vm.allocator, rendered);
        return rendered;
    }

    fn pointerKey(ptr: Pointer) u64 {
        return (@as(u64, ptr.block) << 32) | @as(u64, @intCast(@min(ptr.offset, std.math.maxInt(u32))));
    }

    fn builderInit(vm: *VM, slot: Pointer) !void {
        const key = pointerKey(slot);
        if (vm.string_builders.getPtr(key)) |builder| builder.clearRetainingCapacity() else try vm.string_builders.put(vm.allocator, key, .empty);
    }

    fn builderFree(vm: *VM, slot: Pointer) !void {
        const key = pointerKey(slot);
        if (vm.string_builders.fetchRemove(key)) |entry| {
            var builder = entry.value;
            builder.deinit(vm.allocator);
        }
    }

    fn ensureBuilder(vm: *VM, slot: Pointer) !*std.ArrayList(u8) {
        const key = pointerKey(slot);
        const gop = try vm.string_builders.getOrPut(vm.allocator, key);
        if (!gop.found_existing) gop.value_ptr.* = .empty;
        return gop.value_ptr;
    }

    fn builderAppendValue(vm: *VM, slot: Pointer, value: RegisterValue, diag: Diagnostic) !void {
        const builder = try vm.ensureBuilder(slot);
        switch (value) {
            .string => |text| try builder.appendSlice(vm.allocator, text),
            .bytes => |bytes| try builder.appendSlice(vm.allocator, bytes),
            .code_node => |node| try vm.builderAppendCodeText(builder, node.text),
            .code_nodes => return diag.failAt(0, "VM cannot append a Code_Node array to a String_Builder without indexing it", .{}),
            .ptr => |ptr| try builder.appendSlice(vm.allocator, try vm.readRemainingBytes(ptr, diag)),
            .int => |int_value| {
                const text = try std.fmt.allocPrint(vm.allocator, "{d}", .{int_value});
                defer vm.allocator.free(text);
                try builder.appendSlice(vm.allocator, text);
            },
            .float => |float_value| {
                const text = try std.fmt.allocPrint(vm.allocator, "{d}", .{float_value});
                defer vm.allocator.free(text);
                try builder.appendSlice(vm.allocator, text);
            },
            .bool => |bool_value| try builder.appendSlice(vm.allocator, if (bool_value) "true" else "false"),
            .type_id => |type_id| try builder.appendSlice(vm.allocator, typeName(type_id)),
            .empty => return diag.failAt(0, "VM cannot append an uninitialized value to a String_Builder", .{}),
        }
    }

    fn builderString(vm: *VM, slot: Pointer) ![]const u8 {
        const builder = try vm.ensureBuilder(slot);
        return builder.items;
    }

    fn builderAppendCodeText(vm: *VM, builder: *std.ArrayList(u8), text: []const u8) !void {
        var i: usize = 0;
        while (i < text.len) : (i += 1) {
            try builder.append(vm.allocator, text[i]);
            if (text[i] == ',') {
                const next = i + 1;
                if (next < text.len and !std.ascii.isWhitespace(text[next])) try builder.append(vm.allocator, ' ');
            }
        }
    }
};

fn numericAsFloatOrInt(value: RegisterValue, diag: Diagnostic, context: []const u8) !f64 {
    return switch (value) {
        .int => |v| @floatFromInt(v),
        .float => |v| v,
        .bool => |v| if (v) 1 else 0,
        .ptr => 1,
        .bytes => |v| if (v.len == 0) 0 else 1,
        .type_id => diag.failAt(0, "VM {s} cannot treat Type values as numbers", .{context}),
        .code_node, .code_nodes => diag.failAt(0, "VM {s} cannot treat compiler Code_Node values as numbers", .{context}),
        else => diag.failAt(0, "VM {s} requires numeric or bool value", .{context}),
    };
}

fn registerInt(value: RegisterValue, diag: Diagnostic, context: []const u8) !i64 {
    return switch (value) {
        .int => |v| v,
        .bool => |v| if (v) 1 else 0,
        .ptr => 1,
        else => diag.failAt(0, "VM {s} requires an integer value", .{context}),
    };
}

fn registerTruthy(value: RegisterValue, diag: Diagnostic, context: []const u8) !bool {
    _ = diag;
    _ = context;
    return switch (value) {
        .bool => |v| v,
        .int => |v| v != 0,
        .float => |v| v != 0,
        .string => |v| v.len != 0,
        .bytes => |v| v.len != 0,
        .code_node => true,
        .code_nodes => |v| v.len != 0,
        .type_id => true,
        .ptr => true,
        .empty => false,
    };
}

fn registerPointer(value: RegisterValue, diag: Diagnostic, context: []const u8) !Pointer {
    return switch (value) {
        .ptr => |ptr| ptr,
        else => diag.failAt(0, "VM {s} requires pointer value", .{context}),
    };
}

fn compareSortValues(lhs: RegisterValue, rhs: RegisterValue, kind: u32, diag: Diagnostic) !i32 {
    if (kind == 2) {
        const l = switch (lhs) {
            .string => |v| v,
            .bytes => |v| v,
            else => return diag.failAt(0, "VM string sort found {s} element", .{@tagName(lhs)}),
        };
        const r = switch (rhs) {
            .string => |v| v,
            .bytes => |v| v,
            else => return diag.failAt(0, "VM string sort found {s} element", .{@tagName(rhs)}),
        };
        return switch (std.mem.order(u8, l, r)) {
            .lt => -1,
            .eq => 0,
            .gt => 1,
        };
    }
    const l = try numericAsFloatOrInt(lhs, diag, "sort comparison lhs");
    const r = try numericAsFloatOrInt(rhs, diag, "sort comparison rhs");
    if (l < r) return -1;
    if (l > r) return 1;
    return 0;
}

fn registerValueToValue(value: RegisterValue, diag: Diagnostic) !Value {
    return switch (value) {
        .int => |v| .{ .int = v },
        .float => |v| .{ .float = v },
        .bool => |v| .{ .bool = v },
        .string => |v| .{ .string = v },
        .bytes => |v| .{ .bytes = v },
        .type_id => diag.failAt(0, "VM cannot pass Type values across procedure calls yet", .{}),
        .code_node, .code_nodes => diag.failAt(0, "VM cannot pass compiler Code_Node values across procedure calls yet", .{}),
        .ptr => diag.failAt(0, "VM cannot pass a raw compile-time pointer across procedure calls without a typed value", .{}),
        .empty => diag.failAt(0, "VM call argument register was not initialized", .{}),
    };
}

fn registerValueFromValue(value: Value) RegisterValue {
    return switch (value) {
        .int => |v| .{ .int = v },
        .float => |v| .{ .float = v },
        .bool => |v| .{ .bool = v },
        .string => |v| .{ .string = v },
        .bytes => |v| .{ .bytes = v },
        .void => .empty,
    };
}

fn registerValuesEqual(lhs: RegisterValue, rhs: RegisterValue) bool {
    return switch (lhs) {
        .empty => rhs == .empty,
        .string => |l| switch (rhs) {
            .string => |r| std.mem.eql(u8, l, r),
            else => false,
        },
        .bytes => |l| switch (rhs) {
            .bytes => |r| std.mem.eql(u8, l, r),
            else => false,
        },
        .ptr => |l| switch (rhs) {
            .ptr => |r| l.block == r.block and l.offset == r.offset,
            else => false,
        },
        .type_id => |l| switch (rhs) {
            .type_id => |r| l == r,
            else => false,
        },
        .code_node => |l| switch (rhs) {
            .code_node => |r| std.mem.eql(u8, l.kind, r.kind) and std.mem.eql(u8, l.flags, r.flags) and std.mem.eql(u8, l.text, r.text),
            else => false,
        },
        .code_nodes => |l| switch (rhs) {
            .code_nodes => |r| l.ptr == r.ptr and l.len == r.len,
            else => false,
        },
        .int => |l| switch (rhs) {
            .int => |r| l == r,
            .float => |r| @as(f64, @floatFromInt(l)) == r,
            .bool => |r| (l != 0) == r,
            else => false,
        },
        .float => |l| switch (rhs) {
            .float => |r| l == r,
            .int => |r| l == @as(f64, @floatFromInt(r)),
            .bool => |r| (l != 0) == r,
            else => false,
        },
        .bool => |l| switch (rhs) {
            .bool => |r| l == r,
            .int => |r| l == (r != 0),
            .float => |r| l == (r != 0),
            else => false,
        },
    };
}

fn registerCodeText(value: RegisterValue, diag: Diagnostic, context: []const u8) ![]const u8 {
    return switch (value) {
        .string => |text| text,
        .bytes => |bytes| bytes,
        .code_node => |node| node.text,
        else => diag.failAt(0, "VM {s} requires a Code or Code_Node value", .{context}),
    };
}

fn typeName(type_id: u32) []const u8 {
    return switch (type_id) {
        1 => "bool",
        4 => "s32",
        5 => "int",
        7 => "u8",
        8 => "u16",
        9 => "u32",
        10 => "*void",
        12 => "float",
        13 => "float64",
        14 => "string",
        15 => "Type",
        16 => "Any",
        30 => "procedure",
        31 => "()",
        else => "Type",
    };
}

fn readIntLittle(bytes: []const u8) i64 {
    var buf: [8]u8 = .{0} ** 8;
    @memcpy(buf[0..bytes.len], bytes);
    return @bitCast(std.mem.readInt(u64, &buf, .little));
}
