polymorphic_comptime_run_specializes_type_values :: () {
    expect_compile_output_contains("examples/26/26.15_comprun.jai", "Compiling 'comprun' for T == u8.\n");
    expect_compile_output_contains("examples/26/26.15_comprun.jai", "Compiling 'comprun' for T == float32.\n");
    expect_compile_output_contains("examples/26/26.15_comprun.jai", "Compiling 'comprun' for T == string.\n");
} @TestProcedure

polymorphic_runtime_type_values_are_real :: () {
    expect_program_output_contains("examples/26/26.15_comprun.jai", "The value of x is 5, of type u8.\n");
    expect_program_output_contains("examples/26/26.15_comprun.jai", "The value of x is 1.1, of type float32.\n");
    expect_program_output_contains("examples/26/26.15_comprun.jai", "The value of x is Hello, Sailor!, of type string.\n");
} @TestProcedure
