unfulfilled_placeholder_fails_loudly :: () {
    expect_compile_failure("test/examples/workspace/unfulfilled_placeholder_value.jai", "explicit placeholder 'TRUTH' was used but never fulfilled");
} @TestProcedure
