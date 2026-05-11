workspace_handles_increment_across_comptime_runs :: () {
    expect_program_output("test/examples/workspace/workspace_sequence.jai", "2 3 4 5\n");
} @TestProcedure
