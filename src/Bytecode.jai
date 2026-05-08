// Port of bootstrap/src/Bytecode.zig.

Register :: int;
String_Index :: int;

Opcode :: enum {
    load_int;
    load_float;
    load_string;
    load_bool;
    ret;
    ret_void;
    call;
    call_extern;
}

Instruction :: struct {
    opcode: Opcode;
    dest: Register;
    arg1: int;
    arg2: int;
    source_node: Node_Index;
}

Proc_Bytecode :: struct {
    name: string;
    num_registers: int;
    param_count: int;
}

Bytecode_Program :: struct {
    proc_count: int;
    main_proc: int;
}

