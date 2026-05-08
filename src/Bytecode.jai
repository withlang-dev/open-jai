// Port of bootstrap/src/Bytecode.zig.

Register :: int;
String_Index :: int;

Opcode :: enum {
    load_int;
    load_float;
    load_string;
    load_bool;
    load_null_ptr;
    load_type;
    load_undef;
    load_const_ref;
    neg_int;
    neg_float;
    not_bool;
    mul_int;
    mul_float;
    rem_int;
    add_int;
    add_float;
    sub_int;
    sub_float;
    div_int;
    div_float;
    format_print;
    format_int_value;
    format_float_value;
    call;
    call_proc0;
    call_extern;
    ret;
    ret_void;
    alloc_local;
    load;
    store;
    load_ptr;
    store_ptr;
    ptr_offset;
    load_ptr_string;
    addr_of_local;
    proc_addr;
    alloc_heap;
    alloc_local_bytes;
    array_add;
    array_count;
    array_index;
    memcpy;
    exit_process;
    free_heap;
    make_vector3;
    int_trunc_cast;
    bool_to_int_cast;
    int_to_bool_cast;
    float_cast;
    sin_float;
    current_time_consensus_low;
    current_time_monotonic_low;
    to_calendar;
    load_calendar_field;
    calendar_to_string;
    random_seed;
    random_get;
    random_get_zero_to_one;
    random_get_within_range;
    compiler_arg_count;
    compiler_arg;
    compiler_read_file;
    string_len;
    string_data;
    string_index;
    cmp_lt_int;
    cmp_le_int;
    cmp_gt_int;
    cmp_ge_int;
    cmp_eq;
    cmp_ne;
    bit_not;
    bit_and;
    bit_or;
    bit_xor;
    shl_int;
    shr_int;
    rotl_int;
    bool_and;
    bool_or;
    select_value;
    assert_true;
    jump;
    jump_if_false;
}

Extern_Symbol :: enum {
    openjai_print;
}

Instruction :: struct {
    opcode: Opcode;
    dest: Register;
    arg1: int;
    arg2: int;
    arg3: int;
    arg4: int;
    arg5: int;
    source_node: Node_Index;
}

Proc_Bytecode :: struct {
    name: string;
    instructions: [..] Instruction;
    num_registers: int;
    param_count: int;
    return_type: int;
    instruction_count: int;
}

Bytecode_Program :: struct {
    strings: [..] string;
    procs: [..] Proc_Bytecode;
    string_count: int;
    proc_count: int;
    main_proc: int;
}

instruction_init :: (opcode: Opcode) -> Instruction {
    inst: Instruction;
    inst.opcode = opcode;
    inst.dest = 0;
    inst.arg1 = 0;
    inst.arg2 = 0;
    inst.arg3 = 0;
    inst.arg4 = 0;
    inst.arg5 = 0;
    inst.source_node = 0;
    return inst;
}

bytecode_program_init :: () -> Bytecode_Program {
    program: Bytecode_Program;
    program.string_count = 0;
    program.proc_count = 0;
    program.main_proc = -1;
    return program;
}

bytecode_add_string :: (program: *Bytecode_Program, value: string) -> String_Index {
    index := program.string_count;
    array_add(*program.strings, value);
    program.string_count += 1;
    return index;
}

bytecode_add_proc :: (program: *Bytecode_Program, proc: Proc_Bytecode) -> int {
    index := program.proc_count;
    array_add(*program.procs, proc);
    program.proc_count = program.procs.count;
    return index;
}

proc_bytecode_add_instruction :: (proc: *Proc_Bytecode, inst: Instruction) {
    array_add(*proc.instructions, inst);
    proc.instruction_count = proc.instructions.count;
}
