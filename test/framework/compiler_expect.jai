// Compiler-test helper declarations.
//
// The bootstrap test runner host-implements these procedures while executing
// @TestProcedure bodies. They are declared here so test files describe the
// intended Jai-native API in normal source.

expect_compile_success :: (path: string) #foreign openjai_test_framework;
expect_compile_failure :: (path: string, expected_message: string) #foreign openjai_test_framework;
expect_compile_output :: (path: string, expected: string) #foreign openjai_test_framework;
expect_compile_output_contains :: (path: string, needle: string) #foreign openjai_test_framework;
expect_program_output :: (path: string, expected: string) #foreign openjai_test_framework;
expect_program_output_contains :: (path: string, needle: string) #foreign openjai_test_framework;
expect_example_annotations :: (path: string) #foreign openjai_test_framework;
