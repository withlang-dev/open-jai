top_level_run_command_executes :: () {
    expect_compile_creates_file(
        "test/examples/runtime/run_command_direct.jai",
        "out/test/openjai/run_command_direct_probe.txt",
        "top-level #run executed\n");
} @TestProcedure

