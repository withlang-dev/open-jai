compile_time_command_line_arguments_are_dynamic_strings :: () {
    expect_compile_output_contains_with_arg("test/examples/runtime/command_line_arguments_value.jai", "openjai-runtime-argv-sentinel", "argv:true true\n");
} @TestProcedure
