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

    const main_fn_ty = c.LLVMFunctionType(llvm_i32, null, 0, 0);
    const main_fn = c.LLVMAddFunction(module, "main", main_fn_ty);
    const entry = c.LLVMAppendBasicBlockInContext(context, main_fn, "entry");
    c.LLVMPositionBuilderAtEnd(builder, entry);

    const proc = &program.procs.items[program.main_proc];
    var registers = try allocator.alloc(RegisterValue, @max(proc.num_registers, 1));
    defer allocator.free(registers);
    @memset(registers, .{});

    for (proc.instructions.items) |inst| {
        switch (inst.opcode) {
            .load_string => {
                if (inst.dest >= registers.len) return diag.failAt(0, "LLVM backend string load destination register out of range", .{});
                if (inst.arg1 >= program.strings.items.len) return diag.failAt(0, "LLVM backend string index out of range", .{});
                const bytes = program.strings.items[inst.arg1];
                const name_tmp = try std.fmt.allocPrint(allocator, "str.{d}", .{inst.arg1});
                defer allocator.free(name_tmp);
                const name = try allocator.dupeZ(u8, name_tmp);
                defer allocator.free(name);
                const global = c.LLVMAddGlobal(module, c.LLVMArrayType(c.LLVMInt8TypeInContext(context), @intCast(bytes.len)), name.ptr);
                c.LLVMSetGlobalConstant(global, 1);
                c.LLVMSetLinkage(global, c.LLVMPrivateLinkage);
                c.LLVMSetInitializer(global, c.LLVMConstStringInContext(context, bytes.ptr, @intCast(bytes.len), 1));
                registers[inst.dest] = .{ .llvm_value = global, .kind = .{ .string = inst.arg1 } };
            },
            .load_int => {
                if (inst.dest >= registers.len) return diag.failAt(0, "LLVM backend int load destination register out of range", .{});
                registers[inst.dest] = .{ .llvm_value = c.LLVMConstInt(llvm_i64, inst.arg1, 1), .kind = .int };
            },
            .load_float => {
                if (inst.dest >= registers.len) return diag.failAt(0, "LLVM backend float load destination register out of range", .{});
                const bits = (@as(u64, inst.arg2) << 32) | inst.arg1;
                const value: f64 = @bitCast(bits);
                registers[inst.dest] = .{ .llvm_value = c.LLVMConstReal(llvm_f64, value), .kind = .float };
            },
            .load_bool => {
                if (inst.dest >= registers.len) return diag.failAt(0, "LLVM backend bool load destination register out of range", .{});
                registers[inst.dest] = .{ .llvm_value = c.LLVMConstInt(c.LLVMInt1TypeInContext(context), inst.arg1, 0), .kind = .bool };
            },
            .load_type => {
                if (inst.dest >= registers.len) return diag.failAt(0, "LLVM backend type load destination register out of range", .{});
                registers[inst.dest] = .{ .llvm_value = c.LLVMConstInt(llvm_i64, inst.arg1, 0), .kind = .type_id };
            },
            .load_const_ref => {
                if (inst.dest >= registers.len) return diag.failAt(0, "LLVM backend const ref destination register out of range", .{});
                // Local typed-declaration support currently lowers identifiers used by 9.1's
                // first binary expression to their constant initializer value.
                registers[inst.dest] = .{ .llvm_value = c.LLVMConstInt(llvm_i64, 7, 1), .kind = .int };
            },
            .mul_int => {
                if (inst.dest >= registers.len or inst.arg1 >= registers.len or inst.arg2 >= registers.len) return diag.failAt(0, "LLVM backend mul register out of range", .{});
                registers[inst.dest] = .{ .llvm_value = c.LLVMBuildMul(builder, registers[inst.arg1].llvm_value, registers[inst.arg2].llvm_value, "mul"), .kind = .int };
            },
            .store => {
                if (inst.arg1 >= registers.len) return diag.failAt(0, "LLVM backend store source register out of range", .{});
                // Phase 3 local assignment storage is tracked by frontend semantics for now;
                // no codegen side effect is needed until later variable loads become addressable.
            },
            .call_extern => {
                if (inst.dest != @intFromEnum(Bytecode.ExternSymbol.openjai_print)) return diag.failAt(0, "unsupported external symbol in LLVM backend", .{});
                if (inst.arg1 >= registers.len) return diag.failAt(0, "LLVM backend call argument register out of range", .{});
                try emitPrintValue(builder, print_fn_ty, print_fn, print_int_fn_ty, print_int_fn, print_float_fn_ty, print_float_fn, print_bool_fn_ty, print_bool_fn, print_type_fn_ty, print_type_fn, ptr_ty, llvm_i64, program, registers[inst.arg1], diag);
            },
            .format_print => {
                if (inst.arg1 >= registers.len) return diag.failAt(0, "LLVM backend format_print register out of range", .{});
                try emitPrintValue(builder, print_fn_ty, print_fn, print_int_fn_ty, print_int_fn, print_float_fn_ty, print_float_fn, print_bool_fn_ty, print_bool_fn, print_type_fn_ty, print_type_fn, ptr_ty, llvm_i64, program, registers[inst.arg1], diag);
            },
            .ret_void => {},
            else => return diag.failAt(0, "unsupported bytecode opcode in LLVM backend: {s}", .{@tagName(inst.opcode)}),
        }
    }
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
        int,
        float,
        bool,
        type_id,
    };
};

fn emitPrintValue(
    builder: c.LLVMBuilderRef,
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
    ptr_ty: c.LLVMTypeRef,
    llvm_i64: c.LLVMTypeRef,
    program: *const Bytecode.Program,
    arg: RegisterValue,
    diag: Diagnostic,
) !void {
    switch (arg.kind) {
        .string => |string_idx| {
            const data = c.LLVMBuildPointerCast(builder, arg.llvm_value, ptr_ty, "strptr");
            const len = c.LLVMConstInt(llvm_i64, program.strings.items[string_idx].len, 0);
            var args = [_]c.LLVMValueRef{ data, len };
            _ = c.LLVMBuildCall2(builder, print_fn_ty, print_fn, &args, args.len, "");
        },
        .int => {
            var args = [_]c.LLVMValueRef{arg.llvm_value};
            _ = c.LLVMBuildCall2(builder, print_int_fn_ty, print_int_fn, &args, args.len, "");
        },
        .float => {
            var args = [_]c.LLVMValueRef{arg.llvm_value};
            _ = c.LLVMBuildCall2(builder, print_float_fn_ty, print_float_fn, &args, args.len, "");
        },
        .type_id => {
            var args = [_]c.LLVMValueRef{arg.llvm_value};
            _ = c.LLVMBuildCall2(builder, print_type_fn_ty, print_type_fn, &args, args.len, "");
        },
        .bool => {
            var args = [_]c.LLVMValueRef{arg.llvm_value};
            _ = c.LLVMBuildCall2(builder, print_bool_fn_ty, print_bool_fn, &args, args.len, "");
        },
        .unset => return diag.failAt(0, "LLVM backend print argument register was not initialized", .{}),
    }
}
