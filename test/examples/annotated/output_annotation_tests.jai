// Behavioral tests for examples whose `// =>` annotations currently describe
// stable runtime output. Each procedure compiles and runs the example, then
// checks the annotated expectations in source order.

hello_sailor_output :: () {
    expect_example_annotations("examples/03/3.1_hello_sailor.jai");
} @TestProcedure

exit_example_output :: () {
    expect_example_annotations("examples/03/3.3_exit.jai");
} @TestProcedure

variable_declarations_2_output :: () {
    expect_example_annotations("examples/05/5.4_variable_declarations2.jai");
} @TestProcedure

printing_output :: () {
    expect_example_annotations("examples/05/5.6_printing.jai");
} @TestProcedure

unicode_printing_output :: () {
    expect_example_annotations("examples/05/5.9_printing_unicode.jai");
} @TestProcedure

backtick_identifier_output :: () {
    expect_example_annotations("examples/05/5B.ident_back.jai");
} @TestProcedure

bitwise_output :: () {
    expect_example_annotations("examples/06/6.4_bitwise.jai");
} @TestProcedure

scope_output :: () {
    expect_example_annotations("examples/07/7.1_scope.jai");
} @TestProcedure

shadowing_output :: () {
    expect_example_annotations("examples/07/7.2_shadowing.jai");
} @TestProcedure

defer_output :: () {
    expect_example_annotations("examples/11/11.2_defer.jai");
} @TestProcedure

defer_levels_output :: () {
    expect_example_annotations("examples/11/11.3_defer_levels.jai");
} @TestProcedure

as_using_entities_output :: () {
    expect_example_annotations("examples/12/12.12_#as_using_entities.jai");
} @TestProcedure

if_case_output :: () {
    expect_example_annotations("examples/14/14.3_if_case.jai");
} @TestProcedure

if_tests_output :: () {
    expect_example_annotations("examples/14/14.5_if_tests.jai");
} @TestProcedure

print_proc_output :: () {
    expect_example_annotations("examples/18/18.11_print_proc.jai");
} @TestProcedure

compile_time_if_output :: () {
    expect_program_output_contains("examples/26/26.5_if.jai", "The operating system is ");
    expect_program_output_contains("examples/26/26.5_if.jai", "CONSTANT is 3");
    expect_program_output_contains("examples/26/26.5_if.jai", "name is ");
} @TestProcedure

binary_swap_output :: () {
    expect_example_annotations("examples/28/28.13_binary_swap.jai");
} @TestProcedure

mutex_output :: () {
    expect_example_annotations("examples/31/31.6_mutex1.jai");
} @TestProcedure

hello_example_annotations_output :: () {
    expect_example_annotations("examples/hello.jai");
} @TestProcedure
