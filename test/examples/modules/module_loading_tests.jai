local_module_import_loads_real_source :: () {
    expect_program_output("test/examples/modules/module_import_value.jai", "17\n");
} @TestProcedure

local_module_alias_import_loads_real_source :: () {
    expect_program_output("test/examples/modules/module_alias_import_value.jai", "17\n");
} @TestProcedure

local_module_scope_file_keeps_private_helpers_private :: () {
    expect_compile_failure("test/examples/modules/module_private_import_value.jai", "unresolved identifier 'hidden_module_value'");
} @TestProcedure

commented_module_imports_do_not_load_source :: () {
    expect_compile_failure("test/examples/modules/module_comment_import_value.jai", "unresolved identifier 'comment_only_value'");
} @TestProcedure

duplicate_module_imports_load_source_once :: () {
    expect_compile_output("test/examples/modules/module_duplicate_import_value.jai", "duplicate module loaded\n");
} @TestProcedure
