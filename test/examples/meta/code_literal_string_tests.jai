code_literal_string_fields_are_real :: () {
    expect_compile_output_contains("test/examples/meta/code_literal_string_value.jai", "saw string literal: before\n");
    expect_program_output("test/examples/meta/code_literal_string_value.jai", "after\n");
} @TestProcedure
