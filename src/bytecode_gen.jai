// Port of bootstrap/src/bytecode_gen.zig.

Local_Binding :: struct {
    name: string;
    decl: Node_Index;
    reg: Register;
}

Bytecode_Gen_Context :: struct {
    ast: *Ast;
    typed: *Typed;
    resolved: *Resolved;
    program: *Bytecode_Program;
    proc: *Proc_Bytecode;
    locals: [..] Local_Binding;
}

bytecode_generate :: (ast: *Ast, typed: *Typed, resolved: *Resolved, diag: *Diagnostic) -> Bytecode_Program {
    program := bytecode_program_init();
    if ast.root == NULL_NODE return program;

    root_data := ast_data(ast, ast.root);
    count := ast_extra_count(ast, root_data.lhs);
    i := 0;
    while i < count {
        decl := ast_extra_at(ast, root_data.lhs, i);
        if ast_tag(ast, decl) == .proc_decl {
            proc := bytecode_generate_proc(ast, typed, resolved, *program, decl, diag);
            proc_index := bytecode_add_proc(*program, proc);
            if decl == resolved.main_proc program.main_proc = proc_index;
        }
        i += 1;
    }
    return program;
}

bytecode_generate_proc :: (ast: *Ast, typed: *Typed, resolved: *Resolved, program: *Bytecode_Program, proc_node: Node_Index, diag: *Diagnostic) -> Proc_Bytecode {
    proc: Proc_Bytecode;
    proc.name = ast_token_slice(ast, ast_main_token(ast, proc_node));
    proc.num_registers = 0;
    proc.param_count = 0;
    proc.return_type = type_void().index;

    ctx: Bytecode_Gen_Context;
    ctx.ast = ast;
    ctx.typed = typed;
    ctx.resolved = resolved;
    ctx.program = program;
    ctx.proc = *proc;

    body := ast_data(ast, proc_node).lhs;
    if body != NULL_NODE bytecode_gen_block(*ctx, body, diag);

    if proc.instruction_count == 0 || !bytecode_proc_last_instruction_returns(*proc) {
        ret := instruction_init(.ret_void);
        ret.source_node = proc_node;
        proc_bytecode_add_instruction(*proc, ret);
    }
    return proc;
}

bytecode_proc_last_instruction_returns :: (proc: *Proc_Bytecode) -> bool {
    if proc.instruction_count <= 0 return false;
    op := proc.instructions[proc.instruction_count - 1].opcode;
    return op == .ret || op == .ret_void || op == .exit_process || op == .jump;
}

bytecode_gen_block :: (ctx: *Bytecode_Gen_Context, block: Node_Index, diag: *Diagnostic) {
    count := ast_extra_count(ctx.ast, ast_data(ctx.ast, block).lhs);
    i := 0;
    while i < count {
        stmt := ast_extra_at(ctx.ast, ast_data(ctx.ast, block).lhs, i);
        bytecode_gen_stmt(ctx, stmt, diag);
        i += 1;
    }
}

bytecode_gen_stmt :: (ctx: *Bytecode_Gen_Context, stmt: Node_Index, diag: *Diagnostic) {
    tag := ast_tag(ctx.ast, stmt);
    data := ast_data(ctx.ast, stmt);
    if tag == .import_decl || tag == .load_decl || tag == .meta_stmt {
        return;
    } else if tag == .block || tag == .stmt_list {
        bytecode_gen_block(ctx, stmt, diag);
    } else if tag == .expr_stmt || tag == .run_expr {
        if data.lhs != NULL_NODE bytecode_gen_expr(ctx, data.lhs, diag);
    } else if tag == .var_decl || tag == .const_decl {
        init := data.rhs;
        if tag == .const_decl init = data.lhs;
        reg := 0;
        if init != NULL_NODE reg = bytecode_gen_expr(ctx, init, diag);
        else reg = bytecode_emit_default_for_type(ctx, data.lhs, stmt);
        bytecode_bind_local(ctx, ast_token_slice(ctx.ast, ast_main_token(ctx.ast, stmt)), stmt, reg);
    } else if tag == .assign_stmt {
        rhs := bytecode_gen_expr(ctx, data.rhs, diag);
        if ast_tag(ctx.ast, data.lhs) == .identifier {
            name := ast_token_slice(ctx.ast, ast_main_token(ctx.ast, data.lhs));
            if bytecode_lookup_local(ctx, name) >= 0 {
                old := bytecode_lookup_local(ctx, name);
                inst := instruction_init(.load);
                inst.dest = old;
                inst.arg1 = rhs;
                inst.source_node = stmt;
                proc_bytecode_add_instruction(ctx.proc, inst);
            } else {
                bytecode_bind_local(ctx, name, data.lhs, rhs);
            }
        }
    } else if tag == .return_stmt {
        if data.lhs == NULL_NODE {
            inst := instruction_init(.ret_void);
            inst.source_node = stmt;
            proc_bytecode_add_instruction(ctx.proc, inst);
        } else {
            reg := bytecode_gen_expr(ctx, data.lhs, diag);
            inst := instruction_init(.ret);
            inst.arg1 = reg;
            inst.source_node = stmt;
            proc_bytecode_add_instruction(ctx.proc, inst);
        }
    } else if tag == .if_stmt {
        cond_raw := bytecode_gen_expr(ctx, data.lhs, diag);
        cond := bytecode_coerce_bool(ctx, cond_raw, data.lhs);
        jump_if_index := ctx.proc.instruction_count;
        jump_if := instruction_init(.jump_if_false);
        jump_if.arg1 = cond;
        jump_if.arg2 = 0;
        jump_if.source_node = stmt;
        proc_bytecode_add_instruction(ctx.proc, jump_if);

        then_block := ast_extra_at(ctx.ast, data.rhs, 0);
        bytecode_gen_block(ctx, then_block, diag);

        jump_end_index := ctx.proc.instruction_count;
        jump_end := instruction_init(.jump);
        jump_end.arg1 = 0;
        jump_end.source_node = stmt;
        proc_bytecode_add_instruction(ctx.proc, jump_end);

        ctx.proc.instructions[jump_if_index].arg2 = ctx.proc.instruction_count;
        if ast_extra_count(ctx.ast, data.rhs) > 1 {
            else_block := ast_extra_at(ctx.ast, data.rhs, 1);
            if else_block != NULL_NODE bytecode_gen_block(ctx, else_block, diag);
        }
        ctx.proc.instructions[jump_end_index].arg1 = ctx.proc.instruction_count;
    } else if tag == .while_stmt {
        loop_start := ctx.proc.instruction_count;
        cond_raw := bytecode_gen_expr(ctx, data.lhs, diag);
        cond := bytecode_coerce_bool(ctx, cond_raw, data.lhs);
        jump_if_index := ctx.proc.instruction_count;
        jump_if := instruction_init(.jump_if_false);
        jump_if.arg1 = cond;
        jump_if.arg2 = 0;
        jump_if.source_node = stmt;
        proc_bytecode_add_instruction(ctx.proc, jump_if);

        bytecode_gen_block(ctx, data.rhs, diag);
        back := instruction_init(.jump);
        back.arg1 = loop_start;
        back.source_node = stmt;
        proc_bytecode_add_instruction(ctx.proc, back);
        ctx.proc.instructions[jump_if_index].arg2 = ctx.proc.instruction_count;
    }
}

bytecode_gen_expr :: (ctx: *Bytecode_Gen_Context, expr: Node_Index, diag: *Diagnostic) -> Register {
    tag := ast_tag(ctx.ast, expr);
    data := ast_data(ctx.ast, expr);
    if tag == .integer_literal {
        return bytecode_emit_int(ctx, expr, bytecode_parse_int(ast_token_slice(ctx.ast, ast_main_token(ctx.ast, expr))));
    } else if tag == .string_literal {
        reg := bytecode_alloc_register(ctx);
        idx := bytecode_add_string(ctx.program, ast_string_token_contents(ctx.ast, ast_main_token(ctx.ast, expr)));
        inst := instruction_init(.load_string);
        inst.dest = reg;
        inst.arg1 = idx;
        inst.source_node = expr;
        proc_bytecode_add_instruction(ctx.proc, inst);
        return reg;
    } else if tag == .bool_literal {
        reg := bytecode_alloc_register(ctx);
        inst := instruction_init(.load_bool);
        inst.dest = reg;
        if ast_token_slice(ctx.ast, ast_main_token(ctx.ast, expr)) == "true" inst.arg1 = 1;
        else inst.arg1 = 0;
        inst.source_node = expr;
        proc_bytecode_add_instruction(ctx.proc, inst);
        return reg;
    } else if tag == .null_literal {
        reg := bytecode_alloc_register(ctx);
        inst := instruction_init(.load_null_ptr);
        inst.dest = reg;
        inst.source_node = expr;
        proc_bytecode_add_instruction(ctx.proc, inst);
        return reg;
    } else if tag == .undefined_literal {
        reg := bytecode_alloc_register(ctx);
        inst := instruction_init(.load_undef);
        inst.dest = reg;
        inst.arg1 = ANY_TYPE;
        inst.source_node = expr;
        proc_bytecode_add_instruction(ctx.proc, inst);
        return reg;
    } else if tag == .identifier {
        name := ast_token_slice(ctx.ast, ast_main_token(ctx.ast, expr));
        reg := bytecode_lookup_local(ctx, name);
        if reg >= 0 return reg;
        return bytecode_emit_int(ctx, expr, 0);
    } else if tag == .field_access {
        return bytecode_emit_int(ctx, expr, 0);
    } else if tag == .unary_expr {
        operand := bytecode_gen_expr(ctx, data.lhs, diag);
        op := ctx.ast.tokens.items[ast_main_token(ctx.ast, expr)].tag;
        if op == .bang {
            reg := bytecode_alloc_register(ctx);
            inst := instruction_init(.not_bool);
            inst.dest = reg;
            inst.arg1 = bytecode_coerce_bool(ctx, operand, data.lhs);
            inst.source_node = expr;
            proc_bytecode_add_instruction(ctx.proc, inst);
            return reg;
        } else if op == .minus {
            reg := bytecode_alloc_register(ctx);
            inst := instruction_init(.neg_int);
            inst.dest = reg;
            inst.arg1 = operand;
            inst.source_node = expr;
            proc_bytecode_add_instruction(ctx.proc, inst);
            return reg;
        }
        return operand;
    } else if tag == .binary_expr {
        lhs := bytecode_gen_expr(ctx, data.lhs, diag);
        rhs := bytecode_gen_expr(ctx, data.rhs, diag);
        reg := bytecode_alloc_register(ctx);
        inst := instruction_init(bytecode_binary_opcode(ctx.ast.tokens.items[ast_main_token(ctx.ast, expr)].tag));
        inst.dest = reg;
        inst.arg1 = lhs;
        inst.arg2 = rhs;
        inst.source_node = expr;
        proc_bytecode_add_instruction(ctx.proc, inst);
        return reg;
    } else if tag == .call_expr {
        return bytecode_gen_call(ctx, expr, diag);
    } else if tag == .size_of_expr {
        return bytecode_emit_int(ctx, expr, 8);
    } else if tag == .type_of_expr {
        reg := bytecode_alloc_register(ctx);
        inst := instruction_init(.load_type);
        inst.dest = reg;
        inst.arg1 = ANY_TYPE;
        inst.source_node = expr;
        proc_bytecode_add_instruction(ctx.proc, inst);
        return reg;
    }
    return bytecode_emit_int(ctx, expr, 0);
}

bytecode_gen_call :: (ctx: *Bytecode_Gen_Context, expr: Node_Index, diag: *Diagnostic) -> Register {
    callee := ast_data(ctx.ast, expr).lhs;
    if ast_tag(ctx.ast, callee) != .identifier {
        return bytecode_emit_int(ctx, expr, 0);
    }
    name := ast_token_slice(ctx.ast, ast_main_token(ctx.ast, callee));
    args_extra := ast_data(ctx.ast, expr).rhs;
    arg_count := ast_extra_count(ctx.ast, args_extra);

    if name == "print" || name == "log" {
        i := 0;
        while i < arg_count {
            arg := ast_extra_at(ctx.ast, args_extra, i);
            reg := bytecode_gen_expr(ctx, arg, diag);
            inst := instruction_init(.format_print);
            inst.arg1 = reg;
            inst.source_node = expr;
            proc_bytecode_add_instruction(ctx.proc, inst);
            i += 1;
        }
        return bytecode_emit_int(ctx, expr, 0);
    }
    if name == "exit" {
        code := bytecode_emit_int(ctx, expr, 0);
        if arg_count > 0 code = bytecode_gen_expr(ctx, ast_extra_at(ctx.ast, args_extra, 0), diag);
        inst := instruction_init(.exit_process);
        inst.arg1 = code;
        inst.source_node = expr;
        proc_bytecode_add_instruction(ctx.proc, inst);
        return code;
    }
    if name == "compiler_arg_count" {
        reg := bytecode_alloc_register(ctx);
        inst := instruction_init(.compiler_arg_count);
        inst.dest = reg;
        inst.source_node = expr;
        proc_bytecode_add_instruction(ctx.proc, inst);
        return reg;
    }
    if name == "compiler_arg" {
        idx := bytecode_emit_int(ctx, expr, 0);
        if arg_count > 0 idx = bytecode_gen_expr(ctx, ast_extra_at(ctx.ast, args_extra, 0), diag);
        reg := bytecode_alloc_register(ctx);
        inst := instruction_init(.compiler_arg);
        inst.dest = reg;
        inst.arg1 = idx;
        inst.source_node = expr;
        proc_bytecode_add_instruction(ctx.proc, inst);
        return reg;
    }
    if name == "compiler_read_file" {
        path := bytecode_emit_int(ctx, expr, 0);
        if arg_count > 0 path = bytecode_gen_expr(ctx, ast_extra_at(ctx.ast, args_extra, 0), diag);
        reg := bytecode_alloc_register(ctx);
        inst := instruction_init(.compiler_read_file);
        inst.dest = reg;
        inst.arg1 = path;
        inst.source_node = expr;
        proc_bytecode_add_instruction(ctx.proc, inst);
        return reg;
    }

    proc_index := bytecode_find_proc(ctx.program, name);
    if proc_index >= 0 && arg_count == 0 {
        inst := instruction_init(.call_proc0);
        inst.arg1 = proc_index;
        inst.source_node = expr;
        proc_bytecode_add_instruction(ctx.proc, inst);
    } else {
        i := 0;
        while i < arg_count {
            bytecode_gen_expr(ctx, ast_extra_at(ctx.ast, args_extra, i), diag);
            i += 1;
        }
    }
    return bytecode_emit_int(ctx, expr, 0);
}

bytecode_alloc_register :: (ctx: *Bytecode_Gen_Context) -> Register {
    reg := ctx.proc.num_registers;
    ctx.proc.num_registers += 1;
    return reg;
}

bytecode_emit_int :: (ctx: *Bytecode_Gen_Context, source_node: Node_Index, value: int) -> Register {
    reg := bytecode_alloc_register(ctx);
    inst := instruction_init(.load_int);
    inst.dest = reg;
    inst.arg1 = value;
    inst.source_node = source_node;
    proc_bytecode_add_instruction(ctx.proc, inst);
    return reg;
}

bytecode_emit_default_for_type :: (ctx: *Bytecode_Gen_Context, type_node: Node_Index, source_node: Node_Index) -> Register {
    if type_node != NULL_NODE {
        name := ast_token_slice(ctx.ast, ast_main_token(ctx.ast, type_node));
        if name == "bool" {
            reg := bytecode_alloc_register(ctx);
            inst := instruction_init(.load_bool);
            inst.dest = reg;
            inst.arg1 = 0;
            inst.source_node = source_node;
            proc_bytecode_add_instruction(ctx.proc, inst);
            return reg;
        }
        if name == "string" {
            reg := bytecode_alloc_register(ctx);
            idx := bytecode_add_string(ctx.program, "");
            inst := instruction_init(.load_string);
            inst.dest = reg;
            inst.arg1 = idx;
            inst.source_node = source_node;
            proc_bytecode_add_instruction(ctx.proc, inst);
            return reg;
        }
    }
    return bytecode_emit_int(ctx, source_node, 0);
}

bytecode_coerce_bool :: (ctx: *Bytecode_Gen_Context, reg: Register, source_node: Node_Index) -> Register {
    ty := typed_type_of(ctx.typed, source_node);
    if type_is_bool(ty) return reg;
    out := bytecode_alloc_register(ctx);
    inst := instruction_init(.int_to_bool_cast);
    inst.dest = out;
    inst.arg1 = reg;
    inst.source_node = source_node;
    proc_bytecode_add_instruction(ctx.proc, inst);
    return out;
}

bytecode_binary_opcode :: (tag: Token_Tag) -> Opcode {
    if tag == .plus || tag == .plus_equal return .add_int;
    if tag == .minus || tag == .minus_equal return .sub_int;
    if tag == .star || tag == .star_equal return .mul_int;
    if tag == .slash || tag == .slash_equal return .div_int;
    if tag == .percent return .rem_int;
    if tag == .less_than return .cmp_lt_int;
    if tag == .less_equal return .cmp_le_int;
    if tag == .greater_than return .cmp_gt_int;
    if tag == .greater_equal return .cmp_ge_int;
    if tag == .equal_equal return .cmp_eq;
    if tag == .bang_equal return .cmp_ne;
    if tag == .ampersand_ampersand return .bool_and;
    if tag == .pipe_pipe return .bool_or;
    if tag == .ampersand || tag == .ampersand_equal return .bit_and;
    if tag == .pipe || tag == .pipe_equal return .bit_or;
    if tag == .caret || tag == .caret_equal return .bit_xor;
    if tag == .shift_left return .shl_int;
    if tag == .shift_right return .shr_int;
    return .add_int;
}

bytecode_bind_local :: (ctx: *Bytecode_Gen_Context, name: string, decl: Node_Index, reg: Register) {
    i := 0;
    while i < ctx.locals.count {
        if ctx.locals[i].name == name {
            ctx.locals[i].decl = decl;
            ctx.locals[i].reg = reg;
            return;
        }
        i += 1;
    }
    binding: Local_Binding;
    binding.name = name;
    binding.decl = decl;
    binding.reg = reg;
    array_add(*ctx.locals, binding);
}

bytecode_lookup_local :: (ctx: *Bytecode_Gen_Context, name: string) -> Register {
    i := ctx.locals.count - 1;
    while i >= 0 {
        if ctx.locals[i].name == name return ctx.locals[i].reg;
        i -= 1;
    }
    return -1;
}

bytecode_find_proc :: (program: *Bytecode_Program, name: string) -> int {
    i := 0;
    while i < program.procs.count {
        if program.procs[i].name == name return i;
        i += 1;
    }
    return -1;
}

bytecode_parse_int :: (text: string) -> int {
    sign := 1;
    i := 0;
    if text.count > 0 && text[0] == #char "-" {
        sign = -1;
        i = 1;
    }
    value := 0;
    while i < text.count {
        c := text[i];
        if c >= #char "0" && c <= #char "9" {
            value = value * 10 + cast(int)(c - #char "0");
        }
        i += 1;
    }
    return value * sign;
}
