// Port of bootstrap/src/bytecode_gen.zig.

bytecode_generate :: (ast: *Ast, typed: *Typed, resolved: *Resolved, diag: *Diagnostic) -> Bytecode_Program {
    program := bytecode_program_init();
    if ast.root == NULL_NODE return program;

    root_data := ast_data(ast, ast.root);
    count := ast_extra_count(ast, root_data.lhs);
    i := 0;
    while i < count {
        decl := ast_extra_at(ast, root_data.lhs, i);
        if ast_tag(ast, decl) == .proc_decl {
            proc := bytecode_generate_proc(ast, typed, decl);
            proc_index := bytecode_add_proc(*program, proc);
            if decl == resolved.main_proc program.main_proc = proc_index;
        }
        i += 1;
    }
    return program;
}

bytecode_generate_proc :: (ast: *Ast, typed: *Typed, proc_node: Node_Index) -> Proc_Bytecode {
    proc: Proc_Bytecode;
    proc.name = ast_token_slice(ast, ast_main_token(ast, proc_node));
    proc.num_registers = 1;
    proc.param_count = 0;
    proc.return_type = type_void().index;
    ret := instruction_init(.ret_void);
    ret.source_node = proc_node;
    proc_bytecode_add_instruction(*proc, ret);
    return proc;
}
