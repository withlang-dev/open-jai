// Port of bootstrap/src/bytecode_gen.zig.

bytecode_generate :: (ast: *Ast, typed: *Typed, resolved: *Resolved, diag: *Diagnostic) -> Bytecode_Program {
    program: Bytecode_Program;
    program.proc_count = 0;
    program.main_proc = 0;
    return program;
}

