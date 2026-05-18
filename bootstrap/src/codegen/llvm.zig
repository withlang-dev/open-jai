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
    print_uint_fn_ty: c.LLVMTypeRef,
    print_uint_fn: c.LLVMValueRef,
    print_static_int_array_fn_ty: c.LLVMTypeRef,
    print_static_int_array_fn: c.LLVMValueRef,
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
    get_time_seconds_fn_ty: c.LLVMTypeRef,
    get_time_seconds_fn: c.LLVMValueRef,
    seconds_since_init_fn_ty: c.LLVMTypeRef,
    seconds_since_init_fn: c.LLVMValueRef,
    to_float64_seconds_fn_ty: c.LLVMTypeRef,
    to_float64_seconds_fn: c.LLVMValueRef,
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
    get_command_line_arguments_fn_ty: c.LLVMTypeRef,
    get_command_line_arguments_fn: c.LLVMValueRef,
    sleep_milliseconds_fn_ty: c.LLVMTypeRef,
    sleep_milliseconds_fn: c.LLVMValueRef,
    cpu_has_feature_fn_ty: c.LLVMTypeRef,
    cpu_has_feature_fn: c.LLVMValueRef,
    make_directory_fn_ty: c.LLVMTypeRef,
    make_directory_fn: c.LLVMValueRef,
    delete_directory_fn_ty: c.LLVMTypeRef,
    delete_directory_fn: c.LLVMValueRef,
    file_exists_fn_ty: c.LLVMTypeRef,
    file_exists_fn: c.LLVMValueRef,
    set_working_directory_fn_ty: c.LLVMTypeRef,
    set_working_directory_fn: c.LLVMValueRef,
    get_working_directory_fn_ty: c.LLVMTypeRef,
    get_working_directory_fn: c.LLVMValueRef,
    get_path_of_running_executable_fn_ty: c.LLVMTypeRef,
    get_path_of_running_executable_fn: c.LLVMValueRef,
    file_open_fn_ty: c.LLVMTypeRef,
    file_open_fn: c.LLVMValueRef,
    file_close_fn_ty: c.LLVMTypeRef,
    file_close_fn: c.LLVMValueRef,
    file_length_fn_ty: c.LLVMTypeRef,
    file_length_fn: c.LLVMValueRef,
    file_set_position_fn_ty: c.LLVMTypeRef,
    file_set_position_fn: c.LLVMValueRef,
    file_write_fn_ty: c.LLVMTypeRef,
    file_write_fn: c.LLVMValueRef,
    file_read_fn_ty: c.LLVMTypeRef,
    file_read_fn: c.LLVMValueRef,
    posix_read_fn_ty: c.LLVMTypeRef,
    posix_read_fn: c.LLVMValueRef,
    string_equal_fn_ty: c.LLVMTypeRef,
    string_equal_fn: c.LLVMValueRef,
    string_slice_fn_ty: c.LLVMTypeRef,
    string_slice_fn: c.LLVMValueRef,
    string_builder_init_fn_ty: c.LLVMTypeRef,
    string_builder_init_fn: c.LLVMValueRef,
    string_builder_free_fn_ty: c.LLVMTypeRef,
    string_builder_free_fn: c.LLVMValueRef,
    string_builder_append_string_fn_ty: c.LLVMTypeRef,
    string_builder_append_string_fn: c.LLVMValueRef,
    string_builder_append_int_fn_ty: c.LLVMTypeRef,
    string_builder_append_int_fn: c.LLVMValueRef,
    string_builder_append_float_fn_ty: c.LLVMTypeRef,
    string_builder_append_float_fn: c.LLVMValueRef,
    string_builder_append_bool_fn_ty: c.LLVMTypeRef,
    string_builder_append_bool_fn: c.LLVMValueRef,
    string_builder_to_string_fn_ty: c.LLVMTypeRef,
    string_builder_to_string_fn: c.LLVMValueRef,
    string_builder_length_fn_ty: c.LLVMTypeRef,
    string_builder_length_fn: c.LLVMValueRef,
    string_builder_join_array_fn_ty: c.LLVMTypeRef,
    string_builder_join_array_fn: c.LLVMValueRef,
    string_copy_fn_ty: c.LLVMTypeRef,
    string_copy_fn: c.LLVMValueRef,
    string_to_c_fn_ty: c.LLVMTypeRef,
    string_to_c_fn: c.LLVMValueRef,
    string_from_c_fn_ty: c.LLVMTypeRef,
    string_from_c_fn: c.LLVMValueRef,
    string_from_parts_fn_ty: c.LLVMTypeRef,
    string_from_parts_fn: c.LLVMValueRef,
    string_trim_fn_ty: c.LLVMTypeRef,
    string_trim_fn: c.LLVMValueRef,
    string_compare_fn_ty: c.LLVMTypeRef,
    string_compare_fn: c.LLVMValueRef,
    string_contains_fn_ty: c.LLVMTypeRef,
    string_contains_fn: c.LLVMValueRef,
    string_begins_with_fn_ty: c.LLVMTypeRef,
    string_begins_with_fn: c.LLVMValueRef,
    string_find_fn_ty: c.LLVMTypeRef,
    string_find_fn: c.LLVMValueRef,
    string_split_fn_ty: c.LLVMTypeRef,
    string_split_fn: c.LLVMValueRef,
    string_parse_int_fn_ty: c.LLVMTypeRef,
    string_parse_int_fn: c.LLVMValueRef,
    string_parse_int_ok_fn_ty: c.LLVMTypeRef,
    string_parse_int_ok_fn: c.LLVMValueRef,
    string_parse_float_fn_ty: c.LLVMTypeRef,
    string_parse_float_fn: c.LLVMValueRef,
    string_parse_float_ok_fn_ty: c.LLVMTypeRef,
    string_parse_float_ok_fn: c.LLVMValueRef,
    string_replace_fn_ty: c.LLVMTypeRef,
    string_replace_fn: c.LLVMValueRef,
    path_strip_filename_fn_ty: c.LLVMTypeRef,
    path_strip_filename_fn: c.LLVMValueRef,
    array_add_fn_ty: c.LLVMTypeRef,
    array_add_fn: c.LLVMValueRef,
    array_free_fn_ty: c.LLVMTypeRef,
    array_free_fn: c.LLVMValueRef,
    new_array_fn_ty: c.LLVMTypeRef,
    new_array_fn: c.LLVMValueRef,
    array_count_fn_ty: c.LLVMTypeRef,
    array_count_fn: c.LLVMValueRef,
    array_data_fn_ty: c.LLVMTypeRef,
    array_data_fn: c.LLVMValueRef,
    array_index_fn_ty: c.LLVMTypeRef,
    array_index_fn: c.LLVMValueRef,
    llvm_i32: c.LLVMTypeRef,
    llvm_i64: c.LLVMTypeRef,
    llvm_f32: c.LLVMTypeRef,
    llvm_f64: c.LLVMTypeRef,
    ptr_ty: c.LLVMTypeRef,
    set_type_info_table_fn_ty: c.LLVMTypeRef,
    set_type_info_table_fn: c.LLVMValueRef,
    type_info_get_members_fn_ty: c.LLVMTypeRef,
    type_info_get_members_fn: c.LLVMValueRef,
    type_info_member_name_fn_ty: c.LLVMTypeRef,
    type_info_member_name_fn: c.LLVMValueRef,
    type_info_member_type_name_fn_ty: c.LLVMTypeRef,
    type_info_member_type_name_fn: c.LLVMValueRef,
    type_info_member_int_field_fn_ty: c.LLVMTypeRef,
    type_info_member_int_field_fn: c.LLVMValueRef,
    type_info_lookup_fn_ty: c.LLVMTypeRef,
    type_info_lookup_fn: c.LLVMValueRef,
    current_proc_name: []const u8 = "<none>",
    current_proc_index: usize = 0,
    current_opcode: Bytecode.Opcode = .ret_void,
    current_instruction_index: usize = 0,
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
    const print_uint_params = [_]c.LLVMTypeRef{llvm_i64};
    const print_uint_fn_ty = c.LLVMFunctionType(void_ty, @constCast(&print_uint_params), print_uint_params.len, 0);
    const print_uint_fn = c.LLVMAddFunction(module, "__openjai_print_uint", print_uint_fn_ty);
    const print_static_int_array_params = [_]c.LLVMTypeRef{ ptr_ty, llvm_i64, llvm_i64 };
    const print_static_int_array_fn_ty = c.LLVMFunctionType(void_ty, @constCast(&print_static_int_array_params), print_static_int_array_params.len, 0);
    const print_static_int_array_fn = c.LLVMAddFunction(module, "__openjai_print_static_int_array", print_static_int_array_fn_ty);
    const llvm_f32 = c.LLVMFloatTypeInContext(context);
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
    const get_time_seconds_fn_ty = c.LLVMFunctionType(llvm_f64, null, 0, 0);
    const get_time_seconds_fn = c.LLVMAddFunction(module, "__openjai_get_time_seconds", get_time_seconds_fn_ty);
    const seconds_since_init_fn_ty = c.LLVMFunctionType(llvm_f64, null, 0, 0);
    const seconds_since_init_fn = c.LLVMAddFunction(module, "__openjai_seconds_since_init", seconds_since_init_fn_ty);
    const to_float64_seconds_params = [_]c.LLVMTypeRef{llvm_i64};
    const to_float64_seconds_fn_ty = c.LLVMFunctionType(llvm_f64, @constCast(&to_float64_seconds_params), to_float64_seconds_params.len, 0);
    const to_float64_seconds_fn = c.LLVMAddFunction(module, "__openjai_to_float64_seconds", to_float64_seconds_fn_ty);
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
    const get_command_line_arguments_fn_ty = c.LLVMFunctionType(ptr_ty, null, 0, 0);
    const get_command_line_arguments_fn = c.LLVMAddFunction(module, "__openjai_get_command_line_arguments", get_command_line_arguments_fn_ty);
    const sleep_milliseconds_params = [_]c.LLVMTypeRef{llvm_i64};
    const sleep_milliseconds_fn_ty = c.LLVMFunctionType(void_ty, @constCast(&sleep_milliseconds_params), sleep_milliseconds_params.len, 0);
    const sleep_milliseconds_fn = c.LLVMAddFunction(module, "__openjai_sleep_milliseconds", sleep_milliseconds_fn_ty);
    const cpu_has_feature_fn_ty = c.LLVMFunctionType(c.LLVMInt1TypeInContext(context), @constCast(&sleep_milliseconds_params), sleep_milliseconds_params.len, 0);
    const cpu_has_feature_fn = c.LLVMAddFunction(module, "__openjai_cpu_has_feature", cpu_has_feature_fn_ty);
    const make_directory_params = [_]c.LLVMTypeRef{ ptr_ty, llvm_i64 };
    const make_directory_fn_ty = c.LLVMFunctionType(c.LLVMInt1TypeInContext(context), @constCast(&make_directory_params), make_directory_params.len, 0);
    const make_directory_fn = c.LLVMAddFunction(module, "__openjai_make_directory", make_directory_fn_ty);
    const delete_directory_fn_ty = c.LLVMFunctionType(c.LLVMInt1TypeInContext(context), @constCast(&make_directory_params), make_directory_params.len, 0);
    const delete_directory_fn = c.LLVMAddFunction(module, "__openjai_delete_directory", delete_directory_fn_ty);
    const file_exists_fn_ty = c.LLVMFunctionType(c.LLVMInt1TypeInContext(context), @constCast(&make_directory_params), make_directory_params.len, 0);
    const file_exists_fn = c.LLVMAddFunction(module, "__openjai_file_exists", file_exists_fn_ty);
    const set_working_directory_fn_ty = c.LLVMFunctionType(c.LLVMInt1TypeInContext(context), @constCast(&make_directory_params), make_directory_params.len, 0);
    const set_working_directory_fn = c.LLVMAddFunction(module, "__openjai_set_working_directory", set_working_directory_fn_ty);
    const get_working_directory_fn_ty = c.LLVMFunctionType(ptr_ty, null, 0, 0);
    const get_working_directory_fn = c.LLVMAddFunction(module, "__openjai_get_working_directory", get_working_directory_fn_ty);
    const get_path_of_running_executable_fn_ty = c.LLVMFunctionType(ptr_ty, null, 0, 0);
    const get_path_of_running_executable_fn = c.LLVMAddFunction(module, "__openjai_get_path_of_running_executable", get_path_of_running_executable_fn_ty);
    const file_open_params = [_]c.LLVMTypeRef{ ptr_ty, llvm_i64, c.LLVMInt1TypeInContext(context), c.LLVMInt1TypeInContext(context) };
    const file_open_fn_ty = c.LLVMFunctionType(ptr_ty, @constCast(&file_open_params), file_open_params.len, 0);
    const file_open_fn = c.LLVMAddFunction(module, "__openjai_file_open", file_open_fn_ty);
    const file_close_params = [_]c.LLVMTypeRef{ptr_ty};
    const file_close_fn_ty = c.LLVMFunctionType(c.LLVMInt1TypeInContext(context), @constCast(&file_close_params), file_close_params.len, 0);
    const file_close_fn = c.LLVMAddFunction(module, "__openjai_file_close", file_close_fn_ty);
    const file_length_fn_ty = c.LLVMFunctionType(llvm_i64, @constCast(&file_close_params), file_close_params.len, 0);
    const file_length_fn = c.LLVMAddFunction(module, "__openjai_file_length", file_length_fn_ty);
    const file_set_position_params = [_]c.LLVMTypeRef{ ptr_ty, llvm_i64 };
    const file_set_position_fn_ty = c.LLVMFunctionType(c.LLVMInt1TypeInContext(context), @constCast(&file_set_position_params), file_set_position_params.len, 0);
    const file_set_position_fn = c.LLVMAddFunction(module, "__openjai_file_set_position", file_set_position_fn_ty);
    const file_rw_params = [_]c.LLVMTypeRef{ ptr_ty, ptr_ty, llvm_i64 };
    const file_write_fn_ty = c.LLVMFunctionType(c.LLVMInt1TypeInContext(context), @constCast(&file_rw_params), file_rw_params.len, 0);
    const file_write_fn = c.LLVMAddFunction(module, "__openjai_file_write", file_write_fn_ty);
    const file_read_fn_ty = c.LLVMFunctionType(c.LLVMInt1TypeInContext(context), @constCast(&file_rw_params), file_rw_params.len, 0);
    const file_read_fn = c.LLVMAddFunction(module, "__openjai_file_read", file_read_fn_ty);
    const posix_read_params = [_]c.LLVMTypeRef{ llvm_i64, ptr_ty, llvm_i64 };
    const posix_read_fn_ty = c.LLVMFunctionType(llvm_i64, @constCast(&posix_read_params), posix_read_params.len, 0);
    const posix_read_fn = c.LLVMAddFunction(module, "__openjai_posix_read", posix_read_fn_ty);
    const string_equal_params = [_]c.LLVMTypeRef{ ptr_ty, llvm_i64, ptr_ty, llvm_i64 };
    const string_equal_fn_ty = c.LLVMFunctionType(c.LLVMInt8TypeInContext(context), @constCast(&string_equal_params), string_equal_params.len, 0);
    const string_equal_fn = c.LLVMAddFunction(module, "__openjai_string_equal", string_equal_fn_ty);
    const string_slice_params = [_]c.LLVMTypeRef{ ptr_ty, llvm_i64, llvm_i64 };
    const string_slice_fn_ty = c.LLVMFunctionType(ptr_ty, @constCast(&string_slice_params), string_slice_params.len, 0);
    const string_slice_fn = c.LLVMAddFunction(module, "__openjai_string_slice", string_slice_fn_ty);
    const builder_slot_params = [_]c.LLVMTypeRef{ptr_ty};
    const string_builder_init_fn_ty = c.LLVMFunctionType(void_ty, @constCast(&builder_slot_params), builder_slot_params.len, 0);
    const string_builder_init_fn = c.LLVMAddFunction(module, "__openjai_string_builder_init", string_builder_init_fn_ty);
    const string_builder_free_fn_ty = c.LLVMFunctionType(void_ty, @constCast(&builder_slot_params), builder_slot_params.len, 0);
    const string_builder_free_fn = c.LLVMAddFunction(module, "__openjai_string_builder_free", string_builder_free_fn_ty);
    const builder_append_string_params = [_]c.LLVMTypeRef{ ptr_ty, ptr_ty, llvm_i64 };
    const string_builder_append_string_fn_ty = c.LLVMFunctionType(c.LLVMInt1TypeInContext(context), @constCast(&builder_append_string_params), builder_append_string_params.len, 0);
    const string_builder_append_string_fn = c.LLVMAddFunction(module, "__openjai_string_builder_append_string", string_builder_append_string_fn_ty);
    const builder_append_int_params = [_]c.LLVMTypeRef{ ptr_ty, llvm_i64 };
    const string_builder_append_int_fn_ty = c.LLVMFunctionType(c.LLVMInt1TypeInContext(context), @constCast(&builder_append_int_params), builder_append_int_params.len, 0);
    const string_builder_append_int_fn = c.LLVMAddFunction(module, "__openjai_string_builder_append_int", string_builder_append_int_fn_ty);
    const builder_append_float_params = [_]c.LLVMTypeRef{ ptr_ty, llvm_f64 };
    const string_builder_append_float_fn_ty = c.LLVMFunctionType(c.LLVMInt1TypeInContext(context), @constCast(&builder_append_float_params), builder_append_float_params.len, 0);
    const string_builder_append_float_fn = c.LLVMAddFunction(module, "__openjai_string_builder_append_float", string_builder_append_float_fn_ty);
    const builder_append_bool_params = [_]c.LLVMTypeRef{ ptr_ty, c.LLVMInt1TypeInContext(context) };
    const string_builder_append_bool_fn_ty = c.LLVMFunctionType(c.LLVMInt1TypeInContext(context), @constCast(&builder_append_bool_params), builder_append_bool_params.len, 0);
    const string_builder_append_bool_fn = c.LLVMAddFunction(module, "__openjai_string_builder_append_bool", string_builder_append_bool_fn_ty);
    const string_builder_to_string_fn_ty = c.LLVMFunctionType(ptr_ty, @constCast(&builder_slot_params), builder_slot_params.len, 0);
    const string_builder_to_string_fn = c.LLVMAddFunction(module, "__openjai_string_builder_to_string", string_builder_to_string_fn_ty);
    const string_builder_length_fn_ty = c.LLVMFunctionType(llvm_i64, @constCast(&builder_slot_params), builder_slot_params.len, 0);
    const string_builder_length_fn = c.LLVMAddFunction(module, "__openjai_string_builder_length", string_builder_length_fn_ty);
    const builder_join_array_params = [_]c.LLVMTypeRef{ ptr_ty, ptr_ty, ptr_ty, llvm_i64, llvm_i64 };
    const string_builder_join_array_fn_ty = c.LLVMFunctionType(void_ty, @constCast(&builder_join_array_params), builder_join_array_params.len, 0);
    const string_builder_join_array_fn = c.LLVMAddFunction(module, "__openjai_string_builder_join_array", string_builder_join_array_fn_ty);
    const string_parts_params = [_]c.LLVMTypeRef{ ptr_ty, llvm_i64 };
    const string_copy_fn_ty = c.LLVMFunctionType(ptr_ty, @constCast(&string_parts_params), string_parts_params.len, 0);
    const string_copy_fn = c.LLVMAddFunction(module, "__openjai_copy_string", string_copy_fn_ty);
    const string_to_c_fn_ty = c.LLVMFunctionType(ptr_ty, @constCast(&string_parts_params), string_parts_params.len, 0);
    const string_to_c_fn = c.LLVMAddFunction(module, "__openjai_to_c_string", string_to_c_fn_ty);
    const string_from_c_params = [_]c.LLVMTypeRef{ptr_ty};
    const string_from_c_fn_ty = c.LLVMFunctionType(ptr_ty, @constCast(&string_from_c_params), string_from_c_params.len, 0);
    const string_from_c_fn = c.LLVMAddFunction(module, "__openjai_string_from_c", string_from_c_fn_ty);
    const string_from_parts_fn_ty = c.LLVMFunctionType(ptr_ty, @constCast(&string_parts_params), string_parts_params.len, 0);
    const string_from_parts_fn = c.LLVMAddFunction(module, "__openjai_string_from_parts", string_from_parts_fn_ty);
    const string_trim_fn_ty = c.LLVMFunctionType(ptr_ty, @constCast(&string_parts_params), string_parts_params.len, 0);
    const string_trim_fn = c.LLVMAddFunction(module, "__openjai_string_trim", string_trim_fn_ty);
    const string_two_parts_params = [_]c.LLVMTypeRef{ ptr_ty, llvm_i64, ptr_ty, llvm_i64 };
    const string_compare_fn_ty = c.LLVMFunctionType(llvm_i64, @constCast(&string_two_parts_params), string_two_parts_params.len, 0);
    const string_compare_fn = c.LLVMAddFunction(module, "__openjai_string_compare", string_compare_fn_ty);
    const string_contains_fn_ty = c.LLVMFunctionType(c.LLVMInt1TypeInContext(context), @constCast(&string_two_parts_params), string_two_parts_params.len, 0);
    const string_contains_fn = c.LLVMAddFunction(module, "__openjai_string_contains", string_contains_fn_ty);
    const string_begins_with_fn_ty = c.LLVMFunctionType(c.LLVMInt1TypeInContext(context), @constCast(&string_two_parts_params), string_two_parts_params.len, 0);
    const string_begins_with_fn = c.LLVMAddFunction(module, "__openjai_string_begins_with", string_begins_with_fn_ty);
    const string_find_params = [_]c.LLVMTypeRef{ ptr_ty, llvm_i64, ptr_ty, llvm_i64, c.LLVMInt1TypeInContext(context) };
    const string_find_fn_ty = c.LLVMFunctionType(llvm_i64, @constCast(&string_find_params), string_find_params.len, 0);
    const string_find_fn = c.LLVMAddFunction(module, "__openjai_string_find", string_find_fn_ty);
    const string_split_fn_ty = c.LLVMFunctionType(ptr_ty, @constCast(&string_two_parts_params), string_two_parts_params.len, 0);
    const string_split_fn = c.LLVMAddFunction(module, "__openjai_string_split", string_split_fn_ty);
    const string_parse_int_fn_ty = c.LLVMFunctionType(llvm_i64, @constCast(&string_parts_params), string_parts_params.len, 0);
    const string_parse_int_fn = c.LLVMAddFunction(module, "__openjai_string_parse_int", string_parse_int_fn_ty);
    const string_parse_int_ok_fn_ty = c.LLVMFunctionType(c.LLVMInt1TypeInContext(context), @constCast(&string_parts_params), string_parts_params.len, 0);
    const string_parse_int_ok_fn = c.LLVMAddFunction(module, "__openjai_string_parse_int_ok", string_parse_int_ok_fn_ty);
    const string_parse_float_fn_ty = c.LLVMFunctionType(llvm_f64, @constCast(&string_parts_params), string_parts_params.len, 0);
    const string_parse_float_fn = c.LLVMAddFunction(module, "__openjai_string_parse_float", string_parse_float_fn_ty);
    const string_parse_float_ok_fn_ty = c.LLVMFunctionType(c.LLVMInt1TypeInContext(context), @constCast(&string_parts_params), string_parts_params.len, 0);
    const string_parse_float_ok_fn = c.LLVMAddFunction(module, "__openjai_string_parse_float_ok", string_parse_float_ok_fn_ty);
    const string_replace_params = [_]c.LLVMTypeRef{ ptr_ty, llvm_i64, ptr_ty, llvm_i64, ptr_ty, llvm_i64 };
    const string_replace_fn_ty = c.LLVMFunctionType(ptr_ty, @constCast(&string_replace_params), string_replace_params.len, 0);
    const string_replace_fn = c.LLVMAddFunction(module, "__openjai_string_replace", string_replace_fn_ty);
    const path_strip_filename_fn_ty = c.LLVMFunctionType(ptr_ty, @constCast(&string_parts_params), string_parts_params.len, 0);
    const path_strip_filename_fn = c.LLVMAddFunction(module, "__openjai_path_strip_filename", path_strip_filename_fn_ty);
    const array_add_params = [_]c.LLVMTypeRef{ ptr_ty, ptr_ty, llvm_i64 };
    const array_add_fn_ty = c.LLVMFunctionType(ptr_ty, @constCast(&array_add_params), array_add_params.len, 0);
    const array_add_fn = c.LLVMAddFunction(module, "__openjai_array_add", array_add_fn_ty);
    const array_free_params = [_]c.LLVMTypeRef{ptr_ty};
    const array_free_fn_ty = c.LLVMFunctionType(void_ty, @constCast(&array_free_params), array_free_params.len, 0);
    const array_free_fn = c.LLVMAddFunction(module, "__openjai_array_free", array_free_fn_ty);
    const new_array_params = [_]c.LLVMTypeRef{ llvm_i64, llvm_i64, llvm_i64 };
    const new_array_fn_ty = c.LLVMFunctionType(ptr_ty, @constCast(&new_array_params), new_array_params.len, 0);
    const new_array_fn = c.LLVMAddFunction(module, "__openjai_new_array", new_array_fn_ty);
    const array_count_params = [_]c.LLVMTypeRef{ptr_ty};
    const array_count_fn_ty = c.LLVMFunctionType(llvm_i64, @constCast(&array_count_params), array_count_params.len, 0);
    const array_count_fn = c.LLVMAddFunction(module, "__openjai_array_count", array_count_fn_ty);
    const array_data_params = [_]c.LLVMTypeRef{ptr_ty};
    const array_data_fn_ty = c.LLVMFunctionType(ptr_ty, @constCast(&array_data_params), array_data_params.len, 0);
    const array_data_fn = c.LLVMAddFunction(module, "__openjai_array_data", array_data_fn_ty);
    const array_index_params = [_]c.LLVMTypeRef{ ptr_ty, llvm_i64, llvm_i64 };
    const array_index_fn_ty = c.LLVMFunctionType(ptr_ty, @constCast(&array_index_params), array_index_params.len, 0);
    const array_index_fn = c.LLVMAddFunction(module, "__openjai_array_index", array_index_fn_ty);

    const set_type_info_table_params = [_]c.LLVMTypeRef{ ptr_ty, llvm_i64 };
    const set_type_info_table_fn_ty = c.LLVMFunctionType(void_ty, @constCast(&set_type_info_table_params), set_type_info_table_params.len, 0);
    const set_type_info_table_fn = c.LLVMAddFunction(module, "__openjai_set_type_info_table", set_type_info_table_fn_ty);
    const type_info_get_members_params = [_]c.LLVMTypeRef{llvm_i64};
    const type_info_get_members_fn_ty = c.LLVMFunctionType(ptr_ty, @constCast(&type_info_get_members_params), type_info_get_members_params.len, 0);
    const type_info_get_members_fn = c.LLVMAddFunction(module, "__openjai_type_info_get_members", type_info_get_members_fn_ty);
    const type_info_member_name_params = [_]c.LLVMTypeRef{ptr_ty};
    const type_info_member_name_fn_ty = c.LLVMFunctionType(ptr_ty, @constCast(&type_info_member_name_params), type_info_member_name_params.len, 0);
    const type_info_member_name_fn = c.LLVMAddFunction(module, "__openjai_type_info_member_name", type_info_member_name_fn_ty);
    const type_info_member_type_name_fn_ty = c.LLVMFunctionType(ptr_ty, @constCast(&type_info_member_name_params), type_info_member_name_params.len, 0);
    const type_info_member_type_name_fn = c.LLVMAddFunction(module, "__openjai_type_info_member_type_name", type_info_member_type_name_fn_ty);
    const type_info_member_int_field_params = [_]c.LLVMTypeRef{ ptr_ty, llvm_i64 };
    const type_info_member_int_field_fn_ty = c.LLVMFunctionType(llvm_i64, @constCast(&type_info_member_int_field_params), type_info_member_int_field_params.len, 0);
    const type_info_member_int_field_fn = c.LLVMAddFunction(module, "__openjai_type_info_member_int_field", type_info_member_int_field_fn_ty);
    const type_info_lookup_params = [_]c.LLVMTypeRef{ ptr_ty, llvm_i64 };
    const type_info_lookup_fn_ty = c.LLVMFunctionType(llvm_i64, @constCast(&type_info_lookup_params), type_info_lookup_params.len, 0);
    const type_info_lookup_fn = c.LLVMAddFunction(module, "__openjai_type_info_lookup", type_info_lookup_fn_ty);
    const user_main_fn_ty = c.LLVMFunctionType(void_ty, null, 0, 0);
    const user_main_fn = if (program.main_proc != null) c.LLVMAddFunction(module, "__openjai_user_main", user_main_fn_ty) else null;
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
        const return_ty = llvmReturnTypeForProc(context, llvm_i64, llvm_f64, ptr_ty, proc);
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

    var env = LlvmEnv{ .allocator = allocator, .context = context, .module = module, .builder = builder, .program = program, .proc_functions = proc_functions, .proc_function_tys = proc_function_tys, .proc_void_ty = proc_void_ty, .print_fn_ty = print_fn_ty, .print_fn = print_fn, .print_int_fn_ty = print_int_fn_ty, .print_int_fn = print_int_fn, .print_uint_fn_ty = print_uint_fn_ty, .print_uint_fn = print_uint_fn, .print_static_int_array_fn_ty = print_static_int_array_fn_ty, .print_static_int_array_fn = print_static_int_array_fn, .print_float_fn_ty = print_float_fn_ty, .print_float_fn = print_float_fn, .print_bool_fn_ty = print_bool_fn_ty, .print_bool_fn = print_bool_fn, .print_type_fn_ty = print_type_fn_ty, .print_type_fn = print_type_fn, .print_return_int_fn_ty = print_return_int_fn_ty, .print_return_int_fn = print_return_int_fn, .print_format_int_fn_ty = print_format_int_fn_ty, .print_format_int_fn = print_format_int_fn, .print_format_float_fn_ty = print_format_float_fn_ty, .print_format_float_fn = print_format_float_fn, .alloc_fn_ty = alloc_fn_ty, .alloc_fn = alloc_fn, .free_fn_ty = free_fn_ty, .free_fn = free_fn, .memcpy_fn_ty = memcpy_fn_ty, .memcpy_fn = memcpy_fn, .assert_fail_fn_ty = assert_fail_fn_ty, .assert_fail_fn = assert_fail_fn, .exit_fn_ty = exit_fn_ty, .exit_fn = exit_fn, .current_time_consensus_low_fn_ty = current_time_consensus_low_fn_ty, .current_time_consensus_low_fn = current_time_consensus_low_fn, .current_time_monotonic_low_fn_ty = current_time_monotonic_low_fn_ty, .current_time_monotonic_low_fn = current_time_monotonic_low_fn, .get_time_seconds_fn_ty = get_time_seconds_fn_ty, .get_time_seconds_fn = get_time_seconds_fn, .seconds_since_init_fn_ty = seconds_since_init_fn_ty, .seconds_since_init_fn = seconds_since_init_fn, .to_float64_seconds_fn_ty = to_float64_seconds_fn_ty, .to_float64_seconds_fn = to_float64_seconds_fn, .to_calendar_fn_ty = to_calendar_fn_ty, .to_calendar_fn = to_calendar_fn, .calendar_get_i64_fn_ty = calendar_get_i64_fn_ty, .calendar_get_i64_fn = calendar_get_i64_fn, .calendar_to_string_fn_ty = calendar_to_string_fn_ty, .calendar_to_string_fn = calendar_to_string_fn, .random_seed_fn_ty = random_seed_fn_ty, .random_seed_fn = random_seed_fn, .random_get_fn_ty = random_get_fn_ty, .random_get_fn = random_get_fn, .random_get_zero_to_one_fn_ty = random_get_zero_to_one_fn_ty, .random_get_zero_to_one_fn = random_get_zero_to_one_fn, .random_get_within_range_fn_ty = random_get_within_range_fn_ty, .random_get_within_range_fn = random_get_within_range_fn, .arg_count_fn_ty = arg_count_fn_ty, .arg_count_fn = arg_count_fn, .arg_value_fn_ty = arg_value_fn_ty, .arg_value_fn = arg_value_fn, .read_entire_file_fn_ty = read_entire_file_fn_ty, .read_entire_file_fn = read_entire_file_fn, .write_entire_file_fn_ty = write_entire_file_fn_ty, .write_entire_file_fn = write_entire_file_fn, .get_command_line_arguments_fn_ty = get_command_line_arguments_fn_ty, .get_command_line_arguments_fn = get_command_line_arguments_fn, .sleep_milliseconds_fn_ty = sleep_milliseconds_fn_ty, .sleep_milliseconds_fn = sleep_milliseconds_fn, .cpu_has_feature_fn_ty = cpu_has_feature_fn_ty, .cpu_has_feature_fn = cpu_has_feature_fn, .make_directory_fn_ty = make_directory_fn_ty, .make_directory_fn = make_directory_fn, .delete_directory_fn_ty = delete_directory_fn_ty, .delete_directory_fn = delete_directory_fn, .file_exists_fn_ty = file_exists_fn_ty, .file_exists_fn = file_exists_fn, .set_working_directory_fn_ty = set_working_directory_fn_ty, .set_working_directory_fn = set_working_directory_fn, .get_working_directory_fn_ty = get_working_directory_fn_ty, .get_working_directory_fn = get_working_directory_fn, .get_path_of_running_executable_fn_ty = get_path_of_running_executable_fn_ty, .get_path_of_running_executable_fn = get_path_of_running_executable_fn, .file_open_fn_ty = file_open_fn_ty, .file_open_fn = file_open_fn, .file_close_fn_ty = file_close_fn_ty, .file_close_fn = file_close_fn, .file_length_fn_ty = file_length_fn_ty, .file_length_fn = file_length_fn, .file_set_position_fn_ty = file_set_position_fn_ty, .file_set_position_fn = file_set_position_fn, .file_write_fn_ty = file_write_fn_ty, .file_write_fn = file_write_fn, .file_read_fn_ty = file_read_fn_ty, .file_read_fn = file_read_fn, .posix_read_fn_ty = posix_read_fn_ty, .posix_read_fn = posix_read_fn, .string_equal_fn_ty = string_equal_fn_ty, .string_equal_fn = string_equal_fn, .string_slice_fn_ty = string_slice_fn_ty, .string_slice_fn = string_slice_fn, .string_builder_init_fn_ty = string_builder_init_fn_ty, .string_builder_init_fn = string_builder_init_fn, .string_builder_free_fn_ty = string_builder_free_fn_ty, .string_builder_free_fn = string_builder_free_fn, .string_builder_append_string_fn_ty = string_builder_append_string_fn_ty, .string_builder_append_string_fn = string_builder_append_string_fn, .string_builder_append_int_fn_ty = string_builder_append_int_fn_ty, .string_builder_append_int_fn = string_builder_append_int_fn, .string_builder_append_float_fn_ty = string_builder_append_float_fn_ty, .string_builder_append_float_fn = string_builder_append_float_fn, .string_builder_append_bool_fn_ty = string_builder_append_bool_fn_ty, .string_builder_append_bool_fn = string_builder_append_bool_fn, .string_builder_to_string_fn_ty = string_builder_to_string_fn_ty, .string_builder_to_string_fn = string_builder_to_string_fn, .string_builder_length_fn_ty = string_builder_length_fn_ty, .string_builder_length_fn = string_builder_length_fn, .string_builder_join_array_fn_ty = string_builder_join_array_fn_ty, .string_builder_join_array_fn = string_builder_join_array_fn, .string_copy_fn_ty = string_copy_fn_ty, .string_copy_fn = string_copy_fn, .string_to_c_fn_ty = string_to_c_fn_ty, .string_to_c_fn = string_to_c_fn, .string_from_c_fn_ty = string_from_c_fn_ty, .string_from_c_fn = string_from_c_fn, .string_from_parts_fn_ty = string_from_parts_fn_ty, .string_from_parts_fn = string_from_parts_fn, .string_trim_fn_ty = string_trim_fn_ty, .string_trim_fn = string_trim_fn, .string_compare_fn_ty = string_compare_fn_ty, .string_compare_fn = string_compare_fn, .string_contains_fn_ty = string_contains_fn_ty, .string_contains_fn = string_contains_fn, .string_begins_with_fn_ty = string_begins_with_fn_ty, .string_begins_with_fn = string_begins_with_fn, .string_find_fn_ty = string_find_fn_ty, .string_find_fn = string_find_fn, .string_split_fn_ty = string_split_fn_ty, .string_split_fn = string_split_fn, .string_parse_int_fn_ty = string_parse_int_fn_ty, .string_parse_int_fn = string_parse_int_fn, .string_parse_int_ok_fn_ty = string_parse_int_ok_fn_ty, .string_parse_int_ok_fn = string_parse_int_ok_fn, .string_parse_float_fn_ty = string_parse_float_fn_ty, .string_parse_float_fn = string_parse_float_fn, .string_parse_float_ok_fn_ty = string_parse_float_ok_fn_ty, .string_parse_float_ok_fn = string_parse_float_ok_fn, .string_replace_fn_ty = string_replace_fn_ty, .string_replace_fn = string_replace_fn, .path_strip_filename_fn_ty = path_strip_filename_fn_ty, .path_strip_filename_fn = path_strip_filename_fn, .array_add_fn_ty = array_add_fn_ty, .array_add_fn = array_add_fn, .array_free_fn_ty = array_free_fn_ty, .array_free_fn = array_free_fn, .new_array_fn_ty = new_array_fn_ty, .new_array_fn = new_array_fn, .array_count_fn_ty = array_count_fn_ty, .array_count_fn = array_count_fn, .array_data_fn_ty = array_data_fn_ty, .array_data_fn = array_data_fn, .array_index_fn_ty = array_index_fn_ty, .array_index_fn = array_index_fn, .set_type_info_table_fn_ty = set_type_info_table_fn_ty, .set_type_info_table_fn = set_type_info_table_fn, .type_info_get_members_fn_ty = type_info_get_members_fn_ty, .type_info_get_members_fn = type_info_get_members_fn, .type_info_member_name_fn_ty = type_info_member_name_fn_ty, .type_info_member_name_fn = type_info_member_name_fn, .type_info_member_type_name_fn_ty = type_info_member_type_name_fn_ty, .type_info_member_type_name_fn = type_info_member_type_name_fn, .type_info_member_int_field_fn_ty = type_info_member_int_field_fn_ty, .type_info_member_int_field_fn = type_info_member_int_field_fn, .type_info_lookup_fn_ty = type_info_lookup_fn_ty, .type_info_lookup_fn = type_info_lookup_fn, .llvm_i32 = llvm_i32, .llvm_i64 = llvm_i64, .llvm_f32 = llvm_f32, .llvm_f64 = llvm_f64, .ptr_ty = ptr_ty };

    for (program.procs.items, 0..) |*helper_proc, i| {
        if (program.main_proc != null and i == program.main_proc.?) continue;
        const helper_fn = proc_functions[i] orelse continue;
        env.current_proc_name = helper_proc.name;
        env.current_proc_index = i;
        const helper_entry = c.LLVMAppendBasicBlockInContext(context, helper_fn, "entry");
        c.LLVMPositionBuilderAtEnd(builder, helper_entry);
        const helper_registers = try allocator.alloc(RegisterValue, @max(helper_proc.num_registers, 1));
        defer allocator.free(helper_registers);
        @memset(helper_registers, .{});
        for (helper_proc.param_types.items, 0..) |type_id, param_index| {
            helper_registers[param_index] = registerValueForTypedLlvmValue(c.LLVMGetParam(helper_fn, @intCast(param_index)), type_id);
        }
        try emitProcInstructions(&env, helper_proc, helper_registers, diag);
        if (helper_proc.return_types.items.len != 0) {
            _ = c.LLVMBuildRet(builder, c.LLVMConstNull(llvmReturnTypeForProc(context, llvm_i64, llvm_f64, ptr_ty, helper_proc)));
        } else if (helper_proc.return_type == 0) {
            _ = c.LLVMBuildRetVoid(builder);
        } else {
            _ = c.LLVMBuildRet(builder, defaultLlvmValueForTypeId(&env, helper_proc.return_type));
        }
    }

    if (program.main_proc) |main_proc| {
        const entry = c.LLVMAppendBasicBlockInContext(context, user_main_fn.?, "entry");
        c.LLVMPositionBuilderAtEnd(builder, entry);

        // Generate type info table as global data and call __openjai_set_type_info_table
        try emitTypeInfoTable(&env);

        const proc = &program.procs.items[main_proc];
        env.current_proc_name = proc.name;
        env.current_proc_index = main_proc;
        const registers = try allocator.alloc(RegisterValue, @max(proc.num_registers, 1));
        defer allocator.free(registers);
        @memset(registers, .{});
        try emitProcInstructions(&env, proc, registers, diag);
        _ = c.LLVMBuildRetVoid(builder);
    }

    _ = c.LLVMPrintModuleToFile(module, "/tmp/openjai_dump.ll", null);

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
        10, 17 => ptr_ty,
        else => llvm_i64,
    };
}

fn llvmReturnTypeForProc(context: c.LLVMContextRef, llvm_i64: c.LLVMTypeRef, llvm_f64: c.LLVMTypeRef, ptr_ty: c.LLVMTypeRef, proc: *const Bytecode.ProcBytecode) c.LLVMTypeRef {
    if (proc.return_types.items.len == 0) return llvmTypeForTypeId(context, llvm_i64, llvm_f64, ptr_ty, proc.return_type);
    var fields = std.heap.stackFallback(16 * @sizeOf(c.LLVMTypeRef), std.heap.page_allocator);
    const allocator = fields.get();
    const types = allocator.alloc(c.LLVMTypeRef, proc.return_types.items.len) catch @panic("out of memory while building LLVM multi-return type");
    defer allocator.free(types);
    for (proc.return_types.items, 0..) |type_id, i| {
        types[i] = llvmTypeForTypeId(context, llvm_i64, llvm_f64, ptr_ty, type_id);
    }
    return c.LLVMStructTypeInContext(context, types.ptr, @intCast(types.len), 0);
}

fn emitProcInstructions(env: *LlvmEnv, proc: *const Bytecode.ProcBytecode, registers: []RegisterValue, diag: Diagnostic) !void {
    const function = c.LLVMGetBasicBlockParent(c.LLVMGetInsertBlock(env.builder));
    const instruction_count = proc.instructions.items.len;

    var is_block_start = try env.allocator.alloc(bool, instruction_count + 1);
    defer env.allocator.free(is_block_start);
    @memset(is_block_start, false);
    is_block_start[0] = true;
    is_block_start[instruction_count] = true;
    for (proc.instructions.items) |inst| {
        switch (inst.opcode) {
            .jump => {
                if (inst.arg1 <= instruction_count) is_block_start[inst.arg1] = true;
            },
            .jump_if_false => {
                if (inst.arg2 <= instruction_count) is_block_start[inst.arg2] = true;
            },
            else => {},
        }
    }
    for (proc.instructions.items, 0..) |inst, idx| {
        switch (inst.opcode) {
            .jump, .jump_if_false, .ret, .ret_multi, .ret_void, .exit_process, .host_set_workspace_status, .host_build_cpp_dynamic_lib, .host_custom_link_complete, .host_run_command, .host_run_command_capture => {
                if (idx + 1 <= instruction_count) is_block_start[idx + 1] = true;
            },
            else => {},
        }
    }

    var blocks = try env.allocator.alloc(c.LLVMBasicBlockRef, instruction_count + 1);
    defer env.allocator.free(blocks);
    for (0..instruction_count + 1) |i| {
        if (is_block_start[i]) {
            const name_tmp = try std.fmt.allocPrint(env.allocator, "bc.{d}", .{i});
            defer env.allocator.free(name_tmp);
            const name = try env.allocator.dupeZ(u8, name_tmp);
            defer env.allocator.free(name);
            blocks[i] = c.LLVMAppendBasicBlockInContext(env.context, function, name.ptr);
        } else {
            blocks[i] = null;
        }
    }
    _ = c.LLVMBuildBr(env.builder, blocks[0].?);

    var need_position = true;
    for (proc.instructions.items, 0..) |inst, instruction_index| {
        env.current_opcode = inst.opcode;
        env.current_instruction_index = instruction_index;
        if (is_block_start[instruction_index]) {
            c.LLVMPositionBuilderAtEnd(env.builder, blocks[instruction_index].?);
            need_position = false;
        }
        var terminates_block = false;
        switch (inst.opcode) {
            .load_string => {
                if (inst.dest >= registers.len) return diag.failAt(0, "LLVM backend string load destination register out of range", .{});
                registers[inst.dest] = try staticStringRegister(env, inst.arg1, diag);
            },
            .load_code => {
                if (inst.dest >= registers.len) return diag.failAt(0, "LLVM backend code load destination register out of range", .{});
                registers[inst.dest] = try staticStringRegister(env, inst.arg2, diag);
            },
            .load_source_location => {
                if (inst.dest >= registers.len or inst.arg1 >= env.program.strings.items.len) return diag.failAt(0, "LLVM backend source-location load out of range", .{});
                registers[inst.dest] = .{ .kind = .{ .source_location = .{ .file = inst.arg1, .line = inst.arg2 } } };
            },
            .load_calendar => {
                if (inst.dest >= registers.len or inst.arg1 >= env.program.calendar_literals.items.len) return diag.failAt(0, "LLVM backend calendar literal load out of range", .{});
                const calendar = env.program.calendar_literals.items[inst.arg1];
                const fields = [_]c.LLVMValueRef{
                    c.LLVMConstInt(env.llvm_i64, @bitCast(calendar.year), 1),
                    c.LLVMConstInt(env.llvm_i64, @bitCast(calendar.month_starting_at_0), 1),
                    c.LLVMConstInt(env.llvm_i64, @bitCast(calendar.day_of_month_starting_at_0), 1),
                    c.LLVMConstInt(env.llvm_i64, @bitCast(calendar.day_of_week_starting_at_0), 1),
                    c.LLVMConstInt(env.llvm_i64, @bitCast(calendar.hour), 1),
                    c.LLVMConstInt(env.llvm_i64, @bitCast(calendar.minute), 1),
                    c.LLVMConstInt(env.llvm_i64, @bitCast(calendar.second), 1),
                    c.LLVMConstInt(env.llvm_i64, @bitCast(calendar.millisecond), 1),
                    c.LLVMConstInt(env.llvm_i64, @bitCast(calendar.time_zone), 1),
                };
                const calendar_ty = c.LLVMArrayType(env.llvm_i64, fields.len);
                const calendar_init = c.LLVMConstArray(env.llvm_i64, @constCast(&fields), fields.len);
                const name_tmp = try std.fmt.allocPrint(env.allocator, "calendar.{d}", .{inst.arg1});
                defer env.allocator.free(name_tmp);
                const name = try env.allocator.dupeZ(u8, name_tmp);
                defer env.allocator.free(name);
                const global = c.LLVMAddGlobal(env.module, calendar_ty, name.ptr);
                c.LLVMSetInitializer(global, calendar_init);
                c.LLVMSetGlobalConstant(global, 1);
                c.LLVMSetLinkage(global, c.LLVMPrivateLinkage);
                registers[inst.dest] = .{ .llvm_value = global, .kind = .calendar };
            },
            .load_bytes => {
                if (inst.dest >= registers.len) return diag.failAt(0, "LLVM backend byte-array load destination register out of range", .{});
                if (inst.arg1 >= env.program.byte_arrays.items.len) return diag.failAt(0, "LLVM backend byte-array index out of range", .{});
                const bytes = env.program.byte_arrays.items[inst.arg1];
                const data_name_tmp = try std.fmt.allocPrint(env.allocator, "bytes.{d}.data", .{inst.arg1});
                defer env.allocator.free(data_name_tmp);
                const data_name = try env.allocator.dupeZ(u8, data_name_tmp);
                defer env.allocator.free(data_name);
                const data_global = c.LLVMAddGlobal(env.module, c.LLVMArrayType(c.LLVMInt8TypeInContext(env.context), @intCast(@max(bytes.len, 1))), data_name.ptr);
                c.LLVMSetGlobalConstant(data_global, 1);
                c.LLVMSetLinkage(data_global, c.LLVMPrivateLinkage);
                if (bytes.len == 0) {
                    c.LLVMSetInitializer(data_global, c.LLVMConstNull(c.LLVMArrayType(c.LLVMInt8TypeInContext(env.context), 1)));
                } else {
                    c.LLVMSetInitializer(data_global, c.LLVMConstStringInContext(env.context, bytes.ptr, @intCast(bytes.len), 1));
                }

                const header_name_tmp = try std.fmt.allocPrint(env.allocator, "bytes.{d}.header", .{inst.arg1});
                defer env.allocator.free(header_name_tmp);
                const header_name = try env.allocator.dupeZ(u8, header_name_tmp);
                defer env.allocator.free(header_name);
                var header_fields = [_]c.LLVMTypeRef{ env.llvm_i64, env.llvm_i64, env.ptr_ty };
                const header_ty = c.LLVMStructTypeInContext(env.context, &header_fields, header_fields.len, 0);
                var header_values = [_]c.LLVMValueRef{
                    c.LLVMConstInt(env.llvm_i64, bytes.len, 0),
                    c.LLVMConstInt(env.llvm_i64, bytes.len, 0),
                    c.LLVMConstPointerCast(data_global, env.ptr_ty),
                };
                const header_global = c.LLVMAddGlobal(env.module, header_ty, header_name.ptr);
                c.LLVMSetGlobalConstant(header_global, 1);
                c.LLVMSetLinkage(header_global, c.LLVMPrivateLinkage);
                c.LLVMSetInitializer(header_global, c.LLVMConstStructInContext(env.context, &header_values, header_values.len, 0));
                try setPointerResult(env, registers, inst.dest, header_global);
            },
            .load_int => {
                if (inst.dest >= registers.len) return diag.failAt(0, "LLVM backend load_int destination out of range", .{});
                try setIntResult(env, registers, inst.dest, c.LLVMConstInt(env.llvm_i64, inst.arg1, 1));
            },
            .load_float => {
                if (inst.dest >= registers.len) return diag.failAt(0, "LLVM backend float load destination register out of range", .{});
                const bits = (@as(u64, inst.arg2) << 32) | inst.arg1;
                const value: f64 = @bitCast(bits);
                try setFloatResult(env, registers, inst.dest, c.LLVMConstReal(env.llvm_f64, value));
            },
            .load_bool => {
                if (inst.dest >= registers.len) return diag.failAt(0, "LLVM backend bool load destination register out of range", .{});
                try setBoolResult(env, registers, inst.dest, c.LLVMConstInt(c.LLVMInt1TypeInContext(env.context), inst.arg1, 0));
            },
            .load_null_ptr => {
                if (inst.dest >= registers.len) return diag.failAt(0, "LLVM backend null pointer load destination register out of range", .{});
                registers[inst.dest] = .{ .llvm_value = c.LLVMConstPointerNull(env.ptr_ty), .kind = .pointer };
            },
            .load_type => {
                if (inst.dest >= registers.len) return diag.failAt(0, "LLVM backend type load destination register out of range", .{});
                registers[inst.dest] = .{ .llvm_value = c.LLVMConstInt(env.llvm_i64, inst.arg1, 0), .kind = if (inst.arg1 == 0) .void_value else .type_id };
            },
            .load_type_text => {
                if (inst.dest >= registers.len or inst.arg1 >= env.program.strings.items.len) return diag.failAt(0, "LLVM backend type-text load out of range", .{});
                const type_name = env.program.strings.items[inst.arg1];
                const builtin_id = typeIdFromTypeTextLlvm(type_name);
                if (builtin_id != 0) {
                    registers[inst.dest] = .{ .llvm_value = c.LLVMConstInt(env.llvm_i64, builtin_id, 0), .kind = .type_id };
                } else if (env.program.typeInfoIndexByName(type_name)) |idx| {
                    registers[inst.dest] = .{ .llvm_value = c.LLVMConstInt(env.llvm_i64, type_info_base_id + idx, 0), .kind = .type_id };
                } else {
                    registers[inst.dest] = try staticStringRegister(env, inst.arg1, diag);
                }
            },
            .type_to_string => {
                if (inst.dest >= registers.len or inst.arg1 >= registers.len) return diag.failAt(0, "LLVM backend type_to_string register out of range", .{});
                switch (registers[inst.arg1].kind) {
                    .string, .runtime_string, .string_addr => registers[inst.dest] = registers[inst.arg1],
                    .type_id, .int, .int_addr, .uint, .uint_addr, .pointer, .pointer_addr => {
                        const type_info_name_params = [_]c.LLVMTypeRef{env.llvm_i64};
                        const type_info_name_fn_ty = c.LLVMFunctionType(env.ptr_ty, @constCast(&type_info_name_params), type_info_name_params.len, 0);
                        const type_info_name_fn = c.LLVMGetNamedFunction(env.module, "__openjai_type_info_name") orelse c.LLVMAddFunction(env.module, "__openjai_type_info_name", type_info_name_fn_ty);
                        const val = try valueAsInt(env, registers[inst.arg1], diag);
                        var args = [_]c.LLVMValueRef{val};
                        const result = c.LLVMBuildCall2(env.builder, type_info_name_fn_ty, type_info_name_fn, &args, args.len, "type_name");
                        try setStringResult(env, registers, inst.dest, result);
                    },
                    else => {
                        const result = try emitInlineRuntimeString(env, "<unknown type>");
                        try setStringResult(env, registers, inst.dest, result);
                    },
                }
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
            .global_addr => {
                if (inst.dest >= registers.len or inst.arg1 >= env.program.globals.items.len) return diag.failAt(0, "LLVM backend global_addr register/global index out of range", .{});
                const global = env.program.globals.items[inst.arg1];
                const name_tmp = try std.fmt.allocPrint(env.allocator, "openjai.global.{d}", .{inst.arg1});
                defer env.allocator.free(name_tmp);
                const name = try env.allocator.dupeZ(u8, name_tmp);
                defer env.allocator.free(name);
                const global_value = c.LLVMGetNamedGlobal(env.module, name.ptr) orelse blk: {
                    const init_size = @max(global.size, 1);
                    const ty = c.LLVMArrayType(c.LLVMInt8TypeInContext(env.context), @intCast(init_size));
                    const created = c.LLVMAddGlobal(env.module, ty, name.ptr);
                    if (global.initial_bytes) |initial| {
                        const bytes = try env.allocator.alloc(u8, init_size);
                        defer env.allocator.free(bytes);
                        @memset(bytes, 0);
                        const copy_len = @min(initial.len, global.size);
                        if (copy_len != 0) @memcpy(bytes[0..copy_len], initial[0..copy_len]);
                        c.LLVMSetInitializer(created, c.LLVMConstStringInContext(env.context, bytes.ptr, @intCast(bytes.len), 1));
                    } else {
                        c.LLVMSetInitializer(created, c.LLVMConstNull(ty));
                    }
                    break :blk created;
                };
                try setPointerResult(env, registers, inst.dest, c.LLVMBuildPointerCast(env.builder, global_value, env.ptr_ty, "global_addr"));
            },
            .load_const_ref => {
                if (inst.dest >= registers.len) return diag.failAt(0, "LLVM backend const ref destination register out of range", .{});
                registers[inst.dest] = .{ .llvm_value = c.LLVMConstInt(env.llvm_i64, 7, 1), .kind = .int };
            },
            .neg_int => {
                if (inst.dest >= registers.len or inst.arg1 >= registers.len) return diag.failAt(0, "LLVM backend neg_int register out of range", .{});
                if (isFloatKind(registers[inst.arg1].kind)) {
                    try setFloatResult(env, registers, inst.dest, c.LLVMBuildFNeg(env.builder, try valueAsFloat(env, registers[inst.arg1], diag), "fneg"));
                } else {
                    try setIntResult(env, registers, inst.dest, c.LLVMBuildNeg(env.builder, try valueAsInt(env, registers[inst.arg1], diag), "neg"));
                }
            },
            .neg_float => {
                if (inst.dest >= registers.len or inst.arg1 >= registers.len) return diag.failAt(0, "LLVM backend neg_float register out of range", .{});
                try setFloatResult(env, registers, inst.dest, c.LLVMBuildFNeg(env.builder, try valueAsFloat(env, registers[inst.arg1], diag), "fneg"));
            },
            .not_bool => {
                if (inst.dest >= registers.len or inst.arg1 >= registers.len) return diag.failAt(0, "LLVM backend not_bool register out of range", .{});
                try setBoolResult(env, registers, inst.dest, c.LLVMBuildNot(env.builder, try valueAsBool(env, registers[inst.arg1], diag), "not"));
            },
            .bit_not => {
                if (inst.dest >= registers.len or inst.arg1 >= registers.len) return diag.failAt(0, "LLVM backend bit_not register out of range", .{});
                const operand = try valueAsInt(env, registers[inst.arg1], diag);
                try setIntResult(env, registers, inst.dest, c.LLVMBuildNot(env.builder, operand, "bnot"));
            },
            .mul_int => {
                if (inst.dest >= registers.len or inst.arg1 >= registers.len or inst.arg2 >= registers.len) return diag.failAt(0, "LLVM backend mul register out of range", .{});
                if (isStructKind(registers[inst.arg1].kind) or isStructKind(registers[inst.arg2].kind)) {
                    registers[inst.dest] = if (isStructKind(registers[inst.arg1].kind)) registers[inst.arg1] else registers[inst.arg2];
                } else if (isFloatKind(registers[inst.arg1].kind) or isFloatKind(registers[inst.arg2].kind)) {
                    const lhs_f = try valueAsFloat(env, registers[inst.arg1], diag);
                    const rhs_f = try valueAsFloat(env, registers[inst.arg2], diag);
                    try setFloatResult(env, registers, inst.dest, c.LLVMBuildFMul(env.builder, lhs_f, rhs_f, "fmul"));
                } else {
                    const lhs_int = try valueAsInt(env, registers[inst.arg1], diag);
                    const rhs_int = try valueAsInt(env, registers[inst.arg2], diag);
                    try setIntResult(env, registers, inst.dest, c.LLVMBuildMul(env.builder, lhs_int, rhs_int, "mul"));
                }
            },
            .mul_float => {
                if (inst.dest >= registers.len or inst.arg1 >= registers.len or inst.arg2 >= registers.len) return diag.failAt(0, "LLVM backend fmul register out of range", .{});
                if (isStructKind(registers[inst.arg1].kind) or isStructKind(registers[inst.arg2].kind)) {
                    registers[inst.dest] = if (isStructKind(registers[inst.arg1].kind)) registers[inst.arg1] else registers[inst.arg2];
                } else {
                    const lhs_float = try valueAsFloat(env, registers[inst.arg1], diag);
                    const rhs_float = try valueAsFloat(env, registers[inst.arg2], diag);
                    try setFloatResult(env, registers, inst.dest, c.LLVMBuildFMul(env.builder, lhs_float, rhs_float, "fmul"));
                }
            },
            .rem_int => {
                if (inst.dest >= registers.len or inst.arg1 >= registers.len or inst.arg2 >= registers.len) return diag.failAt(0, "LLVM backend rem register out of range", .{});
                if (isStructKind(registers[inst.arg1].kind) or isStructKind(registers[inst.arg2].kind)) {
                    registers[inst.dest] = if (isStructKind(registers[inst.arg1].kind)) registers[inst.arg1] else registers[inst.arg2];
                } else if (isFloatKind(registers[inst.arg1].kind) or isFloatKind(registers[inst.arg2].kind)) {
                    const lhs_f = try valueAsFloat(env, registers[inst.arg1], diag);
                    const rhs_f = try valueAsFloat(env, registers[inst.arg2], diag);
                    try setFloatResult(env, registers, inst.dest, c.LLVMBuildFRem(env.builder, lhs_f, rhs_f, "frem"));
                } else {
                    const lhs_int = try valueAsInt(env, registers[inst.arg1], diag);
                    const rhs_int = try valueAsInt(env, registers[inst.arg2], diag);
                    try setIntResult(env, registers, inst.dest, c.LLVMBuildSRem(env.builder, lhs_int, rhs_int, "rem"));
                }
            },
            .add_int => {
                if (inst.dest >= registers.len or inst.arg1 >= registers.len) return diag.failAt(0, "LLVM backend add register out of range", .{});
                if (inst.arg2 >= registers.len) {
                    registers[inst.dest] = registers[inst.arg1];
                } else if (isStructKind(registers[inst.arg1].kind) or isStructKind(registers[inst.arg2].kind)) {
                    registers[inst.dest] = if (isStructKind(registers[inst.arg1].kind)) registers[inst.arg1] else registers[inst.arg2];
                } else if (isFloatKind(registers[inst.arg1].kind) or isFloatKind(registers[inst.arg2].kind)) {
                    const lhs_f = try valueAsFloat(env, registers[inst.arg1], diag);
                    const rhs_f = try valueAsFloat(env, registers[inst.arg2], diag);
                    try setFloatResult(env, registers, inst.dest, c.LLVMBuildFAdd(env.builder, lhs_f, rhs_f, "fadd"));
                } else {
                    const lhs_int = try valueAsInt(env, registers[inst.arg1], diag);
                    const rhs_int = try valueAsInt(env, registers[inst.arg2], diag);
                    try setIntResult(env, registers, inst.dest, c.LLVMBuildAdd(env.builder, lhs_int, rhs_int, "add"));
                }
            },
            .add_float => {
                if (inst.dest >= registers.len or inst.arg1 >= registers.len or inst.arg2 >= registers.len) return diag.failAt(0, "LLVM backend fadd register out of range", .{});
                if (isStructKind(registers[inst.arg1].kind) or isStructKind(registers[inst.arg2].kind)) {
                    registers[inst.dest] = if (isStructKind(registers[inst.arg1].kind)) registers[inst.arg1] else registers[inst.arg2];
                } else {
                    const lhs_float = try valueAsFloat(env, registers[inst.arg1], diag);
                    const rhs_float = try valueAsFloat(env, registers[inst.arg2], diag);
                    try setFloatResult(env, registers, inst.dest, c.LLVMBuildFAdd(env.builder, lhs_float, rhs_float, "fadd"));
                }
            },
            .sub_int => {
                if (inst.dest >= registers.len or inst.arg1 >= registers.len or inst.arg2 >= registers.len) return diag.failAt(0, "LLVM backend sub register out of range", .{});
                if (isStructKind(registers[inst.arg1].kind) or isStructKind(registers[inst.arg2].kind)) {
                    registers[inst.dest] = if (isStructKind(registers[inst.arg1].kind)) registers[inst.arg1] else registers[inst.arg2];
                } else if (isFloatKind(registers[inst.arg1].kind) or isFloatKind(registers[inst.arg2].kind)) {
                    const lhs_f = try valueAsFloat(env, registers[inst.arg1], diag);
                    const rhs_f = try valueAsFloat(env, registers[inst.arg2], diag);
                    try setFloatResult(env, registers, inst.dest, c.LLVMBuildFSub(env.builder, lhs_f, rhs_f, "fsub"));
                } else {
                    const lhs_int = try valueAsInt(env, registers[inst.arg1], diag);
                    const rhs_int = try valueAsInt(env, registers[inst.arg2], diag);
                    try setIntResult(env, registers, inst.dest, c.LLVMBuildSub(env.builder, lhs_int, rhs_int, "sub"));
                }
            },
            .sub_float => {
                if (inst.dest >= registers.len or inst.arg1 >= registers.len or inst.arg2 >= registers.len) return diag.failAt(0, "LLVM backend fsub register out of range", .{});
                if (isStructKind(registers[inst.arg1].kind) or isStructKind(registers[inst.arg2].kind)) {
                    registers[inst.dest] = if (isStructKind(registers[inst.arg1].kind)) registers[inst.arg1] else registers[inst.arg2];
                } else {
                    const lhs_float = try valueAsFloat(env, registers[inst.arg1], diag);
                    const rhs_float = try valueAsFloat(env, registers[inst.arg2], diag);
                    try setFloatResult(env, registers, inst.dest, c.LLVMBuildFSub(env.builder, lhs_float, rhs_float, "fsub"));
                }
            },
            .div_float => {
                if (inst.dest >= registers.len or inst.arg1 >= registers.len or inst.arg2 >= registers.len) return diag.failAt(0, "LLVM backend fdiv register out of range", .{});
                if (isStructKind(registers[inst.arg1].kind) or isStructKind(registers[inst.arg2].kind)) {
                    registers[inst.dest] = if (isStructKind(registers[inst.arg1].kind)) registers[inst.arg1] else registers[inst.arg2];
                } else {
                    const lhs_float = try valueAsFloat(env, registers[inst.arg1], diag);
                    const rhs_float = try valueAsFloat(env, registers[inst.arg2], diag);
                    try setFloatResult(env, registers, inst.dest, c.LLVMBuildFDiv(env.builder, lhs_float, rhs_float, "fdiv"));
                }
            },
            .div_int => {
                if (inst.dest >= registers.len or inst.arg1 >= registers.len or inst.arg2 >= registers.len) return diag.failAt(0, "LLVM backend div register out of range", .{});
                if (isStructKind(registers[inst.arg1].kind) or isStructKind(registers[inst.arg2].kind)) {
                    registers[inst.dest] = if (isStructKind(registers[inst.arg1].kind)) registers[inst.arg1] else registers[inst.arg2];
                } else if (isFloatKind(registers[inst.arg1].kind) or isFloatKind(registers[inst.arg2].kind)) {
                    const lhs_f = try valueAsFloat(env, registers[inst.arg1], diag);
                    const rhs_f = try valueAsFloat(env, registers[inst.arg2], diag);
                    try setFloatResult(env, registers, inst.dest, c.LLVMBuildFDiv(env.builder, lhs_f, rhs_f, "fdiv"));
                } else {
                    const lhs_int = try valueAsInt(env, registers[inst.arg1], diag);
                    const rhs_int = try valueAsInt(env, registers[inst.arg2], diag);
                    try setIntResult(env, registers, inst.dest, c.LLVMBuildSDiv(env.builder, lhs_int, rhs_int, "div"));
                }
            },
            .store => {
                if (inst.arg1 >= registers.len) return diag.failAt(0, "LLVM backend store source register out of range", .{});
            },
            .load => {
                if (inst.dest >= registers.len or inst.arg1 >= registers.len) return diag.failAt(0, "LLVM backend load register out of range", .{});
                if (registers[inst.dest].kind == .int_addr) {
                    switch (registers[inst.arg1].kind) {
                        .pointer, .pointer_addr => {
                            _ = c.LLVMBuildStore(env.builder, try pointerValue(env, registers[inst.arg1], diag, "inline return ptr"), registers[inst.dest].llvm_value);
                            registers[inst.dest] = .{ .llvm_value = registers[inst.dest].llvm_value, .kind = .{ .pointer_addr = inst.dest } };
                        },
                        .float, .float_addr => {
                            _ = c.LLVMBuildStore(env.builder, try valueAsFloat(env, registers[inst.arg1], diag), registers[inst.dest].llvm_value);
                            registers[inst.dest] = .{ .llvm_value = registers[inst.dest].llvm_value, .kind = .{ .float_addr = inst.dest } };
                        },
                        .format_float, .string_addr, .calendar, .runtime_string, .string, .undefined_string, .format_int, .void_value, .type_id => registers[inst.dest] = registers[inst.arg1],
                        else => _ = c.LLVMBuildStore(env.builder, try valueAsInt(env, registers[inst.arg1], diag), registers[inst.dest].llvm_value),
                    }
                } else if (registers[inst.dest].kind == .bool_addr) {
                    _ = c.LLVMBuildStore(env.builder, try valueAsBool(env, registers[inst.arg1], diag), registers[inst.dest].llvm_value);
                } else if (registers[inst.dest].kind == .string_addr) {
                    _ = c.LLVMBuildStore(env.builder, try runtimeStringValue(env, registers[inst.arg1], diag), registers[inst.dest].llvm_value);
                } else if (registers[inst.dest].kind == .pointer_addr) {
                    _ = c.LLVMBuildStore(env.builder, try pointerValue(env, registers[inst.arg1], diag, "pointer assignment"), registers[inst.dest].llvm_value);
                } else if (registers[inst.dest].kind == .float_addr) {
                    switch (registers[inst.arg1].kind) {
                        .float, .float_addr => _ = c.LLVMBuildStore(env.builder, try valueAsFloat(env, registers[inst.arg1], diag), registers[inst.dest].llvm_value),
                        else => registers[inst.dest] = registers[inst.arg1],
                    }
                } else {
                    switch (registers[inst.arg1].kind) {
                        .int_addr, .uint_addr => {
                            const loaded = c.LLVMBuildLoad2(env.builder, env.llvm_i64, registers[inst.arg1].llvm_value, "copy_from_addr");
                            try setIntResult(env, registers, inst.dest, loaded);
                        },
                        .float_addr => {
                            const loaded = c.LLVMBuildLoad2(env.builder, env.llvm_f64, registers[inst.arg1].llvm_value, "copy_float_from_addr");
                            try setFloatResult(env, registers, inst.dest, loaded);
                        },
                        .bool_addr => {
                            const loaded = c.LLVMBuildLoad2(env.builder, c.LLVMInt1TypeInContext(env.context), registers[inst.arg1].llvm_value, "copy_bool_from_addr");
                            try setBoolResult(env, registers, inst.dest, loaded);
                        },
                        .pointer_addr => {
                            const loaded = c.LLVMBuildLoad2(env.builder, env.ptr_ty, registers[inst.arg1].llvm_value, "copy_ptr_from_addr");
                            try setPointerResult(env, registers, inst.dest, loaded);
                        },
                        else => registers[inst.dest] = registers[inst.arg1],
                    }
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
                    try setIntResult(env, registers, @intCast(inst.arg1 + 1), result);
                } else try emitPrintValue(env, registers[inst.arg1], diag);
            },
            .format_print => {
                if (inst.arg1 >= registers.len) return diag.failAt(0, "LLVM backend format_print register out of range", .{});
                if (inst.arg2 == 1) {
                    const str_ptr = try pointerValue(env, registers[inst.arg1], diag, "format_print materialized string");
                    var len_indices = [_]c.LLVMValueRef{c.LLVMConstInt(env.llvm_i64, 0, 0)};
                    const len_ptr = c.LLVMBuildGEP2(env.builder, env.llvm_i64, str_ptr, &len_indices, len_indices.len, "mat_strlen_ptr");
                    const len = c.LLVMBuildLoad2(env.builder, env.llvm_i64, len_ptr, "mat_strlen");
                    var data_indices = [_]c.LLVMValueRef{c.LLVMConstInt(env.llvm_i64, 1, 0)};
                    const data_ptr_ptr = c.LLVMBuildGEP2(env.builder, env.llvm_i64, str_ptr, &data_indices, data_indices.len, "mat_strdata_slot");
                    const data_ptr_int = c.LLVMBuildLoad2(env.builder, env.llvm_i64, data_ptr_ptr, "mat_strdata_int");
                    const data = c.LLVMBuildIntToPtr(env.builder, data_ptr_int, env.ptr_ty, "mat_strdata");
                    var args = [_]c.LLVMValueRef{ data, len };
                    _ = c.LLVMBuildCall2(env.builder, env.print_fn_ty, env.print_fn, &args, args.len, "");
                } else if (inst.arg3 == 1) {
                    const int_val = try valueAsInt(env, registers[inst.arg1], diag);
                    try emitPrintPointerOrNull(env, int_val);
                } else {
                    try emitPrintValue(env, registers[inst.arg1], diag);
                }
            },
            .format_static_int_array => {
                if (inst.arg1 >= registers.len) return diag.failAt(0, "LLVM backend static array print register out of range", .{});
                const count_val = if (inst.arg5 == 1 and inst.arg2 < registers.len)
                    try valueAsInt(env, registers[inst.arg2], diag)
                else
                    c.LLVMConstInt(env.llvm_i64, inst.arg2, 0);
                var args = [_]c.LLVMValueRef{
                    try pointerValue(env, registers[inst.arg1], diag, "static array print"),
                    count_val,
                    c.LLVMConstInt(env.llvm_i64, if (inst.arg3 != 0) inst.arg3 else 8, 0),
                };
                _ = c.LLVMBuildCall2(env.builder, env.print_static_int_array_fn_ty, env.print_static_int_array_fn, &args, args.len, "");
            },
            .format_static_float_array, .format_static_string_array, .format_static_bool_array => {
                if (inst.arg1 >= registers.len) return diag.failAt(0, "LLVM backend static array print register out of range", .{});
                const params = [_]c.LLVMTypeRef{ env.ptr_ty, env.llvm_i64 };
                const fn_ty = c.LLVMFunctionType(c.LLVMVoidTypeInContext(env.context), @constCast(&params), params.len, 0);
                const fn_name = switch (inst.opcode) {
                    .format_static_float_array => "__openjai_print_static_float_array",
                    .format_static_bool_array => "__openjai_print_static_bool_array",
                    else => "__openjai_print_static_string_array",
                };
                const fn_ref = c.LLVMGetNamedFunction(env.module, fn_name) orelse c.LLVMAddFunction(env.module, fn_name, fn_ty);
                const count_val = if (inst.arg5 == 1 and inst.arg2 < registers.len)
                    try valueAsInt(env, registers[inst.arg2], diag)
                else
                    c.LLVMConstInt(env.llvm_i64, inst.arg2, 0);
                var args = [_]c.LLVMValueRef{
                    try pointerValue(env, registers[inst.arg1], diag, "static array print"),
                    count_val,
                };
                _ = c.LLVMBuildCall2(env.builder, fn_ty, fn_ref, &args, args.len, "");
            },
            .format_int_value => {
                if (inst.dest >= registers.len or inst.arg1 >= registers.len or inst.arg2 >= registers.len or inst.arg3 >= registers.len) return diag.failAt(0, "LLVM backend format_int_value register out of range", .{});
                const source = try valueAsInt(env, registers[inst.arg1], diag);
                const base_val = try valueAsInt(env, registers[inst.arg2], diag);
                const min_digits_val = try valueAsInt(env, registers[inst.arg3], diag);
                registers[inst.dest] = .{ .llvm_value = source, .kind = .{ .format_int = .{ .base = base_val, .minimum_digits = min_digits_val } } };
            },
            .format_float_value => {
                if (inst.dest >= registers.len or inst.arg1 >= registers.len or inst.arg2 >= registers.len or inst.arg3 >= registers.len) return diag.failAt(0, "LLVM backend format_float_value register out of range", .{});
                if (isStructKind(registers[inst.arg1].kind)) {
                    registers[inst.dest] = registers[inst.arg1];
                } else {
                    const source = try valueAsFloat(env, registers[inst.arg1], diag);
                    const width_val = try valueAsInt(env, registers[inst.arg2], diag);
                    const tw_val = try valueAsInt(env, registers[inst.arg3], diag);
                    registers[inst.dest] = .{ .llvm_value = source, .kind = .{ .format_float = .{ .width = width_val, .trailing_width = tw_val, .zero_removal = inst.arg4, .mode = inst.arg5 } } };
                }
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
                    .float_addr => {
                        registers[inst.dest] = .{ .llvm_value = registers[inst.arg1].llvm_value, .kind = .pointer };
                    },
                    .pointer => {
                        const slot = buildEntryAlloca(env, current_function, env.ptr_ty, "addr_local_ptr");
                        _ = c.LLVMBuildStore(env.builder, registers[inst.arg1].llvm_value, slot);
                        registers[inst.arg1] = .{ .llvm_value = slot, .kind = .{ .pointer_addr = inst.arg1 } };
                        registers[inst.dest] = .{ .llvm_value = slot, .kind = .pointer };
                    },
                    .pointer_addr => {
                        registers[inst.dest] = .{ .llvm_value = registers[inst.arg1].llvm_value, .kind = .pointer };
                    },
                    .runtime_string => {
                        const rs = try runtimeStringValue(env, registers[inst.arg1], diag);
                        registers[inst.dest] = .{ .llvm_value = rs, .kind = .pointer };
                    },
                    .string, .string_addr => {
                        const str_struct_ty = c.LLVMArrayType(env.llvm_i64, 2);
                        const slot = buildEntryAlloca(env, current_function, str_struct_ty, "addr_local_string");
                        const rs = try runtimeStringValue(env, registers[inst.arg1], diag);
                        var src_count_idx = [_]c.LLVMValueRef{c.LLVMConstInt(env.llvm_i64, 0, 0)};
                        const count_val = c.LLVMBuildLoad2(env.builder, env.llvm_i64, c.LLVMBuildGEP2(env.builder, env.llvm_i64, rs, &src_count_idx, 1, "aol_rs_count_ptr"), "aol_rs_count");
                        var src_data_idx = [_]c.LLVMValueRef{c.LLVMConstInt(env.llvm_i64, 1, 0)};
                        const data_val = c.LLVMBuildLoad2(env.builder, env.llvm_i64, c.LLVMBuildGEP2(env.builder, env.llvm_i64, rs, &src_data_idx, 1, "aol_rs_data_ptr"), "aol_rs_data");
                        var dst_count_idx = [_]c.LLVMValueRef{c.LLVMConstInt(env.llvm_i64, 0, 0)};
                        _ = c.LLVMBuildStore(env.builder, count_val, c.LLVMBuildGEP2(env.builder, env.llvm_i64, slot, &dst_count_idx, 1, "aol_dst_count"));
                        var dst_data_idx = [_]c.LLVMValueRef{c.LLVMConstInt(env.llvm_i64, 1, 0)};
                        _ = c.LLVMBuildStore(env.builder, data_val, c.LLVMBuildGEP2(env.builder, env.llvm_i64, slot, &dst_data_idx, 1, "aol_dst_data"));
                        registers[inst.arg1] = .{ .llvm_value = slot, .kind = .runtime_string };
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
                if (inst.arg1 < env.proc_functions.len and env.proc_functions[inst.arg1] != null) {
                    registers[inst.dest] = .{ .llvm_value = c.LLVMBuildPointerCast(env.builder, env.proc_functions[inst.arg1].?, env.ptr_ty, "proc_addr"), .kind = .pointer };
                } else {
                    registers[inst.dest] = .{ .llvm_value = c.LLVMConstIntToPtr(c.LLVMConstInt(env.llvm_i64, 0, 0), env.ptr_ty), .kind = .pointer };
                }
            },
            .load_ptr => {
                if (inst.dest >= registers.len or inst.arg1 >= registers.len) return diag.failAt(0, "LLVM backend load_ptr register out of range", .{});
                switch (registers[inst.arg1].kind) {
                    .pointer, .pointer_addr, .int, .uint, .int_addr, .uint_addr, .bool, .bool_addr, .type_id => {
                        const ptr_value = switch (registers[inst.arg1].kind) {
                            .pointer => registers[inst.arg1].llvm_value,
                            .pointer_addr => c.LLVMBuildLoad2(env.builder, env.ptr_ty, registers[inst.arg1].llvm_value, "deref_load_ptr_addr"),
                            .int, .uint, .int_addr, .uint_addr, .bool, .bool_addr, .type_id => c.LLVMBuildIntToPtr(env.builder, try valueAsInt(env, registers[inst.arg1], diag), env.ptr_ty, "deref_inttoptr"),
                            else => unreachable,
                        };
                        const width = inst.arg2 & 0x7FFFFFFF;
                        const is_signed = (inst.arg2 & 0x80000000) != 0;
                        if (width == 4) {
                            const load_ty = c.LLVMInt32TypeInContext(env.context);
                            const raw = c.LLVMBuildLoad2(env.builder, load_ty, ptr_value, "deref32");
                            const extended = if (is_signed)
                                c.LLVMBuildSExt(env.builder, raw, env.llvm_i64, "sext32")
                            else
                                c.LLVMBuildZExt(env.builder, raw, env.llvm_i64, "zext32");
                            try setIntResult(env, registers, inst.dest, extended);
                        } else if (width == 2) {
                            const load_ty = c.LLVMInt16TypeInContext(env.context);
                            const raw = c.LLVMBuildLoad2(env.builder, load_ty, ptr_value, "deref16");
                            const extended = if (is_signed)
                                c.LLVMBuildSExt(env.builder, raw, env.llvm_i64, "sext16")
                            else
                                c.LLVMBuildZExt(env.builder, raw, env.llvm_i64, "zext16");
                            try setIntResult(env, registers, inst.dest, extended);
                        } else if (width == 1) {
                            const load_ty = c.LLVMInt8TypeInContext(env.context);
                            const raw = c.LLVMBuildLoad2(env.builder, load_ty, ptr_value, "deref8");
                            try setIntResult(env, registers, inst.dest, c.LLVMBuildZExt(env.builder, raw, env.llvm_i64, "zext8"));
                        } else {
                            try setIntResult(env, registers, inst.dest, c.LLVMBuildLoad2(env.builder, env.llvm_i64, ptr_value, "deref"));
                        }
                    },
                    else => {
                        registers[inst.dest] = registers[inst.arg1];
                    },
                }
            },
            .load_ptr_byte => {
                if (inst.dest >= registers.len or inst.arg1 >= registers.len) return diag.failAt(0, "LLVM backend load_ptr_byte register out of range", .{});
                const ptr_value = try pointerValue(env, registers[inst.arg1], diag, "byte pointer dereference");
                const byte = c.LLVMBuildLoad2(env.builder, c.LLVMInt8TypeInContext(env.context), ptr_value, "load_u8");
                try setIntResult(env, registers, inst.dest, c.LLVMBuildZExt(env.builder, byte, env.llvm_i64, "u8_to_i64"));
            },
            .load_ptr_float => {
                if (inst.dest >= registers.len or inst.arg1 >= registers.len) return diag.failAt(0, "LLVM backend load_ptr_float register out of range", .{});
                const ptr_value = try pointerValue(env, registers[inst.arg1], diag, "float pointer dereference");
                if (inst.arg2 == 4) {
                    const fptr = c.LLVMBuildPointerCast(env.builder, ptr_value, c.LLVMPointerType(env.llvm_f32, 0), "float_ptr");
                    const loaded = c.LLVMBuildLoad2(env.builder, env.llvm_f32, fptr, "load_f32");
                    try setFloatResult(env, registers, inst.dest, c.LLVMBuildFPExt(env.builder, loaded, env.llvm_f64, "f32_to_f64"));
                } else {
                    const fptr = c.LLVMBuildPointerCast(env.builder, ptr_value, c.LLVMPointerType(env.llvm_f64, 0), "float_ptr");
                    try setFloatResult(env, registers, inst.dest, c.LLVMBuildLoad2(env.builder, env.llvm_f64, fptr, "load_f64"));
                }
            },
            .load_ptr_string => {
                if (inst.dest >= registers.len or inst.arg1 >= registers.len) return diag.failAt(0, "LLVM backend load_ptr_string register out of range", .{});
                const ptr_value = try pointerValue(env, registers[inst.arg1], diag, "load string pointer");
                try setStringResult(env, registers, inst.dest, ptr_value);
            },
            .store_ptr => {
                if (inst.dest >= registers.len or inst.arg1 >= registers.len) return diag.failAt(0, "LLVM backend store_ptr register out of range", .{});
                const ptr_value = try pointerValue(env, registers[inst.dest], diag, "pointer store destination");
                const source = registers[inst.arg1];
                switch (source.kind) {
                    .runtime_string, .string, .string_addr => {
                        const rs = try runtimeStringValue(env, source, diag);
                        var src_count_idx = [_]c.LLVMValueRef{c.LLVMConstInt(env.llvm_i64, 0, 0)};
                        const count_val = c.LLVMBuildLoad2(env.builder, env.llvm_i64, c.LLVMBuildGEP2(env.builder, env.llvm_i64, rs, &src_count_idx, 1, "src_str_count"), "str_count");
                        var src_data_idx = [_]c.LLVMValueRef{c.LLVMConstInt(env.llvm_i64, 1, 0)};
                        const data_val = c.LLVMBuildLoad2(env.builder, env.llvm_i64, c.LLVMBuildGEP2(env.builder, env.llvm_i64, rs, &src_data_idx, 1, "src_str_data"), "str_data");
                        var dst_count_idx = [_]c.LLVMValueRef{c.LLVMConstInt(env.llvm_i64, 0, 0)};
                        _ = c.LLVMBuildStore(env.builder, count_val, c.LLVMBuildGEP2(env.builder, env.llvm_i64, ptr_value, &dst_count_idx, 1, "dst_str_count"));
                        var dst_data_idx = [_]c.LLVMValueRef{c.LLVMConstInt(env.llvm_i64, 1, 0)};
                        _ = c.LLVMBuildStore(env.builder, data_val, c.LLVMBuildGEP2(env.builder, env.llvm_i64, ptr_value, &dst_data_idx, 1, "dst_str_data"));
                    },
                    else => {
                        const stored = switch (source.kind) {
                            .int, .int_addr, .bool, .bool_addr, .type_id, .uint, .uint_addr => try valueAsInt(env, source, diag),
                            .pointer => source.llvm_value,
                            .pointer_addr => c.LLVMBuildLoad2(env.builder, env.ptr_ty, source.llvm_value, "store_src_load_ptr_addr"),
                            else => source.llvm_value,
                        };
                        const width = inst.arg2 & 0x7FFFFFFF;
                        const is_int_source = (c.LLVMGetTypeKind(c.LLVMTypeOf(stored)) == c.LLVMIntegerTypeKind);
                        if (is_int_source and width == 4) {
                            const trunc = c.LLVMBuildTrunc(env.builder, stored, c.LLVMInt32TypeInContext(env.context), "store_trunc32");
                            _ = c.LLVMBuildStore(env.builder, trunc, ptr_value);
                        } else if (is_int_source and width == 2) {
                            const trunc = c.LLVMBuildTrunc(env.builder, stored, c.LLVMInt16TypeInContext(env.context), "store_trunc16");
                            _ = c.LLVMBuildStore(env.builder, trunc, ptr_value);
                        } else if (is_int_source and width == 1) {
                            const trunc = c.LLVMBuildTrunc(env.builder, stored, c.LLVMInt8TypeInContext(env.context), "store_trunc8");
                            _ = c.LLVMBuildStore(env.builder, trunc, ptr_value);
                        } else {
                            _ = c.LLVMBuildStore(env.builder, stored, ptr_value);
                        }
                    },
                }
            },
            .store_ptr_byte => {
                if (inst.dest >= registers.len or inst.arg1 >= registers.len) return diag.failAt(0, "LLVM backend store_ptr_byte register out of range", .{});
                const base_ptr = try pointerValue(env, registers[inst.dest], diag, "byte pointer store destination");
                const source = try valueAsInt(env, registers[inst.arg1], diag);
                const byte = c.LLVMBuildTrunc(env.builder, source, c.LLVMInt8TypeInContext(env.context), "store_i64_to_u8");
                _ = c.LLVMBuildStore(env.builder, byte, base_ptr);
            },
            .store_ptr_float => {
                if (inst.dest >= registers.len or inst.arg1 >= registers.len) return diag.failAt(0, "LLVM backend store_ptr_float register out of range", .{});
                const ptr_value = try pointerValue(env, registers[inst.dest], diag, "float pointer store destination");
                if (inst.arg2 == 4) {
                    const fptr = c.LLVMBuildPointerCast(env.builder, ptr_value, c.LLVMPointerType(env.llvm_f32, 0), "store_float_ptr");
                    const value = c.LLVMBuildFPTrunc(env.builder, try valueAsFloat(env, registers[inst.arg1], diag), env.llvm_f32, "f64_to_f32");
                    _ = c.LLVMBuildStore(env.builder, value, fptr);
                } else {
                    const fptr = c.LLVMBuildPointerCast(env.builder, ptr_value, c.LLVMPointerType(env.llvm_f64, 0), "store_float_ptr");
                    _ = c.LLVMBuildStore(env.builder, try valueAsFloat(env, registers[inst.arg1], diag), fptr);
                }
            },
            .ptr_offset => {
                if (inst.dest >= registers.len or inst.arg1 >= registers.len) return diag.failAt(0, "LLVM backend ptr_offset register out of range", .{});
                const base_ptr = try pointerValue(env, registers[inst.arg1], diag, "pointer offset base");
                var indices = [_]c.LLVMValueRef{c.LLVMConstInt(env.llvm_i64, inst.arg2, 0)};
                try setPointerResult(env, registers, inst.dest, c.LLVMBuildGEP2(env.builder, c.LLVMInt8TypeInContext(env.context), base_ptr, &indices, indices.len, "ptr_offset"));
            },
            .ptr_offset_reg => {
                if (inst.dest >= registers.len or inst.arg1 >= registers.len or inst.arg2 >= registers.len) return diag.failAt(0, "LLVM backend ptr_offset_reg register out of range", .{});
                const base_ptr = try pointerValue(env, registers[inst.arg1], diag, "pointer offset base");
                const offset = try valueAsInt(env, registers[inst.arg2], diag);
                var indices = [_]c.LLVMValueRef{offset};
                try setPointerResult(env, registers, inst.dest, c.LLVMBuildGEP2(env.builder, c.LLVMInt8TypeInContext(env.context), base_ptr, &indices, indices.len, "ptr_offset_reg"));
            },
            .alloc_heap => {
                if (inst.dest >= registers.len) return diag.failAt(0, "LLVM backend alloc_heap destination register out of range", .{});
                var args = [_]c.LLVMValueRef{c.LLVMConstInt(env.llvm_i64, inst.arg1, 0)};
                const result = c.LLVMBuildCall2(env.builder, env.alloc_fn_ty, env.alloc_fn, &args, args.len, "heap_ptr");
                const slot = buildEntryAlloca(env, c.LLVMGetBasicBlockParent(c.LLVMGetInsertBlock(env.builder)), env.ptr_ty, "ptr_reg");
                _ = c.LLVMBuildStore(env.builder, result, slot);
                registers[inst.dest] = .{ .llvm_value = slot, .kind = .{ .pointer_addr = inst.dest } };
            },
            .alloc_heap_reg => {
                if (inst.dest >= registers.len or inst.arg1 >= registers.len) return diag.failAt(0, "LLVM backend alloc_heap_reg register out of range", .{});
                var args = [_]c.LLVMValueRef{try valueAsInt(env, registers[inst.arg1], diag)};
                const result = c.LLVMBuildCall2(env.builder, env.alloc_fn_ty, env.alloc_fn, &args, args.len, "heap_ptr");
                try setPointerResult(env, registers, inst.dest, result);
            },
            .alloc_heap_owned => {
                if (inst.dest >= registers.len or inst.arg1 >= registers.len or inst.arg2 >= registers.len) return diag.failAt(0, "LLVM backend alloc_heap_owned register out of range", .{});
                const params = [_]c.LLVMTypeRef{ env.llvm_i64, env.ptr_ty };
                const fn_ty = c.LLVMFunctionType(env.ptr_ty, @constCast(&params), params.len, 0);
                const fn_ref = c.LLVMGetNamedFunction(env.module, "__openjai_alloc_owned") orelse c.LLVMAddFunction(env.module, "__openjai_alloc_owned", fn_ty);
                var args = [_]c.LLVMValueRef{
                    try valueAsInt(env, registers[inst.arg1], diag),
                    try pointerValue(env, registers[inst.arg2], diag, "owned allocator"),
                };
                try setPointerResult(env, registers, inst.dest, c.LLVMBuildCall2(env.builder, fn_ty, fn_ref, &args, args.len, "owned_heap_ptr"));
            },
            .allocator_proc_call => {
                if (inst.dest >= registers.len or inst.arg1 >= registers.len) return diag.failAt(0, "LLVM backend allocator_proc_call register out of range", .{});
                if (inst.arg3 + 5 > env.program.call_args.items.len) return diag.failAt(0, "LLVM backend allocator proc argument table out of range", .{});
                const params = [_]c.LLVMTypeRef{ env.ptr_ty, env.llvm_i64, env.llvm_i64, env.llvm_i64, env.ptr_ty, env.ptr_ty };
                const fn_ty = c.LLVMFunctionType(env.ptr_ty, @constCast(&params), params.len, 0);
                const fn_ref = c.LLVMGetNamedFunction(env.module, "__openjai_allocator_proc_call") orelse c.LLVMAddFunction(env.module, "__openjai_allocator_proc_call", fn_ty);
                const mode_reg = env.program.call_args.items[inst.arg3];
                const size_reg = env.program.call_args.items[inst.arg3 + 1];
                const old_size_reg = env.program.call_args.items[inst.arg3 + 2];
                const old_memory_reg = env.program.call_args.items[inst.arg3 + 3];
                const data_reg = env.program.call_args.items[inst.arg3 + 4];
                var args = [_]c.LLVMValueRef{
                    try pointerValue(env, registers[inst.arg1], diag, "allocator proc base"),
                    try valueAsInt(env, registers[mode_reg], diag),
                    try valueAsInt(env, registers[size_reg], diag),
                    try valueAsInt(env, registers[old_size_reg], diag),
                    try pointerValue(env, registers[old_memory_reg], diag, "allocator old memory"),
                    try pointerValue(env, registers[data_reg], diag, "allocator data"),
                };
                try setPointerResult(env, registers, inst.dest, c.LLVMBuildCall2(env.builder, fn_ty, fn_ref, &args, args.len, "allocator_proc_result"));
            },
            .allocator_owns => {
                if (inst.dest >= registers.len or inst.arg1 >= registers.len or inst.arg2 >= registers.len) return diag.failAt(0, "LLVM backend allocator_owns register out of range", .{});
                const params = [_]c.LLVMTypeRef{ env.ptr_ty, env.ptr_ty };
                const fn_ty = c.LLVMFunctionType(c.LLVMInt1TypeInContext(env.context), @constCast(&params), params.len, 0);
                const fn_ref = c.LLVMGetNamedFunction(env.module, "__openjai_allocator_owns") orelse c.LLVMAddFunction(env.module, "__openjai_allocator_owns", fn_ty);
                var args = [_]c.LLVMValueRef{
                    try pointerValue(env, registers[inst.arg1], diag, "allocator owns base"),
                    try pointerValue(env, registers[inst.arg2], diag, "allocator owns memory"),
                };
                try setBoolResult(env, registers, inst.dest, c.LLVMBuildCall2(env.builder, fn_ty, fn_ref, &args, args.len, "allocator_owns"));
            },
            .allocator_cap_flags => {
                if (inst.dest >= registers.len or inst.arg1 >= registers.len) return diag.failAt(0, "LLVM backend allocator_cap_flags register out of range", .{});
                const params = [_]c.LLVMTypeRef{env.ptr_ty};
                const fn_ty = c.LLVMFunctionType(env.llvm_i64, @constCast(&params), params.len, 0);
                const fn_ref = c.LLVMGetNamedFunction(env.module, "__openjai_allocator_cap_flags") orelse c.LLVMAddFunction(env.module, "__openjai_allocator_cap_flags", fn_ty);
                var args = [_]c.LLVMValueRef{try pointerValue(env, registers[inst.arg1], diag, "allocator capabilities")};
                try setIntResult(env, registers, inst.dest, c.LLVMBuildCall2(env.builder, fn_ty, fn_ref, &args, args.len, "allocator_caps"));
            },
            .allocator_cap_name => {
                if (inst.dest >= registers.len or inst.arg1 >= registers.len) return diag.failAt(0, "LLVM backend allocator_cap_name register out of range", .{});
                const params = [_]c.LLVMTypeRef{env.ptr_ty};
                const fn_ty = c.LLVMFunctionType(env.ptr_ty, @constCast(&params), params.len, 0);
                const fn_ref = c.LLVMGetNamedFunction(env.module, "__openjai_allocator_cap_name") orelse c.LLVMAddFunction(env.module, "__openjai_allocator_cap_name", fn_ty);
                var args = [_]c.LLVMValueRef{try pointerValue(env, registers[inst.arg1], diag, "allocator capability name")};
                try setStringResult(env, registers, inst.dest, c.LLVMBuildCall2(env.builder, fn_ty, fn_ref, &args, args.len, "allocator_name"));
            },
            .pool_get => {
                if (inst.dest >= registers.len or inst.arg1 >= registers.len or inst.arg2 >= registers.len) return diag.failAt(0, "LLVM backend pool_get register out of range", .{});
                const params = [_]c.LLVMTypeRef{ env.ptr_ty, env.llvm_i64, env.llvm_i64 };
                const fn_ty = c.LLVMFunctionType(env.ptr_ty, @constCast(&params), params.len, 0);
                const fn_ref = c.LLVMGetNamedFunction(env.module, "__openjai_pool_get") orelse c.LLVMAddFunction(env.module, "__openjai_pool_get", fn_ty);
                var args = [_]c.LLVMValueRef{
                    try pointerValue(env, registers[inst.arg1], diag, "pool pointer"),
                    try valueAsInt(env, registers[inst.arg2], diag),
                    c.LLVMConstInt(env.llvm_i64, inst.arg3, 0),
                };
                try setPointerResult(env, registers, inst.dest, c.LLVMBuildCall2(env.builder, fn_ty, fn_ref, &args, args.len, "pool_get"));
            },
            .pool_release => {
                if (inst.arg1 >= registers.len) return diag.failAt(0, "LLVM backend pool release register out of range", .{});
                const params = [_]c.LLVMTypeRef{env.ptr_ty};
                const fn_ty = c.LLVMFunctionType(c.LLVMVoidTypeInContext(env.context), @constCast(&params), params.len, 0);
                const fn_ref = c.LLVMGetNamedFunction(env.module, "__openjai_pool_release") orelse c.LLVMAddFunction(env.module, "__openjai_pool_release", fn_ty);
                var args = [_]c.LLVMValueRef{try pointerValue(env, registers[inst.arg1], diag, "pool pointer")};
                _ = c.LLVMBuildCall2(env.builder, fn_ty, fn_ref, &args, args.len, "");
            },
            .pool_reset => {
                if (inst.arg1 >= registers.len) return diag.failAt(0, "LLVM backend pool reset register out of range", .{});
                const params = [_]c.LLVMTypeRef{ env.ptr_ty, env.llvm_i64 };
                const fn_ty = c.LLVMFunctionType(c.LLVMVoidTypeInContext(env.context), @constCast(&params), params.len, 0);
                const fn_ref = c.LLVMGetNamedFunction(env.module, "__openjai_pool_reset") orelse c.LLVMAddFunction(env.module, "__openjai_pool_reset", fn_ty);
                var args = [_]c.LLVMValueRef{
                    try pointerValue(env, registers[inst.arg1], diag, "pool pointer"),
                    c.LLVMConstInt(env.llvm_i64, inst.arg2, 0),
                };
                _ = c.LLVMBuildCall2(env.builder, fn_ty, fn_ref, &args, args.len, "");
            },
            .pool_bytes_left => {
                if (inst.dest >= registers.len or inst.arg1 >= registers.len) return diag.failAt(0, "LLVM backend pool_bytes_left register out of range", .{});
                const params = [_]c.LLVMTypeRef{env.ptr_ty};
                const fn_ty = c.LLVMFunctionType(env.llvm_i64, @constCast(&params), params.len, 0);
                const fn_ref = c.LLVMGetNamedFunction(env.module, "__openjai_pool_bytes_left") orelse c.LLVMAddFunction(env.module, "__openjai_pool_bytes_left", fn_ty);
                var args = [_]c.LLVMValueRef{try pointerValue(env, registers[inst.arg1], diag, "pool pointer")};
                try setIntResult(env, registers, inst.dest, c.LLVMBuildCall2(env.builder, fn_ty, fn_ref, &args, args.len, "pool_bytes_left"));
            },
            .new_array => {
                if (inst.dest >= registers.len) return diag.failAt(0, "LLVM backend new_array destination register out of range", .{});
                var args = [_]c.LLVMValueRef{
                    c.LLVMConstInt(env.llvm_i64, inst.arg1, 0),
                    c.LLVMConstInt(env.llvm_i64, inst.arg2, 0),
                    c.LLVMConstInt(env.llvm_i64, inst.arg3, 0),
                };
                try setPointerResult(env, registers, inst.dest, c.LLVMBuildCall2(env.builder, env.new_array_fn_ty, env.new_array_fn, &args, args.len, "new_array"));
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
                const item_val = registers[inst.arg2];
                const item_ptr = if (inst.arg4 != 0)
                    try pointerValue(env, item_val, diag, "array_add struct item")
                else if (isStringValue(item_val) and inst.arg3 >= 16) blk: {
                    const current_function = c.LLVMGetBasicBlockParent(c.LLVMGetInsertBlock(env.builder));
                    const pair_ty = c.LLVMArrayType(env.llvm_i64, 2);
                    const str_slot = buildEntryAlloca(env, current_function, pair_ty, "array_add_str_pair");
                    const parts = try stringParts(env, item_val, diag);
                    var len_idx = [_]c.LLVMValueRef{ c.LLVMConstInt(env.llvm_i64, 0, 0), c.LLVMConstInt(env.llvm_i64, 0, 0) };
                    _ = c.LLVMBuildStore(env.builder, parts.len, c.LLVMBuildGEP2(env.builder, pair_ty, str_slot, &len_idx, len_idx.len, "aa_str_len_slot"));
                    var data_idx = [_]c.LLVMValueRef{ c.LLVMConstInt(env.llvm_i64, 0, 0), c.LLVMConstInt(env.llvm_i64, 1, 0) };
                    _ = c.LLVMBuildStore(env.builder, c.LLVMBuildPtrToInt(env.builder, parts.data, env.llvm_i64, "aa_str_data_int"), c.LLVMBuildGEP2(env.builder, pair_ty, str_slot, &data_idx, data_idx.len, "aa_str_data_slot"));
                    break :blk c.LLVMBuildPointerCast(env.builder, str_slot, env.ptr_ty, "aa_str_pair_ptr");
                } else
                    try valueAddress(env, item_val, diag);
                var args = [_]c.LLVMValueRef{ slot_ptr, item_ptr, c.LLVMConstInt(env.llvm_i64, inst.arg3, 0) };
                const result = c.LLVMBuildCall2(env.builder, env.array_add_fn_ty, env.array_add_fn, &args, args.len, "array_item");
                try setPointerResult(env, registers, inst.dest, result);
            },
            .array_add_spread => {
                if (inst.dest >= registers.len or inst.arg1 >= registers.len or inst.arg2 >= registers.len) return diag.failAt(0, "LLVM backend array_add_spread register out of range", .{});
                const spread_params = [_]c.LLVMTypeRef{ env.ptr_ty, env.ptr_ty, env.llvm_i64, env.llvm_i64 };
                const spread_void_ty = c.LLVMVoidTypeInContext(env.context);
                const spread_fn_ty = c.LLVMFunctionType(spread_void_ty, @constCast(&spread_params), spread_params.len, 0);
                const spread_fn = c.LLVMGetNamedFunction(env.module, "__openjai_array_add_spread") orelse c.LLVMAddFunction(env.module, "__openjai_array_add_spread", spread_fn_ty);
                const slot_ptr = try pointerValue(env, registers[inst.dest], diag, "array_add_spread slot");
                const src_ptr = try pointerValue(env, registers[inst.arg1], diag, "array_add_spread src");
                const count_val = try valueAsInt(env, registers[inst.arg2], diag);
                var spread_args = [_]c.LLVMValueRef{ slot_ptr, src_ptr, count_val, c.LLVMConstInt(env.llvm_i64, inst.arg3, 0) };
                _ = c.LLVMBuildCall2(env.builder, spread_fn_ty, spread_fn, &spread_args, spread_args.len, "");
            },
            .array_insert_at => {
                if (inst.arg1 >= registers.len or inst.arg2 >= registers.len or inst.arg3 >= registers.len) return diag.failAt(0, "LLVM backend array_insert_at register out of range", .{});
                const params = [_]c.LLVMTypeRef{ env.ptr_ty, env.ptr_ty, env.llvm_i64, env.llvm_i64 };
                const void_ty = c.LLVMVoidTypeInContext(env.context);
                const fn_ty = c.LLVMFunctionType(void_ty, @constCast(&params), params.len, 0);
                const fn_ref = c.LLVMGetNamedFunction(env.module, "__openjai_array_insert_at") orelse c.LLVMAddFunction(env.module, "__openjai_array_insert_at", fn_ty);
                const slot_ptr = try pointerValue(env, registers[inst.arg1], diag, "array_insert_at array");
                const item_ptr = try valueAddress(env, registers[inst.arg2], diag);
                const index_val = try valueAsInt(env, registers[inst.arg3], diag);
                var args = [_]c.LLVMValueRef{ slot_ptr, item_ptr, index_val, c.LLVMConstInt(env.llvm_i64, @max(inst.arg4, 1), 0) };
                _ = c.LLVMBuildCall2(env.builder, fn_ty, fn_ref, &args, args.len, "");
            },
            .array_pop => {
                if (inst.dest >= registers.len or inst.arg1 >= registers.len) return diag.failAt(0, "LLVM backend array_pop register out of range", .{});
                const params = [_]c.LLVMTypeRef{ env.ptr_ty, env.llvm_i64 };
                const fn_ty = c.LLVMFunctionType(env.ptr_ty, @constCast(&params), params.len, 0);
                const fn_ref = c.LLVMGetNamedFunction(env.module, "__openjai_array_pop") orelse c.LLVMAddFunction(env.module, "__openjai_array_pop", fn_ty);
                var args = [_]c.LLVMValueRef{ try pointerValue(env, registers[inst.arg1], diag, "array_pop array"), c.LLVMConstInt(env.llvm_i64, inst.arg3, 0) };
                const item_ptr = c.LLVMBuildCall2(env.builder, fn_ty, fn_ref, &args, args.len, "array_pop");
                switch (inst.arg4) {
                    1 => try setPointerResult(env, registers, inst.dest, item_ptr),
                    2 => try setStringResult(env, registers, inst.dest, c.LLVMBuildLoad2(env.builder, env.ptr_ty, item_ptr, "array_pop_string")),
                    else => if (inst.arg3 == 1) {
                        const byte = c.LLVMBuildLoad2(env.builder, c.LLVMInt8TypeInContext(env.context), item_ptr, "array_pop_u8");
                        try setIntResult(env, registers, inst.dest, c.LLVMBuildZExt(env.builder, byte, env.llvm_i64, "array_pop_u8_zext"));
                    } else {
                        try setIntResult(env, registers, inst.dest, c.LLVMBuildLoad2(env.builder, env.llvm_i64, item_ptr, "array_pop_int"));
                    },
                }
            },
            .array_reset => {
                if (inst.arg1 >= registers.len) return diag.failAt(0, "LLVM backend array_reset register out of range", .{});
                const params = [_]c.LLVMTypeRef{env.ptr_ty};
                const fn_ty = c.LLVMFunctionType(c.LLVMVoidTypeInContext(env.context), @constCast(&params), params.len, 0);
                const fn_ref = c.LLVMGetNamedFunction(env.module, "__openjai_array_reset") orelse c.LLVMAddFunction(env.module, "__openjai_array_reset", fn_ty);
                var args = [_]c.LLVMValueRef{try pointerValue(env, registers[inst.arg1], diag, "array_reset array")};
                _ = c.LLVMBuildCall2(env.builder, fn_ty, fn_ref, &args, args.len, "");
            },
            .array_reserve => {
                if (inst.arg1 >= registers.len or inst.arg2 >= registers.len) return diag.failAt(0, "LLVM backend array_reserve register out of range", .{});
                const params = [_]c.LLVMTypeRef{ env.ptr_ty, env.llvm_i64, env.llvm_i64 };
                const fn_ty = c.LLVMFunctionType(c.LLVMVoidTypeInContext(env.context), @constCast(&params), params.len, 0);
                const fn_ref = c.LLVMGetNamedFunction(env.module, "__openjai_array_reserve") orelse c.LLVMAddFunction(env.module, "__openjai_array_reserve", fn_ty);
                var args = [_]c.LLVMValueRef{ try pointerValue(env, registers[inst.arg1], diag, "array_reserve array"), try valueAsInt(env, registers[inst.arg2], diag), c.LLVMConstInt(env.llvm_i64, inst.arg3, 0) };
                _ = c.LLVMBuildCall2(env.builder, fn_ty, fn_ref, &args, args.len, "");
            },
            .array_ordered_remove_by_index => {
                if (inst.arg1 >= registers.len or inst.arg2 >= registers.len) return diag.failAt(0, "LLVM backend array_ordered_remove_by_index register out of range", .{});
                const params = [_]c.LLVMTypeRef{ env.ptr_ty, env.llvm_i64, env.llvm_i64 };
                const fn_ty = c.LLVMFunctionType(c.LLVMVoidTypeInContext(env.context), @constCast(&params), params.len, 0);
                const fn_ref = c.LLVMGetNamedFunction(env.module, "__openjai_array_ordered_remove_by_index") orelse c.LLVMAddFunction(env.module, "__openjai_array_ordered_remove_by_index", fn_ty);
                var args = [_]c.LLVMValueRef{ try pointerValue(env, registers[inst.arg1], diag, "array_ordered_remove_by_index array"), try valueAsInt(env, registers[inst.arg2], diag), c.LLVMConstInt(env.llvm_i64, inst.arg3, 0) };
                _ = c.LLVMBuildCall2(env.builder, fn_ty, fn_ref, &args, args.len, "");
            },
            .array_unordered_remove_by_index => {
                if (inst.arg1 >= registers.len or inst.arg2 >= registers.len) return diag.failAt(0, "LLVM backend array_unordered_remove_by_index register out of range", .{});
                const params = [_]c.LLVMTypeRef{ env.ptr_ty, env.llvm_i64, env.llvm_i64 };
                const fn_ty = c.LLVMFunctionType(c.LLVMVoidTypeInContext(env.context), @constCast(&params), params.len, 0);
                const fn_ref = c.LLVMGetNamedFunction(env.module, "__openjai_array_unordered_remove_by_index") orelse c.LLVMAddFunction(env.module, "__openjai_array_unordered_remove_by_index", fn_ty);
                var args = [_]c.LLVMValueRef{ try pointerValue(env, registers[inst.arg1], diag, "array_unordered_remove_by_index array"), try valueAsInt(env, registers[inst.arg2], diag), c.LLVMConstInt(env.llvm_i64, inst.arg3, 0) };
                _ = c.LLVMBuildCall2(env.builder, fn_ty, fn_ref, &args, args.len, "");
            },
            .array_find => {
                if (inst.dest >= registers.len or inst.arg1 >= registers.len or inst.arg2 >= registers.len) return diag.failAt(0, "LLVM backend array_find register out of range", .{});
                const params = [_]c.LLVMTypeRef{ env.ptr_ty, env.ptr_ty, env.llvm_i64 };
                const fn_ty = c.LLVMFunctionType(env.llvm_i64, @constCast(&params), params.len, 0);
                const fn_ref = c.LLVMGetNamedFunction(env.module, "__openjai_array_find") orelse c.LLVMAddFunction(env.module, "__openjai_array_find", fn_ty);
                const item_ptr = if (inst.arg4 != 0) try pointerValue(env, registers[inst.arg2], diag, "array_find struct item") else try valueAddress(env, registers[inst.arg2], diag);
                var args = [_]c.LLVMValueRef{ try pointerValue(env, registers[inst.arg1], diag, "array_find array"), item_ptr, c.LLVMConstInt(env.llvm_i64, inst.arg3, 0) };
                const found_index = c.LLVMBuildCall2(env.builder, fn_ty, fn_ref, &args, args.len, "array_find");
                const found_bool = c.LLVMBuildICmp(env.builder, c.LLVMIntSGE, found_index, c.LLVMConstInt(env.llvm_i64, 0, 0), "found");
                try setBoolResult(env, registers, inst.dest, found_bool);
                if (inst.arg5 != 0 and inst.arg5 < registers.len) {
                    try setIntResult(env, registers, inst.arg5, found_index);
                }
            },
            .static_array_find => {
                if (inst.dest >= registers.len or inst.arg1 >= registers.len or inst.arg2 >= registers.len) return diag.failAt(0, "LLVM backend static_array_find register out of range", .{});
                const params = [_]c.LLVMTypeRef{ env.ptr_ty, env.llvm_i64, env.ptr_ty, env.llvm_i64 };
                const fn_ty = c.LLVMFunctionType(env.llvm_i64, @constCast(&params), params.len, 0);
                const fn_ref = c.LLVMGetNamedFunction(env.module, "__openjai_static_array_find") orelse c.LLVMAddFunction(env.module, "__openjai_static_array_find", fn_ty);
                const item_ptr = try valueAddress(env, registers[inst.arg2], diag);
                var args = [_]c.LLVMValueRef{ try pointerValue(env, registers[inst.arg1], diag, "static_array_find data"), c.LLVMConstInt(env.llvm_i64, inst.arg4, 0), item_ptr, c.LLVMConstInt(env.llvm_i64, inst.arg3, 0) };
                const found_index = c.LLVMBuildCall2(env.builder, fn_ty, fn_ref, &args, args.len, "static_array_find");
                const found_bool = c.LLVMBuildICmp(env.builder, c.LLVMIntSGE, found_index, c.LLVMConstInt(env.llvm_i64, 0, 0), "found");
                try setBoolResult(env, registers, inst.dest, found_bool);
                if (inst.arg5 != 0 and inst.arg5 < registers.len) {
                    try setIntResult(env, registers, inst.arg5, found_index);
                }
            },
            .array_copy => {
                if (inst.dest >= registers.len or inst.arg1 >= registers.len) return diag.failAt(0, "LLVM backend array_copy register out of range", .{});
                if (inst.arg5 != 0) {
                    if (inst.arg2 >= registers.len) return diag.failAt(0, "LLVM backend array_copy destination register out of range", .{});
                    const params = [_]c.LLVMTypeRef{ env.ptr_ty, env.ptr_ty, env.llvm_i64 };
                    const fn_ty = c.LLVMFunctionType(env.ptr_ty, @constCast(&params), params.len, 0);
                    const fn_ref = c.LLVMGetNamedFunction(env.module, "__openjai_array_copy_to") orelse c.LLVMAddFunction(env.module, "__openjai_array_copy_to", fn_ty);
                    var args = [_]c.LLVMValueRef{ try pointerValue(env, registers[inst.arg2], diag, "array_copy destination"), try pointerValue(env, registers[inst.arg1], diag, "array_copy source"), c.LLVMConstInt(env.llvm_i64, inst.arg3, 0) };
                    try setPointerResult(env, registers, inst.dest, c.LLVMBuildCall2(env.builder, fn_ty, fn_ref, &args, args.len, "array_copy_to"));
                } else {
                    const params = [_]c.LLVMTypeRef{ env.ptr_ty, env.llvm_i64 };
                    const fn_ty = c.LLVMFunctionType(env.ptr_ty, @constCast(&params), params.len, 0);
                    const fn_ref = c.LLVMGetNamedFunction(env.module, "__openjai_array_copy") orelse c.LLVMAddFunction(env.module, "__openjai_array_copy", fn_ty);
                    var args = [_]c.LLVMValueRef{ try pointerValue(env, registers[inst.arg1], diag, "array_copy source"), c.LLVMConstInt(env.llvm_i64, inst.arg3, 0) };
                    try setPointerResult(env, registers, inst.dest, c.LLVMBuildCall2(env.builder, fn_ty, fn_ref, &args, args.len, "array_copy"));
                }
            },
            .sort_array => {
                if (inst.dest >= registers.len or inst.arg1 >= registers.len) return diag.failAt(0, "LLVM backend sort_array register out of range", .{});
                if (inst.arg5 == 0) {
                    const dyn_params = [_]c.LLVMTypeRef{env.ptr_ty};
                    const dyn_fn_ty = c.LLVMFunctionType(c.LLVMVoidTypeInContext(env.context), @constCast(&dyn_params), dyn_params.len, 0);
                    const dyn_fn_name = switch (inst.arg4) {
                        0 => "__openjai_sort_dynamic_i64",
                        1 => "__openjai_sort_dynamic_f64",
                        2 => "__openjai_sort_dynamic_strings",
                        else => return diag.failAt(0, "LLVM backend sort_array has unknown element kind {d}", .{inst.arg4}),
                    };
                    const dyn_fn_ref = c.LLVMGetNamedFunction(env.module, dyn_fn_name) orelse c.LLVMAddFunction(env.module, dyn_fn_name, dyn_fn_ty);
                    var dyn_args = [_]c.LLVMValueRef{try pointerValue(env, registers[inst.arg1], diag, "sort dynamic array")};
                    _ = c.LLVMBuildCall2(env.builder, dyn_fn_ty, dyn_fn_ref, &dyn_args, dyn_args.len, "");
                    registers[inst.dest] = registers[inst.arg1];
                } else if (inst.arg5 == 2) {
                    const params = [_]c.LLVMTypeRef{ env.ptr_ty, env.llvm_i64 };
                    const fn_ty = c.LLVMFunctionType(c.LLVMVoidTypeInContext(env.context), @constCast(&params), params.len, 0);
                    const fn_name = switch (inst.arg4) {
                        0 => "__openjai_sort_i64",
                        1 => "__openjai_sort_f64",
                        2 => "__openjai_sort_runtime_strings",
                        else => return diag.failAt(0, "LLVM backend sort_array has unknown element kind {d}", .{inst.arg4}),
                    };
                    const fn_ref = c.LLVMGetNamedFunction(env.module, fn_name) orelse c.LLVMAddFunction(env.module, fn_name, fn_ty);
                    const slice_ptr = try pointerValue(env, registers[inst.arg1], diag, "sort slice");
                    const count_val = c.LLVMBuildLoad2(env.builder, env.llvm_i64, slice_ptr, "slice_count");
                    var gep_indices = [_]c.LLVMValueRef{c.LLVMConstInt(env.llvm_i64, 8, 0)};
                    const data_gep = c.LLVMBuildGEP2(env.builder, c.LLVMInt8TypeInContext(env.context), slice_ptr, &gep_indices, 1, "slice_data_field");
                    const data_val = c.LLVMBuildLoad2(env.builder, env.ptr_ty, data_gep, "slice_data");
                    var args = [_]c.LLVMValueRef{ data_val, count_val };
                    _ = c.LLVMBuildCall2(env.builder, fn_ty, fn_ref, &args, args.len, "");
                    registers[inst.dest] = registers[inst.arg1];
                } else {
                    const params = [_]c.LLVMTypeRef{ env.ptr_ty, env.llvm_i64 };
                    const fn_ty = c.LLVMFunctionType(c.LLVMVoidTypeInContext(env.context), @constCast(&params), params.len, 0);
                    const fn_name = switch (inst.arg4) {
                        0 => "__openjai_sort_i64",
                        1 => "__openjai_sort_f64",
                        2 => "__openjai_sort_runtime_strings",
                        else => return diag.failAt(0, "LLVM backend sort_array has unknown element kind {d}", .{inst.arg4}),
                    };
                    const fn_ref = c.LLVMGetNamedFunction(env.module, fn_name) orelse c.LLVMAddFunction(env.module, fn_name, fn_ty);
                    var args = [_]c.LLVMValueRef{
                        try pointerValue(env, registers[inst.arg1], diag, "sort array"),
                        c.LLVMConstInt(env.llvm_i64, inst.arg2, 0),
                    };
                    _ = c.LLVMBuildCall2(env.builder, fn_ty, fn_ref, &args, args.len, "");
                    registers[inst.dest] = registers[inst.arg1];
                }
            },
            .array_free => {
                if (inst.arg1 >= registers.len) return diag.failAt(0, "LLVM backend array_free register out of range", .{});
                const array_ptr = try pointerValue(env, registers[inst.arg1], diag, "array_free array");
                var args = [_]c.LLVMValueRef{array_ptr};
                _ = c.LLVMBuildCall2(env.builder, env.array_free_fn_ty, env.array_free_fn, &args, args.len, "");
            },
            .array_count => {
                if (inst.dest >= registers.len or inst.arg1 >= registers.len) return diag.failAt(0, "LLVM backend array_count register out of range", .{});
                if (inst.arg5 == 1) {
                    const view_ptr = try pointerValue(env, registers[inst.arg1], diag, "view_count base");
                    try setIntResult(env, registers, inst.dest, c.LLVMBuildLoad2(env.builder, env.llvm_i64, view_ptr, "view_count"));
                } else {
                    var args = [_]c.LLVMValueRef{try pointerValue(env, registers[inst.arg1], diag, "array_count header")};
                    try setIntResult(env, registers, inst.dest, c.LLVMBuildCall2(env.builder, env.array_count_fn_ty, env.array_count_fn, &args, args.len, "array_count"));
                }
            },
            .array_data => {
                if (inst.dest >= registers.len or inst.arg1 >= registers.len) return diag.failAt(0, "LLVM backend array_data register out of range", .{});
                if (inst.arg5 == 1) {
                    const view_ptr = try pointerValue(env, registers[inst.arg1], diag, "view_data base");
                    var data_gep_idx = [_]c.LLVMValueRef{c.LLVMConstInt(env.llvm_i64, 8, 0)};
                    const data_addr = c.LLVMBuildGEP2(env.builder, c.LLVMInt8TypeInContext(env.context), view_ptr, &data_gep_idx, 1, "view_data_addr");
                    try setPointerResult(env, registers, inst.dest, c.LLVMBuildLoad2(env.builder, env.ptr_ty, data_addr, "view_data"));
                } else {
                    var args = [_]c.LLVMValueRef{try pointerValue(env, registers[inst.arg1], diag, "array_data header")};
                    try setPointerResult(env, registers, inst.dest, c.LLVMBuildCall2(env.builder, env.array_data_fn_ty, env.array_data_fn, &args, args.len, "array_data"));
                }
            },
            .array_index => {
                if (inst.dest >= registers.len or inst.arg1 >= registers.len or inst.arg2 >= registers.len) return diag.failAt(0, "LLVM backend array_index register out of range", .{});
                const item_ptr = if (inst.arg5 == 1) blk: {
                    const base = try pointerValue(env, registers[inst.arg1], diag, "inline_array_index base");
                    const idx = try valueAsInt(env, registers[inst.arg2], diag);
                    const byte_offset = c.LLVMBuildMul(env.builder, idx, c.LLVMConstInt(env.llvm_i64, inst.arg3, 0), "byte_off");
                    const base_as_bytes = c.LLVMBuildPointerCast(env.builder, base, env.ptr_ty, "base_bytes");
                    var gep_indices = [_]c.LLVMValueRef{byte_offset};
                    break :blk c.LLVMBuildGEP2(env.builder, c.LLVMInt8TypeInContext(env.context), base_as_bytes, &gep_indices, 1, "inline_elem");
                } else if (inst.arg5 == 2) blk: {
                    const view_ptr = try pointerValue(env, registers[inst.arg1], diag, "view_array_index base");
                    var data_gep_idx = [_]c.LLVMValueRef{c.LLVMConstInt(env.llvm_i64, 8, 0)};
                    const data_addr = c.LLVMBuildGEP2(env.builder, c.LLVMInt8TypeInContext(env.context), view_ptr, &data_gep_idx, 1, "view_data_addr");
                    const data_ptr = c.LLVMBuildLoad2(env.builder, env.ptr_ty, data_addr, "view_data_ptr");
                    const idx = try valueAsInt(env, registers[inst.arg2], diag);
                    const byte_offset = c.LLVMBuildMul(env.builder, idx, c.LLVMConstInt(env.llvm_i64, inst.arg3, 0), "view_byte_off");
                    var elem_gep_idx = [_]c.LLVMValueRef{byte_offset};
                    break :blk c.LLVMBuildGEP2(env.builder, c.LLVMInt8TypeInContext(env.context), data_ptr, &elem_gep_idx, 1, "view_elem");
                } else blk: {
                    var args = [_]c.LLVMValueRef{
                        try pointerValue(env, registers[inst.arg1], diag, "array_index header"),
                        try valueAsInt(env, registers[inst.arg2], diag),
                        c.LLVMConstInt(env.llvm_i64, inst.arg3, 0),
                    };
                    break :blk c.LLVMBuildCall2(env.builder, env.array_index_fn_ty, env.array_index_fn, &args, args.len, "array_index");
                };
                switch (inst.arg4) {
                    1 => try setPointerResult(env, registers, inst.dest, item_ptr),
                    2 => try setStringResult(env, registers, inst.dest, item_ptr),
                    3 => if (inst.arg3 == 4) {
                        const loaded = c.LLVMBuildLoad2(env.builder, env.llvm_f32, item_ptr, "array_f32");
                        try setFloatResult(env, registers, inst.dest, c.LLVMBuildFPExt(env.builder, loaded, env.llvm_f64, "array_f32_ext"));
                    } else {
                        try setFloatResult(env, registers, inst.dest, c.LLVMBuildLoad2(env.builder, env.llvm_f64, item_ptr, "array_f64"));
                    },
                    else => if (inst.arg3 == 1) {
                        const byte = c.LLVMBuildLoad2(env.builder, c.LLVMInt8TypeInContext(env.context), item_ptr, "array_u8");
                        try setIntResult(env, registers, inst.dest, c.LLVMBuildZExt(env.builder, byte, env.llvm_i64, "array_u8_zext"));
                    } else if (inst.arg3 == 2) {
                        const val = c.LLVMBuildLoad2(env.builder, c.LLVMInt16TypeInContext(env.context), item_ptr, "array_u16");
                        try setIntResult(env, registers, inst.dest, c.LLVMBuildZExt(env.builder, val, env.llvm_i64, "array_u16_zext"));
                    } else if (inst.arg3 == 4) {
                        const val = c.LLVMBuildLoad2(env.builder, c.LLVMInt32TypeInContext(env.context), item_ptr, "array_u32");
                        try setIntResult(env, registers, inst.dest, c.LLVMBuildZExt(env.builder, val, env.llvm_i64, "array_u32_zext"));
                    } else {
                        try setIntResult(env, registers, inst.dest, c.LLVMBuildLoad2(env.builder, env.llvm_i64, item_ptr, "array_int"));
                    },
                }
            },
            .compiler_get_nodes_root, .compiler_get_nodes_exprs, .code_node_field_kind, .code_node_field_flags, .code_node_field_expression, .code_node_field_name, .code_node_field_notes, .code_node_field_type, .code_node_field_subexpressions, .code_node_field_enclosing_load, .code_note_field_text, .code_proc_call_arguments, .code_argument_field_expression, .code_literal_field_value_type, .code_literal_field_s64, .code_literal_set_s64, .code_literal_field_string, .code_literal_set_string, .code_node_to_code, .code_node_location, .compiler_report, .host_add_build_file, .host_compiler_begin_intercept, .host_compiler_end_intercept, .host_compiler_wait_for_message, .message_get_field => {
                if (inst.dest < registers.len) registers[inst.dest] = .{ .llvm_value = c.LLVMConstInt(env.llvm_i64, 0, 0), .kind = .int };
            },
            .source_location_get_field => {
                if (inst.dest >= registers.len or inst.arg1 >= registers.len or inst.arg2 >= env.program.strings.items.len) return diag.failAt(0, "LLVM backend Source_Code_Location field access out of range", .{});
                const loc = switch (registers[inst.arg1].kind) {
                    .source_location => |value| value,
                    else => return diag.failAt(0, "LLVM backend Source_Code_Location field access requires a Source_Code_Location value", .{}),
                };
                const field_name = env.program.strings.items[inst.arg2];
                if (std.mem.eql(u8, field_name, "fully_pathed_filename")) {
                    registers[inst.dest] = try staticStringRegister(env, loc.file, diag);
                } else if (std.mem.eql(u8, field_name, "line_number")) {
                    registers[inst.dest] = .{ .llvm_value = c.LLVMConstInt(env.llvm_i64, loc.line, 0), .kind = .int };
                } else if (std.mem.eql(u8, field_name, "character_number")) {
                    registers[inst.dest] = .{ .llvm_value = c.LLVMConstInt(env.llvm_i64, 0, 0), .kind = .int };
                } else {
                    return diag.failAt(0, "unsupported Source_Code_Location field '{s}'", .{field_name});
                }
            },
            .make_vector3 => {
                if (inst.dest >= registers.len) return diag.failAt(0, "LLVM backend make_vector3 destination register out of range", .{});
                registers[inst.dest] = .{ .llvm_value = c.LLVMConstNull(c.LLVMArrayType(env.llvm_f64, 3)), .kind = .void_value };
            },
            .int_trunc_cast => {
                if (inst.dest >= registers.len or inst.arg1 >= registers.len) return diag.failAt(0, "LLVM backend int_trunc_cast register out of range", .{});
                const int_value = switch (registers[inst.arg1].kind) {
                    .int, .uint, .int_addr, .uint_addr, .bool, .bool_addr => try valueAsInt(env, registers[inst.arg1], diag),
                    .float, .float_addr => c.LLVMBuildFPToSI(env.builder, try valueAsFloat(env, registers[inst.arg1], diag), env.llvm_i64, "fptosi"),
                    else => c.LLVMConstInt(env.llvm_i64, 0, 0),
                };
                switch (inst.arg2) {
                    7 => try setIntResult(env, registers, inst.dest, c.LLVMBuildZExt(env.builder, c.LLVMBuildTrunc(env.builder, int_value, c.LLVMInt8TypeInContext(env.context), "trunc_u8"), env.llvm_i64, "zext_u8")),
                    8 => try setIntResult(env, registers, inst.dest, c.LLVMBuildZExt(env.builder, c.LLVMBuildTrunc(env.builder, int_value, c.LLVMInt16TypeInContext(env.context), "trunc_u16"), env.llvm_i64, "zext_u16")),
                    4 => try setIntResult(env, registers, inst.dest, c.LLVMBuildSExt(env.builder, c.LLVMBuildTrunc(env.builder, int_value, c.LLVMInt32TypeInContext(env.context), "trunc_s32"), env.llvm_i64, "sext_s32")),
                    10 => try setPointerResult(env, registers, inst.dest, c.LLVMBuildIntToPtr(env.builder, int_value, env.ptr_ty, "inttoptr")),
                    else => try setIntResult(env, registers, inst.dest, int_value),
                }
            },
            .bool_to_int_cast => {
                if (inst.dest >= registers.len or inst.arg1 >= registers.len) return diag.failAt(0, "LLVM backend bool_to_int_cast register out of range", .{});
                try setIntResult(env, registers, inst.dest, c.LLVMBuildZExt(env.builder, try valueAsBool(env, registers[inst.arg1], diag), env.llvm_i64, "booltoint"));
            },
            .int_to_bool_cast => {
                if (inst.dest >= registers.len or inst.arg1 >= registers.len) return diag.failAt(0, "LLVM backend int_to_bool_cast register out of range", .{});
                const bool_value = switch (registers[inst.arg1].kind) {
                    .float, .float_addr => c.LLVMBuildFCmp(env.builder, c.LLVMRealONE, try valueAsFloat(env, registers[inst.arg1], diag), c.LLVMConstReal(env.llvm_f64, 0.0), "floattobool"),
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
                switch (registers[inst.arg1].kind) {
                    .int, .int_addr, .bool, .bool_addr => try setFloatResult(env, registers, inst.dest, c.LLVMBuildSIToFP(env.builder, try valueAsInt(env, registers[inst.arg1], diag), env.llvm_f64, "sitofp")),
                    .uint, .uint_addr => try setFloatResult(env, registers, inst.dest, c.LLVMBuildUIToFP(env.builder, try valueAsInt(env, registers[inst.arg1], diag), env.llvm_f64, "uitofp")),
                    .float, .float_addr => try setFloatResult(env, registers, inst.dest, try valueAsFloat(env, registers[inst.arg1], diag)),
                    else => return diag.failAt(0, "LLVM backend float_cast requires int or float source", .{}),
                }
            },
            .sin_float, .sqrt_float, .cos_float => {
                if (inst.dest >= registers.len or inst.arg1 >= registers.len) return diag.failAt(0, "LLVM backend unary float math register out of range", .{});
                const intrinsic_name: [:0]const u8 = switch (inst.opcode) {
                    .sin_float => "llvm.sin.f64",
                    .sqrt_float => "llvm.sqrt.f64",
                    .cos_float => "llvm.cos.f64",
                    else => unreachable,
                };
                try setFloatResult(env, registers, inst.dest, try buildUnaryFloatIntrinsic(env, intrinsic_name, try valueAsFloat(env, registers[inst.arg1], diag)));
            },
            .current_time_consensus_low => {
                if (inst.dest >= registers.len) return diag.failAt(0, "LLVM backend current_time_consensus_low destination out of range", .{});
                const result = c.LLVMBuildCall2(env.builder, env.current_time_consensus_low_fn_ty, env.current_time_consensus_low_fn, null, 0, "time_consensus_low");
                try setIntResult(env, registers, inst.dest, result);
            },
            .current_time_monotonic_low => {
                if (inst.dest >= registers.len) return diag.failAt(0, "LLVM backend current_time_monotonic_low destination out of range", .{});
                const result = c.LLVMBuildCall2(env.builder, env.current_time_monotonic_low_fn_ty, env.current_time_monotonic_low_fn, null, 0, "time_low");
                try setIntResult(env, registers, inst.dest, result);
            },
            .get_time_seconds => {
                if (inst.dest >= registers.len) return diag.failAt(0, "LLVM backend get_time_seconds destination out of range", .{});
                const result = c.LLVMBuildCall2(env.builder, env.get_time_seconds_fn_ty, env.get_time_seconds_fn, null, 0, "time_seconds");
                try setFloatResult(env, registers, inst.dest, result);
            },
            .seconds_since_init => {
                if (inst.dest >= registers.len) return diag.failAt(0, "LLVM backend seconds_since_init destination out of range", .{});
                const result = c.LLVMBuildCall2(env.builder, env.seconds_since_init_fn_ty, env.seconds_since_init_fn, null, 0, "seconds_since_init");
                try setFloatResult(env, registers, inst.dest, result);
            },
            .to_float64_seconds => {
                if (inst.dest >= registers.len or inst.arg1 >= registers.len) return diag.failAt(0, "LLVM backend to_float64_seconds register out of range", .{});
                var args = [_]c.LLVMValueRef{try valueAsInt(env, registers[inst.arg1], diag)};
                const result = c.LLVMBuildCall2(env.builder, env.to_float64_seconds_fn_ty, env.to_float64_seconds_fn, &args, args.len, "apollo_seconds");
                try setFloatResult(env, registers, inst.dest, result);
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
                try setIntResult(env, registers, inst.dest, result);
            },
            .calendar_to_string => {
                if (inst.dest >= registers.len or inst.arg1 >= registers.len) return diag.failAt(0, "LLVM backend calendar_to_string register out of range", .{});
                if (registers[inst.arg1].kind != .calendar) return diag.failAt(0, "calendar_to_string requires Calendar value", .{});
                var args = [_]c.LLVMValueRef{registers[inst.arg1].llvm_value};
                const result = c.LLVMBuildCall2(env.builder, env.calendar_to_string_fn_ty, env.calendar_to_string_fn, &args, args.len, "calendar_string");
                try setStringResult(env, registers, inst.dest, result);
            },
            .random_seed => {
                if (inst.arg1 >= registers.len) return diag.failAt(0, "LLVM backend random_seed seed register out of range", .{});
                var args = [_]c.LLVMValueRef{try valueAsInt(env, registers[inst.arg1], diag)};
                _ = c.LLVMBuildCall2(env.builder, env.random_seed_fn_ty, env.random_seed_fn, &args, args.len, "");
            },
            .random_get => {
                if (inst.dest >= registers.len) return diag.failAt(0, "LLVM backend random_get destination out of range", .{});
                const result = c.LLVMBuildCall2(env.builder, env.random_get_fn_ty, env.random_get_fn, null, 0, "random_u64");
                registers[inst.dest] = .{ .llvm_value = result, .kind = .uint };
            },
            .random_get_zero_to_one => {
                if (inst.dest >= registers.len) return diag.failAt(0, "LLVM backend random_get_zero_to_one destination out of range", .{});
                const result = c.LLVMBuildCall2(env.builder, env.random_get_zero_to_one_fn_ty, env.random_get_zero_to_one_fn, null, 0, "random_f64");
                try setFloatResult(env, registers, inst.dest, result);
            },
            .random_get_within_range => {
                if (inst.dest >= registers.len or inst.arg1 >= registers.len or inst.arg2 >= registers.len) return diag.failAt(0, "LLVM backend random_get_within_range register out of range", .{});
                var args = [_]c.LLVMValueRef{ try valueAsFloat(env, registers[inst.arg1], diag), try valueAsFloat(env, registers[inst.arg2], diag) };
                const result = c.LLVMBuildCall2(env.builder, env.random_get_within_range_fn_ty, env.random_get_within_range_fn, &args, args.len, "random_range");
                try setFloatResult(env, registers, inst.dest, result);
            },
            .compiler_arg_count => {
                if (inst.dest >= registers.len) return diag.failAt(0, "LLVM backend compiler_arg_count destination out of range", .{});
                const result = c.LLVMBuildCall2(env.builder, env.arg_count_fn_ty, env.arg_count_fn, null, 0, "openjai_argc");
                try setIntResult(env, registers, inst.dest, result);
            },
            .compiler_arg => {
                if (inst.dest >= registers.len or inst.arg1 >= registers.len) return diag.failAt(0, "LLVM backend compiler_arg register out of range", .{});
                var args = [_]c.LLVMValueRef{try valueAsInt(env, registers[inst.arg1], diag)};
                const result = c.LLVMBuildCall2(env.builder, env.arg_value_fn_ty, env.arg_value_fn, &args, args.len, "openjai_argv");
                try setStringResult(env, registers, inst.dest, result);
            },
            .compiler_read_file, .read_entire_file => {
                if (inst.dest >= registers.len or inst.arg1 >= registers.len) return diag.failAt(0, "LLVM backend read_entire_file register out of range", .{});
                const parts = try stringParts(env, registers[inst.arg1], diag);
                var args = [_]c.LLVMValueRef{ parts.data, parts.len };
                const result = c.LLVMBuildCall2(env.builder, env.read_entire_file_fn_ty, env.read_entire_file_fn, &args, args.len, "openjai_file");
                try setStringResult(env, registers, inst.dest, result);
                if (inst.arg2 != std.math.maxInt(u32) and inst.arg2 < registers.len) {
                    const is_null = c.LLVMBuildICmp(env.builder, c.LLVMIntNE, result, c.LLVMConstNull(env.ptr_ty), "file_ok");
                    try setBoolResult(env, registers, inst.arg2, is_null);
                }
            },
            .compiler_write_file => {
                if (inst.dest >= registers.len or inst.arg1 >= registers.len or inst.arg2 >= registers.len) return diag.failAt(0, "LLVM backend compiler_write_file register out of range", .{});
                const path = try stringParts(env, registers[inst.arg1], diag);
                const contents = try stringParts(env, registers[inst.arg2], diag);
                var args = [_]c.LLVMValueRef{ path.data, path.len, contents.data, contents.len };
                const result = c.LLVMBuildCall2(env.builder, env.write_entire_file_fn_ty, env.write_entire_file_fn, &args, args.len, "openjai_write_file");
                try setBoolResult(env, registers, inst.dest, result);
            },
            .get_command_line_arguments => {
                if (inst.dest >= registers.len) return diag.failAt(0, "LLVM backend get_command_line_arguments destination out of range", .{});
                const result = c.LLVMBuildCall2(env.builder, env.get_command_line_arguments_fn_ty, env.get_command_line_arguments_fn, null, 0, "argv_array");
                try setPointerResult(env, registers, inst.dest, result);
            },
            .sleep_milliseconds => {
                if (inst.arg1 >= registers.len) return diag.failAt(0, "LLVM backend sleep_milliseconds register out of range", .{});
                var args = [_]c.LLVMValueRef{try valueAsInt(env, registers[inst.arg1], diag)};
                _ = c.LLVMBuildCall2(env.builder, env.sleep_milliseconds_fn_ty, env.sleep_milliseconds_fn, &args, args.len, "");
                if (inst.dest < registers.len) try setIntResult(env, registers, inst.dest, c.LLVMConstInt(env.llvm_i64, 0, 0));
            },
            .cpu_has_feature => {
                if (inst.dest >= registers.len or inst.arg1 >= registers.len) return diag.failAt(0, "LLVM backend cpu_has_feature register out of range", .{});
                var args = [_]c.LLVMValueRef{try valueAsInt(env, registers[inst.arg1], diag)};
                const result = c.LLVMBuildCall2(env.builder, env.cpu_has_feature_fn_ty, env.cpu_has_feature_fn, &args, args.len, "cpu_has_feature");
                try setBoolResult(env, registers, inst.dest, result);
            },
            .make_directory => {
                if (inst.dest >= registers.len or inst.arg1 >= registers.len) return diag.failAt(0, "LLVM backend make_directory register out of range", .{});
                const path = try stringParts(env, registers[inst.arg1], diag);
                var args = [_]c.LLVMValueRef{ path.data, path.len };
                const result = c.LLVMBuildCall2(env.builder, env.make_directory_fn_ty, env.make_directory_fn, &args, args.len, "mkdir_ok");
                try setBoolResult(env, registers, inst.dest, result);
            },
            .delete_directory => {
                if (inst.dest >= registers.len or inst.arg1 >= registers.len) return diag.failAt(0, "LLVM backend delete_directory register out of range", .{});
                const path = try stringParts(env, registers[inst.arg1], diag);
                var args = [_]c.LLVMValueRef{ path.data, path.len };
                const result = c.LLVMBuildCall2(env.builder, env.delete_directory_fn_ty, env.delete_directory_fn, &args, args.len, "delete_directory_ok");
                try setBoolResult(env, registers, inst.dest, result);
            },
            .file_exists => {
                if (inst.dest >= registers.len or inst.arg1 >= registers.len) return diag.failAt(0, "LLVM backend file_exists register out of range", .{});
                const path = try stringParts(env, registers[inst.arg1], diag);
                var args = [_]c.LLVMValueRef{ path.data, path.len };
                const result = c.LLVMBuildCall2(env.builder, env.file_exists_fn_ty, env.file_exists_fn, &args, args.len, "file_exists");
                try setBoolResult(env, registers, inst.dest, result);
            },
            .set_working_directory => {
                if (inst.dest >= registers.len or inst.arg1 >= registers.len) return diag.failAt(0, "LLVM backend set_working_directory register out of range", .{});
                const path = try stringParts(env, registers[inst.arg1], diag);
                var args = [_]c.LLVMValueRef{ path.data, path.len };
                const result = c.LLVMBuildCall2(env.builder, env.set_working_directory_fn_ty, env.set_working_directory_fn, &args, args.len, "set_working_directory");
                try setBoolResult(env, registers, inst.dest, result);
            },
            .get_working_directory => {
                if (inst.dest >= registers.len) return diag.failAt(0, "LLVM backend get_working_directory register out of range", .{});
                const result = c.LLVMBuildCall2(env.builder, env.get_working_directory_fn_ty, env.get_working_directory_fn, null, 0, "get_working_directory");
                try setStringResult(env, registers, inst.dest, result);
            },
            .get_path_of_running_executable => {
                if (inst.dest >= registers.len) return diag.failAt(0, "LLVM backend get_path_of_running_executable register out of range", .{});
                const result = c.LLVMBuildCall2(env.builder, env.get_path_of_running_executable_fn_ty, env.get_path_of_running_executable_fn, null, 0, "get_path_of_running_executable");
                try setStringResult(env, registers, inst.dest, result);
            },
            .file_open => {
                if (inst.dest >= registers.len or inst.arg1 >= registers.len) return diag.failAt(0, "LLVM backend file_open register out of range", .{});
                const path = try stringParts(env, registers[inst.arg1], diag);
                var args = [_]c.LLVMValueRef{
                    path.data,
                    path.len,
                    c.LLVMConstInt(c.LLVMInt1TypeInContext(env.context), inst.arg2, 0),
                    c.LLVMConstInt(c.LLVMInt1TypeInContext(env.context), inst.arg3, 0),
                };
                const result = c.LLVMBuildCall2(env.builder, env.file_open_fn_ty, env.file_open_fn, &args, args.len, "file_handle");
                try setPointerResult(env, registers, inst.dest, result);
                if (inst.arg4 != 0) {
                    const ok_reg = inst.arg4 - 1;
                    if (ok_reg < registers.len) {
                        const is_ok = c.LLVMBuildICmp(env.builder, c.LLVMIntNE, result, c.LLVMConstNull(env.ptr_ty), "file_open_ok");
                        try setBoolResult(env, registers, ok_reg, is_ok);
                    }
                }
            },
            .file_close => {
                if (inst.arg1 >= registers.len) return diag.failAt(0, "LLVM backend file_close register out of range", .{});
                var args = [_]c.LLVMValueRef{try pointerValue(env, registers[inst.arg1], diag, "file_close handle")};
                _ = c.LLVMBuildCall2(env.builder, env.file_close_fn_ty, env.file_close_fn, &args, args.len, "");
            },
            .file_length => {
                if (inst.dest >= registers.len or inst.arg1 >= registers.len) return diag.failAt(0, "LLVM backend file_length register out of range", .{});
                var args = [_]c.LLVMValueRef{try pointerValue(env, registers[inst.arg1], diag, "file_length handle")};
                const result = c.LLVMBuildCall2(env.builder, env.file_length_fn_ty, env.file_length_fn, &args, args.len, "file_length");
                try setIntResult(env, registers, inst.dest, result);
            },
            .file_set_position => {
                if (inst.dest >= registers.len or inst.arg1 >= registers.len or inst.arg2 >= registers.len) return diag.failAt(0, "LLVM backend file_set_position register out of range", .{});
                var args = [_]c.LLVMValueRef{ try pointerValue(env, registers[inst.arg1], diag, "file_set_position handle"), try valueAsInt(env, registers[inst.arg2], diag) };
                const result = c.LLVMBuildCall2(env.builder, env.file_set_position_fn_ty, env.file_set_position_fn, &args, args.len, "file_seek_ok");
                try setBoolResult(env, registers, inst.dest, result);
            },
            .file_write => {
                if (inst.dest >= registers.len or inst.arg1 >= registers.len or inst.arg2 >= registers.len or inst.arg3 >= registers.len) return diag.failAt(0, "LLVM backend file_write register out of range", .{});
                const data_ptr, const data_len = if (inst.arg4 != 0) blk: {
                    const parts = try stringParts(env, registers[inst.arg2], diag);
                    break :blk .{ parts.data, parts.len };
                } else .{ try pointerValue(env, registers[inst.arg2], diag, "file_write data"), try valueAsInt(env, registers[inst.arg3], diag) };
                var args = [_]c.LLVMValueRef{ try pointerValue(env, registers[inst.arg1], diag, "file_write handle"), data_ptr, data_len };
                const result = c.LLVMBuildCall2(env.builder, env.file_write_fn_ty, env.file_write_fn, &args, args.len, "file_write_ok");
                try setBoolResult(env, registers, inst.dest, result);
            },
            .file_read => {
                if (inst.dest >= registers.len or inst.arg1 >= registers.len or inst.arg2 >= registers.len or inst.arg3 >= registers.len) return diag.failAt(0, "LLVM backend file_read register out of range", .{});
                var args = [_]c.LLVMValueRef{ try pointerValue(env, registers[inst.arg1], diag, "file_read handle"), try pointerValue(env, registers[inst.arg2], diag, "file_read data"), try valueAsInt(env, registers[inst.arg3], diag) };
                const result = c.LLVMBuildCall2(env.builder, env.file_read_fn_ty, env.file_read_fn, &args, args.len, "file_read_ok");
                try setBoolResult(env, registers, inst.dest, result);
            },
            .posix_read => {
                if (inst.dest >= registers.len or inst.arg1 >= registers.len or inst.arg2 >= registers.len or inst.arg3 >= registers.len) return diag.failAt(0, "LLVM backend posix_read register out of range", .{});
                var args = [_]c.LLVMValueRef{ try valueAsInt(env, registers[inst.arg1], diag), try pointerValue(env, registers[inst.arg2], diag, "read data"), try valueAsInt(env, registers[inst.arg3], diag) };
                const result = c.LLVMBuildCall2(env.builder, env.posix_read_fn_ty, env.posix_read_fn, &args, args.len, "read_count");
                try setIntResult(env, registers, inst.dest, result);
            },
            .string_builder_init => {
                if (inst.arg1 >= registers.len) return diag.failAt(0, "LLVM backend string_builder_init register out of range", .{});
                var args = [_]c.LLVMValueRef{try pointerValue(env, registers[inst.arg1], diag, "string builder slot")};
                _ = c.LLVMBuildCall2(env.builder, env.string_builder_init_fn_ty, env.string_builder_init_fn, &args, args.len, "");
            },
            .string_builder_free => {
                if (inst.arg1 >= registers.len) return diag.failAt(0, "LLVM backend string_builder_free register out of range", .{});
                var args = [_]c.LLVMValueRef{try pointerValue(env, registers[inst.arg1], diag, "string builder slot")};
                _ = c.LLVMBuildCall2(env.builder, env.string_builder_free_fn_ty, env.string_builder_free_fn, &args, args.len, "");
            },
            .string_builder_append_string, .string_builder_append_int, .string_builder_append_float => {
                if (inst.arg1 >= registers.len or inst.arg2 >= registers.len) return diag.failAt(0, "LLVM backend string_builder_append register out of range", .{});
                try emitBuilderAppendValue(env, registers[inst.arg1], registers[inst.arg2], diag);
            },
            .string_builder_to_string => {
                if (inst.dest >= registers.len or inst.arg1 >= registers.len) return diag.failAt(0, "LLVM backend string_builder_to_string register out of range", .{});
                var args = [_]c.LLVMValueRef{try pointerValue(env, registers[inst.arg1], diag, "string builder slot")};
                const result = c.LLVMBuildCall2(env.builder, env.string_builder_to_string_fn_ty, env.string_builder_to_string_fn, &args, args.len, "builder_string");
                const fn_parent = c.LLVMGetBasicBlockParent(c.LLVMGetInsertBlock(env.builder));
                const slot = buildEntryAlloca(env, fn_parent, env.ptr_ty, "builder_string_slot");
                _ = c.LLVMBuildStore(env.builder, result, slot);
                registers[inst.dest] = .{ .llvm_value = slot, .kind = .{ .string_addr = inst.dest } };
            },
            .string_builder_length => {
                if (inst.dest >= registers.len or inst.arg1 >= registers.len) return diag.failAt(0, "LLVM backend string_builder_length register out of range", .{});
                var args = [_]c.LLVMValueRef{try pointerValue(env, registers[inst.arg1], diag, "string builder slot")};
                try setIntResult(env, registers, inst.dest, c.LLVMBuildCall2(env.builder, env.string_builder_length_fn_ty, env.string_builder_length_fn, &args, args.len, "builder_len"));
            },
            .string_builder_join_array => {
                if (inst.arg1 >= registers.len or inst.arg2 >= registers.len or inst.arg3 >= registers.len) return diag.failAt(0, "LLVM backend string_builder_join_array register out of range", .{});
                const builder_ptr = try pointerValue(env, registers[inst.arg1], diag, "string builder slot");
                const arr_ptr = try pointerValue(env, registers[inst.arg2], diag, "join array");
                const sep = try stringParts(env, registers[inst.arg3], diag);
                const flags = c.LLVMConstInt(env.llvm_i64, inst.arg4, 0);
                var args = [_]c.LLVMValueRef{ builder_ptr, arr_ptr, sep.data, sep.len, flags };
                _ = c.LLVMBuildCall2(env.builder, env.string_builder_join_array_fn_ty, env.string_builder_join_array_fn, &args, args.len, "");
            },
            .string_copy => {
                if (inst.dest >= registers.len or inst.arg1 >= registers.len) return diag.failAt(0, "LLVM backend string_copy register out of range", .{});
                const parts = try stringParts(env, registers[inst.arg1], diag);
                var args = [_]c.LLVMValueRef{ parts.data, parts.len };
                try setStringResult(env, registers, inst.dest, c.LLVMBuildCall2(env.builder, env.string_copy_fn_ty, env.string_copy_fn, &args, args.len, "copy_string"));
            },
            .string_to_c => {
                if (inst.dest >= registers.len or inst.arg1 >= registers.len) return diag.failAt(0, "LLVM backend string_to_c register out of range", .{});
                const parts = try stringParts(env, registers[inst.arg1], diag);
                var args = [_]c.LLVMValueRef{ parts.data, parts.len };
                try setPointerResult(env, registers, inst.dest, c.LLVMBuildCall2(env.builder, env.string_to_c_fn_ty, env.string_to_c_fn, &args, args.len, "cstring"));
            },
            .string_from_c => {
                if (inst.dest >= registers.len or inst.arg1 >= registers.len) return diag.failAt(0, "LLVM backend string_from_c register out of range", .{});
                var args = [_]c.LLVMValueRef{try pointerValue(env, registers[inst.arg1], diag, "C string pointer")};
                try setStringResult(env, registers, inst.dest, c.LLVMBuildCall2(env.builder, env.string_from_c_fn_ty, env.string_from_c_fn, &args, args.len, "string_from_c"));
            },
            .string_from_parts => {
                if (inst.dest >= registers.len or inst.arg1 >= registers.len or inst.arg2 >= registers.len) return diag.failAt(0, "LLVM backend string_from_parts register out of range", .{});
                var args = [_]c.LLVMValueRef{ try pointerValue(env, registers[inst.arg1], diag, "string data pointer"), try valueAsInt(env, registers[inst.arg2], diag) };
                try setStringResult(env, registers, inst.dest, c.LLVMBuildCall2(env.builder, env.string_from_parts_fn_ty, env.string_from_parts_fn, &args, args.len, "string_from_parts"));
            },
            .string_trim => {
                if (inst.dest >= registers.len or inst.arg1 >= registers.len) return diag.failAt(0, "LLVM backend string_trim register out of range", .{});
                const parts = try stringParts(env, registers[inst.arg1], diag);
                var args = [_]c.LLVMValueRef{ parts.data, parts.len };
                try setStringResult(env, registers, inst.dest, c.LLVMBuildCall2(env.builder, env.string_trim_fn_ty, env.string_trim_fn, &args, args.len, "trim"));
            },
            .string_compare, .string_contains, .string_begins_with, .string_find => {
                if (inst.dest >= registers.len or inst.arg1 >= registers.len or inst.arg2 >= registers.len) return diag.failAt(0, "LLVM backend string operation register out of range", .{});
                const lhs = try stringParts(env, registers[inst.arg1], diag);
                const rhs = try stringParts(env, registers[inst.arg2], diag);
                if (inst.opcode == .string_compare) {
                    var args = [_]c.LLVMValueRef{ lhs.data, lhs.len, rhs.data, rhs.len };
                    try setIntResult(env, registers, inst.dest, c.LLVMBuildCall2(env.builder, env.string_compare_fn_ty, env.string_compare_fn, &args, args.len, "string_compare"));
                } else if (inst.opcode == .string_contains) {
                    var args = [_]c.LLVMValueRef{ lhs.data, lhs.len, rhs.data, rhs.len };
                    try setBoolResult(env, registers, inst.dest, c.LLVMBuildCall2(env.builder, env.string_contains_fn_ty, env.string_contains_fn, &args, args.len, "string_contains"));
                } else if (inst.opcode == .string_begins_with) {
                    var args = [_]c.LLVMValueRef{ lhs.data, lhs.len, rhs.data, rhs.len };
                    try setBoolResult(env, registers, inst.dest, c.LLVMBuildCall2(env.builder, env.string_begins_with_fn_ty, env.string_begins_with_fn, &args, args.len, "string_begins_with"));
                } else {
                    var args = [_]c.LLVMValueRef{ lhs.data, lhs.len, rhs.data, rhs.len, c.LLVMConstInt(c.LLVMInt1TypeInContext(env.context), inst.arg3, 0) };
                    try setIntResult(env, registers, inst.dest, c.LLVMBuildCall2(env.builder, env.string_find_fn_ty, env.string_find_fn, &args, args.len, "string_find"));
                }
            },
            .string_split => {
                if (inst.dest >= registers.len or inst.arg1 >= registers.len or inst.arg2 >= registers.len) return diag.failAt(0, "LLVM backend string_split register out of range", .{});
                const lhs = try stringParts(env, registers[inst.arg1], diag);
                const sep_reg = registers[inst.arg2];
                const rhs = switch (sep_reg.kind) {
                    .int, .int_addr, .uint, .uint_addr => blk: {
                        const byte_val = try valueAsInt(env, sep_reg, diag);
                        const byte_trunc = c.LLVMBuildTrunc(env.builder, byte_val, c.LLVMInt8TypeInContext(env.context), "sep_byte");
                        const alloca = c.LLVMBuildAlloca(env.builder, c.LLVMInt8TypeInContext(env.context), "sep_buf");
                        _ = c.LLVMBuildStore(env.builder, byte_trunc, alloca);
                        break :blk StringParts{
                            .data = alloca,
                            .len = c.LLVMConstInt(env.llvm_i64, 1, 0),
                        };
                    },
                    else => try stringParts(env, sep_reg, diag),
                };
                var args = [_]c.LLVMValueRef{ lhs.data, lhs.len, rhs.data, rhs.len };
                try setPointerResult(env, registers, inst.dest, c.LLVMBuildCall2(env.builder, env.string_split_fn_ty, env.string_split_fn, &args, args.len, "split"));
            },
            .string_parse_int => {
                if (inst.dest >= registers.len or inst.arg1 >= registers.len or inst.arg2 >= registers.len) return diag.failAt(0, "LLVM backend string_parse_int register out of range", .{});
                const parts = try stringParts(env, registers[inst.arg1], diag);
                var value_args = [_]c.LLVMValueRef{ parts.data, parts.len };
                try setIntResult(env, registers, inst.dest, c.LLVMBuildCall2(env.builder, env.string_parse_int_fn_ty, env.string_parse_int_fn, &value_args, value_args.len, "parse_int"));
                var ok_args = [_]c.LLVMValueRef{ parts.data, parts.len };
                try setBoolResult(env, registers, inst.arg2, c.LLVMBuildCall2(env.builder, env.string_parse_int_ok_fn_ty, env.string_parse_int_ok_fn, &ok_args, ok_args.len, "parse_int_ok"));
            },
            .string_parse_float => {
                if (inst.dest >= registers.len or inst.arg1 >= registers.len or inst.arg2 >= registers.len) return diag.failAt(0, "LLVM backend string_parse_float register out of range", .{});
                const parts = try stringParts(env, registers[inst.arg1], diag);
                var value_args = [_]c.LLVMValueRef{ parts.data, parts.len };
                try setFloatResult(env, registers, inst.dest, c.LLVMBuildCall2(env.builder, env.string_parse_float_fn_ty, env.string_parse_float_fn, &value_args, value_args.len, "parse_float"));
                var ok_args = [_]c.LLVMValueRef{ parts.data, parts.len };
                try setBoolResult(env, registers, inst.arg2, c.LLVMBuildCall2(env.builder, env.string_parse_float_ok_fn_ty, env.string_parse_float_ok_fn, &ok_args, ok_args.len, "parse_float_ok"));
            },
            .string_replace => {
                if (inst.dest >= registers.len or inst.arg1 >= registers.len or inst.arg2 >= registers.len or inst.arg3 >= registers.len) return diag.failAt(0, "LLVM backend string_replace register out of range", .{});
                const source = try stringParts(env, registers[inst.arg1], diag);
                const needle = try stringParts(env, registers[inst.arg2], diag);
                const replacement = try stringParts(env, registers[inst.arg3], diag);
                var args = [_]c.LLVMValueRef{ source.data, source.len, needle.data, needle.len, replacement.data, replacement.len };
                try setStringResult(env, registers, inst.dest, c.LLVMBuildCall2(env.builder, env.string_replace_fn_ty, env.string_replace_fn, &args, args.len, "replace"));
            },
            .string_len => {
                if (inst.dest >= registers.len or inst.arg1 >= registers.len) return diag.failAt(0, "LLVM backend string_len register out of range", .{});
                const parts = try stringParts(env, registers[inst.arg1], diag);
                try setIntResult(env, registers, inst.dest, parts.len);
            },
            .string_data => {
                if (inst.dest >= registers.len or inst.arg1 >= registers.len) return diag.failAt(0, "LLVM backend string_data register out of range", .{});
                const parts = try stringParts(env, registers[inst.arg1], diag);
                try setPointerResult(env, registers, inst.dest, parts.data);
            },
            .string_slice => {
                if (inst.dest >= registers.len or inst.arg1 >= registers.len or inst.arg2 >= registers.len or inst.arg3 >= registers.len) return diag.failAt(0, "LLVM backend string_slice register out of range", .{});
                const source = try runtimeStringValue(env, registers[inst.arg1], diag);
                const start = try valueAsInt(env, registers[inst.arg2], diag);
                const len = try valueAsInt(env, registers[inst.arg3], diag);
                var args = [_]c.LLVMValueRef{ source, start, len };
                const result = c.LLVMBuildCall2(env.builder, env.string_slice_fn_ty, env.string_slice_fn, &args, args.len, "string_slice");
                try setStringResult(env, registers, inst.dest, result);
            },
            .path_strip_filename => {
                if (inst.dest >= registers.len or inst.arg1 >= registers.len) return diag.failAt(0, "LLVM backend path_strip_filename register out of range", .{});
                const parts = try stringParts(env, registers[inst.arg1], diag);
                var args = [_]c.LLVMValueRef{ parts.data, parts.len };
                const result = c.LLVMBuildCall2(env.builder, env.path_strip_filename_fn_ty, env.path_strip_filename_fn, &args, args.len, "path_strip_filename");
                try setStringResult(env, registers, inst.dest, result);
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
                    .int, .uint, .int_addr, .uint_addr, .bool, .bool_addr => c.LLVMBuildIntToPtr(env.builder, try valueAsInt(env, registers[inst.arg1], diag), env.ptr_ty, "free_inttoptr"),
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
                    .int_addr, .uint_addr, .bool_addr => c.LLVMBuildPointerCast(env.builder, registers[inst.dest].llvm_value, env.ptr_ty, "memcpy_dst_scalar_slot"),
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
                    .int, .uint, .int_addr, .uint_addr, .bool, .bool_addr, .type_id, .float, .float_addr => try valueAddress(env, registers[inst.arg1], diag),
                    .void_value, .unset => blk_void: {
                        const fn_parent = c.LLVMGetBasicBlockParent(c.LLVMGetInsertBlock(env.builder));
                        const slot = buildEntryAlloca(env, fn_parent, env.llvm_i64, "memcpy_void_src");
                        _ = c.LLVMBuildStore(env.builder, c.LLVMConstInt(env.llvm_i64, 0, 0), slot);
                        break :blk_void slot;
                    },
                    else => return diag.failAt(0, "LLVM backend memcpy source requires byte-addressable value, got {s}", .{@tagName(registers[inst.arg1].kind)}),
                };
                const count = try valueAsInt(env, registers[inst.arg2], diag);
                var args = [_]c.LLVMValueRef{ dst_ptr, src_ptr, count };
                _ = c.LLVMBuildCall2(env.builder, env.memcpy_fn_ty, env.memcpy_fn, &args, args.len, "");
            },
            .memset => {
                if (inst.dest >= registers.len or inst.arg1 >= registers.len or inst.arg2 >= registers.len) return diag.failAt(0, "LLVM backend memset register out of range", .{});
                const dst_ptr = switch (registers[inst.dest].kind) {
                    .pointer => registers[inst.dest].llvm_value,
                    .pointer_addr => blk: {
                        const loaded = c.LLVMBuildLoad2(env.builder, env.ptr_ty, registers[inst.dest].llvm_value, "memset_dst_load_ptr_addr");
                        const slot = c.LLVMBuildPointerCast(env.builder, registers[inst.dest].llvm_value, env.ptr_ty, "memset_dst_ptr_slot");
                        const is_null = c.LLVMBuildICmp(env.builder, c.LLVMIntEQ, loaded, c.LLVMConstPointerNull(env.ptr_ty), "memset_dst_ptr_is_null");
                        break :blk c.LLVMBuildSelect(env.builder, is_null, slot, loaded, "memset_dst_ptr_or_slot");
                    },
                    .int_addr, .uint_addr, .bool_addr => c.LLVMBuildPointerCast(env.builder, registers[inst.dest].llvm_value, env.ptr_ty, "memset_dst_scalar_slot"),
                    else => return diag.failAt(0, "LLVM backend memset destination requires addressable storage, got {s}", .{@tagName(registers[inst.dest].kind)}),
                };
                const value = c.LLVMBuildTrunc(env.builder, try valueAsInt(env, registers[inst.arg1], diag), c.LLVMInt8TypeInContext(env.context), "memset_byte");
                const count = try valueAsInt(env, registers[inst.arg2], diag);
                _ = c.LLVMBuildMemSet(env.builder, dst_ptr, value, count, 1);
            },
            .exit_process => {
                if (inst.arg1 >= registers.len) return diag.failAt(0, "LLVM backend exit_process register out of range", .{});
                const status_i64 = try valueAsInt(env, registers[inst.arg1], diag);
                const status = c.LLVMBuildIntCast2(env.builder, status_i64, env.llvm_i32, 1, "exit_status");
                var args = [_]c.LLVMValueRef{status};
                _ = c.LLVMBuildCall2(env.builder, env.exit_fn_ty, env.exit_fn, &args, args.len, "");
                _ = c.LLVMBuildUnreachable(env.builder);
                terminates_block = true;
            },
            .ret_void => {
                _ = c.LLVMBuildBr(env.builder, blocks[instruction_count].?);
                terminates_block = true;
            },
            .ret_multi => {
                if (inst.arg1 + inst.arg2 > env.program.call_args.items.len) return diag.failAt(0, "LLVM backend multi-return register table out of range", .{});
                if (proc.return_types.items.len != inst.arg2) return diag.failAt(0, "LLVM backend multi-return type count mismatch", .{});
                var result = c.LLVMGetUndef(llvmReturnTypeForProc(env.context, env.llvm_i64, env.llvm_f64, env.ptr_ty, proc));
                for (proc.return_types.items, 0..) |type_id, return_index| {
                    const reg_index = env.program.call_args.items[inst.arg1 + return_index];
                    if (reg_index >= registers.len) return diag.failAt(0, "LLVM backend multi-return register out of range", .{});
                    const value = try callArgValueForType(env, registers[reg_index], type_id, diag);
                    result = c.LLVMBuildInsertValue(env.builder, result, value, @intCast(return_index), "ret_insert");
                }
                _ = c.LLVMBuildRet(env.builder, result);
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
                if (isFloatKind(lhs_val.kind) or isFloatKind(rhs_val.kind)) {
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
                } else if (isFloatKind(lhs.kind) or isFloatKind(rhs.kind)) {
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
                try setIntResult(env, registers, inst.dest, value);
            },
            .select_value => {
                if (inst.dest >= registers.len or inst.arg1 >= registers.len or inst.arg2 >= registers.len or inst.arg3 >= registers.len) return diag.failAt(0, "LLVM backend select register out of range", .{});
                const cond = try valueAsBool(env, registers[inst.arg1], diag);
                const then_val = registers[inst.arg2];
                const else_val = registers[inst.arg3];
                if ((then_val.kind == .int or then_val.kind == .uint) and (else_val.kind == .int or else_val.kind == .uint)) {
                    try setIntResult(env, registers, inst.dest, c.LLVMBuildSelect(env.builder, cond, then_val.llvm_value, else_val.llvm_value, "ifx"));
                } else if ((then_val.kind == .bool or then_val.kind == .bool_addr) and (else_val.kind == .bool or else_val.kind == .bool_addr)) {
                    try setBoolResult(env, registers, inst.dest, c.LLVMBuildSelect(env.builder, cond, try valueAsBool(env, then_val, diag), try valueAsBool(env, else_val, diag), "ifx"));
                } else if (isStringValue(then_val) and isStringValue(else_val)) {
                    const then_string = try runtimeStringValue(env, then_val, diag);
                    const else_string = try runtimeStringValue(env, else_val, diag);
                    try setStringResult(env, registers, inst.dest, c.LLVMBuildSelect(env.builder, cond, then_string, else_string, "ifx_str"));
                } else if (isFloatKind(then_val.kind) or isFloatKind(else_val.kind)) {
                    const then_float = try valueAsFloat(env, then_val, diag);
                    const else_float = try valueAsFloat(env, else_val, diag);
                    try setFloatResult(env, registers, inst.dest, c.LLVMBuildSelect(env.builder, cond, then_float, else_float, "ifx"));
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
                _ = c.LLVMBuildBr(env.builder, blocks[inst.arg1].?);
                terminates_block = true;
            },
            .jump_if_false => {
                if (inst.arg1 >= registers.len or inst.arg2 > instruction_count) return diag.failAt(0, "LLVM backend conditional jump out of range", .{});
                const cond = try valueAsBool(env, registers[inst.arg1], diag);
                _ = c.LLVMBuildCondBr(env.builder, cond, blocks[instruction_index + 1].?, blocks[inst.arg2].?);
                terminates_block = true;
            },
            .call => {
                if (inst.arg1 >= env.proc_functions.len or env.proc_functions[inst.arg1] == null or env.proc_function_tys[inst.arg1] == null) {
                    const name = if (inst.arg1 < env.program.procs.items.len) env.program.procs.items[inst.arg1].name else "?";
                    return diag.failAt(0, "LLVM backend call target not resolved: proc[{d}] '{s}' (total={d}) from '{s}'", .{ inst.arg1, name, env.proc_functions.len, env.current_proc_name });
                }
                const target_proc = &env.program.procs.items[inst.arg1];
                if (inst.arg2 != target_proc.param_types.items.len) {
                    const name = if (inst.arg1 < env.program.procs.items.len) env.program.procs.items[inst.arg1].name else "?";
                    return diag.failAt(0, "LLVM backend call argument count mismatch for '{s}': got {d}, expected {d}", .{ name, inst.arg2, target_proc.param_types.items.len });
                }
                if (inst.arg3 + inst.arg2 > env.program.call_args.items.len) return diag.failAt(0, "LLVM backend call argument table out of range", .{});
                const args = try env.allocator.alloc(c.LLVMValueRef, inst.arg2);
                defer env.allocator.free(args);
                for (args, 0..) |*arg, arg_index| {
                    const reg_index = env.program.call_args.items[inst.arg3 + arg_index];
                    if (reg_index >= registers.len) return diag.failAt(0, "LLVM backend call argument register out of range", .{});
                    arg.* = try callArgValueForType(env, registers[reg_index], target_proc.param_types.items[arg_index], diag);
                }
                const result = c.LLVMBuildCall2(env.builder, env.proc_function_tys[inst.arg1], env.proc_functions[inst.arg1], if (args.len == 0) null else args.ptr, @intCast(args.len), if (target_proc.return_type == 0) "" else "call");
                if (target_proc.return_types.items.len != 0) {
                    if (inst.dest >= registers.len) return diag.failAt(0, "LLVM backend call destination out of range", .{});
                    registers[inst.dest] = .{ .llvm_value = result, .kind = .{ .tuple = target_proc.return_types.items } };
                } else if (target_proc.return_type != 0) {
                    if (inst.dest >= registers.len) return diag.failAt(0, "LLVM backend call destination out of range", .{});
                    try setTypedResult(env, registers, inst.dest, result, target_proc.return_type);
                }
            },
            .call_foreign => {
                if (inst.arg1 >= env.program.foreign_functions.items.len) return diag.failAt(0, "LLVM backend foreign call target out of range", .{});
                const foreign = env.program.foreign_functions.items[inst.arg1];
                if (inst.arg2 != foreign.param_types.len) return diag.failAt(0, "LLVM backend foreign call argument count mismatch for '{s}'", .{foreign.name});
                if (inst.arg3 + inst.arg2 > env.program.call_args.items.len) return diag.failAt(0, "LLVM backend foreign call argument table out of range", .{});
                var param_types = try env.allocator.alloc(c.LLVMTypeRef, foreign.param_types.len);
                defer env.allocator.free(param_types);
                for (foreign.param_types, 0..) |type_id, param_index| {
                    param_types[param_index] = llvmTypeForTypeId(env.context, env.llvm_i64, env.llvm_f64, env.ptr_ty, type_id);
                }
                const return_ty = llvmTypeForTypeId(env.context, env.llvm_i64, env.llvm_f64, env.ptr_ty, foreign.return_type);
                const foreign_ty = c.LLVMFunctionType(return_ty, if (param_types.len == 0) null else param_types.ptr, @intCast(param_types.len), 0);
                const name_z = try env.allocator.dupeZ(u8, foreign.name);
                defer env.allocator.free(name_z);
                const foreign_fn = c.LLVMGetNamedFunction(env.module, name_z.ptr) orelse c.LLVMAddFunction(env.module, name_z.ptr, foreign_ty);
                const args = try env.allocator.alloc(c.LLVMValueRef, inst.arg2);
                defer env.allocator.free(args);
                for (args, 0..) |*arg, arg_index| {
                    const reg_index = env.program.call_args.items[inst.arg3 + arg_index];
                    if (reg_index >= registers.len) return diag.failAt(0, "LLVM backend foreign call argument register out of range", .{});
                    arg.* = try callArgValueForType(env, registers[reg_index], foreign.param_types[arg_index], diag);
                }
                const result = c.LLVMBuildCall2(env.builder, foreign_ty, foreign_fn, if (args.len == 0) null else args.ptr, @intCast(args.len), if (foreign.return_type == 0) "" else "foreign_call");
                if (foreign.return_type != 0) {
                    if (inst.dest >= registers.len) return diag.failAt(0, "LLVM backend foreign call destination out of range", .{});
                    try setTypedResult(env, registers, inst.dest, result, foreign.return_type);
                }
            },
            .tuple_extract => {
                if (inst.dest >= registers.len or inst.arg1 >= registers.len) return diag.failAt(0, "LLVM backend tuple_extract register out of range", .{});
                const tuple_types = switch (registers[inst.arg1].kind) {
                    .tuple => |types| types,
                    else => {
                        registers[inst.dest] = registers[inst.arg1];
                        continue;
                    },
                };
                if (inst.arg2 >= tuple_types.len) return diag.failAt(0, "LLVM backend tuple_extract index out of range", .{});
                const value = c.LLVMBuildExtractValue(env.builder, registers[inst.arg1].llvm_value, inst.arg2, "tuple_extract");
                try setTypedResult(env, registers, inst.dest, value, tuple_types[inst.arg2]);
            },
            .call_proc0 => {
                if (inst.arg1 >= env.proc_functions.len or env.proc_functions[inst.arg1] == null) return diag.failAt(0, "LLVM backend call_proc0 target out of range", .{});
                _ = c.LLVMBuildCall2(env.builder, env.proc_void_ty, env.proc_functions[inst.arg1], null, 0, "");
            },
            .type_info_field => {
                if (inst.dest >= registers.len or inst.arg1 >= registers.len or inst.arg2 >= env.program.strings.items.len) {
                    return diag.failAt(0, "LLVM backend type_info_field register out of range", .{});
                }
                const field_name = env.program.strings.items[inst.arg2];
                // Check for builtin type handling (type texts that aren't in the type_info table)
                const builtin_tag = builtinTypeInfoTag(env, registers[inst.arg1]);
                // Resolve the source register to a type_id (i64).
                // The source may be a type_id (int), a string (type text from load_type_text),
                // or a pointer (from a previous "members" access).
                const type_id_val = try resolveTypeInfoId(env, registers[inst.arg1], diag);
                if (std.mem.eql(u8, field_name, "name") or std.mem.eql(u8, field_name, "type")) {
                    if (builtin_tag) |tag_info| {
                        // For builtin types, emit the name/tag directly as a string literal
                        const text = if (std.mem.eql(u8, field_name, "type")) tag_info.tag_name else tag_info.type_name;
                        const result = try emitInlineRuntimeString(env, text);
                        try setStringResult(env, registers, inst.dest, result);
                    } else {
                        const type_info_name_params = [_]c.LLVMTypeRef{env.llvm_i64};
                        const type_info_name_fn_ty = c.LLVMFunctionType(env.ptr_ty, @constCast(&type_info_name_params), type_info_name_params.len, 0);
                        const fn_name = if (std.mem.eql(u8, field_name, "type")) "__openjai_type_info_tag_name" else "__openjai_type_info_name";
                        const type_info_name_fn = c.LLVMGetNamedFunction(env.module, fn_name) orelse c.LLVMAddFunction(env.module, fn_name, type_info_name_fn_ty);
                        var args = [_]c.LLVMValueRef{type_id_val};
                        const result = c.LLVMBuildCall2(env.builder, type_info_name_fn_ty, type_info_name_fn, &args, args.len, "type_info_name");
                        try setStringResult(env, registers, inst.dest, result);
                    }
                } else if (std.mem.eql(u8, field_name, "members")) {
                    // Call __openjai_type_info_get_members(type_id) -> returns dynamic array ptr
                    var args = [_]c.LLVMValueRef{type_id_val};
                    const result = c.LLVMBuildCall2(env.builder, env.type_info_get_members_fn_ty, env.type_info_get_members_fn, &args, args.len, "type_info_members");
                    try setPointerResult(env, registers, inst.dest, result);
                } else if (std.mem.eql(u8, field_name, "count")) {
                    // "count" may be called on either a type_id (for member_count) or a pointer (from members array)
                    const src_kind = registers[inst.arg1].kind;
                    if (src_kind == .pointer or src_kind == .pointer_addr) {
                        // Source is a members array pointer - use array_count
                        const ptr = try pointerValue(env, registers[inst.arg1], diag, "type_info_field count");
                        var args = [_]c.LLVMValueRef{ptr};
                        const result = c.LLVMBuildCall2(env.builder, env.array_count_fn_ty, env.array_count_fn, &args, args.len, "members_count");
                        try setIntResult(env, registers, inst.dest, result);
                    } else {
                        // Source is a type_id - use type_info_int_field with field_id 3
                        const type_info_int_params = [_]c.LLVMTypeRef{ env.llvm_i64, env.llvm_i64 };
                        const type_info_int_fn_ty = c.LLVMFunctionType(env.llvm_i64, @constCast(&type_info_int_params), type_info_int_params.len, 0);
                        const type_info_int_fn = c.LLVMGetNamedFunction(env.module, "__openjai_type_info_int_field") orelse c.LLVMAddFunction(env.module, "__openjai_type_info_int_field", type_info_int_fn_ty);
                        var args = [_]c.LLVMValueRef{ type_id_val, c.LLVMConstInt(env.llvm_i64, 3, 0) };
                        const result = c.LLVMBuildCall2(env.builder, type_info_int_fn_ty, type_info_int_fn, &args, args.len, "type_info_int");
                        try setIntResult(env, registers, inst.dest, result);
                    }
                } else if (std.mem.eql(u8, field_name, "notes")) {
                    const fn_params = [_]c.LLVMTypeRef{env.llvm_i64};
                    const fn_ty = c.LLVMFunctionType(env.ptr_ty, @constCast(&fn_params), fn_params.len, 0);
                    const func = c.LLVMGetNamedFunction(env.module, "__openjai_type_info_notes") orelse c.LLVMAddFunction(env.module, "__openjai_type_info_notes", fn_ty);
                    var args = [_]c.LLVMValueRef{type_id_val};
                    const result = c.LLVMBuildCall2(env.builder, fn_ty, func, &args, args.len, "type_info_notes");
                    try setStringResult(env, registers, inst.dest, result);
                } else {
                    if (builtin_tag != null and std.mem.eql(u8, field_name, "tag")) {
                        try setIntResult(env, registers, inst.dest, c.LLVMConstInt(env.llvm_i64, builtin_tag.?.tag_value, 0));
                    } else {
                        const type_info_int_params = [_]c.LLVMTypeRef{ env.llvm_i64, env.llvm_i64 };
                        const type_info_int_fn_ty = c.LLVMFunctionType(env.llvm_i64, @constCast(&type_info_int_params), type_info_int_params.len, 0);
                        const type_info_int_fn = c.LLVMGetNamedFunction(env.module, "__openjai_type_info_int_field") orelse c.LLVMAddFunction(env.module, "__openjai_type_info_int_field", type_info_int_fn_ty);
                        const field_id: u64 = if (std.mem.eql(u8, field_name, "runtime_size")) 1 else if (std.mem.eql(u8, field_name, "tag")) 2 else if (std.mem.eql(u8, field_name, "signed")) 4 else if (std.mem.eql(u8, field_name, "enum_type_flags")) 5 else if (std.mem.eql(u8, field_name, "internal_type")) 6 else 0;
                        var args = [_]c.LLVMValueRef{ type_id_val, c.LLVMConstInt(env.llvm_i64, field_id, 0) };
                        const result = c.LLVMBuildCall2(env.builder, type_info_int_fn_ty, type_info_int_fn, &args, args.len, "type_info_int");
                        try setIntResult(env, registers, inst.dest, result);
                    }
                }
            },
            .type_info_member_field => {
                if (inst.dest >= registers.len or inst.arg1 >= registers.len or inst.arg2 >= env.program.strings.items.len) {
                    return diag.failAt(0, "LLVM backend type_info_member_field register out of range", .{});
                }
                const field_name = env.program.strings.items[inst.arg2];
                // The source register is a pointer to a TypeInfoMemberEntry, either from:
                // - array_index (pointer to element in the members array data)
                // - load_type_info_member (pointer into the global member pool)
                const member_ptr = try pointerValue(env, registers[inst.arg1], diag, "type_info_member_field");
                if (std.mem.eql(u8, field_name, "name")) {
                    var args = [_]c.LLVMValueRef{member_ptr};
                    const result = c.LLVMBuildCall2(env.builder, env.type_info_member_name_fn_ty, env.type_info_member_name_fn, &args, args.len, "member_name");
                    try setStringResult(env, registers, inst.dest, result);
                } else if (std.mem.eql(u8, field_name, "type_name")) {
                    var args = [_]c.LLVMValueRef{member_ptr};
                    const result = c.LLVMBuildCall2(env.builder, env.type_info_member_type_name_fn_ty, env.type_info_member_type_name_fn, &args, args.len, "member_type_name");
                    try setStringResult(env, registers, inst.dest, result);
                } else if (std.mem.eql(u8, field_name, "type")) {
                    const fn_params = [_]c.LLVMTypeRef{env.ptr_ty};
                    const fn_ty = c.LLVMFunctionType(env.llvm_i64, @constCast(&fn_params), fn_params.len, 0);
                    const func = c.LLVMGetNamedFunction(env.module, "__openjai_type_info_member_type_id") orelse c.LLVMAddFunction(env.module, "__openjai_type_info_member_type_id", fn_ty);
                    var args = [_]c.LLVMValueRef{member_ptr};
                    const result = c.LLVMBuildCall2(env.builder, fn_ty, func, &args, args.len, "member_type_id");
                    try setIntResult(env, registers, inst.dest, result);
                } else if (std.mem.eql(u8, field_name, "notes")) {
                    const fn_params = [_]c.LLVMTypeRef{env.ptr_ty};
                    const fn_ty = c.LLVMFunctionType(env.ptr_ty, @constCast(&fn_params), fn_params.len, 0);
                    const func = c.LLVMGetNamedFunction(env.module, "__openjai_type_info_member_notes") orelse c.LLVMAddFunction(env.module, "__openjai_type_info_member_notes", fn_ty);
                    var args = [_]c.LLVMValueRef{member_ptr};
                    const result = c.LLVMBuildCall2(env.builder, fn_ty, func, &args, args.len, "member_notes");
                    try setStringResult(env, registers, inst.dest, result);
                } else {
                    const field_id: u64 = if (std.mem.eql(u8, field_name, "flags")) 0 else if (std.mem.eql(u8, field_name, "offset_in_bytes")) 1 else 0;
                    var args = [_]c.LLVMValueRef{ member_ptr, c.LLVMConstInt(env.llvm_i64, field_id, 0) };
                    const result = c.LLVMBuildCall2(env.builder, env.type_info_member_int_field_fn_ty, env.type_info_member_int_field_fn, &args, args.len, "member_int_field");
                    try setIntResult(env, registers, inst.dest, result);
                }
            },
            .load_type_info_member => {
                if (inst.dest >= registers.len) return diag.failAt(0, "LLVM backend load_type_info_member register out of range", .{});
                // Return a pointer into the global type_info_member_pool array
                const pool_global = c.LLVMGetNamedGlobal(env.module, "openjai_type_info_member_pool");
                if (pool_global != null) {
                    // GEP into the pool array to get a pointer to the member entry
                    const member_entry_fields = [_]c.LLVMTypeRef{ env.ptr_ty, env.llvm_i64, env.ptr_ty, env.llvm_i64, env.llvm_i64, env.llvm_i64, env.ptr_ty, env.llvm_i64 };
                    const member_entry_ty = c.LLVMStructTypeInContext(env.context, @constCast(&member_entry_fields), member_entry_fields.len, 0);
                    const pool_arr_ty = c.LLVMArrayType(member_entry_ty, @intCast(env.program.type_info_members.items.len));
                    var gep_indices = [_]c.LLVMValueRef{
                        c.LLVMConstInt(env.llvm_i64, 0, 0),
                        c.LLVMConstInt(env.llvm_i64, inst.arg1, 0),
                    };
                    const member_ptr = c.LLVMBuildGEP2(env.builder, pool_arr_ty, pool_global, &gep_indices, gep_indices.len, "member_ptr");
                    try setPointerResult(env, registers, inst.dest, member_ptr);
                } else {
                    // Fallback: no pool was generated, return null pointer
                    try setPointerResult(env, registers, inst.dest, c.LLVMConstPointerNull(env.ptr_ty));
                }
            },
            .type_info_get_field => {
                if (inst.dest >= registers.len or inst.arg1 >= registers.len or inst.arg2 >= registers.len) {
                    return diag.failAt(0, "LLVM backend type_info_get_field register out of range", .{});
                }
                const type_id_val = try resolveTypeInfoId(env, registers[inst.arg1], diag);
                const str_parts = try stringParts(env, registers[inst.arg2], diag);
                const params = [_]c.LLVMTypeRef{ env.llvm_i64, env.ptr_ty, env.llvm_i64 };
                const fn_ty = c.LLVMFunctionType(env.ptr_ty, @constCast(&params), params.len, 0);
                const fn_ref = c.LLVMGetNamedFunction(env.module, "__openjai_type_info_get_field") orelse c.LLVMAddFunction(env.module, "__openjai_type_info_get_field", fn_ty);
                var args = [_]c.LLVMValueRef{ type_id_val, str_parts.data, str_parts.len };
                const result = c.LLVMBuildCall2(env.builder, fn_ty, fn_ref, &args, args.len, "get_field_result");
                try setPointerResult(env, registers, inst.dest, result);
            },
            .type_info_ptr => {
                if (inst.dest >= registers.len or inst.arg1 >= env.program.strings.items.len) {
                    return diag.failAt(0, "LLVM backend type_info_ptr out of range", .{});
                }
                const type_name = env.program.strings.items[inst.arg1];
                const type_id_val = if (env.program.typeInfoIndexByName(type_name)) |idx|
                    c.LLVMConstInt(env.llvm_i64, type_info_base_id + idx, 0)
                else blk: {
                    const builtin_id = typeIdFromTypeTextLlvm(type_name);
                    if (builtin_id == 0) return diag.failAt(0, "LLVM backend type_info_ptr: unknown type '{s}'", .{type_name});
                    break :blk c.LLVMConstInt(env.llvm_i64, builtin_id, 0);
                };
                registers[inst.dest] = .{ .llvm_value = type_id_val, .kind = .type_id };
            },
            .load_build_options,
            .host_set_build_options,
            .host_set_optimization,
            .build_options_get_field,
            .build_options_set_field,
            .host_compiler_create_workspace,
            .host_get_current_workspace,
            .host_add_build_string,
            .host_generate_bindings,
            .host_set_workspace_status,
            .host_build_cpp_dynamic_lib,
            .host_custom_link_complete,
            .host_run_command,
            .host_run_command_capture,
            => {
                if (inst.dest < registers.len) registers[inst.dest] = .{ .llvm_value = c.LLVMConstInt(env.llvm_i64, 0, 0), .kind = .int };
                _ = c.LLVMBuildCall2(env.builder, env.assert_fail_fn_ty, env.assert_fail_fn, null, 0, "");
                _ = c.LLVMBuildUnreachable(env.builder);
                terminates_block = true;
            },
            else => return diag.failAt(0, "unsupported bytecode opcode in LLVM backend: {s}", .{@tagName(inst.opcode)}),
        }
        if (terminates_block) {
            if (instruction_index + 1 < instruction_count and !is_block_start[instruction_index + 1]) {
                const dead_bb = c.LLVMAppendBasicBlockInContext(env.context, function, "dead");
                c.LLVMPositionBuilderAtEnd(env.builder, dead_bb);
            }
        } else if (is_block_start[instruction_index + 1]) {
            _ = c.LLVMBuildBr(env.builder, blocks[instruction_index + 1].?);
        }
    }
    if (blocks[instruction_count]) |end_block| {
        c.LLVMPositionBuilderAtEnd(env.builder, end_block);
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
        format_int: struct { base: c.LLVMValueRef, minimum_digits: c.LLVMValueRef },
        format_float: struct { width: c.LLVMValueRef, trailing_width: c.LLVMValueRef, zero_removal: u32, mode: u32 },
        int,
        uint,
        int_addr: u32,
        uint_addr: u32,
        bool_addr: u32,
        pointer,
        pointer_addr: u32,
        string_addr: u32,
        calendar,
        float,
        float_addr: u32,
        bool,
        void_value,
        type_id,
        tuple: []const u32,
        source_location: struct { file: Bytecode.StringIndex, line: u32 },
    };
};

// User-defined type IDs start at this offset to avoid colliding with builtin type IDs (1-31).
// Must match USER_TYPE_ID_OFFSET in rt/core.zig.
const type_info_base_id: u64 = 0x10000;

fn typeIdFromTypeTextLlvm(name: []const u8) u64 {
    if (std.mem.eql(u8, name, "bool")) return 1;
    if (std.mem.eql(u8, name, "s32") or std.mem.eql(u8, name, "u32")) return 4;
    if (std.mem.eql(u8, name, "int") or std.mem.eql(u8, name, "s64") or std.mem.eql(u8, name, "u64")) return 5;
    if (std.mem.eql(u8, name, "u8") or std.mem.eql(u8, name, "s8")) return 7;
    if (std.mem.eql(u8, name, "u16") or std.mem.eql(u8, name, "s16")) return 8;
    if (std.mem.eql(u8, name, "float") or std.mem.eql(u8, name, "float32")) return 12;
    if (std.mem.eql(u8, name, "float64")) return 13;
    if (std.mem.eql(u8, name, "string")) return 14;
    if (std.mem.eql(u8, name, "Type")) return 15;
    if (std.mem.eql(u8, name, "Any")) return 16;
    if (std.mem.eql(u8, name, "Vector3")) return 17;
    if (std.mem.eql(u8, name, "Vector4")) return 22;
    return 0;
}

fn staticStringRegister(env: *LlvmEnv, string_idx: Bytecode.StringIndex, diag: Diagnostic) !RegisterValue {
    if (string_idx >= env.program.strings.items.len) return diag.failAt(0, "LLVM backend string index out of range", .{});
    const bytes = env.program.strings.items[string_idx];
    const name_tmp = try std.fmt.allocPrint(env.allocator, "str.{d}", .{string_idx});
    defer env.allocator.free(name_tmp);
    const name = try env.allocator.dupeZ(u8, name_tmp);
    defer env.allocator.free(name);
    const global = c.LLVMGetNamedGlobal(env.module, name.ptr) orelse blk: {
        const ty = c.LLVMArrayType(c.LLVMInt8TypeInContext(env.context), @intCast(bytes.len + 1));
        const created = c.LLVMAddGlobal(env.module, ty, name.ptr);
        c.LLVMSetGlobalConstant(created, 1);
        c.LLVMSetLinkage(created, c.LLVMPrivateLinkage);
        if (bytes.len == 0) {
            c.LLVMSetInitializer(created, c.LLVMConstNull(ty));
        } else {
            c.LLVMSetInitializer(created, c.LLVMConstStringInContext(env.context, bytes.ptr, @intCast(bytes.len), 0));
        }
        break :blk created;
    };
    return .{ .llvm_value = global, .kind = .{ .string = string_idx } };
}

fn registerValueForTypedLlvmValue(value: c.LLVMValueRef, type_id: u32) RegisterValue {
    return switch (type_id) {
        1 => .{ .llvm_value = value, .kind = .bool },
        12, 13 => .{ .llvm_value = value, .kind = .float },
        10, 17 => .{ .llvm_value = value, .kind = .pointer },
        14 => .{ .llvm_value = value, .kind = .runtime_string },
        0 => .{ .llvm_value = value, .kind = .void_value },
        else => .{ .llvm_value = value, .kind = .int },
    };
}

fn defaultLlvmValueForTypeId(env: *LlvmEnv, type_id: u32) c.LLVMValueRef {
    return switch (type_id) {
        1 => c.LLVMConstInt(c.LLVMInt1TypeInContext(env.context), 0, 0),
        12, 13 => c.LLVMConstReal(env.llvm_f64, 0.0),
        10, 14, 17 => c.LLVMConstPointerNull(env.ptr_ty),
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
        .int, .uint, .int_addr, .uint_addr, .bool, .bool_addr, .type_id => c.LLVMBuildIntToPtr(env.builder, try valueAsInt(env, value, diag), env.ptr_ty, "inttoptr"),
        .float => blk: {
            const function = c.LLVMGetBasicBlockParent(c.LLVMGetInsertBlock(env.builder));
            const slot = buildEntryAlloca(env, function, env.llvm_f64, "float_spill");
            _ = c.LLVMBuildStore(env.builder, try valueAsFloat(env, value, diag), slot);
            break :blk slot;
        },
        .float_addr => value.llvm_value,
        .void_value, .unset => c.LLVMConstPointerNull(env.ptr_ty),
        else => diag.failAt(0, "{s} requires pointer-compatible register, got {s}", .{ context, @tagName(value.kind) }),
    };
}

fn builderSlotPointerValue(env: *LlvmEnv, value: RegisterValue, diag: Diagnostic) !c.LLVMValueRef {
    return switch (value.kind) {
        .pointer, .pointer_addr => value.llvm_value,
        else => pointerValue(env, value, diag, "String_Builder procedure call argument"),
    };
}

fn runtimeStringValue(env: *LlvmEnv, value: RegisterValue, diag: Diagnostic) anyerror!c.LLVMValueRef {
    return switch (value.kind) {
        .runtime_string => value.llvm_value,
        .string_addr => c.LLVMBuildLoad2(env.builder, env.ptr_ty, value.llvm_value, "load_runtime_string_local"),
        .string => |string_idx| blk: {
            if (string_idx >= env.program.strings.items.len) return diag.failAt(0, "LLVM backend string index out of range", .{});
            const data = c.LLVMBuildPointerCast(env.builder, value.llvm_value, env.ptr_ty, "literal_strdata_ptr");
            const len = c.LLVMConstInt(env.llvm_i64, env.program.strings.items[string_idx].len, 0);
            var args = [_]c.LLVMValueRef{ data, len };
            break :blk c.LLVMBuildCall2(env.builder, env.string_from_parts_fn_ty, env.string_from_parts_fn, &args, args.len, "literal_runtime_string");
        },
        .pointer => value.llvm_value,
        .pointer_addr => c.LLVMBuildLoad2(env.builder, env.ptr_ty, value.llvm_value, "load_runtime_string_addr"),
        .int, .uint, .int_addr, .uint_addr => c.LLVMBuildIntToPtr(env.builder, try valueAsInt(env, value, diag), env.ptr_ty, "runtime_string_inttoptr"),
        .bool, .bool_addr => blk: {
            const bool_value = try valueAsBool(env, value, diag);
            const true_text = c.LLVMBuildGlobalStringPtr(env.builder, "true", "bool_true_text");
            const false_text = c.LLVMBuildGlobalStringPtr(env.builder, "false", "bool_false_text");
            const data = c.LLVMBuildSelect(env.builder, bool_value, true_text, false_text, "bool_string_data");
            const len = c.LLVMBuildSelect(env.builder, bool_value, c.LLVMConstInt(env.llvm_i64, 4, 0), c.LLVMConstInt(env.llvm_i64, 5, 0), "bool_string_len");
            const function = c.LLVMGetBasicBlockParent(c.LLVMGetInsertBlock(env.builder));
            const pair_ty = c.LLVMArrayType(env.llvm_i64, 2);
            const slot = buildEntryAlloca(env, function, pair_ty, "bool_runtime_string");
            var len_indices = [_]c.LLVMValueRef{ c.LLVMConstInt(env.llvm_i64, 0, 0), c.LLVMConstInt(env.llvm_i64, 0, 0) };
            _ = c.LLVMBuildStore(env.builder, len, c.LLVMBuildGEP2(env.builder, pair_ty, slot, &len_indices, len_indices.len, "bool_strlen_slot"));
            var data_indices = [_]c.LLVMValueRef{ c.LLVMConstInt(env.llvm_i64, 0, 0), c.LLVMConstInt(env.llvm_i64, 1, 0) };
            _ = c.LLVMBuildStore(env.builder, c.LLVMBuildPtrToInt(env.builder, data, env.llvm_i64, "bool_strdata_int"), c.LLVMBuildGEP2(env.builder, pair_ty, slot, &data_indices, data_indices.len, "bool_strdata_slot"));
            break :blk c.LLVMBuildPointerCast(env.builder, slot, env.ptr_ty, "bool_runtime_string_ptr");
        },
        else => diag.failAt(0, "expected string-compatible register, got {s}", .{@tagName(value.kind)}),
    };
}

fn valueAddress(env: *LlvmEnv, value: RegisterValue, diag: Diagnostic) !c.LLVMValueRef {
    const function = c.LLVMGetBasicBlockParent(c.LLVMGetInsertBlock(env.builder));
    switch (value.kind) {
        .int, .uint, .int_addr, .uint_addr, .bool, .bool_addr, .type_id => {
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
        .float_addr => return value.llvm_value,
        .void_value, .unset => {
            const slot = buildEntryAlloca(env, function, env.llvm_i64, "value_addr_void");
            _ = c.LLVMBuildStore(env.builder, c.LLVMConstInt(env.llvm_i64, 0, 0), slot);
            return slot;
        },
        else => return diag.failAt(0, "cannot take byte address of register kind {s}", .{@tagName(value.kind)}),
    }
}

fn valueAsInt(env: *LlvmEnv, value: RegisterValue, diag: Diagnostic) !c.LLVMValueRef {
    return switch (value.kind) {
        .int, .uint => if (c.LLVMGetTypeKind(c.LLVMTypeOf(value.llvm_value)) == c.LLVMPointerTypeKind)
            c.LLVMBuildPtrToInt(env.builder, value.llvm_value, env.llvm_i64, "intkind_ptrtoint")
        else
            value.llvm_value,
        .int_addr => c.LLVMBuildLoad2(env.builder, env.llvm_i64, value.llvm_value, "load_int_addr_cmp"),
        .uint_addr => c.LLVMBuildLoad2(env.builder, env.llvm_i64, value.llvm_value, "load_uint_addr_cmp"),
        .bool => c.LLVMBuildZExt(env.builder, value.llvm_value, env.llvm_i64, "booltoint"),
        .bool_addr => c.LLVMBuildZExt(env.builder, c.LLVMBuildLoad2(env.builder, c.LLVMInt1TypeInContext(env.context), value.llvm_value, "load_bool_addr_int"), env.llvm_i64, "booladdrtoint"),
        .pointer => c.LLVMBuildPtrToInt(env.builder, value.llvm_value, env.llvm_i64, "ptrtoint"),
        .pointer_addr => c.LLVMBuildPtrToInt(env.builder, c.LLVMBuildLoad2(env.builder, env.ptr_ty, value.llvm_value, "load_ptr_addr_int"), env.llvm_i64, "ptraddrtoint"),
        .string, .runtime_string, .string_addr => c.LLVMBuildPtrToInt(env.builder, try runtimeStringValue(env, value, diag), env.llvm_i64, "strptrtoint"),
        .undefined_string => c.LLVMConstInt(env.llvm_i64, 0, 0),
        .type_id => value.llvm_value,
        .void_value, .unset => c.LLVMConstInt(env.llvm_i64, 0, 0),
        else => diag.failAt(0, "expected integer-compatible register in proc '{s}' ({d}) for LLVM instruction {s}#{d}, got {s}", .{ env.current_proc_name, env.current_proc_index, @tagName(env.current_opcode), env.current_instruction_index, @tagName(value.kind) }),
    };
}

fn callArgValueForType(env: *LlvmEnv, value: RegisterValue, type_id: u32, diag: Diagnostic) !c.LLVMValueRef {
    return switch (type_id) {
        1 => valueAsBool(env, value, diag),
        12, 13 => valueAsFloat(env, value, diag),
        10 => pointerValue(env, value, diag, "procedure call argument"),
        17 => builderSlotPointerValue(env, value, diag),
        14 => runtimeStringValue(env, value, diag),
        else => valueAsInt(env, value, diag),
    };
}

fn setTypedResult(env: *LlvmEnv, registers: []RegisterValue, dest: u32, value: c.LLVMValueRef, type_id: u32) !void {
    switch (type_id) {
        1 => try setBoolResult(env, registers, dest, value),
        12, 13 => try setFloatResult(env, registers, dest, value),
        10, 17 => try setPointerResult(env, registers, dest, value),
        14 => try setStringResult(env, registers, dest, value),
        else => try setIntResult(env, registers, dest, value),
    }
}

fn isStructKind(kind: anytype) bool {
    return switch (kind) {
        .pointer, .pointer_addr => true,
        else => false,
    };
}

fn isFloatKind(kind: anytype) bool {
    return switch (kind) {
        .float, .float_addr => true,
        else => false,
    };
}

fn setFloatResult(env: *LlvmEnv, registers: []RegisterValue, dest: u32, value: c.LLVMValueRef) !void {
    if (registers[dest].kind == .float_addr) {
        _ = c.LLVMBuildStore(env.builder, value, registers[dest].llvm_value);
        return;
    }
    const function = c.LLVMGetBasicBlockParent(c.LLVMGetInsertBlock(env.builder));
    const slot = buildEntryAlloca(env, function, env.llvm_f64, "float_reg");
    _ = c.LLVMBuildStore(env.builder, value, slot);
    registers[dest] = .{ .llvm_value = slot, .kind = .{ .float_addr = dest } };
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

fn setStringResult(env: *LlvmEnv, registers: []RegisterValue, dest: u32, value: c.LLVMValueRef) !void {
    if (registers[dest].kind == .string_addr) {
        _ = c.LLVMBuildStore(env.builder, value, registers[dest].llvm_value);
        return;
    }
    const function = c.LLVMGetBasicBlockParent(c.LLVMGetInsertBlock(env.builder));
    const slot = buildEntryAlloca(env, function, env.ptr_ty, "str_reg");
    _ = c.LLVMBuildStore(env.builder, value, slot);
    registers[dest] = .{ .llvm_value = slot, .kind = .{ .string_addr = dest } };
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
        .float_addr => c.LLVMBuildLoad2(env.builder, env.llvm_f64, value.llvm_value, "load_float_addr"),
        .int, .int_addr, .bool, .bool_addr => c.LLVMBuildSIToFP(env.builder, try valueAsInt(env, value, diag), env.llvm_f64, "tofp"),
        .uint, .uint_addr => c.LLVMBuildUIToFP(env.builder, try valueAsInt(env, value, diag), env.llvm_f64, "uitofp"),
        else => diag.failAt(0, "expected numeric register in proc '{s}' ({d}) for LLVM instruction {s}#{d}, got {s}", .{ env.current_proc_name, env.current_proc_index, @tagName(env.current_opcode), env.current_instruction_index, @tagName(value.kind) }),
    };
}

fn buildUnaryFloatIntrinsic(env: *LlvmEnv, name: [:0]const u8, arg: c.LLVMValueRef) !c.LLVMValueRef {
    const params = [_]c.LLVMTypeRef{env.llvm_f64};
    const fn_ty = c.LLVMFunctionType(env.llvm_f64, @constCast(&params), params.len, 0);
    const fn_ref = c.LLVMGetNamedFunction(env.module, name.ptr) orelse c.LLVMAddFunction(env.module, name.ptr, fn_ty);
    var args = [_]c.LLVMValueRef{arg};
    return c.LLVMBuildCall2(env.builder, fn_ty, fn_ref, &args, args.len, "float_math");
}

fn valueAsBool(env: *LlvmEnv, value: RegisterValue, diag: Diagnostic) !c.LLVMValueRef {
    return switch (value.kind) {
        .bool => value.llvm_value,
        .bool_addr => c.LLVMBuildLoad2(env.builder, c.LLVMInt1TypeInContext(env.context), value.llvm_value, "load_bool_addr"),
        .int, .uint, .int_addr, .uint_addr, .type_id, .void_value => c.LLVMBuildICmp(env.builder, c.LLVMIntNE, try valueAsInt(env, value, diag), c.LLVMConstInt(env.llvm_i64, 0, 0), "tobool"),
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
        .float_addr => c.LLVMBuildFCmp(env.builder, c.LLVMRealONE, c.LLVMBuildLoad2(env.builder, env.llvm_f64, value.llvm_value, "load_float_bool"), c.LLVMConstReal(env.llvm_f64, 0.0), "float_nonzero"),
        else => diag.failAt(0, "expected bool-compatible register in proc '{s}' ({d}), got {s}", .{ env.current_proc_name, env.current_proc_index, @tagName(value.kind) }),
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
        .pointer, .pointer_addr, .int, .uint, .int_addr, .uint_addr => true,
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
        .pointer, .pointer_addr, .int, .uint, .int_addr, .uint_addr => blk: {
            const runtime_string = switch (value.kind) {
                .pointer => value.llvm_value,
                .pointer_addr => c.LLVMBuildLoad2(env.builder, env.ptr_ty, value.llvm_value, "opaque_load_ptr_addr"),
                .int, .uint, .int_addr, .uint_addr => c.LLVMBuildIntToPtr(env.builder, try valueAsInt(env, value, diag), env.ptr_ty, "opaque_strptr"),
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

fn emitBuilderAppendValue(env: *LlvmEnv, builder_slot_value: RegisterValue, arg: RegisterValue, diag: Diagnostic) !void {
    const builder_slot = try pointerValue(env, builder_slot_value, diag, "string builder slot");
    switch (arg.kind) {
        .string, .runtime_string, .string_addr => {
            const parts = try stringParts(env, arg, diag);
            var args = [_]c.LLVMValueRef{ builder_slot, parts.data, parts.len };
            _ = c.LLVMBuildCall2(env.builder, env.string_builder_append_string_fn_ty, env.string_builder_append_string_fn, &args, args.len, "");
        },
        .format_int => {
            var args = [_]c.LLVMValueRef{ builder_slot, arg.llvm_value };
            _ = c.LLVMBuildCall2(env.builder, env.string_builder_append_int_fn_ty, env.string_builder_append_int_fn, &args, args.len, "");
        },
        .format_float => {
            var args = [_]c.LLVMValueRef{ builder_slot, arg.llvm_value };
            _ = c.LLVMBuildCall2(env.builder, env.string_builder_append_float_fn_ty, env.string_builder_append_float_fn, &args, args.len, "");
        },
        .int, .int_addr, .pointer, .pointer_addr, .type_id, .void_value => {
            var args = [_]c.LLVMValueRef{ builder_slot, try valueAsInt(env, arg, diag) };
            _ = c.LLVMBuildCall2(env.builder, env.string_builder_append_int_fn_ty, env.string_builder_append_int_fn, &args, args.len, "");
        },
        .uint, .uint_addr => {
            var args = [_]c.LLVMValueRef{ builder_slot, try valueAsInt(env, arg, diag) };
            _ = c.LLVMBuildCall2(env.builder, env.string_builder_append_int_fn_ty, env.string_builder_append_int_fn, &args, args.len, "");
        },
        .bool, .bool_addr => {
            var args = [_]c.LLVMValueRef{ builder_slot, try valueAsBool(env, arg, diag) };
            _ = c.LLVMBuildCall2(env.builder, env.string_builder_append_bool_fn_ty, env.string_builder_append_bool_fn, &args, args.len, "");
        },
        .float, .float_addr => {
            var args = [_]c.LLVMValueRef{ builder_slot, try valueAsFloat(env, arg, diag) };
            _ = c.LLVMBuildCall2(env.builder, env.string_builder_append_float_fn_ty, env.string_builder_append_float_fn, &args, args.len, "");
        },
        .undefined_string => return diag.failAt(0, "cannot append explicitly uninitialized string value", .{}),
        else => return diag.failAt(0, "cannot append register kind {s} to String_Builder", .{@tagName(arg.kind)}),
    }
}

fn emitPrintPointerOrNull(env: *LlvmEnv, int_value: c.LLVMValueRef) !void {
    const func = c.LLVMGetBasicBlockParent(c.LLVMGetInsertBlock(env.builder));
    const is_null = c.LLVMBuildICmp(env.builder, c.LLVMIntEQ, int_value, c.LLVMConstInt(env.llvm_i64, 0, 0), "ptr_is_null");
    const then_bb = c.LLVMAppendBasicBlockInContext(env.context, func, "ptr_null");
    const else_bb = c.LLVMAppendBasicBlockInContext(env.context, func, "ptr_nonnull");
    const merge_bb = c.LLVMAppendBasicBlockInContext(env.context, func, "ptr_merge");
    _ = c.LLVMBuildCondBr(env.builder, is_null, then_bb, else_bb);
    c.LLVMPositionBuilderAtEnd(env.builder, then_bb);
    const null_str = c.LLVMBuildGlobalStringPtr(env.builder, "null", "null_str");
    var null_args = [_]c.LLVMValueRef{ null_str, c.LLVMConstInt(env.llvm_i64, 4, 0) };
    _ = c.LLVMBuildCall2(env.builder, env.print_fn_ty, env.print_fn, &null_args, null_args.len, "");
    _ = c.LLVMBuildBr(env.builder, merge_bb);
    c.LLVMPositionBuilderAtEnd(env.builder, else_bb);
    var hex_args = [_]c.LLVMValueRef{ int_value, c.LLVMConstInt(env.llvm_i64, 16, 0), c.LLVMConstInt(env.llvm_i64, 0, 0) };
    _ = c.LLVMBuildCall2(env.builder, env.print_format_int_fn_ty, env.print_format_int_fn, &hex_args, hex_args.len, "");
    _ = c.LLVMBuildBr(env.builder, merge_bb);
    c.LLVMPositionBuilderAtEnd(env.builder, merge_bb);
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
        .uint => {
            var args = [_]c.LLVMValueRef{arg.llvm_value};
            _ = c.LLVMBuildCall2(env.builder, env.print_uint_fn_ty, env.print_uint_fn, &args, args.len, "");
        },
        .format_int => |fmt| {
            var args = [_]c.LLVMValueRef{ arg.llvm_value, fmt.base, fmt.minimum_digits };
            _ = c.LLVMBuildCall2(env.builder, env.print_format_int_fn_ty, env.print_format_int_fn, &args, args.len, "");
        },
        .format_float => |fmt| {
            var args = [_]c.LLVMValueRef{ arg.llvm_value, fmt.width, fmt.trailing_width, c.LLVMConstInt(env.llvm_i64, fmt.zero_removal, 0), c.LLVMConstInt(env.llvm_i64, fmt.mode, 0) };
            _ = c.LLVMBuildCall2(env.builder, env.print_format_float_fn_ty, env.print_format_float_fn, &args, args.len, "");
        },
        .int_addr => {
            const loaded = c.LLVMBuildLoad2(env.builder, env.llvm_i64, arg.llvm_value, "print_load_int_addr");
            var args = [_]c.LLVMValueRef{loaded};
            _ = c.LLVMBuildCall2(env.builder, env.print_int_fn_ty, env.print_int_fn, &args, args.len, "");
        },
        .uint_addr => {
            const loaded = c.LLVMBuildLoad2(env.builder, env.llvm_i64, arg.llvm_value, "print_load_uint_addr");
            var args = [_]c.LLVMValueRef{loaded};
            _ = c.LLVMBuildCall2(env.builder, env.print_uint_fn_ty, env.print_uint_fn, &args, args.len, "");
        },
        .pointer => {
            const as_int = c.LLVMBuildPtrToInt(env.builder, arg.llvm_value, env.llvm_i64, "ptrtoint");
            try emitPrintPointerOrNull(env, as_int);
        },
        .pointer_addr => {
            const ptr = c.LLVMBuildLoad2(env.builder, env.ptr_ty, arg.llvm_value, "print_load_ptr_addr");
            const as_int = c.LLVMBuildPtrToInt(env.builder, ptr, env.llvm_i64, "ptraddrtoint");
            try emitPrintPointerOrNull(env, as_int);
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
        .float_addr => {
            const loaded = c.LLVMBuildLoad2(env.builder, env.llvm_f64, arg.llvm_value, "load_float_print");
            var args = [_]c.LLVMValueRef{loaded};
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
        .source_location => |loc| {
            try emitPrintValue(env, try staticStringRegister(env, loc.file, diag), diag);
            const colon = c.LLVMBuildGlobalStringPtr(env.builder, ":", "source_location_colon");
            var colon_args = [_]c.LLVMValueRef{ colon, c.LLVMConstInt(env.llvm_i64, 1, 0) };
            _ = c.LLVMBuildCall2(env.builder, env.print_fn_ty, env.print_fn, &colon_args, colon_args.len, "");
            var line_args = [_]c.LLVMValueRef{c.LLVMConstInt(env.llvm_i64, loc.line, 0)};
            _ = c.LLVMBuildCall2(env.builder, env.print_int_fn_ty, env.print_int_fn, &line_args, line_args.len, "");
        },
        .bool => {
            var args = [_]c.LLVMValueRef{arg.llvm_value};
            _ = c.LLVMBuildCall2(env.builder, env.print_bool_fn_ty, env.print_bool_fn, &args, args.len, "");
        },
        .bool_addr => {
            var args = [_]c.LLVMValueRef{try valueAsBool(env, arg, diag)};
            _ = c.LLVMBuildCall2(env.builder, env.print_bool_fn_ty, env.print_bool_fn, &args, args.len, "");
        },
        .tuple => |types| {
            if (types.len == 0) return;
            const first = c.LLVMBuildExtractValue(env.builder, arg.llvm_value, 0, "print_tuple_first");
            const first_type = types[0];
            var first_reg = RegisterValue{ .llvm_value = first, .kind = .unset };
            try setTypedResult(env, @as(*[1]RegisterValue, &first_reg), 0, first, first_type);
            try emitPrintValue(env, first_reg, diag);
        },
        .unset => return diag.failAt(0, "LLVM backend print argument register was not initialized", .{}),
    }
}

const BuiltinTagInfo = struct {
    type_name: []const u8,
    tag_name: []const u8,
    tag_value: u64,
};

fn builtinTypeInfoTag(env: *LlvmEnv, value: RegisterValue) ?BuiltinTagInfo {
    const type_name = switch (value.kind) {
        .string => |string_idx| blk: {
            if (string_idx >= env.program.strings.items.len) break :blk null;
            break :blk env.program.strings.items[string_idx];
        },
        else => null,
    } orelse return null;
    // Check if this is a builtin type that won't be in the type_info_table
    if (env.program.typeInfoIndexByName(type_name) != null) return null;
    if (std.mem.eql(u8, type_name, "int") or std.mem.eql(u8, type_name, "s64") or std.mem.eql(u8, type_name, "s32") or std.mem.eql(u8, type_name, "s16") or std.mem.eql(u8, type_name, "s8") or std.mem.eql(u8, type_name, "u8") or std.mem.eql(u8, type_name, "u16") or std.mem.eql(u8, type_name, "u32") or std.mem.eql(u8, type_name, "u64")) return .{ .type_name = type_name, .tag_name = "INTEGER", .tag_value = 1 };
    if (std.mem.eql(u8, type_name, "float") or std.mem.eql(u8, type_name, "float32") or std.mem.eql(u8, type_name, "float64")) return .{ .type_name = type_name, .tag_name = "FLOAT", .tag_value = 2 };
    if (std.mem.eql(u8, type_name, "bool")) return .{ .type_name = type_name, .tag_name = "BOOL", .tag_value = 3 };
    if (std.mem.eql(u8, type_name, "string")) return .{ .type_name = type_name, .tag_name = "STRING", .tag_value = 9 };
    if (std.mem.eql(u8, type_name, "void")) return .{ .type_name = type_name, .tag_name = "VOID", .tag_value = 0 };
    if (std.mem.eql(u8, type_name, "Any")) return .{ .type_name = type_name, .tag_name = "ANY", .tag_value = 0 };
    if (std.mem.eql(u8, type_name, "Procedure")) return .{ .type_name = type_name, .tag_name = "PROCEDURE", .tag_value = 8 };
    if (std.mem.startsWith(u8, type_name, "*")) return .{ .type_name = type_name, .tag_name = "POINTER", .tag_value = 4 };
    return null;
}

/// Create a runtime string from inline text (not from the string pool).
fn emitInlineRuntimeString(env: *LlvmEnv, text: []const u8) !c.LLVMValueRef {
    // Create a global constant for the text
    const ty = c.LLVMArrayType(c.LLVMInt8TypeInContext(env.context), @intCast(text.len));
    const g = c.LLVMAddGlobal(env.module, ty, "builtin_type_str");
    c.LLVMSetGlobalConstant(g, 1);
    c.LLVMSetLinkage(g, c.LLVMPrivateLinkage);
    if (text.len > 0) {
        c.LLVMSetInitializer(g, c.LLVMConstStringInContext(env.context, text.ptr, @intCast(text.len), 1));
    } else {
        c.LLVMSetInitializer(g, c.LLVMConstNull(ty));
    }
    const data_ptr = c.LLVMBuildPointerCast(env.builder, g, env.ptr_ty, "builtin_str_ptr");
    const len = c.LLVMConstInt(env.llvm_i64, text.len, 0);
    var args = [_]c.LLVMValueRef{ data_ptr, len };
    return c.LLVMBuildCall2(env.builder, env.string_from_parts_fn_ty, env.string_from_parts_fn, &args, args.len, "builtin_runtime_string");
}

/// Resolve a register value that may be a type_id (int), type_text (string), or pointer
/// into an i64 type_id value suitable for calling __openjai_type_info_* runtime functions.
/// For string type texts, this calls __openjai_type_info_lookup at runtime.
/// For type_id/int values, this returns the value directly.
fn resolveTypeInfoId(env: *LlvmEnv, value: RegisterValue, diag: Diagnostic) !c.LLVMValueRef {
    return switch (value.kind) {
        .type_id, .int, .uint, .int_addr, .uint_addr => valueAsInt(env, value, diag),
        .string => |string_idx| blk: {
            // Compile-time type text - look up by name at compile time if possible
            if (string_idx < env.program.strings.items.len) {
                const type_name = env.program.strings.items[string_idx];
                if (env.program.typeInfoIndexByName(type_name)) |idx| {
                    break :blk c.LLVMConstInt(env.llvm_i64, idx, 0);
                }
            }
            // Fallback: runtime lookup
            const str_ptr = c.LLVMBuildPointerCast(env.builder, value.llvm_value, env.ptr_ty, "type_text_ptr");
            const str_len = if (string_idx < env.program.strings.items.len)
                c.LLVMConstInt(env.llvm_i64, env.program.strings.items[string_idx].len, 0)
            else
                c.LLVMConstInt(env.llvm_i64, 0, 0);
            var args = [_]c.LLVMValueRef{ str_ptr, str_len };
            break :blk c.LLVMBuildCall2(env.builder, env.type_info_lookup_fn_ty, env.type_info_lookup_fn, &args, args.len, "type_info_lookup");
        },
        .runtime_string, .string_addr => blk: {
            // Runtime string - need to extract ptr/len and call lookup
            // For runtime strings, we get the ptr which is an OpenJaiRuntimeString (len + ptr)
            const str_val = try runtimeStringValue(env, value, diag);
            // OpenJaiRuntimeString layout: { len: i64, data_ptr: i64 }
            // Load len (first i64)
            const len_ptr = c.LLVMBuildPointerCast(env.builder, str_val, env.ptr_ty, "rs_len_ptr");
            const len = c.LLVMBuildLoad2(env.builder, env.llvm_i64, len_ptr, "rs_len");
            // Load data_ptr (second i64, at offset 8)
            var offset = [_]c.LLVMValueRef{c.LLVMConstInt(env.llvm_i64, 8, 0)};
            const data_addr = c.LLVMBuildGEP2(env.builder, c.LLVMInt8TypeInContext(env.context), str_val, &offset, 1, "rs_data_addr");
            const data_int = c.LLVMBuildLoad2(env.builder, env.llvm_i64, data_addr, "rs_data_int");
            const data_ptr = c.LLVMBuildIntToPtr(env.builder, data_int, env.ptr_ty, "rs_data_ptr");
            var args = [_]c.LLVMValueRef{ data_ptr, len };
            break :blk c.LLVMBuildCall2(env.builder, env.type_info_lookup_fn_ty, env.type_info_lookup_fn, &args, args.len, "type_info_lookup");
        },
        .pointer, .pointer_addr => valueAsInt(env, value, diag),
        else => c.LLVMConstInt(env.llvm_i64, 0, 0),
    };
}

fn emitTypeInfoTable(env: *LlvmEnv) !void {
    const type_infos = env.program.type_infos.items;
    const count = type_infos.len;
    if (count == 0) {
        // Even with no type infos, call set_type_info_table with null/0
        var args = [_]c.LLVMValueRef{
            c.LLVMConstPointerNull(env.ptr_ty),
            c.LLVMConstInt(env.llvm_i64, 0, 0),
        };
        _ = c.LLVMBuildCall2(env.builder, env.set_type_info_table_fn_ty, env.set_type_info_table_fn, &args, args.len, "");
        return;
    }

    // TypeInfoMemberEntry struct layout: { name_ptr: ptr, name_len: i64, type_name_ptr: ptr, type_name_len: i64, flags: i64, offset_in_bytes: i64 }
    const member_entry_fields = [_]c.LLVMTypeRef{ env.ptr_ty, env.llvm_i64, env.ptr_ty, env.llvm_i64, env.llvm_i64, env.llvm_i64, env.ptr_ty, env.llvm_i64 };
    const member_entry_ty = c.LLVMStructTypeInContext(env.context, @constCast(&member_entry_fields), member_entry_fields.len, 0);

    // TypeInfoEntry struct layout: { name_ptr: ptr, name_len: i64, tag: i64, member_count: i64, members: ptr, runtime_size: i64 }
    const type_entry_fields = [_]c.LLVMTypeRef{ env.ptr_ty, env.llvm_i64, env.llvm_i64, env.llvm_i64, env.ptr_ty, env.llvm_i64, env.ptr_ty, env.llvm_i64 };
    const type_entry_ty = c.LLVMStructTypeInContext(env.context, @constCast(&type_entry_fields), type_entry_fields.len, 0);

    // Create global constant arrays for each type's members, and string globals for names
    var type_entry_values = try env.allocator.alloc(c.LLVMValueRef, count);
    defer env.allocator.free(type_entry_values);

    for (type_infos, 0..) |ti, ti_idx| {
        // Create name string global
        const name_global = blk: {
            const name_z = try std.fmt.allocPrint(env.allocator, "ti_name_{d}", .{ti_idx});
            defer env.allocator.free(name_z);
            const name_z2 = try env.allocator.dupeZ(u8, name_z);
            defer env.allocator.free(name_z2);
            const ty = c.LLVMArrayType(c.LLVMInt8TypeInContext(env.context), @intCast(ti.name.len));
            const g = c.LLVMAddGlobal(env.module, ty, name_z2.ptr);
            c.LLVMSetGlobalConstant(g, 1);
            c.LLVMSetLinkage(g, c.LLVMPrivateLinkage);
            if (ti.name.len > 0) {
                c.LLVMSetInitializer(g, c.LLVMConstStringInContext(env.context, ti.name.ptr, @intCast(ti.name.len), 1));
            } else {
                c.LLVMSetInitializer(g, c.LLVMConstNull(ty));
            }
            break :blk g;
        };

        // Create member entries array
        const members_global = blk: {
            if (ti.members.len == 0) {
                break :blk c.LLVMConstPointerNull(env.ptr_ty);
            }
            var member_values = try env.allocator.alloc(c.LLVMValueRef, ti.members.len);
            defer env.allocator.free(member_values);
            for (ti.members, 0..) |member, m_idx| {
                // Create member name string global
                const m_name_global = mblk: {
                    const m_name_z = try std.fmt.allocPrint(env.allocator, "ti_{d}_m_{d}_name", .{ ti_idx, m_idx });
                    defer env.allocator.free(m_name_z);
                    const m_name_z2 = try env.allocator.dupeZ(u8, m_name_z);
                    defer env.allocator.free(m_name_z2);
                    const mty = c.LLVMArrayType(c.LLVMInt8TypeInContext(env.context), @intCast(member.name.len));
                    const mg = c.LLVMAddGlobal(env.module, mty, m_name_z2.ptr);
                    c.LLVMSetGlobalConstant(mg, 1);
                    c.LLVMSetLinkage(mg, c.LLVMPrivateLinkage);
                    if (member.name.len > 0) {
                        c.LLVMSetInitializer(mg, c.LLVMConstStringInContext(env.context, member.name.ptr, @intCast(member.name.len), 1));
                    } else {
                        c.LLVMSetInitializer(mg, c.LLVMConstNull(mty));
                    }
                    break :mblk mg;
                };
                // Create member type_name string global
                const m_type_name_global = mblk: {
                    const m_tn_z = try std.fmt.allocPrint(env.allocator, "ti_{d}_m_{d}_typename", .{ ti_idx, m_idx });
                    defer env.allocator.free(m_tn_z);
                    const m_tn_z2 = try env.allocator.dupeZ(u8, m_tn_z);
                    defer env.allocator.free(m_tn_z2);
                    const tnty = c.LLVMArrayType(c.LLVMInt8TypeInContext(env.context), @intCast(member.type_name.len));
                    const tng = c.LLVMAddGlobal(env.module, tnty, m_tn_z2.ptr);
                    c.LLVMSetGlobalConstant(tng, 1);
                    c.LLVMSetLinkage(tng, c.LLVMPrivateLinkage);
                    if (member.type_name.len > 0) {
                        c.LLVMSetInitializer(tng, c.LLVMConstStringInContext(env.context, member.type_name.ptr, @intCast(member.type_name.len), 1));
                    } else {
                        c.LLVMSetInitializer(tng, c.LLVMConstNull(tnty));
                    }
                    break :mblk tng;
                };
                const m_notes_str = formatNotesString(env.allocator, member.notes) catch "[]";
                const m_notes_global = mblk: {
                    const m_notes_z = try std.fmt.allocPrint(env.allocator, "ti_{d}_m_{d}_notes", .{ ti_idx, m_idx });
                    defer env.allocator.free(m_notes_z);
                    const m_notes_z2 = try env.allocator.dupeZ(u8, m_notes_z);
                    defer env.allocator.free(m_notes_z2);
                    const nty = c.LLVMArrayType(c.LLVMInt8TypeInContext(env.context), @intCast(m_notes_str.len));
                    const ng = c.LLVMAddGlobal(env.module, nty, m_notes_z2.ptr);
                    c.LLVMSetGlobalConstant(ng, 1);
                    c.LLVMSetLinkage(ng, c.LLVMPrivateLinkage);
                    c.LLVMSetInitializer(ng, c.LLVMConstStringInContext(env.context, m_notes_str.ptr, @intCast(m_notes_str.len), 1));
                    break :mblk ng;
                };
                var member_fields_vals = [_]c.LLVMValueRef{
                    m_name_global,
                    c.LLVMConstInt(env.llvm_i64, member.name.len, 0),
                    m_type_name_global,
                    c.LLVMConstInt(env.llvm_i64, member.type_name.len, 0),
                    c.LLVMConstInt(env.llvm_i64, member.flags, 0),
                    c.LLVMConstInt(env.llvm_i64, member.offset_in_bytes, 0),
                    m_notes_global,
                    c.LLVMConstInt(env.llvm_i64, m_notes_str.len, 0),
                };
                member_values[m_idx] = c.LLVMConstStructInContext(env.context, &member_fields_vals, member_fields_vals.len, 0);
            }
            // Create global array of member entries
            const members_arr_ty = c.LLVMArrayType(member_entry_ty, @intCast(ti.members.len));
            const members_arr_name = try std.fmt.allocPrint(env.allocator, "ti_{d}_members", .{ti_idx});
            defer env.allocator.free(members_arr_name);
            const members_arr_name_z = try env.allocator.dupeZ(u8, members_arr_name);
            defer env.allocator.free(members_arr_name_z);
            const members_g = c.LLVMAddGlobal(env.module, members_arr_ty, members_arr_name_z.ptr);
            c.LLVMSetGlobalConstant(members_g, 1);
            c.LLVMSetLinkage(members_g, c.LLVMPrivateLinkage);
            c.LLVMSetInitializer(members_g, c.LLVMConstArray(member_entry_ty, member_values.ptr, @intCast(ti.members.len)));
            break :blk members_g;
        };

        const ti_notes_str = formatNotesString(env.allocator, ti.notes) catch "[]";
        const ti_notes_global = blk2: {
            const tn_z = try std.fmt.allocPrint(env.allocator, "ti_{d}_notes", .{ti_idx});
            defer env.allocator.free(tn_z);
            const tn_z2 = try env.allocator.dupeZ(u8, tn_z);
            defer env.allocator.free(tn_z2);
            const nty = c.LLVMArrayType(c.LLVMInt8TypeInContext(env.context), @intCast(ti_notes_str.len));
            const ng = c.LLVMAddGlobal(env.module, nty, tn_z2.ptr);
            c.LLVMSetGlobalConstant(ng, 1);
            c.LLVMSetLinkage(ng, c.LLVMPrivateLinkage);
            c.LLVMSetInitializer(ng, c.LLVMConstStringInContext(env.context, ti_notes_str.ptr, @intCast(ti_notes_str.len), 1));
            break :blk2 ng;
        };
        var type_fields_vals = [_]c.LLVMValueRef{
            name_global,
            c.LLVMConstInt(env.llvm_i64, ti.name.len, 0),
            c.LLVMConstInt(env.llvm_i64, ti.tag, 0),
            c.LLVMConstInt(env.llvm_i64, ti.members.len, 0),
            members_global,
            c.LLVMConstInt(env.llvm_i64, ti.runtime_size, 0),
            ti_notes_global,
            c.LLVMConstInt(env.llvm_i64, ti_notes_str.len, 0),
        };
        type_entry_values[ti_idx] = c.LLVMConstStructInContext(env.context, &type_fields_vals, type_fields_vals.len, 0);
    }

    // Create global array of TypeInfoEntry
    const table_arr_ty = c.LLVMArrayType(type_entry_ty, @intCast(count));
    const table_global = c.LLVMAddGlobal(env.module, table_arr_ty, "openjai_type_info_table");
    c.LLVMSetGlobalConstant(table_global, 1);
    c.LLVMSetLinkage(table_global, c.LLVMPrivateLinkage);
    c.LLVMSetInitializer(table_global, c.LLVMConstArray(type_entry_ty, type_entry_values.ptr, @intCast(count)));

    // Also create a global array for type_info_members pool (used by load_type_info_member)
    const ti_members = env.program.type_info_members.items;
    if (ti_members.len > 0) {
        var pool_values = try env.allocator.alloc(c.LLVMValueRef, ti_members.len);
        defer env.allocator.free(pool_values);
        for (ti_members, 0..) |member, m_idx| {
            const m_name_global = mblk: {
                const nm = try std.fmt.allocPrint(env.allocator, "tim_{d}_name", .{m_idx});
                defer env.allocator.free(nm);
                const nm_z = try env.allocator.dupeZ(u8, nm);
                defer env.allocator.free(nm_z);
                const mty = c.LLVMArrayType(c.LLVMInt8TypeInContext(env.context), @intCast(member.name.len));
                const mg = c.LLVMAddGlobal(env.module, mty, nm_z.ptr);
                c.LLVMSetGlobalConstant(mg, 1);
                c.LLVMSetLinkage(mg, c.LLVMPrivateLinkage);
                if (member.name.len > 0) {
                    c.LLVMSetInitializer(mg, c.LLVMConstStringInContext(env.context, member.name.ptr, @intCast(member.name.len), 1));
                } else {
                    c.LLVMSetInitializer(mg, c.LLVMConstNull(mty));
                }
                break :mblk mg;
            };
            const m_type_name_global = mblk: {
                const tn = try std.fmt.allocPrint(env.allocator, "tim_{d}_typename", .{m_idx});
                defer env.allocator.free(tn);
                const tn_z = try env.allocator.dupeZ(u8, tn);
                defer env.allocator.free(tn_z);
                const tnty = c.LLVMArrayType(c.LLVMInt8TypeInContext(env.context), @intCast(member.type_name.len));
                const tng = c.LLVMAddGlobal(env.module, tnty, tn_z.ptr);
                c.LLVMSetGlobalConstant(tng, 1);
                c.LLVMSetLinkage(tng, c.LLVMPrivateLinkage);
                if (member.type_name.len > 0) {
                    c.LLVMSetInitializer(tng, c.LLVMConstStringInContext(env.context, member.type_name.ptr, @intCast(member.type_name.len), 1));
                } else {
                    c.LLVMSetInitializer(tng, c.LLVMConstNull(tnty));
                }
                break :mblk tng;
            };
            const pool_notes_str = formatNotesString(env.allocator, member.notes) catch "[]";
            const pool_notes_global = mblk: {
                const pn = try std.fmt.allocPrint(env.allocator, "tim_{d}_notes", .{m_idx});
                defer env.allocator.free(pn);
                const pn_z = try env.allocator.dupeZ(u8, pn);
                defer env.allocator.free(pn_z);
                const pnty = c.LLVMArrayType(c.LLVMInt8TypeInContext(env.context), @intCast(pool_notes_str.len));
                const png = c.LLVMAddGlobal(env.module, pnty, pn_z.ptr);
                c.LLVMSetGlobalConstant(png, 1);
                c.LLVMSetLinkage(png, c.LLVMPrivateLinkage);
                c.LLVMSetInitializer(png, c.LLVMConstStringInContext(env.context, pool_notes_str.ptr, @intCast(pool_notes_str.len), 1));
                break :mblk png;
            };
            var member_fields_vals = [_]c.LLVMValueRef{
                m_name_global,
                c.LLVMConstInt(env.llvm_i64, member.name.len, 0),
                m_type_name_global,
                c.LLVMConstInt(env.llvm_i64, member.type_name.len, 0),
                c.LLVMConstInt(env.llvm_i64, member.flags, 0),
                c.LLVMConstInt(env.llvm_i64, member.offset_in_bytes, 0),
                pool_notes_global,
                c.LLVMConstInt(env.llvm_i64, pool_notes_str.len, 0),
            };
            pool_values[m_idx] = c.LLVMConstStructInContext(env.context, &member_fields_vals, member_fields_vals.len, 0);
        }
        const pool_arr_ty = c.LLVMArrayType(member_entry_ty, @intCast(ti_members.len));
        const pool_global = c.LLVMAddGlobal(env.module, pool_arr_ty, "openjai_type_info_member_pool");
        c.LLVMSetGlobalConstant(pool_global, 1);
        c.LLVMSetLinkage(pool_global, c.LLVMPrivateLinkage);
        c.LLVMSetInitializer(pool_global, c.LLVMConstArray(member_entry_ty, pool_values.ptr, @intCast(ti_members.len)));
    }

    // Call __openjai_set_type_info_table(table_ptr, count)
    var args = [_]c.LLVMValueRef{
        table_global,
        c.LLVMConstInt(env.llvm_i64, count, 0),
    };
    _ = c.LLVMBuildCall2(env.builder, env.set_type_info_table_fn_ty, env.set_type_info_table_fn, &args, args.len, "");
}

fn formatNotesString(allocator: std.mem.Allocator, notes: []const []const u8) ![]const u8 {
    if (notes.len == 0) return "[]";
    var buf = std.ArrayList(u8).empty;
    defer buf.deinit(allocator);
    try buf.append(allocator, '[');
    for (notes, 0..) |note, i| {
        if (i > 0) try buf.appendSlice(allocator, ", ");
        try buf.append(allocator, '"');
        try buf.appendSlice(allocator, note);
        try buf.append(allocator, '"');
    }
    try buf.append(allocator, ']');
    return try allocator.dupe(u8, buf.items);
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
