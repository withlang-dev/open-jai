workspace_handles_increment_across_comptime_runs :: () {
    expect_program_output("test/examples/workspace/workspace_sequence.jai", "2 3 4 5\n");
} @TestProcedure

build_options_are_real_comptime_values :: () {
    expect_program_output("test/examples/workspace/build_options_value.jai", "12345\n");
} @TestProcedure
