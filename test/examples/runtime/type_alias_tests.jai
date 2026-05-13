compile_time_type_alias_locals_copy_values :: () {
    expect_compile_output("test/examples/runtime/type_alias_value_copy.jai", "alias-copy:1 2 3 4\n");
} @TestProcedure

expression_form_run_type_is_materialized :: () {
    expect_compile_output("test/examples/runtime/type_run_value.jai", "type:string\n");
} @TestProcedure
