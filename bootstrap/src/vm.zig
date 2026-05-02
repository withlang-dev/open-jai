const std = @import("std");
const Bytecode = @import("Bytecode.zig");
const Diagnostic = @import("diagnostics.zig").Diagnostic;

pub const Value = union(enum) {
    void,
    int: i64,
    float: f64,
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
            .cmp_lt_int => {
                if (inst.dest >= regs.len or inst.arg1 >= regs.len or inst.arg2 >= regs.len) return diag.failAt(0, "VM cmp_lt_int register out of range", .{});
                const lhs = switch (regs[inst.arg1]) { .int => |v| v, else => return diag.failAt(0, "VM cmp_lt_int requires integer lhs", .{}) };
                const rhs = switch (regs[inst.arg2]) { .int => |v| v, else => return diag.failAt(0, "VM cmp_lt_int requires integer rhs", .{}) };
                regs[inst.dest] = .{ .bool = lhs < rhs };
            },
            .jump => {
                if (inst.arg1 >= proc.instructions.items.len) return diag.failAt(0, "VM jump target out of range", .{});
                ip = inst.arg1;
            },
            .jump_if_false => {
                if (inst.arg1 >= regs.len or inst.arg2 > proc.instructions.items.len) return diag.failAt(0, "VM conditional jump out of range", .{});
                const cond = switch (regs[inst.arg1]) { .bool => |v| v, else => return diag.failAt(0, "VM conditional jump requires bool condition", .{}) };
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
            .mul_int, .rem_int, .add_int, .sub_int => {
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
                    else => unreachable,
                } };
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
            .call_extern => {
                if (inst.dest != @intFromEnum(Bytecode.ExternSymbol.openjai_print)) return diag.failAt(0, "VM only supports compile-time print extern calls", .{});
                if (inst.arg1 >= regs.len) return diag.failAt(0, "VM print argument register out of range", .{});
                switch (regs[inst.arg1]) {
                    .string => |text| std.debug.print("{s}", .{text}),
                    .int => |value| std.debug.print("{d}", .{value}),
                    .float => |value| std.debug.print("{d}", .{value}),
                    else => return diag.failAt(0, "VM compile-time print currently requires string, integer, or float argument", .{}),
                }
            },
            .ret => {
                if (inst.arg1 >= regs.len) return diag.failAt(0, "VM return register out of range", .{});
                return switch (regs[inst.arg1]) {
                    .int => |value| .{ .int = value },
                    .float => |value| .{ .float = value },
                    else => diag.failAt(0, "VM #run return currently supports only integer and float values", .{}),
                };
            },
            .ret_void => return .void,
            else => return diag.failAt(0, "VM does not support opcode {s} in #run yet", .{@tagName(inst.opcode)}),
        }
        }
        return .void;
    }
};
