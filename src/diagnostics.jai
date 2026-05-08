// Port of bootstrap/src/diagnostics.zig.

Diagnostic :: struct {
    filename: string;
    source: string;
    failed: bool;
}

diagnostic_init :: (filename: string, source: string) -> Diagnostic {
    d: Diagnostic;
    d.filename = filename;
    d.source = source;
    d.failed = false;
    return d;
}

diagnostic_fail_at :: (diag: *Diagnostic, offset: int, message: string) -> Compile_Result {
    diag.failed = true;
    print("%:%: error: %\n", diag.filename, offset, message);
    return .FAILED;
}

