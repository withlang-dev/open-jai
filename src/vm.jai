// Port of bootstrap/src/vm.zig.

VM_Value_Kind :: enum {
    VOID;
    INT;
    FLOAT;
    BOOL;
    STRING;
}

VM_Value :: struct {
    kind: VM_Value_Kind;
    int_value: int;
    float_value: float;
    bool_value: bool;
    string_value: string;
}

VM :: struct {
    program: *Bytecode_Program;
}

vm_value_void :: () -> VM_Value {
    v: VM_Value;
    v.kind = .VOID;
    return v;
}

vm_init :: (program: *Bytecode_Program) -> VM {
    vm: VM;
    vm.program = program;
    return vm;
}

vm_run_main :: (vm: *VM, diag: *Diagnostic) -> VM_Value {
    return vm_value_void();
}
