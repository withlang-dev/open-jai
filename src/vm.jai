// Port of bootstrap/src/vm.zig.

VM :: struct {
    program: *Bytecode_Program;
}

vm_init :: (program: *Bytecode_Program) -> VM {
    vm: VM;
    vm.program = program;
    return vm;
}

vm_run_main :: (vm: *VM, diag: *Diagnostic) -> Value {
    return value_void();
}

