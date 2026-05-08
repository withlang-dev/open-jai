// Port of bootstrap/src/diagnostics.zig.

Diagnostic :: struct {
    filename: string;
    source: string;
    failed: bool;
}

Line_Col :: struct {
    line: int;
    col: int;
    line_start: int;
    line_end: int;
}

diagnostic_init :: (filename: string, source: string) -> Diagnostic {
    d: Diagnostic;
    d.filename = filename;
    d.source = source;
    d.failed = false;
    return d;
}

diagnostic_fail_at :: (diag: *Diagnostic, offset: int, message: string) -> Compile_Result {
    lc := diagnostic_line_col(diag, offset);
    diag.failed = true;
    print("%:%:%: error: %\n", diag.filename, lc.line, lc.col, message);
    diagnostic_print_line(diag, lc, offset);
    return .FAILED;
}

diagnostic_note_at :: (diag: *Diagnostic, offset: int, message: string) {
    lc := diagnostic_line_col(diag, offset);
    print("%:%:%: note: %\n", diag.filename, lc.line, lc.col, message);
}

diagnostic_line_col :: (diag: *Diagnostic, offset_raw: int) -> Line_Col {
    offset := offset_raw;
    if offset < 0 offset = 0;
    if offset > diag.source.count offset = diag.source.count;

    lc: Line_Col;
    lc.line = 1;
    lc.line_start = 0;

    i := 0;
    while i < offset {
        if diag.source[i] == #char "\n" {
            lc.line += 1;
            lc.line_start = i + 1;
        }
        i += 1;
    }

    lc.line_end = lc.line_start;
    while lc.line_end < diag.source.count && diag.source[lc.line_end] != #char "\n" {
        lc.line_end += 1;
    }

    lc.col = offset - lc.line_start + 1;
    return lc;
}

diagnostic_print_line :: (diag: *Diagnostic, lc: Line_Col, offset: int) {
    if lc.line_start > diag.source.count return;
    if lc.line_end > diag.source.count return;
    if lc.line_start > lc.line_end return;

    line_text := diag.source;
    print("    %\n    ", line_text);

    caret_col := offset - lc.line_start;
    if caret_col < 0 caret_col = 0;
    i := 0;
    while i < caret_col {
        print(" ");
        i += 1;
    }
    print("^\n");
}

