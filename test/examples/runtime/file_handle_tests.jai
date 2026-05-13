compile_time_file_handles_are_real_host_files :: () {
    expect_compile_output("test/examples/runtime/file_handle_value.jai", "file-handles:true true true true true true true\n");
} @TestProcedure
