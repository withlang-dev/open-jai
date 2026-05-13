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

process_module_import_loads_real_source :: () {
    expect_compile_output("test/examples/modules/process_module_import_value.jai", "process:0 process-module  false\n");
} @TestProcedure

file_utilities_module_import_loads_real_source :: () {
    expect_compile_output("test/examples/modules/file_utilities_module_import_value.jai", "file-utilities:true true copied\n");
} @TestProcedure

build_cpp_module_import_loads_real_source :: () {
    expect_compile_output("test/examples/modules/build_cpp_module_import_value.jai", "build-cpp:true\n");
} @TestProcedure

posix_module_import_loads_real_source :: () {
    expect_compile_output("test/examples/modules/posix_module_import_value.jai", "posix:0 1 2\n");
} @TestProcedure

system_module_import_loads_real_source :: () {
    expect_compile_output("test/examples/modules/system_module_import_value.jai", "system:true true\n");
} @TestProcedure

program_print_module_import_loads_real_source_from_local_alias :: () {
    expect_compile_output("test/examples/modules/program_print_local_alias_value.jai", "program-print:value :: 42\n");
} @TestProcedure

testscope_module_import_loads_real_source :: () {
    expect_program_output("test/examples/modules/testscope_module_import_value.jai", "42\n");
} @TestProcedure
