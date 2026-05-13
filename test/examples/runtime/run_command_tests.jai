top_level_run_command_executes :: () {
    expect_compile_creates_file(
        "test/examples/runtime/run_command_direct.jai",
        "out/test/openjai/run_command_direct_probe.txt",
        "top-level #run executed\n");
} @TestProcedure

run_command_captures_output_values :: () {
    expect_compile_output("test/examples/runtime/run_command_capture.jai", "result:0 output:captured stdout error:captured stderr timeout:false\n");
} @TestProcedure
