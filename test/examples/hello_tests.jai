// Aspirational OpenJai test-framework style test.
//
// These helpers are provided by the future test framework described in
// docs/open_jai_test_spec.md. This file is intentionally written as a normal Jai
// test program with zero-argument procedures tagged by @TestProcedure.

hello_example_compiles :: () {
    expect_compile_success("examples/hello.jai");
} @TestProcedure

hello_example_output_matches :: () {
    expect_program_output("examples/hello.jai", "Hello from OpenJai test example!\n");
} @TestProcedure
