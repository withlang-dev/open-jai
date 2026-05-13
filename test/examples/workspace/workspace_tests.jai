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
    expect_compile_output("test/examples/workspace/message_loop_value.jai", "IMPORT:3\nFILE:3\nPHASE:3\nphase:ALL_SOURCE_CODE_PARSED\nPHASE:3\nphase:TYPECHECKED_ALL_WE_CAN\nTYPECHECKED:3\nchecked:1\nPHASE:3\nphase:ALL_TARGET_CODE_BUILT\nPHASE:3\nphase:PRE_WRITE_EXECUTABLE\nPHASE:3\nphase:POST_WRITE_EXECUTABLE\nCOMPLETE:3\n");
} @TestProcedure

compiler_report_uses_code_declaration_locations :: () {
    expect_compile_output_contains("test/examples/workspace/compiler_report_location.jai", "test/examples/workspace/report_target.jai:3: declaration was reported\n");
} @TestProcedure

typechecked_subexpressions_drive_compiler_reports :: () {
    expect_compile_output("examples/30/30.9_house_rules.jai", "main5.jai:4: Too many levels of pointer indirection.\n");
} @TestProcedure

workspace_failed_status_reaches_complete_message :: () {
    expect_compile_output("test/examples/workspace/workspace_failed_status_value.jai", "post failed:true linker:1\ncomplete error:1\n");
} @TestProcedure

custom_link_command_phase_waits_for_completion_signal :: () {
    expect_compile_output("test/examples/workspace/custom_link_command_value.jai", "ready:custom-app\npost:custom-app\ncomplete:custom-app error:0\n");
} @TestProcedure

compile_time_command_line_is_exposed_to_build_scripts :: () {
    expect_compile_output_contains_with_arg("test/examples/workspace/compile_time_command_line_value.jai", "openjai-command-line-sentinel", "found:true\n");
} @TestProcedure

compiler_intercept_reports_target_source_errors :: () {
    expect_compile_output_contains("test/examples/workspace/error_message_value.jai", "error:3\ncomplete:1\n");
} @TestProcedure

compiler_file_and_import_messages_expose_specific_fields :: () {
    expect_compile_output_contains("test/examples/workspace/file_import_message_value.jai", "file:report_target.jai\nimport:Basic:report_target.jai\n");
} @TestProcedure

compiler_import_messages_are_ast_backed_and_deduped :: () {
    expect_compile_output("test/examples/workspace/import_message_ast_value.jai", "import:Basic\nimports:1\n");
} @TestProcedure
