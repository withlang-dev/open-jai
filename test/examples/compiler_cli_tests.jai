compiler_version_flag_prints_without_source_file :: () {
    expect_compiler_command_output("-version", "OpenJai 0.1.0\n");
} @TestProcedure
