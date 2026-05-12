caller_code_argument_expression_prints_source_name :: () {
    expect_compile_output("examples/26/26.23_get_variable_name.jai", "a_constant\n");
} @TestProcedure
