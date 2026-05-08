// Port of bootstrap/src/codegen/llvm.zig.

llvm_emit_object :: (program: *Bytecode_Program, object_path: string, diag: *Diagnostic) -> Compile_Result {
    diagnostic_fail_at(diag, 0, "Jai LLVM backend port is not implemented yet");
    return .FAILED;
}

