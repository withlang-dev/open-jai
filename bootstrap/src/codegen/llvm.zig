const std = @import("std");
const Bytecode = @import("../Bytecode.zig");
const Diagnostic = @import("../diagnostics.zig").Diagnostic;

const c = @cImport({
    @cInclude("llvm-c/Core.h");
    @cInclude("llvm-c/Analysis.h");
    @cInclude("llvm-c/Target.h");
    @cInclude("llvm-c/TargetMachine.h");
    @cInclude("llvm-c/BitWriter.h");
});

const LlvmEnv = struct {
    allocator: std.mem.Allocator,
    context: c.LLVMContextRef,
    module: c.LLVMModuleRef,
    builder: c.LLVMBuilderRef,
    program: *const Bytecode.Program,
    proc_functions: []c.LLVMValueRef,
    proc_void_ty: c.LLVMTypeRef,
    print_fn_ty: c.LLVMTypeRef,
    print_fn: c.LLVMValueRef,
    print_int_fn_ty: c.LLVMTypeRef,
    print_int_fn: c.LLVMValueRef,
    print_float_fn_ty: c.LLVMTypeRef,
    print_float_fn: c.LLVMValueRef,
    print_bool_fn_ty: c.LLVMTypeRef,
    print_bool_fn: c.LLVMValueRef,
    print_type_fn_ty: c.LLVMTypeRef,
    print_type_fn: c.LLVMValueRef,
    print_return_int_fn_ty: c.LLVMTypeRef,
    print_return_int_fn: c.LLVMValueRef,
    print_format_int_fn_ty: c.LLVMTypeRef,
    print_format_int_fn: c.LLVMValueRef,
    print_format_float_fn_ty: c.LLVMTypeRef,
    print_format_float_fn: c.LLVMValueRef,
    alloc_fn_ty: c.LLVMTypeRef,
    alloc_fn: c.LLVMValueRef,
    free_fn_ty: c.LLVMTypeRef,
    free_fn: c.LLVMValueRef,
    memcpy_fn_ty: c.LLVMTypeRef,
    memcpy_fn: c.LLVMValueRef,
    assert_fail_fn_ty: c.LLVMTypeRef,
    assert_fail_fn: c.LLVMValueRef,
    exit_fn_ty: c.LLVMTypeRef,
    exit_fn: c.LLVMValueRef,
    current_time_consensus_low_fn_ty: c.LLVMTypeRef,
    current_time_consensus_low_fn: c.LLVMValueRef,
    current_time_monotonic_low_fn_ty: c.LLVMTypeRef,
    current_time_monotonic_low_fn: c.LLVMValueRef,
    to_calendar_fn_ty: c.LLVMTypeRef,
    to_calendar_fn: c.LLVMValueRef,
    calendar_get_i64_fn_ty: c.LLVMTypeRef,
    calendar_get_i64_fn: c.LLVMValueRef,
    calendar_to_string_fn_ty: c.LLVMTypeRef,
    calendar_to_string_fn: c.LLVMValueRef,
    random_seed_fn_ty: c.LLVMTypeRef,
    random_seed_fn: c.LLVMValueRef,
    random_get_fn_ty: c.LLVMTypeRef,
    random_get_fn: c.LLVMValueRef,
    random_get_zero_to_one_fn_ty: c.LLVMTypeRef,
    random_get_zero_to_one_fn: c.LLVMValueRef,
    random_get_within_range_fn_ty: c.LLVMTypeRef,
    random_get_within_range_fn: c.LLVMValueRef,
    llvm_i32: c.LLVMTypeRef,
    llvm_i64: c.LLVMTypeRef,
    llvm_f64: c.LLVMTypeRef,
    ptr_ty: c.LLVMTypeRef,
};

pub fn emitObject(allocator: std.mem.Allocator, program: *const Bytecode.Program, output_obj: []const u8, diag: Diagnostic) !void {
    if (program.procs.items.len == 0) return diag.failAt(0, "LLVM backend received no procedures", .{});

    c.LLVMInitializeAArch64TargetInfo();
    c.LLVMInitializeAArch64Target();
    c.LLVMInitializeAArch64TargetMC();
    c.LLVMInitializeAArch64AsmPrinter();
    c.LLVMInitializeX86TargetInfo();
    c.LLVMInitializeX86Target();
    c.LLVMInitializeX86TargetMC();
    c.LLVMInitializeX86AsmPrinter();

    const context = c.LLVMContextCreate() orelse return diag.failAt(0, "LLVMContextCreate failed", .{});
    defer c.LLVMContextDispose(context);
    const module = c.LLVMModuleCreateWithNameInContext("openjai", context) orelse return diag.failAt(0, "LLVMModuleCreateWithNameInContext failed", .{});
    defer c.LLVMDisposeModule(module);
    const builder = c.LLVMCreateBuilderInContext(context) orelse return diag.failAt(0, "LLVMCreateBuilderInContext failed", .{});
    defer c.LLVMDisposeBuilder(builder);

    const triple_z = try detectTriple(allocator);
    defer allocator.free(triple_z);
    c.LLVMSetTarget(module, triple_z.ptr);

    const llvm_i32 = c.LLVMInt32TypeInContext(context);
    const llvm_i64 = c.LLVMInt64TypeInContext(context);
    const void_ty = c.LLVMVoidTypeInContext(context);
    const ptr_ty = c.LLVMPointerTypeInContext(context, 0);
    const print_params = [_]c.LLVMTypeRef{ ptr_ty, llvm_i64 };
    const print_fn_ty = c.LLVMFunctionType(void_ty, @constCast(&print_params), print_params.len, 0);
    const print_fn = c.LLVMAddFunction(module, "__openjai_print", print_fn_ty);
    const print_int_params = [_]c.LLVMTypeRef{llvm_i64};
    const print_int_fn_ty = c.LLVMFunctionType(void_ty, @constCast(&print_int_params), print_int_params.len, 0);
    const print_int_fn = c.LLVMAddFunction(module, "__openjai_print_int", print_int_fn_ty);
    const llvm_f64 = c.LLVMDoubleTypeInContext(context);
    const print_float_params = [_]c.LLVMTypeRef{llvm_f64};
    const print_float_fn_ty = c.LLVMFunctionType(void_ty, @constCast(&print_float_params), print_float_params.len, 0);
    const print_float_fn = c.LLVMAddFunction(module, "__openjai_print_float", print_float_fn_ty);
    const print_bool_params = [_]c.LLVMTypeRef{c.LLVMInt1TypeInContext(context)};
    const print_bool_fn_ty = c.LLVMFunctionType(void_ty, @constCast(&print_bool_params), print_bool_params.len, 0);
    const print_bool_fn = c.LLVMAddFunction(module, "__openjai_print_bool", print_bool_fn_ty);
    const print_type_params = [_]c.LLVMTypeRef{llvm_i64};
    const print_type_fn_ty = c.LLVMFunctionType(void_ty, @constCast(&print_type_params), print_type_params.len, 0);
    const print_type_fn = c.LLVMAddFunction(module, "__openjai_print_type", print_type_fn_ty);
    const print_return_int_params = [_]c.LLVMTypeRef{ ptr_ty, llvm_i64 };
    const print_return_int_fn_ty = c.LLVMFunctionType(llvm_i64, @constCast(&print_return_int_params), print_return_int_params.len, 0);
    const print_return_int_fn = c.LLVMAddFunction(module, "__openjai_print_return_int", print_return_int_fn_ty);
    const print_format_int_params = [_]c.LLVMTypeRef{ llvm_i64, llvm_i64, llvm_i64 };
    const print_format_int_fn_ty = c.LLVMFunctionType(void_ty, @constCast(&print_format_int_params), print_format_int_params.len, 0);
    const print_format_int_fn = c.LLVMAddFunction(module, "__openjai_print_format_int", print_format_int_fn_ty);
    const print_format_float_params = [_]c.LLVMTypeRef{ llvm_f64, llvm_i64, llvm_i64, llvm_i64, llvm_i64 };
    const print_format_float_fn_ty = c.LLVMFunctionType(void_ty, @constCast(&print_format_float_params), print_format_float_params.len, 0);
    const print_format_float_fn = c.LLVMAddFunction(module, "__openjai_print_format_float", print_format_float_fn_ty);
    const alloc_params = [_]c.LLVMTypeRef{llvm_i64};
    const alloc_fn_ty = c.LLVMFunctionType(ptr_ty, @constCast(&alloc_params), alloc_params.len, 0);
    const alloc_fn = c.LLVMAddFunction(module, "__openjai_alloc", alloc_fn_ty);
    const free_params = [_]c.LLVMTypeRef{ptr_ty};
    const free_fn_ty = c.LLVMFunctionType(void_ty, @constCast(&free_params), free_params.len, 0);
    const free_fn = c.LLVMAddFunction(module, "__openjai_free", free_fn_ty);
    const memcpy_params = [_]c.LLVMTypeRef{ ptr_ty, ptr_ty, llvm_i64 };
    const memcpy_fn_ty = c.LLVMFunctionType(void_ty, @constCast(&memcpy_params), memcpy_params.len, 0);
    const memcpy_fn = c.LLVMAddFunction(module, "__openjai_memcpy", memcpy_fn_ty);
    const assert_fail_fn_ty = c.LLVMFunctionType(void_ty, null, 0, 0);
    const assert_fail_fn = c.LLVMAddFunction(module, "__openjai_assert_fail", assert_fail_fn_ty);
    const exit_params = [_]c.LLVMTypeRef{llvm_i32};
    const exit_fn_ty = c.LLVMFunctionType(void_ty, @constCast(&exit_params), exit_params.len, 0);
    const exit_fn = c.LLVMAddFunction(module, "__openjai_exit", exit_fn_ty);
    const current_time_consensus_low_fn_ty = c.LLVMFunctionType(llvm_i64, null, 0, 0);
    const current_time_consensus_low_fn = c.LLVMAddFunction(module, "__openjai_current_time_consensus_low", current_time_consensus_low_fn_ty);
    const current_time_monotonic_low_fn_ty = c.LLVMFunctionType(llvm_i64, null, 0, 0);
    const current_time_monotonic_low_fn = c.LLVMAddFunction(module, "__openjai_current_time_monotonic_low", current_time_monotonic_low_fn_ty);
    const to_calendar_params = [_]c.LLVMTypeRef{ llvm_i64, llvm_i64 };
    const to_calendar_fn_ty = c.LLVMFunctionType(ptr_ty, @constCast(&to_calendar_params), to_calendar_params.len, 0);
    const to_calendar_fn = c.LLVMAddFunction(module, "__openjai_to_calendar", to_calendar_fn_ty);
    const calendar_get_i64_params = [_]c.LLVMTypeRef{ ptr_ty, llvm_i64 };
    const calendar_get_i64_fn_ty = c.LLVMFunctionType(llvm_i64, @constCast(&calendar_get_i64_params), calendar_get_i64_params.len, 0);
    const calendar_get_i64_fn = c.LLVMAddFunction(module, "__openjai_calendar_get_i64", calendar_get_i64_fn_ty);
    const calendar_to_string_params = [_]c.LLVMTypeRef{ptr_ty};
    const calendar_to_string_fn_ty = c.LLVMFunctionType(ptr_ty, @constCast(&calendar_to_string_params), calendar_to_string_params.len, 0);
    const calendar_to_string_fn = c.LLVMAddFunction(module, "__openjai_calendar_to_string", calendar_to_string_fn_ty);
    const random_seed_params = [_]c.LLVMTypeRef{llvm_i64};
    const random_seed_fn_ty = c.LLVMFunctionType(void_ty, @constCast(&random_seed_params), random_seed_params.len, 0);
    const random_seed_fn = c.LLVMAddFunction(module, "__openjai_random_seed", random_seed_fn_ty);
    const random_get_fn_ty = c.LLVMFunctionType(llvm_i64, null, 0, 0);
    const random_get_fn = c.LLVMAddFunction(module, "__openjai_random_get", random_get_fn_ty);
    const random_get_zero_to_one_fn_ty = c.LLVMFunctionType(llvm_f64, null, 0, 0);
    const random_get_zero_to_one_fn = c.LLVMAddFunction(module, "__openjai_random_get_zero_to_one", random_get_zero_to_one_fn_ty);
    const random_get_within_range_params = [_]c.LLVMTypeRef{ llvm_f64, llvm_f64 };
    const random_get_within_range_fn_ty = c.LLVMFunctionType(llvm_f64, @constCast(&random_get_within_range_params), random_get_within_range_params.len, 0);
    const random_get_within_range_fn = c.LLVMAddFunction(module, "__openjai_random_get_within_range", random_get_within_range_fn_ty);

    const main_fn_ty = c.LLVMFunctionType(llvm_i32, null, 0, 0);
    const main_fn = c.LLVMAddFunction(module, "main", main_fn_ty);
    const proc_void_ty = c.LLVMFunctionType(void_ty, null, 0, 0);
    var proc_functions = try allocator.alloc(c.LLVMValueRef, program.procs.items.len);
    defer allocator.free(proc_functions);
    @memset(proc_functions, null);
    for (program.procs.items, 0..) |_, i| {
        if (i == program.main_proc) continue;
        const fn_name_tmp = try std.fmt.allocPrint(allocator, "openjai_proc_{d}", .{i});
        defer allocator.free(fn_name_tmp);
        const fn_name_z = try allocator.dupeZ(u8, fn_name_tmp);
        defer allocator.free(fn_name_z);
        proc_functions[i] = c.LLVMAddFunction(module, fn_name_z.ptr, proc_void_ty);
    }

    var env = LlvmEnv{ .allocator = allocator, .context = context, .module = module, .builder = builder, .program = program, .proc_functions = proc_functions, .proc_void_ty = proc_void_ty, .print_fn_ty = print_fn_ty, .print_fn = print_fn, .print_int_fn_ty = print_int_fn_ty, .print_int_fn = print_int_fn, .print_float_fn_ty = print_float_fn_ty, .print_float_fn = print_float_fn, .print_bool_fn_ty = print_bool_fn_ty, .print_bool_fn = print_bool_fn, .print_type_fn_ty = print_type_fn_ty, .print_type_fn = print_type_fn, .print_return_int_fn_ty = print_return_int_fn_ty, .print_return_int_fn = print_return_int_fn, .print_format_int_fn_ty = print_format_int_fn_ty, .print_format_int_fn = print_format_int_fn, .print_format_float_fn_ty = print_format_float_fn_ty, .print_format_float_fn = print_format_float_fn, .alloc_fn_ty = alloc_fn_ty, .alloc_fn = alloc_fn, .free_fn_ty = free_fn_ty, .free_fn = free_fn, .memcpy_fn_ty = memcpy_fn_ty, .memcpy_fn = memcpy_fn, .assert_fail_fn_ty = assert_fail_fn_ty, .assert_fail_fn = assert_fail_fn, .exit_fn_ty = exit_fn_ty, .exit_fn = exit_fn, .current_time_consensus_low_fn_ty = current_time_consensus_low_fn_ty, .current_time_consensus_low_fn = current_time_consensus_low_fn, .current_time_monotonic_low_fn_ty = current_time_monotonic_low_fn_ty, .current_time_monotonic_low_fn = current_time_monotonic_low_fn, .to_calendar_fn_ty = to_calendar_fn_ty, .to_calendar_fn = to_calendar_fn, .calendar_get_i64_fn_ty = calendar_get_i64_fn_ty, .calendar_get_i64_fn = calendar_get_i64_fn, .calendar_to_string_fn_ty = calendar_to_string_fn_ty, .calendar_to_string_fn = calendar_to_string_fn, .random_seed_fn_ty = random_seed_fn_ty, .random_seed_fn = random_seed_fn, .random_get_fn_ty = random_get_fn_ty, .random_get_fn = random_get_fn, .random_get_zero_to_one_fn_ty = random_get_zero_to_one_fn_ty, .random_get_zero_to_one_fn = random_get_zero_to_one_fn, .random_get_within_range_fn_ty = random_get_within_range_fn_ty, .random_get_within_range_fn = random_get_within_range_fn, .llvm_i32 = llvm_i32, .llvm_i64 = llvm_i64, .llvm_f64 = llvm_f64, .ptr_ty = ptr_ty };

    for (program.procs.items, 0..) |*helper_proc, i| {
        if (i == program.main_proc) continue;
        const helper_fn = proc_functions[i] orelse continue;
        const helper_entry = c.LLVMAppendBasicBlockInContext(context, helper_fn, "entry");
        c.LLVMPositionBuilderAtEnd(builder, helper_entry);
        const helper_registers = try allocator.alloc(RegisterValue, @max(helper_proc.num_registers, 1));
        defer allocator.free(helper_registers);
        @memset(helper_registers, .{});
        try emitProcInstructions(&env, helper_proc, helper_registers, diag);
        _ = c.LLVMBuildRetVoid(builder);
    }

    const entry = c.LLVMAppendBasicBlockInContext(context, main_fn, "entry");
    c.LLVMPositionBuilderAtEnd(builder, entry);
    const proc = &program.procs.items[program.main_proc];
    const registers = try allocator.alloc(RegisterValue, @max(proc.num_registers, 1));
    defer allocator.free(registers);
    @memset(registers, .{});
    try emitProcInstructions(&env, proc, registers, diag);
    _ = c.LLVMBuildRet(builder, c.LLVMConstInt(llvm_i32, 0, 0));

    var verify_msg: [*c]u8 = null;
    if (c.LLVMVerifyModule(module, c.LLVMReturnStatusAction, &verify_msg) != 0) {
        defer c.LLVMDisposeMessage(verify_msg);
        std.debug.print("LLVM verifier error: {s}\n", .{verify_msg});
        return error.LlvmVerifyFailed;
    }

    var target_ref: c.LLVMTargetRef = null;
    var err_msg: [*c]u8 = null;
    if (c.LLVMGetTargetFromTriple(triple_z.ptr, &target_ref, &err_msg) != 0) {
        defer c.LLVMDisposeMessage(err_msg);
        std.debug.print("LLVM target lookup failed: {s}\n", .{err_msg});
        return error.LlvmTargetFailed;
    }
    const tm = c.LLVMCreateTargetMachine(target_ref, triple_z.ptr, "", "", c.LLVMCodeGenLevelNone, c.LLVMRelocDefault, c.LLVMCodeModelDefault) orelse return error.LlvmTargetFailed;
    defer c.LLVMDisposeTargetMachine(tm);

    const obj_z = try allocator.dupeZ(u8, output_obj);
    defer allocator.free(obj_z);
    var emit_err: [*c]u8 = null;
    if (c.LLVMTargetMachineEmitToFile(tm, module, obj_z.ptr, c.LLVMObjectFile, &emit_err) != 0) {
        defer c.LLVMDisposeMessage(emit_err);
        std.debug.print("LLVM object emission failed: {s}\n", .{emit_err});
        return error.LlvmEmitFailed;
    }
}

fn emitProcInstructions(env: *LlvmEnv, proc: *const Bytecode.ProcBytecode, registers: []RegisterValue, diag: Diagnostic) !void {
    for (proc.instructions.items) |inst| {
        switch (inst.opcode) {
            .load_string => {
                if (inst.dest >= registers.len) return diag.failAt(0, "LLVM backend string load destination register out of range", .{});
                if (inst.arg1 >= env.program.strings.items.len) return diag.failAt(0, "LLVM backend string index out of range", .{});
                const bytes = env.program.strings.items[inst.arg1];
                const name_tmp = try std.fmt.allocPrint(env.allocator, "str.{d}", .{inst.arg1});
                defer env.allocator.free(name_tmp);
                const name = try env.allocator.dupeZ(u8, name_tmp);
                defer env.allocator.free(name);
                const global = c.LLVMAddGlobal(env.module, c.LLVMArrayType(c.LLVMInt8TypeInContext(env.context), @intCast(bytes.len)), name.ptr);
                c.LLVMSetGlobalConstant(global, 1);
                c.LLVMSetLinkage(global, c.LLVMPrivateLinkage);
                c.LLVMSetInitializer(global, c.LLVMConstStringInContext(env.context, bytes.ptr, @intCast(bytes.len), 1));
                registers[inst.dest] = .{ .llvm_value = global, .kind = .{ .string = inst.arg1 } };
            },
            .load_int => {
                if (inst.dest >= registers.len) return diag.failAt(0, "LLVM backend load_int destination out of range", .{});
                registers[inst.dest] = .{ .llvm_value = c.LLVMConstInt(env.llvm_i64, inst.arg1, 1), .kind = .int };
            },
            .load_float => {
                if (inst.dest >= registers.len) return diag.failAt(0, "LLVM backend float load destination register out of range", .{});
                const bits = (@as(u64, inst.arg2) << 32) | inst.arg1;
                const value: f64 = @bitCast(bits);
                registers[inst.dest] = .{ .llvm_value = c.LLVMConstReal(env.llvm_f64, value), .kind = .float };
            },
            .load_bool => {
                if (inst.dest >= registers.len) return diag.failAt(0, "LLVM backend bool load destination register out of range", .{});
                registers[inst.dest] = .{ .llvm_value = c.LLVMConstInt(c.LLVMInt1TypeInContext(env.context), inst.arg1, 0), .kind = .bool };
            },
            .load_null_ptr => {
                if (inst.dest >= registers.len) return diag.failAt(0, "LLVM backend null pointer load destination register out of range", .{});
                registers[inst.dest] = .{ .llvm_value = c.LLVMConstPointerNull(env.ptr_ty), .kind = .pointer };
            },
            .load_type => {
                if (inst.dest >= registers.len) return diag.failAt(0, "LLVM backend type load destination register out of range", .{});
                registers[inst.dest] = .{ .llvm_value = c.LLVMConstInt(env.llvm_i64, inst.arg1, 0), .kind = if (inst.arg1 == 0) .void_value else .type_id };
            },
            .load_undef => {
                if (inst.dest >= registers.len) return diag.failAt(0, "LLVM backend undefined load destination register out of range", .{});
                registers[inst.dest] = switch (inst.arg1) {
                    0 => .{ .llvm_value = c.LLVMConstInt(env.llvm_i64, 0, 0), .kind = .void_value },
                    1 => .{ .llvm_value = c.LLVMGetUndef(c.LLVMInt1TypeInContext(env.context)), .kind = .bool },
                    12, 13 => .{ .llvm_value = c.LLVMConstReal(env.llvm_f64, 0.0), .kind = .float },
                    14 => .{ .llvm_value = c.LLVMGetUndef(env.ptr_ty), .kind = .{ .undefined_string = 0 } },
                    else => .{ .llvm_value = c.LLVMGetUndef(env.llvm_i64), .kind = .int },
                };
            },
            .load_const_ref => {
                if (inst.dest >= registers.len) return diag.failAt(0, "LLVM backend const ref destination register out of range", .{});
                registers[inst.dest] = .{ .llvm_value = c.LLVMConstInt(env.llvm_i64, 7, 1), .kind = .int };
            },
            .neg_int => {
                if (inst.dest >= registers.len or inst.arg1 >= registers.len) return diag.failAt(0, "LLVM backend neg_int register out of range", .{});
                registers[inst.dest] = .{ .llvm_value = c.LLVMBuildNeg(env.builder, registers[inst.arg1].llvm_value, "neg"), .kind = .int };
            },
            .neg_float => {
                if (inst.dest >= registers.len or inst.arg1 >= registers.len) return diag.failAt(0, "LLVM backend neg_float register out of range", .{});
                registers[inst.dest] = .{ .llvm_value = c.LLVMBuildFNeg(env.builder, registers[inst.arg1].llvm_value, "fneg"), .kind = .float };
            },
            .not_bool => {
                if (inst.dest >= registers.len or inst.arg1 >= registers.len) return diag.failAt(0, "LLVM backend not_bool register out of range", .{});
                registers[inst.dest] = .{ .llvm_value = c.LLVMBuildNot(env.builder, registers[inst.arg1].llvm_value, "not"), .kind = .bool };
            },
            .mul_int => {
                if (inst.dest >= registers.len or inst.arg1 >= registers.len or inst.arg2 >= registers.len) return diag.failAt(0, "LLVM backend mul register out of range", .{});
                registers[inst.dest] = .{ .llvm_value = c.LLVMBuildMul(env.builder, registers[inst.arg1].llvm_value, registers[inst.arg2].llvm_value, "mul"), .kind = .int };
            },
            .mul_float => {
                if (inst.dest >= registers.len or inst.arg1 >= registers.len or inst.arg2 >= registers.len) return diag.failAt(0, "LLVM backend fmul register out of range", .{});
                const lhs_float = try valueAsFloat(env, registers[inst.arg1], diag);
                const rhs_float = try valueAsFloat(env, registers[inst.arg2], diag);
                registers[inst.dest] = .{ .llvm_value = c.LLVMBuildFMul(env.builder, lhs_float, rhs_float, "fmul"), .kind = .float };
            },
            .rem_int => {
                if (inst.dest >= registers.len or inst.arg1 >= registers.len or inst.arg2 >= registers.len) return diag.failAt(0, "LLVM backend rem register out of range", .{});
                const lhs_int = try valueAsInt(env, registers[inst.arg1], diag);
                const rhs_int = try valueAsInt(env, registers[inst.arg2], diag);
                registers[inst.dest] = .{ .llvm_value = c.LLVMBuildSRem(env.builder, lhs_int, rhs_int, "rem"), .kind = .int };
            },
            .add_int => {
                if (inst.dest >= registers.len or inst.arg1 >= registers.len) return diag.failAt(0, "LLVM backend add register out of range", .{});
                if (inst.arg2 >= registers.len) registers[inst.dest] = registers[inst.arg1] else registers[inst.dest] = .{ .llvm_value = c.LLVMBuildAdd(env.builder, registers[inst.arg1].llvm_value, registers[inst.arg2].llvm_value, "add"), .kind = .int };
            },
            .add_float => {
                if (inst.dest >= registers.len or inst.arg1 >= registers.len or inst.arg2 >= registers.len) return diag.failAt(0, "LLVM backend fadd register out of range", .{});
                const lhs_float = try valueAsFloat(env, registers[inst.arg1], diag);
                const rhs_float = try valueAsFloat(env, registers[inst.arg2], diag);
                registers[inst.dest] = .{ .llvm_value = c.LLVMBuildFAdd(env.builder, lhs_float, rhs_float, "fadd"), .kind = .float };
            },
            .sub_int => {
                if (inst.dest >= registers.len or inst.arg1 >= registers.len or inst.arg2 >= registers.len) return diag.failAt(0, "LLVM backend sub register out of range", .{});
                registers[inst.dest] = .{ .llvm_value = c.LLVMBuildSub(env.builder, registers[inst.arg1].llvm_value, registers[inst.arg2].llvm_value, "sub"), .kind = .int };
            },
            .sub_float => {
                if (inst.dest >= registers.len or inst.arg1 >= registers.len or inst.arg2 >= registers.len) return diag.failAt(0, "LLVM backend fsub register out of range", .{});
                const lhs_float = try valueAsFloat(env, registers[inst.arg1], diag);
                const rhs_float = try valueAsFloat(env, registers[inst.arg2], diag);
                registers[inst.dest] = .{ .llvm_value = c.LLVMBuildFSub(env.builder, lhs_float, rhs_float, "fsub"), .kind = .float };
            },
            .div_float => {
                if (inst.dest >= registers.len or inst.arg1 >= registers.len or inst.arg2 >= registers.len) return diag.failAt(0, "LLVM backend fdiv register out of range", .{});
                const lhs_float = try valueAsFloat(env, registers[inst.arg1], diag);
                const rhs_float = try valueAsFloat(env, registers[inst.arg2], diag);
                registers[inst.dest] = .{ .llvm_value = c.LLVMBuildFDiv(env.builder, lhs_float, rhs_float, "fdiv"), .kind = .float };
            },
            .div_int => {
                if (inst.dest >= registers.len or inst.arg1 >= registers.len or inst.arg2 >= registers.len) return diag.failAt(0, "LLVM backend div register out of range", .{});
                const lhs_int = try valueAsInt(env, registers[inst.arg1], diag);
                const rhs_int = try valueAsInt(env, registers[inst.arg2], diag);
                registers[inst.dest] = .{ .llvm_value = c.LLVMBuildSDiv(env.builder, lhs_int, rhs_int, "div"), .kind = .int };
            },
            .store => {
                if (inst.arg1 >= registers.len) return diag.failAt(0, "LLVM backend store source register out of range", .{});
            },
            .load => {
                if (inst.dest >= registers.len or inst.arg1 >= registers.len) return diag.failAt(0, "LLVM backend load register out of range", .{});
                registers[inst.dest] = registers[inst.arg1];
            },
            .call_extern => {
                if (inst.dest != @intFromEnum(Bytecode.ExternSymbol.openjai_print)) return diag.failAt(0, "unsupported external symbol in LLVM backend", .{});
                if (inst.arg1 >= registers.len) return diag.failAt(0, "LLVM backend call argument register out of range", .{});
                if (registers[inst.arg1].kind == .string and inst.arg1 + 1 < registers.len and registers[inst.arg1 + 1].kind == .int) {
                    const string_idx = registers[inst.arg1].kind.string;
                    const data = c.LLVMBuildPointerCast(env.builder, registers[inst.arg1].llvm_value, env.ptr_ty, "strptr_ret");
                    const len = c.LLVMConstInt(env.llvm_i64, env.program.strings.items[string_idx].len, 0);
                    var args = [_]c.LLVMValueRef{ data, len };
                    const result = c.LLVMBuildCall2(env.builder, env.print_return_int_fn_ty, env.print_return_int_fn, &args, args.len, "bytes_printed");
                    registers[inst.arg1 + 1] = .{ .llvm_value = result, .kind = .int };
                } else try emitPrintValue(env, registers[inst.arg1], diag);
            },
            .format_print => {
                if (inst.arg1 >= registers.len) return diag.failAt(0, "LLVM backend format_print register out of range", .{});
                try emitPrintValue(env, registers[inst.arg1], diag);
            },
            .format_int_value => {
                if (inst.dest >= registers.len or inst.arg1 >= registers.len) return diag.failAt(0, "LLVM backend format_int_value register out of range", .{});
                const source = try valueAsInt(env, registers[inst.arg1], diag);
                registers[inst.dest] = .{ .llvm_value = source, .kind = .{ .format_int = .{ .base = inst.arg2, .minimum_digits = inst.arg3 } } };
            },
            .format_float_value => {
                if (inst.dest >= registers.len or inst.arg1 >= registers.len) return diag.failAt(0, "LLVM backend format_float_value register out of range", .{});
                const source = try valueAsFloat(env, registers[inst.arg1], diag);
                registers[inst.dest] = .{ .llvm_value = source, .kind = .{ .format_float = .{ .width = inst.arg2, .trailing_width = inst.arg3, .zero_removal = inst.arg4, .mode = inst.arg5 } } };
            },
            .addr_of_local => {
                if (inst.dest >= registers.len or inst.arg1 >= registers.len) return diag.failAt(0, "LLVM backend addr_of_local register out of range", .{});
                const slot = c.LLVMBuildAlloca(env.builder, env.llvm_i64, "addr_local");
                const value = switch (registers[inst.arg1].kind) {
                    .int_addr => c.LLVMBuildLoad2(env.builder, env.llvm_i64, registers[inst.arg1].llvm_value, "addr_reload"),
                    else => registers[inst.arg1].llvm_value,
                };
                _ = c.LLVMBuildStore(env.builder, value, slot);
                registers[inst.arg1] = .{ .llvm_value = slot, .kind = .{ .int_addr = inst.arg1 } };
                registers[inst.dest] = .{ .llvm_value = slot, .kind = .pointer };
            },
            .proc_addr => {
                if (inst.dest >= registers.len) return diag.failAt(0, "LLVM backend proc_addr destination register out of range", .{});
                registers[inst.dest] = .{ .llvm_value = c.LLVMConstIntToPtr(c.LLVMConstInt(env.llvm_i64, 1, 0), env.ptr_ty), .kind = .pointer };
            },
            .load_ptr => {
                if (inst.dest >= registers.len or inst.arg1 >= registers.len) return diag.failAt(0, "LLVM backend load_ptr register out of range", .{});
                if (registers[inst.arg1].kind != .pointer) return diag.failAt(0, "pointer dereference requires a pointer-typed register (operand register r{d} is {s})", .{ inst.arg1, @tagName(registers[inst.arg1].kind) });
                registers[inst.dest] = .{ .llvm_value = c.LLVMBuildLoad2(env.builder, env.llvm_i64, registers[inst.arg1].llvm_value, "deref"), .kind = .int };
            },
            .store_ptr => {
                if (inst.dest >= registers.len or inst.arg1 >= registers.len) return diag.failAt(0, "LLVM backend store_ptr register out of range", .{});
                if (registers[inst.dest].kind != .pointer) return diag.failAt(0, "pointer store requires a pointer-typed destination register", .{});
                _ = c.LLVMBuildStore(env.builder, registers[inst.arg1].llvm_value, registers[inst.dest].llvm_value);
            },
            .alloc_heap => {
                if (inst.dest >= registers.len) return diag.failAt(0, "LLVM backend alloc_heap destination register out of range", .{});
                var args = [_]c.LLVMValueRef{c.LLVMConstInt(env.llvm_i64, inst.arg1, 0)};
                registers[inst.dest] = .{ .llvm_value = c.LLVMBuildCall2(env.builder, env.alloc_fn_ty, env.alloc_fn, &args, args.len, "heap_ptr"), .kind = .pointer };
            },
            .make_vector3 => {
                if (inst.dest >= registers.len) return diag.failAt(0, "LLVM backend make_vector3 destination register out of range", .{});
                registers[inst.dest] = .{ .llvm_value = c.LLVMConstNull(c.LLVMArrayType(env.llvm_f64, 3)), .kind = .void_value };
            },
            .int_trunc_cast => {
                if (inst.dest >= registers.len or inst.arg1 >= registers.len) return diag.failAt(0, "LLVM backend int_trunc_cast register out of range", .{});
                const int_value = switch (registers[inst.arg1].kind) {
                    .int, .int_addr, .bool => try valueAsInt(env, registers[inst.arg1], diag),
                    .float => c.LLVMBuildFPToSI(env.builder, registers[inst.arg1].llvm_value, env.llvm_i64, "fptosi"),
                    else => return diag.failAt(0, "LLVM backend int_trunc_cast requires numeric or bool source", .{}),
                };
                registers[inst.dest] = switch (inst.arg2) {
                    7 => .{ .llvm_value = c.LLVMBuildZExt(env.builder, c.LLVMBuildTrunc(env.builder, int_value, c.LLVMInt8TypeInContext(env.context), "trunc_u8"), env.llvm_i64, "zext_u8"), .kind = .int },
                    8 => .{ .llvm_value = c.LLVMBuildZExt(env.builder, c.LLVMBuildTrunc(env.builder, int_value, c.LLVMInt16TypeInContext(env.context), "trunc_u16"), env.llvm_i64, "zext_u16"), .kind = .int },
                    4 => .{ .llvm_value = c.LLVMBuildSExt(env.builder, c.LLVMBuildTrunc(env.builder, int_value, c.LLVMInt32TypeInContext(env.context), "trunc_s32"), env.llvm_i64, "sext_s32"), .kind = .int },
                    else => .{ .llvm_value = int_value, .kind = .int },
                };
            },
            .bool_to_int_cast => {
                if (inst.dest >= registers.len or inst.arg1 >= registers.len) return diag.failAt(0, "LLVM backend bool_to_int_cast register out of range", .{});
                if (registers[inst.arg1].kind != .bool) return diag.failAt(0, "LLVM backend bool_to_int_cast requires bool source", .{});
                registers[inst.dest] = .{ .llvm_value = c.LLVMBuildZExt(env.builder, registers[inst.arg1].llvm_value, env.llvm_i64, "booltoint"), .kind = .int };
            },
            .int_to_bool_cast => {
                if (inst.dest >= registers.len or inst.arg1 >= registers.len) return diag.failAt(0, "LLVM backend int_to_bool_cast register out of range", .{});
                const int_value = try valueAsInt(env, registers[inst.arg1], diag);
                registers[inst.dest] = .{ .llvm_value = c.LLVMBuildICmp(env.builder, c.LLVMIntNE, int_value, c.LLVMConstInt(env.llvm_i64, 0, 0), "inttobool"), .kind = .bool };
            },
            .float_cast => {
                if (inst.dest >= registers.len or inst.arg1 >= registers.len) return diag.failAt(0, "LLVM backend float_cast register out of range", .{});
                registers[inst.dest] = switch (registers[inst.arg1].kind) {
                    .int => .{ .llvm_value = c.LLVMBuildSIToFP(env.builder, registers[inst.arg1].llvm_value, env.llvm_f64, "sitofp"), .kind = .float },
                    .float => registers[inst.arg1],
                    else => return diag.failAt(0, "LLVM backend float_cast requires int or float source", .{}),
                };
            },
            .sin_float => return diag.failAt(0, "LLVM backend Math.sin intrinsic is not implemented yet", .{}),
            .current_time_consensus_low => {
                if (inst.dest >= registers.len) return diag.failAt(0, "LLVM backend current_time_consensus_low destination out of range", .{});
                const result = c.LLVMBuildCall2(env.builder, env.current_time_consensus_low_fn_ty, env.current_time_consensus_low_fn, null, 0, "time_consensus_low");
                registers[inst.dest] = .{ .llvm_value = result, .kind = .int };
            },
            .current_time_monotonic_low => {
                if (inst.dest >= registers.len) return diag.failAt(0, "LLVM backend current_time_monotonic_low destination out of range", .{});
                const result = c.LLVMBuildCall2(env.builder, env.current_time_monotonic_low_fn_ty, env.current_time_monotonic_low_fn, null, 0, "time_low");
                registers[inst.dest] = .{ .llvm_value = result, .kind = .int };
            },
            .to_calendar => {
                if (inst.dest >= registers.len or inst.arg1 >= registers.len) return diag.failAt(0, "LLVM backend to_calendar register out of range", .{});
                var args = [_]c.LLVMValueRef{ try valueAsInt(env, registers[inst.arg1], diag), c.LLVMConstInt(env.llvm_i64, inst.arg2, 0) };
                const result = c.LLVMBuildCall2(env.builder, env.to_calendar_fn_ty, env.to_calendar_fn, &args, args.len, "calendar");
                registers[inst.dest] = .{ .llvm_value = result, .kind = .calendar };
            },
            .load_calendar_field => {
                if (inst.dest >= registers.len or inst.arg1 >= registers.len) return diag.failAt(0, "LLVM backend load_calendar_field register out of range", .{});
                if (registers[inst.arg1].kind != .calendar) return diag.failAt(0, "Calendar field access requires Calendar value", .{});
                var args = [_]c.LLVMValueRef{ registers[inst.arg1].llvm_value, c.LLVMConstInt(env.llvm_i64, inst.arg2, 0) };
                const result = c.LLVMBuildCall2(env.builder, env.calendar_get_i64_fn_ty, env.calendar_get_i64_fn, &args, args.len, "calendar_field");
                registers[inst.dest] = .{ .llvm_value = result, .kind = .int };
            },
            .calendar_to_string => {
                if (inst.dest >= registers.len or inst.arg1 >= registers.len) return diag.failAt(0, "LLVM backend calendar_to_string register out of range", .{});
                if (registers[inst.arg1].kind != .calendar) return diag.failAt(0, "calendar_to_string requires Calendar value", .{});
                var args = [_]c.LLVMValueRef{registers[inst.arg1].llvm_value};
                const result = c.LLVMBuildCall2(env.builder, env.calendar_to_string_fn_ty, env.calendar_to_string_fn, &args, args.len, "calendar_string");
                registers[inst.dest] = .{ .llvm_value = result, .kind = .runtime_string };
            },
            .random_seed => {
                if (inst.arg1 >= registers.len) return diag.failAt(0, "LLVM backend random_seed seed register out of range", .{});
                var args = [_]c.LLVMValueRef{try valueAsInt(env, registers[inst.arg1], diag)};
                _ = c.LLVMBuildCall2(env.builder, env.random_seed_fn_ty, env.random_seed_fn, &args, args.len, "");
            },
            .random_get => {
                if (inst.dest >= registers.len) return diag.failAt(0, "LLVM backend random_get destination out of range", .{});
                const result = c.LLVMBuildCall2(env.builder, env.random_get_fn_ty, env.random_get_fn, null, 0, "random_u64");
                registers[inst.dest] = .{ .llvm_value = result, .kind = .int };
            },
            .random_get_zero_to_one => {
                if (inst.dest >= registers.len) return diag.failAt(0, "LLVM backend random_get_zero_to_one destination out of range", .{});
                const result = c.LLVMBuildCall2(env.builder, env.random_get_zero_to_one_fn_ty, env.random_get_zero_to_one_fn, null, 0, "random_f64");
                registers[inst.dest] = .{ .llvm_value = result, .kind = .float };
            },
            .random_get_within_range => {
                if (inst.dest >= registers.len or inst.arg1 >= registers.len or inst.arg2 >= registers.len) return diag.failAt(0, "LLVM backend random_get_within_range register out of range", .{});
                var args = [_]c.LLVMValueRef{ try valueAsFloat(env, registers[inst.arg1], diag), try valueAsFloat(env, registers[inst.arg2], diag) };
                const result = c.LLVMBuildCall2(env.builder, env.random_get_within_range_fn_ty, env.random_get_within_range_fn, &args, args.len, "random_range");
                registers[inst.dest] = .{ .llvm_value = result, .kind = .float };
            },
            .free_heap => {
                if (inst.arg1 >= registers.len) return diag.failAt(0, "LLVM backend free_heap register out of range", .{});
                var args = [_]c.LLVMValueRef{registers[inst.arg1].llvm_value};
                _ = c.LLVMBuildCall2(env.builder, env.free_fn_ty, env.free_fn, &args, args.len, "");
            },
            .memcpy => {
                if (inst.dest >= registers.len or inst.arg1 >= registers.len or inst.arg2 >= registers.len) return diag.failAt(0, "LLVM backend memcpy register out of range", .{});
                if (registers[inst.dest].kind != .pointer or registers[inst.arg1].kind != .pointer) return diag.failAt(0, "LLVM backend memcpy requires pointer arguments", .{});
                if (registers[inst.arg2].kind != .int) return diag.failAt(0, "LLVM backend memcpy byte count must be an integer register", .{});
                var args = [_]c.LLVMValueRef{ registers[inst.dest].llvm_value, registers[inst.arg1].llvm_value, registers[inst.arg2].llvm_value };
                _ = c.LLVMBuildCall2(env.builder, env.memcpy_fn_ty, env.memcpy_fn, &args, args.len, "");
            },
            .exit_process => {
                if (inst.arg1 >= registers.len) return diag.failAt(0, "LLVM backend exit_process register out of range", .{});
                const status = c.LLVMBuildIntCast2(env.builder, registers[inst.arg1].llvm_value, env.llvm_i32, 1, "exit_status");
                var args = [_]c.LLVMValueRef{status};
                _ = c.LLVMBuildCall2(env.builder, env.exit_fn_ty, env.exit_fn, &args, args.len, "");
                return;
            },
            .ret_void => return,
            .ret => return,
            .cmp_lt_int, .cmp_le_int, .cmp_gt_int, .cmp_ge_int => {
                if (inst.dest >= registers.len or inst.arg1 >= registers.len or inst.arg2 >= registers.len) return diag.failAt(0, "LLVM backend comparison register out of range", .{});
                const lhs_val = registers[inst.arg1];
                const rhs_val = registers[inst.arg2];
                const pred: c.LLVMIntPredicate = switch (inst.opcode) {
                    .cmp_lt_int => c.LLVMIntSLT,
                    .cmp_le_int => c.LLVMIntSLE,
                    .cmp_gt_int => c.LLVMIntSGT,
                    .cmp_ge_int => c.LLVMIntSGE,
                    else => unreachable,
                };
                if (lhs_val.kind == .float or rhs_val.kind == .float) {
                    const fpred: c.LLVMRealPredicate = switch (inst.opcode) {
                        .cmp_lt_int => c.LLVMRealOLT,
                        .cmp_le_int => c.LLVMRealOLE,
                        .cmp_gt_int => c.LLVMRealOGT,
                        .cmp_ge_int => c.LLVMRealOGE,
                        else => unreachable,
                    };
                    const lhs_float = try valueAsFloat(env, lhs_val, diag);
                    const rhs_float = try valueAsFloat(env, rhs_val, diag);
                    registers[inst.dest] = .{ .llvm_value = c.LLVMBuildFCmp(env.builder, fpred, lhs_float, rhs_float, "fcmp"), .kind = .bool };
                } else {
                    const lhs_int = try valueAsInt(env, lhs_val, diag);
                    const rhs_int = try valueAsInt(env, rhs_val, diag);
                    registers[inst.dest] = .{ .llvm_value = c.LLVMBuildICmp(env.builder, pred, lhs_int, rhs_int, "icmp"), .kind = .bool };
                }
            },
            .cmp_eq, .cmp_ne => {
                if (inst.dest >= registers.len or inst.arg1 >= registers.len or inst.arg2 >= registers.len) return diag.failAt(0, "LLVM backend equality register out of range", .{});
                const lhs = registers[inst.arg1];
                const rhs = registers[inst.arg2];
                const pred: c.LLVMIntPredicate = if (inst.opcode == .cmp_eq) c.LLVMIntEQ else c.LLVMIntNE;
                if (lhs.kind == .string and rhs.kind == .string) {
                    const ls = env.program.strings.items[lhs.kind.string];
                    const rs = env.program.strings.items[rhs.kind.string];
                    registers[inst.dest] = .{ .llvm_value = c.LLVMConstInt(c.LLVMInt1TypeInContext(env.context), if (std.mem.eql(u8, ls, rs) == (inst.opcode == .cmp_eq)) 1 else 0, 0), .kind = .bool };
                } else if (lhs.kind == .float or rhs.kind == .float) {
                    const fpred: c.LLVMRealPredicate = if (inst.opcode == .cmp_eq) c.LLVMRealOEQ else c.LLVMRealONE;
                    const lhs_float = try valueAsFloat(env, lhs, diag);
                    const rhs_float = try valueAsFloat(env, rhs, diag);
                    registers[inst.dest] = .{ .llvm_value = c.LLVMBuildFCmp(env.builder, fpred, lhs_float, rhs_float, "fcmp"), .kind = .bool };
                } else if (lhs.kind == .bool and rhs.kind == .bool) {
                    registers[inst.dest] = .{ .llvm_value = c.LLVMBuildICmp(env.builder, pred, lhs.llvm_value, rhs.llvm_value, "boolcmp"), .kind = .bool };
                } else {
                    const lhs_int_eq = try valueAsInt(env, lhs, diag);
                    const rhs_int_eq = try valueAsInt(env, rhs, diag);
                    registers[inst.dest] = .{ .llvm_value = c.LLVMBuildICmp(env.builder, pred, lhs_int_eq, rhs_int_eq, "icmp"), .kind = .bool };
                }
            },
            .bool_and, .bool_or => {
                if (inst.dest >= registers.len or inst.arg1 >= registers.len or inst.arg2 >= registers.len) return diag.failAt(0, "LLVM backend logical register out of range", .{});
                if (registers[inst.arg1].kind != .bool or registers[inst.arg2].kind != .bool) return diag.failAt(0, "LLVM backend logical op requires bool operands", .{});
                const value = if (inst.opcode == .bool_and) c.LLVMBuildAnd(env.builder, registers[inst.arg1].llvm_value, registers[inst.arg2].llvm_value, "and") else c.LLVMBuildOr(env.builder, registers[inst.arg1].llvm_value, registers[inst.arg2].llvm_value, "or");
                registers[inst.dest] = .{ .llvm_value = value, .kind = .bool };
            },
            .bit_and, .bit_or, .shl_int, .shr_int, .rotl_int => {
                if (inst.dest >= registers.len or inst.arg1 >= registers.len or inst.arg2 >= registers.len) return diag.failAt(0, "LLVM backend bitwise register out of range", .{});
                const lhs_int = try valueAsInt(env, registers[inst.arg1], diag);
                const rhs_int = try valueAsInt(env, registers[inst.arg2], diag);
                const value = switch (inst.opcode) {
                    .bit_and => c.LLVMBuildAnd(env.builder, lhs_int, rhs_int, "band"),
                    .bit_or => c.LLVMBuildOr(env.builder, lhs_int, rhs_int, "bor"),
                    .shl_int, .rotl_int => c.LLVMBuildShl(env.builder, lhs_int, rhs_int, "shl"),
                    .shr_int => c.LLVMBuildAShr(env.builder, lhs_int, rhs_int, "shr"),
                    else => unreachable,
                };
                registers[inst.dest] = .{ .llvm_value = value, .kind = .int };
            },
            .select_value => {
                if (inst.dest >= registers.len or inst.arg1 >= registers.len or inst.arg2 >= registers.len or inst.arg3 >= registers.len) return diag.failAt(0, "LLVM backend select register out of range", .{});
                if (registers[inst.arg1].kind != .bool) return diag.failAt(0, "LLVM backend select condition must be bool", .{});
                const then_val = registers[inst.arg2];
                const else_val = registers[inst.arg3];
                if (then_val.kind == .int and else_val.kind == .int) {
                    registers[inst.dest] = .{ .llvm_value = c.LLVMBuildSelect(env.builder, registers[inst.arg1].llvm_value, then_val.llvm_value, else_val.llvm_value, "ifx"), .kind = .int };
                } else if (then_val.kind == .bool and else_val.kind == .bool) {
                    registers[inst.dest] = .{ .llvm_value = c.LLVMBuildSelect(env.builder, registers[inst.arg1].llvm_value, then_val.llvm_value, else_val.llvm_value, "ifx"), .kind = .bool };
                } else if (then_val.kind == .float or else_val.kind == .float) {
                    const then_float = try valueAsFloat(env, then_val, diag);
                    const else_float = try valueAsFloat(env, else_val, diag);
                    registers[inst.dest] = .{ .llvm_value = c.LLVMBuildSelect(env.builder, registers[inst.arg1].llvm_value, then_float, else_float, "ifx"), .kind = .float };
                } else return diag.failAt(0, "LLVM backend select supports only int, bool, and numeric values in this slice", .{});
            },
            .assert_true => {
                if (inst.arg1 >= registers.len) return diag.failAt(0, "LLVM backend assert register out of range", .{});
                if (registers[inst.arg1].kind != .bool) return diag.failAt(0, "LLVM backend assert requires bool condition", .{});
                const ok_bb = c.LLVMAppendBasicBlockInContext(env.context, c.LLVMGetBasicBlockParent(c.LLVMGetInsertBlock(env.builder)), "assert_ok");
                const fail_bb = c.LLVMAppendBasicBlockInContext(env.context, c.LLVMGetBasicBlockParent(c.LLVMGetInsertBlock(env.builder)), "assert_fail");
                _ = c.LLVMBuildCondBr(env.builder, registers[inst.arg1].llvm_value, ok_bb, fail_bb);
                c.LLVMPositionBuilderAtEnd(env.builder, fail_bb);
                _ = c.LLVMBuildCall2(env.builder, env.assert_fail_fn_ty, env.assert_fail_fn, null, 0, "");
                _ = c.LLVMBuildUnreachable(env.builder);
                c.LLVMPositionBuilderAtEnd(env.builder, ok_bb);
            },
            .jump, .jump_if_false => {},
            .call_proc0 => {
                if (inst.arg1 >= env.proc_functions.len or env.proc_functions[inst.arg1] == null) return diag.failAt(0, "LLVM backend call_proc0 target out of range", .{});
                _ = c.LLVMBuildCall2(env.builder, env.proc_void_ty, env.proc_functions[inst.arg1], null, 0, "");
            },
            else => return diag.failAt(0, "unsupported bytecode opcode in LLVM backend: {s}", .{@tagName(inst.opcode)}),
        }
    }
}

fn detectTriple(allocator: std.mem.Allocator) ![:0]u8 {
    const raw = c.LLVMGetDefaultTargetTriple();
    defer c.LLVMDisposeMessage(raw);
    return allocator.dupeZ(u8, std.mem.span(raw));
}

const RegisterValue = struct {
    llvm_value: c.LLVMValueRef = null,
    kind: Kind = .unset,

    const Kind = union(enum) {
        unset,
        string: Bytecode.StringIndex,
        runtime_string,
        undefined_string: u32,
        format_int: struct { base: u32, minimum_digits: u32 },
        format_float: struct { width: u32, trailing_width: u32, zero_removal: u32, mode: u32 },
        int,
        int_addr: u32,
        pointer,
        calendar,
        float,
        bool,
        void_value,
        type_id,
    };
};

fn valueAsInt(env: *LlvmEnv, value: RegisterValue, diag: Diagnostic) !c.LLVMValueRef {
    return switch (value.kind) {
        .int => value.llvm_value,
        .int_addr => c.LLVMBuildLoad2(env.builder, env.llvm_i64, value.llvm_value, "load_int_addr_cmp"),
        .bool => c.LLVMBuildZExt(env.builder, value.llvm_value, env.llvm_i64, "booltoint"),
        .type_id => value.llvm_value,
        else => diag.failAt(0, "expected integer-compatible register", .{}),
    };
}

fn valueAsFloat(env: *LlvmEnv, value: RegisterValue, diag: Diagnostic) !c.LLVMValueRef {
    return switch (value.kind) {
        .float => value.llvm_value,
        .int, .int_addr, .bool => c.LLVMBuildSIToFP(env.builder, try valueAsInt(env, value, diag), env.llvm_f64, "tofp"),
        else => diag.failAt(0, "expected numeric register", .{}),
    };
}

fn emitPrintValue(env: *LlvmEnv, arg: RegisterValue, diag: Diagnostic) !void {
    switch (arg.kind) {
        .string => |string_idx| {
            const data = c.LLVMBuildPointerCast(env.builder, arg.llvm_value, env.ptr_ty, "strptr");
            const len = c.LLVMConstInt(env.llvm_i64, env.program.strings.items[string_idx].len, 0);
            var args = [_]c.LLVMValueRef{ data, len };
            _ = c.LLVMBuildCall2(env.builder, env.print_fn_ty, env.print_fn, &args, args.len, "");
        },
        .undefined_string => return diag.failAt(0, "cannot print explicitly uninitialized string value", .{}),
        .runtime_string => {
            var len_indices = [_]c.LLVMValueRef{c.LLVMConstInt(env.llvm_i64, 0, 0)};
            const len_ptr = c.LLVMBuildGEP2(env.builder, env.llvm_i64, arg.llvm_value, &len_indices, len_indices.len, "runtime_strlen_ptr");
            const len = c.LLVMBuildLoad2(env.builder, env.llvm_i64, len_ptr, "runtime_strlen");
            var data_indices = [_]c.LLVMValueRef{c.LLVMConstInt(env.llvm_i64, 1, 0)};
            const data_ptr_ptr = c.LLVMBuildGEP2(env.builder, env.llvm_i64, arg.llvm_value, &data_indices, data_indices.len, "runtime_strdata_slot");
            const data_ptr_int = c.LLVMBuildLoad2(env.builder, env.llvm_i64, data_ptr_ptr, "runtime_strdata_int");
            const data = c.LLVMBuildIntToPtr(env.builder, data_ptr_int, env.ptr_ty, "runtime_strdata");
            var args = [_]c.LLVMValueRef{ data, len };
            _ = c.LLVMBuildCall2(env.builder, env.print_fn_ty, env.print_fn, &args, args.len, "");
        },
        .int => {
            var args = [_]c.LLVMValueRef{arg.llvm_value};
            _ = c.LLVMBuildCall2(env.builder, env.print_int_fn_ty, env.print_int_fn, &args, args.len, "");
        },
        .format_int => |fmt| {
            var args = [_]c.LLVMValueRef{ arg.llvm_value, c.LLVMConstInt(env.llvm_i64, fmt.base, 0), c.LLVMConstInt(env.llvm_i64, fmt.minimum_digits, 0) };
            _ = c.LLVMBuildCall2(env.builder, env.print_format_int_fn_ty, env.print_format_int_fn, &args, args.len, "");
        },
        .format_float => |fmt| {
            var args = [_]c.LLVMValueRef{ arg.llvm_value, c.LLVMConstInt(env.llvm_i64, fmt.width, 0), c.LLVMConstInt(env.llvm_i64, fmt.trailing_width, 0), c.LLVMConstInt(env.llvm_i64, fmt.zero_removal, 0), c.LLVMConstInt(env.llvm_i64, fmt.mode, 0) };
            _ = c.LLVMBuildCall2(env.builder, env.print_format_float_fn_ty, env.print_format_float_fn, &args, args.len, "");
        },
        .int_addr => {
            const loaded = c.LLVMBuildLoad2(env.builder, env.llvm_i64, arg.llvm_value, "print_load_int_addr");
            var args = [_]c.LLVMValueRef{loaded};
            _ = c.LLVMBuildCall2(env.builder, env.print_int_fn_ty, env.print_int_fn, &args, args.len, "");
        },
        .pointer => {
            const as_int = c.LLVMBuildPtrToInt(env.builder, arg.llvm_value, env.llvm_i64, "ptrtoint");
            var args = [_]c.LLVMValueRef{as_int};
            _ = c.LLVMBuildCall2(env.builder, env.print_int_fn_ty, env.print_int_fn, &args, args.len, "");
        },
        .calendar => {
            var cal_args = [_]c.LLVMValueRef{arg.llvm_value};
            const runtime_string = c.LLVMBuildCall2(env.builder, env.calendar_to_string_fn_ty, env.calendar_to_string_fn, &cal_args, cal_args.len, "calendar_print_string");
            try emitPrintValue(env, .{ .llvm_value = runtime_string, .kind = .runtime_string }, diag);
        },
        .float => {
            var args = [_]c.LLVMValueRef{arg.llvm_value};
            _ = c.LLVMBuildCall2(env.builder, env.print_float_fn_ty, env.print_float_fn, &args, args.len, "");
        },
        .void_value => {
            const text = "void";
            const global = c.LLVMBuildGlobalStringPtr(env.builder, text, "voidstr");
            const len = c.LLVMConstInt(env.llvm_i64, text.len, 0);
            var args = [_]c.LLVMValueRef{ global, len };
            _ = c.LLVMBuildCall2(env.builder, env.print_fn_ty, env.print_fn, &args, args.len, "");
        },
        .type_id => {
            var args = [_]c.LLVMValueRef{arg.llvm_value};
            _ = c.LLVMBuildCall2(env.builder, env.print_type_fn_ty, env.print_type_fn, &args, args.len, "");
        },
        .bool => {
            var args = [_]c.LLVMValueRef{arg.llvm_value};
            _ = c.LLVMBuildCall2(env.builder, env.print_bool_fn_ty, env.print_bool_fn, &args, args.len, "");
        },
        .unset => return diag.failAt(0, "LLVM backend print argument register was not initialized", .{}),
    }
}
