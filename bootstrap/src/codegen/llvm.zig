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
    proc_function_tys: []c.LLVMTypeRef,
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
    arg_count_fn_ty: c.LLVMTypeRef,
    arg_count_fn: c.LLVMValueRef,
    arg_value_fn_ty: c.LLVMTypeRef,
    arg_value_fn: c.LLVMValueRef,
    read_entire_file_fn_ty: c.LLVMTypeRef,
    read_entire_file_fn: c.LLVMValueRef,
    write_entire_file_fn_ty: c.LLVMTypeRef,
    write_entire_file_fn: c.LLVMValueRef,
    string_equal_fn_ty: c.LLVMTypeRef,
    string_equal_fn: c.LLVMValueRef,
    string_slice_fn_ty: c.LLVMTypeRef,
    string_slice_fn: c.LLVMValueRef,
    array_add_fn_ty: c.LLVMTypeRef,
    array_add_fn: c.LLVMValueRef,
    array_count_fn_ty: c.LLVMTypeRef,
    array_count_fn: c.LLVMValueRef,
    array_index_fn_ty: c.LLVMTypeRef,
    array_index_fn: c.LLVMValueRef,
    llvm_i32: c.LLVMTypeRef,
    llvm_i64: c.LLVMTypeRef,
    llvm_f64: c.LLVMTypeRef,
    ptr_ty: c.LLVMTypeRef,
};

pub fn emitObject(allocator: std.mem.Allocator, program: *const Bytecode.Program, output_obj: []const u8, diag: Diagnostic) !void {
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
    const arg_count_fn_ty = c.LLVMFunctionType(llvm_i64, null, 0, 0);
    const arg_count_fn = c.LLVMAddFunction(module, "__openjai_arg_count", arg_count_fn_ty);
    const arg_value_params = [_]c.LLVMTypeRef{llvm_i64};
    const arg_value_fn_ty = c.LLVMFunctionType(ptr_ty, @constCast(&arg_value_params), arg_value_params.len, 0);
    const arg_value_fn = c.LLVMAddFunction(module, "__openjai_arg_value", arg_value_fn_ty);
    const read_entire_file_params = [_]c.LLVMTypeRef{ ptr_ty, llvm_i64 };
    const read_entire_file_fn_ty = c.LLVMFunctionType(ptr_ty, @constCast(&read_entire_file_params), read_entire_file_params.len, 0);
    const read_entire_file_fn = c.LLVMAddFunction(module, "__openjai_read_entire_file", read_entire_file_fn_ty);
    const write_entire_file_params = [_]c.LLVMTypeRef{ ptr_ty, llvm_i64, ptr_ty, llvm_i64 };
    const write_entire_file_fn_ty = c.LLVMFunctionType(c.LLVMInt1TypeInContext(context), @constCast(&write_entire_file_params), write_entire_file_params.len, 0);
    const write_entire_file_fn = c.LLVMAddFunction(module, "__openjai_write_entire_file", write_entire_file_fn_ty);
    const string_equal_params = [_]c.LLVMTypeRef{ ptr_ty, llvm_i64, ptr_ty, llvm_i64 };
    const string_equal_fn_ty = c.LLVMFunctionType(c.LLVMInt8TypeInContext(context), @constCast(&string_equal_params), string_equal_params.len, 0);
    const string_equal_fn = c.LLVMAddFunction(module, "__openjai_string_equal", string_equal_fn_ty);
    const string_slice_params = [_]c.LLVMTypeRef{ ptr_ty, llvm_i64, llvm_i64 };
    const string_slice_fn_ty = c.LLVMFunctionType(ptr_ty, @constCast(&string_slice_params), string_slice_params.len, 0);
    const string_slice_fn = c.LLVMAddFunction(module, "__openjai_string_slice", string_slice_fn_ty);
    const array_add_params = [_]c.LLVMTypeRef{ ptr_ty, ptr_ty, llvm_i64 };
    const array_add_fn_ty = c.LLVMFunctionType(ptr_ty, @constCast(&array_add_params), array_add_params.len, 0);
    const array_add_fn = c.LLVMAddFunction(module, "__openjai_array_add", array_add_fn_ty);
    const array_count_params = [_]c.LLVMTypeRef{ptr_ty};
    const array_count_fn_ty = c.LLVMFunctionType(llvm_i64, @constCast(&array_count_params), array_count_params.len, 0);
    const array_count_fn = c.LLVMAddFunction(module, "__openjai_array_count", array_count_fn_ty);
    const array_index_params = [_]c.LLVMTypeRef{ ptr_ty, llvm_i64, llvm_i64 };
    const array_index_fn_ty = c.LLVMFunctionType(ptr_ty, @constCast(&array_index_params), array_index_params.len, 0);
    const array_index_fn = c.LLVMAddFunction(module, "__openjai_array_index", array_index_fn_ty);

    const main_fn_ty = c.LLVMFunctionType(llvm_i32, null, 0, 0);
    const main_fn = if (program.main_proc != null) c.LLVMAddFunction(module, "main", main_fn_ty) else null;
    const proc_void_ty = c.LLVMFunctionType(void_ty, null, 0, 0);
    var proc_functions = try allocator.alloc(c.LLVMValueRef, program.procs.items.len);
    defer allocator.free(proc_functions);
    var proc_function_tys = try allocator.alloc(c.LLVMTypeRef, program.procs.items.len);
    defer allocator.free(proc_function_tys);
    @memset(proc_functions, null);
    @memset(proc_function_tys, null);
    for (program.procs.items, 0..) |*proc, i| {
        if (program.main_proc != null and i == program.main_proc.?) continue;
        var param_types = try allocator.alloc(c.LLVMTypeRef, proc.param_types.items.len);
        defer allocator.free(param_types);
        for (proc.param_types.items, 0..) |type_id, param_index| {
            param_types[param_index] = llvmTypeForTypeId(context, llvm_i64, llvm_f64, ptr_ty, type_id);
        }
        const return_ty = llvmTypeForTypeId(context, llvm_i64, llvm_f64, ptr_ty, proc.return_type);
        const fn_ty = c.LLVMFunctionType(return_ty, if (param_types.len == 0) null else param_types.ptr, @intCast(param_types.len), 0);
        proc_function_tys[i] = fn_ty;
        const safe_proc_name = try sanitizeLlvmSymbolName(allocator, proc.name);
        defer allocator.free(safe_proc_name);
        const fn_name_tmp = try std.fmt.allocPrint(allocator, "openjai_proc_{d}_{s}", .{ i, safe_proc_name });
        defer allocator.free(fn_name_tmp);
        const fn_name_z = try allocator.dupeZ(u8, fn_name_tmp);
        defer allocator.free(fn_name_z);
        proc_functions[i] = c.LLVMAddFunction(module, fn_name_z.ptr, fn_ty);
    }

    var env = LlvmEnv{ .allocator = allocator, .context = context, .module = module, .builder = builder, .program = program, .proc_functions = proc_functions, .proc_function_tys = proc_function_tys, .proc_void_ty = proc_void_ty, .print_fn_ty = print_fn_ty, .print_fn = print_fn, .print_int_fn_ty = print_int_fn_ty, .print_int_fn = print_int_fn, .print_float_fn_ty = print_float_fn_ty, .print_float_fn = print_float_fn, .print_bool_fn_ty = print_bool_fn_ty, .print_bool_fn = print_bool_fn, .print_type_fn_ty = print_type_fn_ty, .print_type_fn = print_type_fn, .print_return_int_fn_ty = print_return_int_fn_ty, .print_return_int_fn = print_return_int_fn, .print_format_int_fn_ty = print_format_int_fn_ty, .print_format_int_fn = print_format_int_fn, .print_format_float_fn_ty = print_format_float_fn_ty, .print_format_float_fn = print_format_float_fn, .alloc_fn_ty = alloc_fn_ty, .alloc_fn = alloc_fn, .free_fn_ty = free_fn_ty, .free_fn = free_fn, .memcpy_fn_ty = memcpy_fn_ty, .memcpy_fn = memcpy_fn, .assert_fail_fn_ty = assert_fail_fn_ty, .assert_fail_fn = assert_fail_fn, .exit_fn_ty = exit_fn_ty, .exit_fn = exit_fn, .current_time_consensus_low_fn_ty = current_time_consensus_low_fn_ty, .current_time_consensus_low_fn = current_time_consensus_low_fn, .current_time_monotonic_low_fn_ty = current_time_monotonic_low_fn_ty, .current_time_monotonic_low_fn = current_time_monotonic_low_fn, .to_calendar_fn_ty = to_calendar_fn_ty, .to_calendar_fn = to_calendar_fn, .calendar_get_i64_fn_ty = calendar_get_i64_fn_ty, .calendar_get_i64_fn = calendar_get_i64_fn, .calendar_to_string_fn_ty = calendar_to_string_fn_ty, .calendar_to_string_fn = calendar_to_string_fn, .random_seed_fn_ty = random_seed_fn_ty, .random_seed_fn = random_seed_fn, .random_get_fn_ty = random_get_fn_ty, .random_get_fn = random_get_fn, .random_get_zero_to_one_fn_ty = random_get_zero_to_one_fn_ty, .random_get_zero_to_one_fn = random_get_zero_to_one_fn, .random_get_within_range_fn_ty = random_get_within_range_fn_ty, .random_get_within_range_fn = random_get_within_range_fn, .arg_count_fn_ty = arg_count_fn_ty, .arg_count_fn = arg_count_fn, .arg_value_fn_ty = arg_value_fn_ty, .arg_value_fn = arg_value_fn, .read_entire_file_fn_ty = read_entire_file_fn_ty, .read_entire_file_fn = read_entire_file_fn, .write_entire_file_fn_ty = write_entire_file_fn_ty, .write_entire_file_fn = write_entire_file_fn, .string_equal_fn_ty = string_equal_fn_ty, .string_equal_fn = string_equal_fn, .string_slice_fn_ty = string_slice_fn_ty, .string_slice_fn = string_slice_fn, .array_add_fn_ty = array_add_fn_ty, .array_add_fn = array_add_fn, .array_count_fn_ty = array_count_fn_ty, .array_count_fn = array_count_fn, .array_index_fn_ty = array_index_fn_ty, .array_index_fn = array_index_fn, .llvm_i32 = llvm_i32, .llvm_i64 = llvm_i64, .llvm_f64 = llvm_f64, .ptr_ty = ptr_ty };

    for (program.procs.items, 0..) |*helper_proc, i| {
        if (program.main_proc != null and i == program.main_proc.?) continue;
        const helper_fn = proc_functions[i] orelse continue;
        const helper_entry = c.LLVMAppendBasicBlockInContext(context, helper_fn, "entry");
        c.LLVMPositionBuilderAtEnd(builder, helper_entry);
        const helper_registers = try allocator.alloc(RegisterValue, @max(helper_proc.num_registers, 1));
        defer allocator.free(helper_registers);
        @memset(helper_registers, .{});
        for (helper_proc.param_types.items, 0..) |type_id, param_index| {
            helper_registers[param_index] = registerValueForTypedLlvmValue(c.LLVMGetParam(helper_fn, @intCast(param_index)), type_id);
        }
        try emitProcInstructions(&env, helper_proc, helper_registers, diag);
        if (helper_proc.return_type == 0) {
            _ = c.LLVMBuildRetVoid(builder);
        } else {
            _ = c.LLVMBuildRet(builder, defaultLlvmValueForTypeId(&env, helper_proc.return_type));
        }
    }

    if (program.main_proc) |main_proc| {
        const entry = c.LLVMAppendBasicBlockInContext(context, main_fn.?, "entry");
        c.LLVMPositionBuilderAtEnd(builder, entry);
        const proc = &program.procs.items[main_proc];
        const registers = try allocator.alloc(RegisterValue, @max(proc.num_registers, 1));
        defer allocator.free(registers);
        @memset(registers, .{});
        try emitProcInstructions(&env, proc, registers, diag);
        _ = c.LLVMBuildRet(builder, c.LLVMConstInt(llvm_i32, 0, 0));
    }

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

fn llvmTypeForTypeId(context: c.LLVMContextRef, llvm_i64: c.LLVMTypeRef, llvm_f64: c.LLVMTypeRef, ptr_ty: c.LLVMTypeRef, type_id: u32) c.LLVMTypeRef {
    return switch (type_id) {
        0 => c.LLVMVoidTypeInContext(context),
        1 => c.LLVMInt1TypeInContext(context),
        12, 13 => llvm_f64,
        14 => ptr_ty,
        10 => ptr_ty,
        else => llvm_i64,
    };
}

fn emitProcInstructions(env: *LlvmEnv, proc: *const Bytecode.ProcBytecode, registers: []RegisterValue, diag: Diagnostic) !void {
    const function = c.LLVMGetBasicBlockParent(c.LLVMGetInsertBlock(env.builder));
    const instruction_count = proc.instructions.items.len;
    var blocks = try env.allocator.alloc(c.LLVMBasicBlockRef, instruction_count + 1);
    defer env.allocator.free(blocks);
    for (0..instruction_count + 1) |i| {
        const name_tmp = try std.fmt.allocPrint(env.allocator, "bc.{d}", .{i});
        defer env.allocator.free(name_tmp);
        const name = try env.allocator.dupeZ(u8, name_tmp);
        defer env.allocator.free(name);
        blocks[i] = c.LLVMAppendBasicBlockInContext(env.context, function, name.ptr);
    }
    _ = c.LLVMBuildBr(env.builder, blocks[0]);

    for (proc.instructions.items, 0..) |inst, instruction_index| {
        c.LLVMPositionBuilderAtEnd(env.builder, blocks[instruction_index]);
        var terminates_block = false;
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
                try setBoolResult(env, registers, inst.dest, c.LLVMBuildNot(env.builder, try valueAsBool(env, registers[inst.arg1], diag), "not"));
            },
            .bit_not => {
                if (inst.dest >= registers.len or inst.arg1 >= registers.len) return diag.failAt(0, "LLVM backend bit_not register out of range", .{});
                const operand = try valueAsInt(env, registers[inst.arg1], diag);
                registers[inst.dest] = .{ .llvm_value = c.LLVMBuildNot(env.builder, operand, "bnot"), .kind = .int };
            },
            .mul_int => {
                if (inst.dest >= registers.len or inst.arg1 >= registers.len or inst.arg2 >= registers.len) return diag.failAt(0, "LLVM backend mul register out of range", .{});
                const lhs_int = try valueAsInt(env, registers[inst.arg1], diag);
                const rhs_int = try valueAsInt(env, registers[inst.arg2], diag);
                try setIntResult(env, registers, inst.dest, c.LLVMBuildMul(env.builder, lhs_int, rhs_int, "mul"));
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
                try setIntResult(env, registers, inst.dest, c.LLVMBuildSRem(env.builder, lhs_int, rhs_int, "rem"));
            },
            .add_int => {
                if (inst.dest >= registers.len or inst.arg1 >= registers.len) return diag.failAt(0, "LLVM backend add register out of range", .{});
                if (inst.arg2 >= registers.len) {
                    registers[inst.dest] = registers[inst.arg1];
                } else {
                    const lhs_int = try valueAsInt(env, registers[inst.arg1], diag);
                    const rhs_int = try valueAsInt(env, registers[inst.arg2], diag);
                    try setIntResult(env, registers, inst.dest, c.LLVMBuildAdd(env.builder, lhs_int, rhs_int, "add"));
                }
            },
            .add_float => {
                if (inst.dest >= registers.len or inst.arg1 >= registers.len or inst.arg2 >= registers.len) return diag.failAt(0, "LLVM backend fadd register out of range", .{});
                const lhs_float = try valueAsFloat(env, registers[inst.arg1], diag);
                const rhs_float = try valueAsFloat(env, registers[inst.arg2], diag);
                registers[inst.dest] = .{ .llvm_value = c.LLVMBuildFAdd(env.builder, lhs_float, rhs_float, "fadd"), .kind = .float };
            },
            .sub_int => {
                if (inst.dest >= registers.len or inst.arg1 >= registers.len or inst.arg2 >= registers.len) return diag.failAt(0, "LLVM backend sub register out of range", .{});
                const lhs_int = try valueAsInt(env, registers[inst.arg1], diag);
                const rhs_int = try valueAsInt(env, registers[inst.arg2], diag);
                try setIntResult(env, registers, inst.dest, c.LLVMBuildSub(env.builder, lhs_int, rhs_int, "sub"));
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
                try setIntResult(env, registers, inst.dest, c.LLVMBuildSDiv(env.builder, lhs_int, rhs_int, "div"));
            },
            .store => {
                if (inst.arg1 >= registers.len) return diag.failAt(0, "LLVM backend store source register out of range", .{});
            },
            .load => {
                if (inst.dest >= registers.len or inst.arg1 >= registers.len) return diag.failAt(0, "LLVM backend load register out of range", .{});
                if (registers[inst.dest].kind == .int_addr) {
                    switch (registers[inst.arg1].kind) {
                        .float, .pointer, .pointer_addr, .string_addr, .calendar, .runtime_string, .string, .undefined_string, .format_int, .format_float, .void_value, .type_id => registers[inst.dest] = registers[inst.arg1],
                        else => _ = c.LLVMBuildStore(env.builder, try valueAsInt(env, registers[inst.arg1], diag), registers[inst.dest].llvm_value),
                    }
                } else if (registers[inst.dest].kind == .bool_addr) {
                    _ = c.LLVMBuildStore(env.builder, try valueAsBool(env, registers[inst.arg1], diag), registers[inst.dest].llvm_value);
                } else if (registers[inst.dest].kind == .string_addr) {
                    _ = c.LLVMBuildStore(env.builder, try runtimeStringValue(env, registers[inst.arg1], diag), registers[inst.dest].llvm_value);
                } else if (registers[inst.dest].kind == .pointer_addr) {
                    _ = c.LLVMBuildStore(env.builder, try pointerValue(env, registers[inst.arg1], diag, "pointer assignment"), registers[inst.dest].llvm_value);
                } else {
                    registers[inst.dest] = registers[inst.arg1];
                }
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
                const current_function = c.LLVMGetBasicBlockParent(c.LLVMGetInsertBlock(env.builder));
                switch (registers[inst.arg1].kind) {
                    .float => {
                        const slot = buildEntryAlloca(env, current_function, env.llvm_f64, "addr_local_f64");
                        _ = c.LLVMBuildStore(env.builder, registers[inst.arg1].llvm_value, slot);
                        registers[inst.dest] = .{ .llvm_value = slot, .kind = .pointer };
                    },
                    .pointer, .pointer_addr => {
                        const slot = buildEntryAlloca(env, current_function, env.ptr_ty, "addr_local_ptr");
                        _ = c.LLVMBuildStore(env.builder, try pointerValue(env, registers[inst.arg1], diag, "addressable pointer local"), slot);
                        registers[inst.arg1] = .{ .llvm_value = slot, .kind = .{ .pointer_addr = inst.arg1 } };
                        registers[inst.dest] = .{ .llvm_value = slot, .kind = .pointer };
                    },
                    .runtime_string, .string => {
                        const slot = buildEntryAlloca(env, current_function, env.ptr_ty, "addr_local_string");
                        _ = c.LLVMBuildStore(env.builder, try runtimeStringValue(env, registers[inst.arg1], diag), slot);
                        registers[inst.arg1] = .{ .llvm_value = slot, .kind = .{ .string_addr = inst.arg1 } };
                        registers[inst.dest] = .{ .llvm_value = slot, .kind = .pointer };
                    },
                    else => {
                        const slot = buildEntryAlloca(env, current_function, env.llvm_i64, "addr_local");
                        const value = try valueAsInt(env, registers[inst.arg1], diag);
                        _ = c.LLVMBuildStore(env.builder, value, slot);
                        registers[inst.arg1] = .{ .llvm_value = slot, .kind = .{ .int_addr = inst.arg1 } };
                        registers[inst.dest] = .{ .llvm_value = slot, .kind = .pointer };
                    },
                }
            },
            .proc_addr => {
                if (inst.dest >= registers.len) return diag.failAt(0, "LLVM backend proc_addr destination register out of range", .{});
                registers[inst.dest] = .{ .llvm_value = c.LLVMConstIntToPtr(c.LLVMConstInt(env.llvm_i64, 1, 0), env.ptr_ty), .kind = .pointer };
            },
            .load_ptr => {
                if (inst.dest >= registers.len or inst.arg1 >= registers.len) return diag.failAt(0, "LLVM backend load_ptr register out of range", .{});
                switch (registers[inst.arg1].kind) {
                    .pointer, .pointer_addr, .int, .int_addr, .bool, .bool_addr, .type_id => {
                        const ptr_value = switch (registers[inst.arg1].kind) {
                            .pointer => registers[inst.arg1].llvm_value,
                            .pointer_addr => c.LLVMBuildLoad2(env.builder, env.ptr_ty, registers[inst.arg1].llvm_value, "deref_load_ptr_addr"),
                            .int, .int_addr, .bool, .bool_addr, .type_id => c.LLVMBuildIntToPtr(env.builder, try valueAsInt(env, registers[inst.arg1], diag), env.ptr_ty, "deref_inttoptr"),
                            else => unreachable,
                        };
                        try setIntResult(env, registers, inst.dest, c.LLVMBuildLoad2(env.builder, env.llvm_i64, ptr_value, "deref"));
                    },
                    else => {
                        registers[inst.dest] = registers[inst.arg1];
                    },
                }
            },
            .load_ptr_string => {
                if (inst.dest >= registers.len or inst.arg1 >= registers.len) return diag.failAt(0, "LLVM backend load_ptr_string register out of range", .{});
                const ptr_value = try pointerValue(env, registers[inst.arg1], diag, "load string pointer");
                registers[inst.dest] = .{ .llvm_value = c.LLVMBuildLoad2(env.builder, env.ptr_ty, ptr_value, "load_runtime_string"), .kind = .runtime_string };
            },
            .store_ptr => {
                if (inst.dest >= registers.len or inst.arg1 >= registers.len) return diag.failAt(0, "LLVM backend store_ptr register out of range", .{});
                const ptr_value = try pointerValue(env, registers[inst.dest], diag, "pointer store destination");
                const source = registers[inst.arg1];
                const stored = switch (source.kind) {
                    .int, .int_addr, .bool, .bool_addr, .type_id => try valueAsInt(env, source, diag),
                    .pointer => source.llvm_value,
                    .pointer_addr => c.LLVMBuildLoad2(env.builder, env.ptr_ty, source.llvm_value, "store_src_load_ptr_addr"),
                    .runtime_string, .string, .string_addr => try runtimeStringValue(env, source, diag),
                    else => source.llvm_value,
                };
                _ = c.LLVMBuildStore(env.builder, stored, ptr_value);
            },
            .ptr_offset => {
                if (inst.dest >= registers.len or inst.arg1 >= registers.len) return diag.failAt(0, "LLVM backend ptr_offset register out of range", .{});
                const base_ptr = try pointerValue(env, registers[inst.arg1], diag, "pointer offset base");
                var indices = [_]c.LLVMValueRef{c.LLVMConstInt(env.llvm_i64, inst.arg2, 0)};
                try setPointerResult(env, registers, inst.dest, c.LLVMBuildGEP2(env.builder, c.LLVMInt8TypeInContext(env.context), base_ptr, &indices, indices.len, "ptr_offset"));
            },
            .alloc_heap => {
                if (inst.dest >= registers.len) return diag.failAt(0, "LLVM backend alloc_heap destination register out of range", .{});
                var args = [_]c.LLVMValueRef{c.LLVMConstInt(env.llvm_i64, inst.arg1, 0)};
                const result = c.LLVMBuildCall2(env.builder, env.alloc_fn_ty, env.alloc_fn, &args, args.len, "heap_ptr");
                const slot = buildEntryAlloca(env, c.LLVMGetBasicBlockParent(c.LLVMGetInsertBlock(env.builder)), env.ptr_ty, "ptr_reg");
                _ = c.LLVMBuildStore(env.builder, result, slot);
                registers[inst.dest] = .{ .llvm_value = slot, .kind = .{ .pointer_addr = inst.dest } };
            },
            .alloc_local_bytes => {
                if (inst.dest >= registers.len) return diag.failAt(0, "LLVM backend alloc_local_bytes destination register out of range", .{});
                const current_function = c.LLVMGetBasicBlockParent(c.LLVMGetInsertBlock(env.builder));
                const slot = buildEntryAlloca(env, current_function, c.LLVMArrayType(c.LLVMInt8TypeInContext(env.context), @intCast(@max(inst.arg1, 1))), "local_bytes");
                _ = c.LLVMBuildStore(env.builder, c.LLVMConstNull(c.LLVMArrayType(c.LLVMInt8TypeInContext(env.context), @intCast(@max(inst.arg1, 1)))), slot);
                registers[inst.dest] = .{ .llvm_value = c.LLVMBuildPointerCast(env.builder, slot, env.ptr_ty, "local_bytes_ptr"), .kind = .pointer };
            },
            .array_add => {
                if (inst.dest >= registers.len or inst.arg1 >= registers.len or inst.arg2 >= registers.len) return diag.failAt(0, "LLVM backend array_add register out of range", .{});
                const slot_ptr = try pointerValue(env, registers[inst.arg1], diag, "array_add slot");
                const item_ptr = if (inst.arg4 != 0)
                    try pointerValue(env, registers[inst.arg2], diag, "array_add struct item")
                else
                    try valueAddress(env, registers[inst.arg2], diag);
                var args = [_]c.LLVMValueRef{ slot_ptr, item_ptr, c.LLVMConstInt(env.llvm_i64, inst.arg3, 0) };
                const result = c.LLVMBuildCall2(env.builder, env.array_add_fn_ty, env.array_add_fn, &args, args.len, "array_item");
                try setPointerResult(env, registers, inst.dest, result);
            },
            .array_count => {
                if (inst.dest >= registers.len or inst.arg1 >= registers.len) return diag.failAt(0, "LLVM backend array_count register out of range", .{});
                var args = [_]c.LLVMValueRef{try pointerValue(env, registers[inst.arg1], diag, "array_count header")};
                try setIntResult(env, registers, inst.dest, c.LLVMBuildCall2(env.builder, env.array_count_fn_ty, env.array_count_fn, &args, args.len, "array_count"));
            },
            .array_index => {
                if (inst.dest >= registers.len or inst.arg1 >= registers.len or inst.arg2 >= registers.len) return diag.failAt(0, "LLVM backend array_index register out of range", .{});
                var args = [_]c.LLVMValueRef{
                    try pointerValue(env, registers[inst.arg1], diag, "array_index header"),
                    try valueAsInt(env, registers[inst.arg2], diag),
                    c.LLVMConstInt(env.llvm_i64, inst.arg3, 0),
                };
                const item_ptr = c.LLVMBuildCall2(env.builder, env.array_index_fn_ty, env.array_index_fn, &args, args.len, "array_index");
                switch (inst.arg4) {
                    1 => try setPointerResult(env, registers, inst.dest, item_ptr),
                    2 => registers[inst.dest] = .{ .llvm_value = c.LLVMBuildLoad2(env.builder, env.ptr_ty, item_ptr, "array_string"), .kind = .runtime_string },
                    else => try setIntResult(env, registers, inst.dest, c.LLVMBuildLoad2(env.builder, env.llvm_i64, item_ptr, "array_int")),
                }
            },
            .make_vector3 => {
                if (inst.dest >= registers.len) return diag.failAt(0, "LLVM backend make_vector3 destination register out of range", .{});
                registers[inst.dest] = .{ .llvm_value = c.LLVMConstNull(c.LLVMArrayType(env.llvm_f64, 3)), .kind = .void_value };
            },
            .int_trunc_cast => {
                if (inst.dest >= registers.len or inst.arg1 >= registers.len) return diag.failAt(0, "LLVM backend int_trunc_cast register out of range", .{});
                const int_value = switch (registers[inst.arg1].kind) {
                    .int, .int_addr, .bool, .bool_addr => try valueAsInt(env, registers[inst.arg1], diag),
                    .float => c.LLVMBuildFPToSI(env.builder, registers[inst.arg1].llvm_value, env.llvm_i64, "fptosi"),
                    else => c.LLVMConstInt(env.llvm_i64, 0, 0),
                };
                registers[inst.dest] = switch (inst.arg2) {
                    7 => .{ .llvm_value = c.LLVMBuildZExt(env.builder, c.LLVMBuildTrunc(env.builder, int_value, c.LLVMInt8TypeInContext(env.context), "trunc_u8"), env.llvm_i64, "zext_u8"), .kind = .int },
                    8 => .{ .llvm_value = c.LLVMBuildZExt(env.builder, c.LLVMBuildTrunc(env.builder, int_value, c.LLVMInt16TypeInContext(env.context), "trunc_u16"), env.llvm_i64, "zext_u16"), .kind = .int },
                    4 => .{ .llvm_value = c.LLVMBuildSExt(env.builder, c.LLVMBuildTrunc(env.builder, int_value, c.LLVMInt32TypeInContext(env.context), "trunc_s32"), env.llvm_i64, "sext_s32"), .kind = .int },
                    10 => .{ .llvm_value = c.LLVMBuildIntToPtr(env.builder, int_value, env.ptr_ty, "inttoptr"), .kind = .pointer },
                    else => .{ .llvm_value = int_value, .kind = .int },
                };
            },
            .bool_to_int_cast => {
                if (inst.dest >= registers.len or inst.arg1 >= registers.len) return diag.failAt(0, "LLVM backend bool_to_int_cast register out of range", .{});
                registers[inst.dest] = .{ .llvm_value = c.LLVMBuildZExt(env.builder, try valueAsBool(env, registers[inst.arg1], diag), env.llvm_i64, "booltoint"), .kind = .int };
            },
            .int_to_bool_cast => {
                if (inst.dest >= registers.len or inst.arg1 >= registers.len) return diag.failAt(0, "LLVM backend int_to_bool_cast register out of range", .{});
                const bool_value = switch (registers[inst.arg1].kind) {
                    .float => c.LLVMBuildFCmp(env.builder, c.LLVMRealONE, registers[inst.arg1].llvm_value, c.LLVMConstReal(env.llvm_f64, 0.0), "floattobool"),
                    .pointer => c.LLVMBuildICmp(
                        env.builder,
                        c.LLVMIntNE,
                        c.LLVMBuildPtrToInt(env.builder, registers[inst.arg1].llvm_value, env.llvm_i64, "ptrtoint_bool"),
                        c.LLVMConstInt(env.llvm_i64, 0, 0),
                        "ptrtobool",
                    ),
                    .pointer_addr => c.LLVMBuildICmp(
                        env.builder,
                        c.LLVMIntNE,
                        c.LLVMBuildPtrToInt(env.builder, c.LLVMBuildLoad2(env.builder, env.ptr_ty, registers[inst.arg1].llvm_value, "load_ptr_addr_bool"), env.llvm_i64, "ptraddrtoint_bool"),
                        c.LLVMConstInt(env.llvm_i64, 0, 0),
                        "ptraddrtobool",
                    ),
                    .string => |string_idx| c.LLVMBuildICmp(
                        env.builder,
                        c.LLVMIntNE,
                        c.LLVMConstInt(env.llvm_i64, env.program.strings.items[string_idx].len, 0),
                        c.LLVMConstInt(env.llvm_i64, 0, 0),
                        "strtobool",
                    ),
                    .runtime_string, .string_addr => blk: {
                        const runtime_string = try runtimeStringValue(env, registers[inst.arg1], diag);
                        var len_indices = [_]c.LLVMValueRef{c.LLVMConstInt(env.llvm_i64, 0, 0)};
                        const len_ptr = c.LLVMBuildGEP2(env.builder, env.llvm_i64, runtime_string, &len_indices, len_indices.len, "runtime_strlen_ptr_bool");
                        const len = c.LLVMBuildLoad2(env.builder, env.llvm_i64, len_ptr, "runtime_strlen_bool");
                        break :blk c.LLVMBuildICmp(env.builder, c.LLVMIntNE, len, c.LLVMConstInt(env.llvm_i64, 0, 0), "runtime_strtobool");
                    },
                    else => blk: {
                        const int_value = try valueAsInt(env, registers[inst.arg1], diag);
                        break :blk c.LLVMBuildICmp(env.builder, c.LLVMIntNE, int_value, c.LLVMConstInt(env.llvm_i64, 0, 0), "inttobool");
                    },
                };
                try setBoolResult(env, registers, inst.dest, bool_value);
            },
            .float_cast => {
                if (inst.dest >= registers.len or inst.arg1 >= registers.len) return diag.failAt(0, "LLVM backend float_cast register out of range", .{});
                registers[inst.dest] = switch (registers[inst.arg1].kind) {
                    .int, .int_addr, .bool, .bool_addr => .{ .llvm_value = c.LLVMBuildSIToFP(env.builder, try valueAsInt(env, registers[inst.arg1], diag), env.llvm_f64, "sitofp"), .kind = .float },
                    .float => registers[inst.arg1],
                    else => return diag.failAt(0, "LLVM backend float_cast requires int or float source", .{}),
                };
            },
            .sin_float => {
                if (inst.dest >= registers.len or inst.arg1 >= registers.len) return diag.failAt(0, "LLVM backend sin register out of range", .{});
                registers[inst.dest] = .{ .llvm_value = try valueAsFloat(env, registers[inst.arg1], diag), .kind = .float };
            },
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
            .compiler_arg_count => {
                if (inst.dest >= registers.len) return diag.failAt(0, "LLVM backend compiler_arg_count destination out of range", .{});
                const result = c.LLVMBuildCall2(env.builder, env.arg_count_fn_ty, env.arg_count_fn, null, 0, "openjai_argc");
                registers[inst.dest] = .{ .llvm_value = result, .kind = .int };
            },
            .compiler_arg => {
                if (inst.dest >= registers.len or inst.arg1 >= registers.len) return diag.failAt(0, "LLVM backend compiler_arg register out of range", .{});
                var args = [_]c.LLVMValueRef{try valueAsInt(env, registers[inst.arg1], diag)};
                const result = c.LLVMBuildCall2(env.builder, env.arg_value_fn_ty, env.arg_value_fn, &args, args.len, "openjai_argv");
                registers[inst.dest] = .{ .llvm_value = result, .kind = .runtime_string };
            },
            .compiler_read_file => {
                if (inst.dest >= registers.len or inst.arg1 >= registers.len) return diag.failAt(0, "LLVM backend compiler_read_file register out of range", .{});
                const parts = try stringParts(env, registers[inst.arg1], diag);
                var args = [_]c.LLVMValueRef{ parts.data, parts.len };
                const result = c.LLVMBuildCall2(env.builder, env.read_entire_file_fn_ty, env.read_entire_file_fn, &args, args.len, "openjai_file");
                registers[inst.dest] = .{ .llvm_value = result, .kind = .runtime_string };
            },
            .compiler_write_file => {
                if (inst.dest >= registers.len or inst.arg1 >= registers.len or inst.arg2 >= registers.len) return diag.failAt(0, "LLVM backend compiler_write_file register out of range", .{});
                const path = try stringParts(env, registers[inst.arg1], diag);
                const contents = try stringParts(env, registers[inst.arg2], diag);
                var args = [_]c.LLVMValueRef{ path.data, path.len, contents.data, contents.len };
                const result = c.LLVMBuildCall2(env.builder, env.write_entire_file_fn_ty, env.write_entire_file_fn, &args, args.len, "openjai_write_file");
                try setBoolResult(env, registers, inst.dest, result);
            },
            .string_len => {
                if (inst.dest >= registers.len or inst.arg1 >= registers.len) return diag.failAt(0, "LLVM backend string_len register out of range", .{});
                const parts = try stringParts(env, registers[inst.arg1], diag);
                try setIntResult(env, registers, inst.dest, parts.len);
            },
            .string_data => {
                if (inst.dest >= registers.len or inst.arg1 >= registers.len) return diag.failAt(0, "LLVM backend string_data register out of range", .{});
                const parts = try stringParts(env, registers[inst.arg1], diag);
                registers[inst.dest] = .{ .llvm_value = parts.data, .kind = .pointer };
            },
            .string_slice => {
                if (inst.dest >= registers.len or inst.arg1 >= registers.len or inst.arg2 >= registers.len or inst.arg3 >= registers.len) return diag.failAt(0, "LLVM backend string_slice register out of range", .{});
                const source = try pointerValue(env, registers[inst.arg1], diag, "string_slice source");
                const start = try valueAsInt(env, registers[inst.arg2], diag);
                const len = try valueAsInt(env, registers[inst.arg3], diag);
                var args = [_]c.LLVMValueRef{ source, start, len };
                const result = c.LLVMBuildCall2(env.builder, env.string_slice_fn_ty, env.string_slice_fn, &args, args.len, "string_slice");
                registers[inst.dest] = .{ .llvm_value = result, .kind = .runtime_string };
            },
            .string_index => {
                if (inst.dest >= registers.len or inst.arg1 >= registers.len or inst.arg2 >= registers.len) return diag.failAt(0, "LLVM backend string_index register out of range", .{});
                const parts = try stringParts(env, registers[inst.arg1], diag);
                const index = try valueAsInt(env, registers[inst.arg2], diag);
                var indices = [_]c.LLVMValueRef{index};
                const ptr = c.LLVMBuildGEP2(env.builder, c.LLVMInt8TypeInContext(env.context), parts.data, &indices, indices.len, "string_byte_ptr");
                const byte = c.LLVMBuildLoad2(env.builder, c.LLVMInt8TypeInContext(env.context), ptr, "string_byte");
                try setIntResult(env, registers, inst.dest, c.LLVMBuildZExt(env.builder, byte, env.llvm_i64, "string_byte_i64"));
            },
            .free_heap => {
                if (inst.arg1 >= registers.len) return diag.failAt(0, "LLVM backend free_heap register out of range", .{});
                const ptr_value = switch (registers[inst.arg1].kind) {
                    .pointer => registers[inst.arg1].llvm_value,
                    .pointer_addr => c.LLVMBuildLoad2(env.builder, env.ptr_ty, registers[inst.arg1].llvm_value, "free_load_ptr_addr"),
                    .int, .int_addr, .bool, .bool_addr => c.LLVMBuildIntToPtr(env.builder, try valueAsInt(env, registers[inst.arg1], diag), env.ptr_ty, "free_inttoptr"),
                    .string => c.LLVMBuildPointerCast(env.builder, registers[inst.arg1].llvm_value, env.ptr_ty, "free_strptr"),
                    .runtime_string, .string_addr => blk: {
                        const runtime_string = try runtimeStringValue(env, registers[inst.arg1], diag);
                        var data_indices = [_]c.LLVMValueRef{c.LLVMConstInt(env.llvm_i64, 1, 0)};
                        const data_ptr_ptr = c.LLVMBuildGEP2(env.builder, env.llvm_i64, runtime_string, &data_indices, data_indices.len, "free_runtime_strdata_slot");
                        const data_ptr_int = c.LLVMBuildLoad2(env.builder, env.llvm_i64, data_ptr_ptr, "free_runtime_strdata_int");
                        break :blk c.LLVMBuildIntToPtr(env.builder, data_ptr_int, env.ptr_ty, "free_runtime_strdata");
                    },
                    .undefined_string => c.LLVMConstNull(env.ptr_ty),
                    else => return diag.failAt(0, "LLVM backend free_heap requires a pointer-compatible register", .{}),
                };
                var args = [_]c.LLVMValueRef{ptr_value};
                _ = c.LLVMBuildCall2(env.builder, env.free_fn_ty, env.free_fn, &args, args.len, "");
            },
            .memcpy => {
                if (inst.dest >= registers.len or inst.arg1 >= registers.len or inst.arg2 >= registers.len) return diag.failAt(0, "LLVM backend memcpy register out of range", .{});
                const dst_ptr = switch (registers[inst.dest].kind) {
                    .pointer => registers[inst.dest].llvm_value,
                    .pointer_addr => blk: {
                        const loaded = c.LLVMBuildLoad2(env.builder, env.ptr_ty, registers[inst.dest].llvm_value, "memcpy_dst_load_ptr_addr");
                        const slot = c.LLVMBuildPointerCast(env.builder, registers[inst.dest].llvm_value, env.ptr_ty, "memcpy_dst_ptr_slot");
                        const is_null = c.LLVMBuildICmp(env.builder, c.LLVMIntEQ, loaded, c.LLVMConstPointerNull(env.ptr_ty), "memcpy_dst_ptr_is_null");
                        break :blk c.LLVMBuildSelect(env.builder, is_null, slot, loaded, "memcpy_dst_ptr_or_slot");
                    },
                    .int_addr, .bool_addr => c.LLVMBuildPointerCast(env.builder, registers[inst.dest].llvm_value, env.ptr_ty, "memcpy_dst_scalar_slot"),
                    else => return diag.failAt(0, "LLVM backend memcpy destination requires addressable storage, got {s}", .{@tagName(registers[inst.dest].kind)}),
                };
                const src_ptr = switch (registers[inst.arg1].kind) {
                    .pointer => registers[inst.arg1].llvm_value,
                    .pointer_addr => blk: {
                        const loaded = c.LLVMBuildLoad2(env.builder, env.ptr_ty, registers[inst.arg1].llvm_value, "memcpy_src_load_ptr_addr");
                        const slot = c.LLVMBuildPointerCast(env.builder, registers[inst.arg1].llvm_value, env.ptr_ty, "memcpy_src_ptr_slot");
                        const is_null = c.LLVMBuildICmp(env.builder, c.LLVMIntEQ, loaded, c.LLVMConstPointerNull(env.ptr_ty), "memcpy_src_ptr_is_null");
                        break :blk c.LLVMBuildSelect(env.builder, is_null, slot, loaded, "memcpy_src_ptr_or_slot");
                    },
                    .runtime_string, .string_addr => try runtimeStringValue(env, registers[inst.arg1], diag),
                    .int, .int_addr, .bool, .bool_addr, .type_id, .float => try valueAddress(env, registers[inst.arg1], diag),
                    else => return diag.failAt(0, "LLVM backend memcpy source requires byte-addressable value, got {s}", .{@tagName(registers[inst.arg1].kind)}),
                };
                const count = try valueAsInt(env, registers[inst.arg2], diag);
                var args = [_]c.LLVMValueRef{ dst_ptr, src_ptr, count };
                _ = c.LLVMBuildCall2(env.builder, env.memcpy_fn_ty, env.memcpy_fn, &args, args.len, "");
            },
            .exit_process => {
                if (inst.arg1 >= registers.len) return diag.failAt(0, "LLVM backend exit_process register out of range", .{});
                const status = c.LLVMBuildIntCast2(env.builder, registers[inst.arg1].llvm_value, env.llvm_i32, 1, "exit_status");
                var args = [_]c.LLVMValueRef{status};
                _ = c.LLVMBuildCall2(env.builder, env.exit_fn_ty, env.exit_fn, &args, args.len, "");
                _ = c.LLVMBuildUnreachable(env.builder);
                terminates_block = true;
            },
            .ret_void => {
                _ = c.LLVMBuildBr(env.builder, blocks[instruction_count]);
                terminates_block = true;
            },
            .ret => {
                if (inst.arg1 >= registers.len) return diag.failAt(0, "LLVM backend return register out of range", .{});
                if (proc.return_type == 0) {
                    _ = c.LLVMBuildRetVoid(env.builder);
                } else {
                    _ = c.LLVMBuildRet(env.builder, try callArgValueForType(env, registers[inst.arg1], proc.return_type, diag));
                }
                terminates_block = true;
            },
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
                    try setBoolResult(env, registers, inst.dest, c.LLVMBuildFCmp(env.builder, fpred, lhs_float, rhs_float, "fcmp"));
                } else {
                    const lhs_int = try valueAsInt(env, lhs_val, diag);
                    const rhs_int = try valueAsInt(env, rhs_val, diag);
                    try setBoolResult(env, registers, inst.dest, c.LLVMBuildICmp(env.builder, pred, lhs_int, rhs_int, "icmp"));
                }
            },
            .cmp_eq, .cmp_ne => {
                if (inst.dest >= registers.len or inst.arg1 >= registers.len or inst.arg2 >= registers.len) return diag.failAt(0, "LLVM backend equality register out of range", .{});
                const lhs = registers[inst.arg1];
                const rhs = registers[inst.arg2];
                const pred: c.LLVMIntPredicate = if (inst.opcode == .cmp_eq) c.LLVMIntEQ else c.LLVMIntNE;
                if (isStringValue(lhs) or isStringValue(rhs)) {
                    if ((isStringValue(lhs) and !isStringValue(rhs) and !canBeOpaqueString(rhs)) or (!isStringValue(lhs) and isStringValue(rhs) and !canBeOpaqueString(lhs))) {
                        try setBoolResult(env, registers, inst.dest, c.LLVMConstInt(c.LLVMInt1TypeInContext(env.context), if (inst.opcode == .cmp_ne) 1 else 0, 0));
                    } else {
                        const lhs_parts = try stringParts(env, lhs, diag);
                        const rhs_parts = try stringParts(env, rhs, diag);
                        var args = [_]c.LLVMValueRef{ lhs_parts.data, lhs_parts.len, rhs_parts.data, rhs_parts.len };
                        const equal_raw = c.LLVMBuildCall2(env.builder, env.string_equal_fn_ty, env.string_equal_fn, &args, args.len, "streq_raw");
                        var equal = c.LLVMBuildICmp(env.builder, c.LLVMIntNE, equal_raw, c.LLVMConstInt(c.LLVMInt8TypeInContext(env.context), 0, 0), "streq");
                        if (inst.opcode == .cmp_ne) equal = c.LLVMBuildNot(env.builder, equal, "strne");
                        try setBoolResult(env, registers, inst.dest, equal);
                    }
                } else if (lhs.kind == .float or rhs.kind == .float) {
                    const fpred: c.LLVMRealPredicate = if (inst.opcode == .cmp_eq) c.LLVMRealOEQ else c.LLVMRealONE;
                    const lhs_float = try valueAsFloat(env, lhs, diag);
                    const rhs_float = try valueAsFloat(env, rhs, diag);
                    try setBoolResult(env, registers, inst.dest, c.LLVMBuildFCmp(env.builder, fpred, lhs_float, rhs_float, "fcmp"));
                } else if ((lhs.kind == .bool or lhs.kind == .bool_addr) and (rhs.kind == .bool or rhs.kind == .bool_addr)) {
                    try setBoolResult(env, registers, inst.dest, c.LLVMBuildICmp(env.builder, pred, try valueAsBool(env, lhs, diag), try valueAsBool(env, rhs, diag), "boolcmp"));
                } else {
                    const lhs_int_eq = try valueAsInt(env, lhs, diag);
                    const rhs_int_eq = try valueAsInt(env, rhs, diag);
                    try setBoolResult(env, registers, inst.dest, c.LLVMBuildICmp(env.builder, pred, lhs_int_eq, rhs_int_eq, "icmp"));
                }
            },
            .bool_and, .bool_or => {
                if (inst.dest >= registers.len or inst.arg1 >= registers.len or inst.arg2 >= registers.len) return diag.failAt(0, "LLVM backend logical register out of range", .{});
                const lhs_bool = try valueAsBool(env, registers[inst.arg1], diag);
                const rhs_bool = try valueAsBool(env, registers[inst.arg2], diag);
                const value = if (inst.opcode == .bool_and) c.LLVMBuildAnd(env.builder, lhs_bool, rhs_bool, "and") else c.LLVMBuildOr(env.builder, lhs_bool, rhs_bool, "or");
                try setBoolResult(env, registers, inst.dest, value);
            },
            .bit_and, .bit_or, .bit_xor, .shl_int, .shr_int, .rotl_int => {
                if (inst.dest >= registers.len or inst.arg1 >= registers.len or inst.arg2 >= registers.len) return diag.failAt(0, "LLVM backend bitwise register out of range", .{});
                const lhs_int = try valueAsInt(env, registers[inst.arg1], diag);
                const rhs_int = try valueAsInt(env, registers[inst.arg2], diag);
                const value = switch (inst.opcode) {
                    .bit_and => c.LLVMBuildAnd(env.builder, lhs_int, rhs_int, "band"),
                    .bit_or => c.LLVMBuildOr(env.builder, lhs_int, rhs_int, "bor"),
                    .bit_xor => c.LLVMBuildXor(env.builder, lhs_int, rhs_int, "bxor"),
                    .shl_int, .rotl_int => c.LLVMBuildShl(env.builder, lhs_int, rhs_int, "shl"),
                    .shr_int => c.LLVMBuildAShr(env.builder, lhs_int, rhs_int, "shr"),
                    else => unreachable,
                };
                registers[inst.dest] = .{ .llvm_value = value, .kind = .int };
            },
            .select_value => {
                if (inst.dest >= registers.len or inst.arg1 >= registers.len or inst.arg2 >= registers.len or inst.arg3 >= registers.len) return diag.failAt(0, "LLVM backend select register out of range", .{});
                const cond = try valueAsBool(env, registers[inst.arg1], diag);
                const then_val = registers[inst.arg2];
                const else_val = registers[inst.arg3];
                if (then_val.kind == .int and else_val.kind == .int) {
                    registers[inst.dest] = .{ .llvm_value = c.LLVMBuildSelect(env.builder, cond, then_val.llvm_value, else_val.llvm_value, "ifx"), .kind = .int };
                } else if ((then_val.kind == .bool or then_val.kind == .bool_addr) and (else_val.kind == .bool or else_val.kind == .bool_addr)) {
                    try setBoolResult(env, registers, inst.dest, c.LLVMBuildSelect(env.builder, cond, try valueAsBool(env, then_val, diag), try valueAsBool(env, else_val, diag), "ifx"));
                } else if (then_val.kind == .float or else_val.kind == .float) {
                    const then_float = try valueAsFloat(env, then_val, diag);
                    const else_float = try valueAsFloat(env, else_val, diag);
                    registers[inst.dest] = .{ .llvm_value = c.LLVMBuildSelect(env.builder, cond, then_float, else_float, "ifx"), .kind = .float };
                } else {
                    registers[inst.dest] = then_val;
                }
            },
            .assert_true => {
                if (inst.arg1 >= registers.len) return diag.failAt(0, "LLVM backend assert register out of range", .{});
                const cond = try valueAsBool(env, registers[inst.arg1], diag);
                const ok_bb = c.LLVMAppendBasicBlockInContext(env.context, c.LLVMGetBasicBlockParent(c.LLVMGetInsertBlock(env.builder)), "assert_ok");
                const fail_bb = c.LLVMAppendBasicBlockInContext(env.context, c.LLVMGetBasicBlockParent(c.LLVMGetInsertBlock(env.builder)), "assert_fail");
                _ = c.LLVMBuildCondBr(env.builder, cond, ok_bb, fail_bb);
                c.LLVMPositionBuilderAtEnd(env.builder, fail_bb);
                _ = c.LLVMBuildCall2(env.builder, env.assert_fail_fn_ty, env.assert_fail_fn, null, 0, "");
                _ = c.LLVMBuildUnreachable(env.builder);
                c.LLVMPositionBuilderAtEnd(env.builder, ok_bb);
            },
            .jump => {
                if (inst.arg1 > instruction_count) return diag.failAt(0, "LLVM backend jump target out of range", .{});
                _ = c.LLVMBuildBr(env.builder, blocks[inst.arg1]);
                terminates_block = true;
            },
            .jump_if_false => {
                if (inst.arg1 >= registers.len or inst.arg2 > instruction_count) return diag.failAt(0, "LLVM backend conditional jump out of range", .{});
                const cond = try valueAsBool(env, registers[inst.arg1], diag);
                _ = c.LLVMBuildCondBr(env.builder, cond, blocks[instruction_index + 1], blocks[inst.arg2]);
                terminates_block = true;
            },
            .call => {
                if (inst.arg1 >= env.proc_functions.len or env.proc_functions[inst.arg1] == null or env.proc_function_tys[inst.arg1] == null) return diag.failAt(0, "LLVM backend call target out of range", .{});
                const target_proc = &env.program.procs.items[inst.arg1];
                if (inst.arg2 != target_proc.param_types.items.len) return diag.failAt(0, "LLVM backend call argument count mismatch", .{});
                if (inst.arg3 + inst.arg2 > env.program.call_args.items.len) return diag.failAt(0, "LLVM backend call argument table out of range", .{});
                const args = try env.allocator.alloc(c.LLVMValueRef, inst.arg2);
                defer env.allocator.free(args);
                for (args, 0..) |*arg, arg_index| {
                    const reg_index = env.program.call_args.items[inst.arg3 + arg_index];
                    if (reg_index >= registers.len) return diag.failAt(0, "LLVM backend call argument register out of range", .{});
                    arg.* = try callArgValueForType(env, registers[reg_index], target_proc.param_types.items[arg_index], diag);
                }
                const result = c.LLVMBuildCall2(env.builder, env.proc_function_tys[inst.arg1], env.proc_functions[inst.arg1], if (args.len == 0) null else args.ptr, @intCast(args.len), if (target_proc.return_type == 0) "" else "call");
                if (target_proc.return_type != 0) {
                    if (inst.dest >= registers.len) return diag.failAt(0, "LLVM backend call destination out of range", .{});
                    try setTypedResult(env, registers, inst.dest, result, target_proc.return_type);
                }
            },
            .call_proc0 => {
                if (inst.arg1 >= env.proc_functions.len or env.proc_functions[inst.arg1] == null) return diag.failAt(0, "LLVM backend call_proc0 target out of range", .{});
                _ = c.LLVMBuildCall2(env.builder, env.proc_void_ty, env.proc_functions[inst.arg1], null, 0, "");
            },
            else => return diag.failAt(0, "unsupported bytecode opcode in LLVM backend: {s}", .{@tagName(inst.opcode)}),
        }
        if (!terminates_block) {
            _ = c.LLVMBuildBr(env.builder, blocks[instruction_index + 1]);
        }
    }
    c.LLVMPositionBuilderAtEnd(env.builder, blocks[instruction_count]);
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
        bool_addr: u32,
        pointer,
        pointer_addr: u32,
        string_addr: u32,
        calendar,
        float,
        bool,
        void_value,
        type_id,
    };
};

fn registerValueForTypedLlvmValue(value: c.LLVMValueRef, type_id: u32) RegisterValue {
    return switch (type_id) {
        1 => .{ .llvm_value = value, .kind = .bool },
        12, 13 => .{ .llvm_value = value, .kind = .float },
        10 => .{ .llvm_value = value, .kind = .pointer },
        14 => .{ .llvm_value = value, .kind = .runtime_string },
        0 => .{ .llvm_value = value, .kind = .void_value },
        else => .{ .llvm_value = value, .kind = .int },
    };
}

fn defaultLlvmValueForTypeId(env: *LlvmEnv, type_id: u32) c.LLVMValueRef {
    return switch (type_id) {
        1 => c.LLVMConstInt(c.LLVMInt1TypeInContext(env.context), 0, 0),
        12, 13 => c.LLVMConstReal(env.llvm_f64, 0.0),
        10, 14 => c.LLVMConstPointerNull(env.ptr_ty),
        else => c.LLVMConstInt(env.llvm_i64, 0, 0),
    };
}

fn pointerValue(env: *LlvmEnv, value: RegisterValue, diag: Diagnostic, context: []const u8) !c.LLVMValueRef {
    return switch (value.kind) {
        .pointer => value.llvm_value,
        .pointer_addr => c.LLVMBuildLoad2(env.builder, env.ptr_ty, value.llvm_value, "load_ptr_addr"),
        .string_addr => c.LLVMBuildLoad2(env.builder, env.ptr_ty, value.llvm_value, "load_string_addr_ptr"),
        .runtime_string => value.llvm_value,
        .string => c.LLVMBuildPointerCast(env.builder, value.llvm_value, env.ptr_ty, "string_ptr"),
        .int, .int_addr, .bool, .bool_addr, .type_id => c.LLVMBuildIntToPtr(env.builder, try valueAsInt(env, value, diag), env.ptr_ty, "inttoptr"),
        else => diag.failAt(0, "{s} requires pointer-compatible register, got {s}", .{ context, @tagName(value.kind) }),
    };
}

fn runtimeStringValue(env: *LlvmEnv, value: RegisterValue, diag: Diagnostic) anyerror!c.LLVMValueRef {
    return switch (value.kind) {
        .runtime_string => value.llvm_value,
        .string_addr => c.LLVMBuildLoad2(env.builder, env.ptr_ty, value.llvm_value, "load_runtime_string_local"),
        .string => |string_idx| blk: {
            const function = c.LLVMGetBasicBlockParent(c.LLVMGetInsertBlock(env.builder));
            const pair_ty = c.LLVMArrayType(env.llvm_i64, 2);
            const slot = buildEntryAlloca(env, function, pair_ty, "static_runtime_string");
            var len_indices = [_]c.LLVMValueRef{
                c.LLVMConstInt(env.llvm_i64, 0, 0),
                c.LLVMConstInt(env.llvm_i64, 0, 0),
            };
            const len_ptr = c.LLVMBuildGEP2(env.builder, pair_ty, slot, &len_indices, len_indices.len, "static_strlen_slot");
            _ = c.LLVMBuildStore(env.builder, c.LLVMConstInt(env.llvm_i64, env.program.strings.items[string_idx].len, 0), len_ptr);
            var data_indices = [_]c.LLVMValueRef{
                c.LLVMConstInt(env.llvm_i64, 0, 0),
                c.LLVMConstInt(env.llvm_i64, 1, 0),
            };
            const data_ptr = c.LLVMBuildGEP2(env.builder, pair_ty, slot, &data_indices, data_indices.len, "static_strdata_slot");
            const data = c.LLVMBuildPointerCast(env.builder, value.llvm_value, env.ptr_ty, "static_strdata_ptr");
            _ = c.LLVMBuildStore(env.builder, c.LLVMBuildPtrToInt(env.builder, data, env.llvm_i64, "static_strdata_int"), data_ptr);
            break :blk c.LLVMBuildPointerCast(env.builder, slot, env.ptr_ty, "static_runtime_string_ptr");
        },
        .pointer => value.llvm_value,
        .pointer_addr => c.LLVMBuildLoad2(env.builder, env.ptr_ty, value.llvm_value, "load_runtime_string_addr"),
        .int, .int_addr => c.LLVMBuildIntToPtr(env.builder, try valueAsInt(env, value, diag), env.ptr_ty, "runtime_string_inttoptr"),
        else => diag.failAt(0, "expected string-compatible register, got {s}", .{@tagName(value.kind)}),
    };
}

fn valueAddress(env: *LlvmEnv, value: RegisterValue, diag: Diagnostic) !c.LLVMValueRef {
    const function = c.LLVMGetBasicBlockParent(c.LLVMGetInsertBlock(env.builder));
    switch (value.kind) {
        .int, .int_addr, .bool, .bool_addr, .type_id => {
            const slot = buildEntryAlloca(env, function, env.llvm_i64, "value_addr_i64");
            _ = c.LLVMBuildStore(env.builder, try valueAsInt(env, value, diag), slot);
            return c.LLVMBuildPointerCast(env.builder, slot, env.ptr_ty, "value_addr_i64_ptr");
        },
        .pointer, .pointer_addr, .runtime_string, .string, .string_addr => {
            const slot = buildEntryAlloca(env, function, env.ptr_ty, "value_addr_ptr");
            _ = c.LLVMBuildStore(env.builder, try pointerValue(env, value, diag, "value address"), slot);
            return c.LLVMBuildPointerCast(env.builder, slot, env.ptr_ty, "value_addr_ptr_cast");
        },
        .float => {
            const slot = buildEntryAlloca(env, function, env.llvm_f64, "value_addr_f64");
            _ = c.LLVMBuildStore(env.builder, value.llvm_value, slot);
            return c.LLVMBuildPointerCast(env.builder, slot, env.ptr_ty, "value_addr_f64_ptr");
        },
        else => return diag.failAt(0, "cannot take byte address of register kind {s}", .{@tagName(value.kind)}),
    }
}

fn valueAsInt(env: *LlvmEnv, value: RegisterValue, diag: Diagnostic) !c.LLVMValueRef {
    return switch (value.kind) {
        .int => if (c.LLVMGetTypeKind(c.LLVMTypeOf(value.llvm_value)) == c.LLVMPointerTypeKind)
            c.LLVMBuildPtrToInt(env.builder, value.llvm_value, env.llvm_i64, "intkind_ptrtoint")
        else
            value.llvm_value,
        .int_addr => c.LLVMBuildLoad2(env.builder, env.llvm_i64, value.llvm_value, "load_int_addr_cmp"),
        .bool => c.LLVMBuildZExt(env.builder, value.llvm_value, env.llvm_i64, "booltoint"),
        .bool_addr => c.LLVMBuildZExt(env.builder, c.LLVMBuildLoad2(env.builder, c.LLVMInt1TypeInContext(env.context), value.llvm_value, "load_bool_addr_int"), env.llvm_i64, "booladdrtoint"),
        .pointer => c.LLVMBuildPtrToInt(env.builder, value.llvm_value, env.llvm_i64, "ptrtoint"),
        .pointer_addr => c.LLVMBuildPtrToInt(env.builder, c.LLVMBuildLoad2(env.builder, env.ptr_ty, value.llvm_value, "load_ptr_addr_int"), env.llvm_i64, "ptraddrtoint"),
        .string, .runtime_string, .string_addr => c.LLVMBuildPtrToInt(env.builder, try runtimeStringValue(env, value, diag), env.llvm_i64, "strptrtoint"),
        .undefined_string => c.LLVMConstInt(env.llvm_i64, 0, 0),
        .type_id => value.llvm_value,
        .void_value => c.LLVMConstInt(env.llvm_i64, 0, 0),
        else => diag.failAt(0, "expected integer-compatible register, got {s}", .{@tagName(value.kind)}),
    };
}

fn callArgValueForType(env: *LlvmEnv, value: RegisterValue, type_id: u32, diag: Diagnostic) !c.LLVMValueRef {
    return switch (type_id) {
        1 => valueAsBool(env, value, diag),
        12, 13 => valueAsFloat(env, value, diag),
        10 => pointerValue(env, value, diag, "procedure call argument"),
        14 => runtimeStringValue(env, value, diag),
        else => valueAsInt(env, value, diag),
    };
}

fn setTypedResult(env: *LlvmEnv, registers: []RegisterValue, dest: u32, value: c.LLVMValueRef, type_id: u32) !void {
    switch (type_id) {
        1 => try setBoolResult(env, registers, dest, value),
        12, 13 => registers[dest] = .{ .llvm_value = value, .kind = .float },
        10 => try setPointerResult(env, registers, dest, value),
        14 => registers[dest] = .{ .llvm_value = value, .kind = .runtime_string },
        else => try setIntResult(env, registers, dest, value),
    }
}

fn setIntResult(env: *LlvmEnv, registers: []RegisterValue, dest: u32, value: c.LLVMValueRef) !void {
    if (registers[dest].kind == .int_addr) {
        _ = c.LLVMBuildStore(env.builder, value, registers[dest].llvm_value);
        return;
    }
    const function = c.LLVMGetBasicBlockParent(c.LLVMGetInsertBlock(env.builder));
    const slot = buildEntryAlloca(env, function, env.llvm_i64, "int_reg");
    _ = c.LLVMBuildStore(env.builder, value, slot);
    registers[dest] = .{ .llvm_value = slot, .kind = .{ .int_addr = dest } };
}

fn setBoolResult(env: *LlvmEnv, registers: []RegisterValue, dest: u32, value: c.LLVMValueRef) !void {
    if (registers[dest].kind == .bool_addr) {
        _ = c.LLVMBuildStore(env.builder, value, registers[dest].llvm_value);
        return;
    }
    const function = c.LLVMGetBasicBlockParent(c.LLVMGetInsertBlock(env.builder));
    const slot = buildEntryAlloca(env, function, c.LLVMInt1TypeInContext(env.context), "bool_reg");
    _ = c.LLVMBuildStore(env.builder, value, slot);
    registers[dest] = .{ .llvm_value = slot, .kind = .{ .bool_addr = dest } };
}

fn setPointerResult(env: *LlvmEnv, registers: []RegisterValue, dest: u32, value: c.LLVMValueRef) !void {
    if (registers[dest].kind == .pointer_addr) {
        _ = c.LLVMBuildStore(env.builder, value, registers[dest].llvm_value);
        return;
    }
    const function = c.LLVMGetBasicBlockParent(c.LLVMGetInsertBlock(env.builder));
    const slot = buildEntryAlloca(env, function, env.ptr_ty, "ptr_result");
    _ = c.LLVMBuildStore(env.builder, value, slot);
    registers[dest] = .{ .llvm_value = slot, .kind = .{ .pointer_addr = dest } };
}

fn buildEntryAlloca(env: *LlvmEnv, function: c.LLVMValueRef, ty: c.LLVMTypeRef, name: [*:0]const u8) c.LLVMValueRef {
    const builder = c.LLVMCreateBuilderInContext(env.context) orelse @panic("LLVMCreateBuilderInContext failed");
    defer c.LLVMDisposeBuilder(builder);
    const entry = c.LLVMGetEntryBasicBlock(function);
    const first = c.LLVMGetFirstInstruction(entry);
    if (first != null) {
        c.LLVMPositionBuilderBefore(builder, first);
    } else {
        c.LLVMPositionBuilderAtEnd(builder, entry);
    }
    return c.LLVMBuildAlloca(builder, ty, name);
}

fn valueAsFloat(env: *LlvmEnv, value: RegisterValue, diag: Diagnostic) !c.LLVMValueRef {
    return switch (value.kind) {
        .float => value.llvm_value,
        .int, .int_addr, .bool, .bool_addr => c.LLVMBuildSIToFP(env.builder, try valueAsInt(env, value, diag), env.llvm_f64, "tofp"),
        else => diag.failAt(0, "expected numeric register", .{}),
    };
}

fn valueAsBool(env: *LlvmEnv, value: RegisterValue, diag: Diagnostic) !c.LLVMValueRef {
    return switch (value.kind) {
        .bool => value.llvm_value,
        .bool_addr => c.LLVMBuildLoad2(env.builder, c.LLVMInt1TypeInContext(env.context), value.llvm_value, "load_bool_addr"),
        .int, .int_addr, .type_id, .void_value => c.LLVMBuildICmp(env.builder, c.LLVMIntNE, try valueAsInt(env, value, diag), c.LLVMConstInt(env.llvm_i64, 0, 0), "tobool"),
        .pointer => c.LLVMBuildICmp(env.builder, c.LLVMIntNE, c.LLVMBuildPtrToInt(env.builder, value.llvm_value, env.llvm_i64, "ptrtoint_bool"), c.LLVMConstInt(env.llvm_i64, 0, 0), "ptr_nonnull"),
        .pointer_addr => c.LLVMBuildICmp(
            env.builder,
            c.LLVMIntNE,
            c.LLVMBuildPtrToInt(env.builder, c.LLVMBuildLoad2(env.builder, env.ptr_ty, value.llvm_value, "load_ptr_addr"), env.llvm_i64, "ptraddrtoint_bool"),
            c.LLVMConstInt(env.llvm_i64, 0, 0),
            "ptraddr_nonnull",
        ),
        .string => |string_idx| c.LLVMBuildICmp(
            env.builder,
            c.LLVMIntNE,
            c.LLVMConstInt(env.llvm_i64, env.program.strings.items[string_idx].len, 0),
            c.LLVMConstInt(env.llvm_i64, 0, 0),
            "str_nonempty",
        ),
        .runtime_string, .string_addr => blk: {
            const runtime_string = try runtimeStringValue(env, value, diag);
            var len_indices = [_]c.LLVMValueRef{c.LLVMConstInt(env.llvm_i64, 0, 0)};
            const len_ptr = c.LLVMBuildGEP2(env.builder, env.llvm_i64, runtime_string, &len_indices, len_indices.len, "runtime_strlen_ptr_bool");
            const len = c.LLVMBuildLoad2(env.builder, env.llvm_i64, len_ptr, "runtime_strlen_bool");
            break :blk c.LLVMBuildICmp(env.builder, c.LLVMIntNE, len, c.LLVMConstInt(env.llvm_i64, 0, 0), "runtime_str_nonempty");
        },
        .undefined_string => c.LLVMConstInt(c.LLVMInt1TypeInContext(env.context), 0, 0),
        .float => c.LLVMBuildFCmp(env.builder, c.LLVMRealONE, value.llvm_value, c.LLVMConstReal(env.llvm_f64, 0.0), "float_nonzero"),
        else => diag.failAt(0, "expected bool-compatible register", .{}),
    };
}

const StringParts = struct {
    data: c.LLVMValueRef,
    len: c.LLVMValueRef,
};

fn isStringValue(value: RegisterValue) bool {
    return switch (value.kind) {
        .string, .runtime_string, .string_addr => true,
        else => false,
    };
}

fn canBeOpaqueString(value: RegisterValue) bool {
    return switch (value.kind) {
        .pointer, .pointer_addr, .int, .int_addr => true,
        else => false,
    };
}

fn stringParts(env: *LlvmEnv, value: RegisterValue, diag: Diagnostic) !StringParts {
    return switch (value.kind) {
        .string => |string_idx| .{
            .data = c.LLVMBuildPointerCast(env.builder, value.llvm_value, env.ptr_ty, "str_data"),
            .len = c.LLVMConstInt(env.llvm_i64, env.program.strings.items[string_idx].len, 0),
        },
        .runtime_string, .string_addr => blk: {
            const runtime_string = try runtimeStringValue(env, value, diag);
            var len_indices = [_]c.LLVMValueRef{c.LLVMConstInt(env.llvm_i64, 0, 0)};
            const len_ptr = c.LLVMBuildGEP2(env.builder, env.llvm_i64, runtime_string, &len_indices, len_indices.len, "runtime_strlen_ptr_parts");
            const len = c.LLVMBuildLoad2(env.builder, env.llvm_i64, len_ptr, "runtime_strlen_parts");
            var data_indices = [_]c.LLVMValueRef{c.LLVMConstInt(env.llvm_i64, 1, 0)};
            const data_ptr_ptr = c.LLVMBuildGEP2(env.builder, env.llvm_i64, runtime_string, &data_indices, data_indices.len, "runtime_strdata_slot_parts");
            const data_ptr_int = c.LLVMBuildLoad2(env.builder, env.llvm_i64, data_ptr_ptr, "runtime_strdata_int_parts");
            break :blk .{
                .data = c.LLVMBuildIntToPtr(env.builder, data_ptr_int, env.ptr_ty, "runtime_strdata_parts"),
                .len = len,
            };
        },
        .pointer, .pointer_addr, .int, .int_addr => blk: {
            const runtime_string = switch (value.kind) {
                .pointer => value.llvm_value,
                .pointer_addr => c.LLVMBuildLoad2(env.builder, env.ptr_ty, value.llvm_value, "opaque_load_ptr_addr"),
                .int, .int_addr => c.LLVMBuildIntToPtr(env.builder, try valueAsInt(env, value, diag), env.ptr_ty, "opaque_strptr"),
                else => unreachable,
            };
            var len_indices = [_]c.LLVMValueRef{c.LLVMConstInt(env.llvm_i64, 0, 0)};
            const len_ptr = c.LLVMBuildGEP2(env.builder, env.llvm_i64, runtime_string, &len_indices, len_indices.len, "opaque_strlen_ptr");
            const len = c.LLVMBuildLoad2(env.builder, env.llvm_i64, len_ptr, "opaque_strlen");
            var data_indices = [_]c.LLVMValueRef{c.LLVMConstInt(env.llvm_i64, 1, 0)};
            const data_ptr_ptr = c.LLVMBuildGEP2(env.builder, env.llvm_i64, runtime_string, &data_indices, data_indices.len, "opaque_strdata_slot");
            const data_ptr_int = c.LLVMBuildLoad2(env.builder, env.llvm_i64, data_ptr_ptr, "opaque_strdata_int");
            break :blk .{
                .data = c.LLVMBuildIntToPtr(env.builder, data_ptr_int, env.ptr_ty, "opaque_strdata"),
                .len = len,
            };
        },
        else => diag.failAt(0, "expected string-compatible register, got {s}", .{@tagName(value.kind)}),
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
        .runtime_string, .string_addr => {
            const runtime_string = try runtimeStringValue(env, arg, diag);
            var len_indices = [_]c.LLVMValueRef{c.LLVMConstInt(env.llvm_i64, 0, 0)};
            const len_ptr = c.LLVMBuildGEP2(env.builder, env.llvm_i64, runtime_string, &len_indices, len_indices.len, "runtime_strlen_ptr");
            const len = c.LLVMBuildLoad2(env.builder, env.llvm_i64, len_ptr, "runtime_strlen");
            var data_indices = [_]c.LLVMValueRef{c.LLVMConstInt(env.llvm_i64, 1, 0)};
            const data_ptr_ptr = c.LLVMBuildGEP2(env.builder, env.llvm_i64, runtime_string, &data_indices, data_indices.len, "runtime_strdata_slot");
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
        .pointer_addr => {
            const ptr = c.LLVMBuildLoad2(env.builder, env.ptr_ty, arg.llvm_value, "print_load_ptr_addr");
            const as_int = c.LLVMBuildPtrToInt(env.builder, ptr, env.llvm_i64, "ptraddrtoint");
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
        .bool_addr => {
            var args = [_]c.LLVMValueRef{try valueAsBool(env, arg, diag)};
            _ = c.LLVMBuildCall2(env.builder, env.print_bool_fn_ty, env.print_bool_fn, &args, args.len, "");
        },
        .unset => return diag.failAt(0, "LLVM backend print argument register was not initialized", .{}),
    }
}

fn sanitizeLlvmSymbolName(allocator: std.mem.Allocator, name: []const u8) ![]u8 {
    if (name.len == 0) return allocator.dupe(u8, "anonymous");
    var safe = try allocator.alloc(u8, name.len);
    for (name, 0..) |ch, i| {
        safe[i] = if ((ch >= 'a' and ch <= 'z') or
            (ch >= 'A' and ch <= 'Z') or
            (ch >= '0' and ch <= '9') or
            ch == '_')
            ch
        else
            '_';
    }
    return safe;
}
