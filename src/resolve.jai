// Port of bootstrap/src/resolve.zig.

Resolved :: struct {
    require_main: bool;
    main_proc: Node_Index;
}

resolve :: (ast: *Ast, diag: *Diagnostic, require_main: bool) -> Resolved {
    r: Resolved;
    r.require_main = require_main;
    r.main_proc = NULL_NODE;
    return r;
}

