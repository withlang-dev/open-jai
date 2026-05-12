workspace_handles_increment_across_comptime_runs :: () {
    expect_program_output("test/examples/workspace/workspace_sequence.jai", "2 3 4 5\n");
} @TestProcedure

build_options_are_real_comptime_values :: () {
    expect_program_output("test/examples/workspace/build_options_value.jai", "12345\n");
} @TestProcedure

global_data_handles_embed_bytes :: () {
    expect_program_output("examples/30/30.15_global_data.jai", "43\n43\n");
} @TestProcedure

compiler_intercept_messages_are_real_values :: () {
    expect_compile_output("test/examples/workspace/message_loop_value.jai", "IMPORT:3\nFILE:3\nPHASE:3\nphase:TYPECHECKED_ALL_WE_CAN\nTYPECHECKED:3\nchecked:1\nPHASE:3\nphase:POST_WRITE_EXECUTABLE\nCOMPLETE:3\n");
} @TestProcedure

compiler_report_uses_code_declaration_locations :: () {
    expect_compile_output_contains("test/examples/workspace/compiler_report_location.jai", "test/examples/workspace/report_target.jai:3: declaration was reported\n");
} @TestProcedure

typechecked_subexpressions_drive_compiler_reports :: () {
    expect_compile_output("examples/30/30.9_house_rules.jai", "main5.jai:4: Too many levels of pointer indirection.\n");
} @TestProcedure
