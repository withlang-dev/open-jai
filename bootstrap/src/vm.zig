const std = @import("std");
const Bytecode = @import("Bytecode.zig");
const Diagnostic = @import("diagnostics.zig").Diagnostic;

pub const Value = union(enum) {
    void,
    int: i64,
    float: f64,
    bool: bool,
    string: []const u8,
};

const RegisterValue = union(enum) {
    empty,
    string: []const u8,
    int: i64,
    float: f64,
    bool: bool,
};

pub const VM = struct {
    allocator: std.mem.Allocator,
    program: *const Bytecode.Program,

    pub fn init(allocator: std.mem.Allocator, program: *const Bytecode.Program) VM {
        return .{ .allocator = allocator, .program = program };
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
        if (args.len > regs.len) return diag.failAt(0, "VM #run argument count exceeds register file", .{});
        for (args, 0..) |arg, i| {
            regs[i] = switch (arg) {
                .int => |v| .{ .int = v },
                .float => |v| .{ .float = v },
                .bool => |v| .{ .bool = v },
                .string => |v| .{ .string = v },
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
            .load_null_ptr, .load_const_ref, .load_type => {
                if (inst.dest >= regs.len) return diag.failAt(0, "VM placeholder/reference load register out of range", .{});
                regs[inst.dest] = .{ .int = @intCast(inst.arg1) };
            },
            .load_undef => {
                if (inst.dest >= regs.len) return diag.failAt(0, "VM undefined load register out of range", .{});
                regs[inst.dest] = .{ .int = 0 };
            },
            .cmp_lt_int => {
                if (inst.dest >= regs.len or inst.arg1 >= regs.len or inst.arg2 >= regs.len) return diag.failAt(0, "VM cmp_lt_int register out of range", .{});
                const lhs = switch (regs[inst.arg1]) { .int => |v| v, else => return diag.failAt(0, "VM cmp_lt_int requires integer lhs", .{}) };
                const rhs = switch (regs[inst.arg2]) { .int => |v| v, else => return diag.failAt(0, "VM cmp_lt_int requires integer rhs", .{}) };
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
                regs[inst.dest] = .{ .int = -switch (regs[inst.arg1]) { .int => |v| v, else => return diag.failAt(0, "VM neg_int requires integer operand", .{}) } };
            },
            .neg_float => {
                if (inst.dest >= regs.len or inst.arg1 >= regs.len) return diag.failAt(0, "VM neg_float register out of range", .{});
                regs[inst.dest] = .{ .float = -switch (regs[inst.arg1]) { .float => |v| v, .int => |v| @as(f64, @floatFromInt(v)), else => return diag.failAt(0, "VM neg_float requires numeric operand", .{}) } };
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
                    else => return diag.failAt(0, "VM integer arithmetic requires integer lhs", .{}),
                };
                const rhs = switch (regs[inst.arg2]) {
                    .int => |v| v,
                    else => return diag.failAt(0, "VM integer arithmetic requires integer rhs", .{}),
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
                regs[inst.dest] = .{ .int = @intCast(inst.arg1 + 1) };
            },
            .call_extern => {
                if (inst.dest != @intFromEnum(Bytecode.ExternSymbol.openjai_print)) return diag.failAt(0, "VM only supports compile-time print extern calls", .{});
                if (inst.arg1 >= regs.len) return diag.failAt(0, "VM print argument register out of range", .{});
                switch (regs[inst.arg1]) {
                    .string => |text| std.debug.print("{s}", .{text}),
                    .int => |value| std.debug.print("{d}", .{value}),
                    .float => |value| std.debug.print("{d}", .{value}),
                    .bool => |value| std.debug.print("{s}", .{if (value) "true" else "false"}),
                    else => return diag.failAt(0, "VM compile-time print currently requires string, integer, float, or bool argument", .{}),
                }
            },
            .format_print => {
                if (inst.arg1 >= regs.len) return diag.failAt(0, "VM format_print register out of range", .{});
                switch (regs[inst.arg1]) {
                    .string => |text| std.debug.print("{s}", .{text}),
                    .int => |value| std.debug.print("{d}", .{value}),
                    .float => |value| std.debug.print("{d}", .{value}),
                    .bool => |value| std.debug.print("{s}", .{if (value) "true" else "false"}),
                    else => return diag.failAt(0, "VM format_print currently requires string, integer, float, or bool argument", .{}),
                }
            },
            .ret => {
                if (inst.arg1 >= regs.len) return diag.failAt(0, "VM return register out of range", .{});
                return switch (regs[inst.arg1]) {
                    .int => |value| .{ .int = value },
                    .float => |value| .{ .float = value },
                    .bool => |value| .{ .bool = value },
                    .string => |value| .{ .string = value },
                    else => diag.failAt(0, "VM #run return currently supports only concrete scalar values", .{}),
                };
            },
            .assert_true => {
                if (inst.arg1 >= regs.len) return diag.failAt(0, "VM assert register out of range", .{});
                _ = try registerTruthy(regs[inst.arg1], diag, "assert condition");
            },
            .ret_void => return .void,
            .memcpy, .free_heap => {},
            else => return diag.failAt(0, "VM does not support opcode {s} in #run yet", .{@tagName(inst.opcode)}),
        }
        }
        return .void;
    }
};

fn numericAsFloatOrInt(value: RegisterValue, diag: Diagnostic, context: []const u8) !f64 {
    return switch (value) {
        .int => |v| @floatFromInt(v),
        .float => |v| v,
        .bool => |v| if (v) 1 else 0,
        else => diag.failAt(0, "VM {s} requires numeric or bool value", .{context}),
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
        .empty => false,
    };
}

fn registerValuesEqual(lhs: RegisterValue, rhs: RegisterValue) bool {
    return switch (lhs) {
        .empty => rhs == .empty,
        .string => |l| switch (rhs) {
            .string => |r| std.mem.eql(u8, l, r),
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
