// Port of bootstrap/src/link.zig.

link_executable :: (object_path: string, runtime_path: string, output_path: string, diag: *Diagnostic) -> Compile_Result {
    diagnostic_fail_at(diag, 0, "Jai linker port is not implemented yet");
    return .FAILED;
}

