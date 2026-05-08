// Port of bootstrap/src/Sema.zig.

Typed :: struct {
    main_proc: Node_Index;
}

sema_analyze :: (ast: *Ast, resolved: *Resolved, pool: *Intern_Pool, diag: *Diagnostic) -> Typed {
    typed: Typed;
    typed.main_proc = resolved.main_proc;
    return typed;
}

