target_workspace_add_build_string_emits_executable :: () {
    expect_compile_creates_program_output(
        "examples/30/30.3B_build_add_build_string.jai",
        "out/build_string",
        "This program was built with metaprogram 30.3B_build_add_build_string.jai\n");
} @TestProcedure
