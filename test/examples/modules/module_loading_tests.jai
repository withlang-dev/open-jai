local_module_import_loads_real_source :: () {
    expect_program_output("test/examples/modules/module_import_value.jai", "17\n");
} @TestProcedure

local_module_scope_file_keeps_private_helpers_private :: () {
    expect_compile_failure("test/examples/modules/module_private_import_value.jai", "unresolved identifier 'hidden_module_value'");
} @TestProcedure
