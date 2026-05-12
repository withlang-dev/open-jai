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

code_nodes_compile_time_output :: () {
    expect_compile_output("examples/26/26.11_code_nodes.jai", "The code is: a := Vector3.{1, 2, 3}\nHere are the types of all expressions in this syntax tree:\n[0] IDENT 0\n[1] TYPE_INSTANTIATION 0\n[2] LITERAL 0\n[3] LITERAL 0\n[4] LITERAL 0\n[5] LITERAL 0\n[6] DECLARATION ALLOWED_BY_CONTEXT\n");
} @TestProcedure

compile_time_if_output :: () {
    expect_program_output_contains("examples/26/26.5_if.jai", "The operating system is ");
    expect_program_output_contains("examples/26/26.5_if.jai", "CONSTANT is 3");
    expect_program_output_contains("examples/26/26.5_if.jai", "name is ");
} @TestProcedure

insert_multi_output :: () {
    expect_program_output("examples/26/26.24_insert_multi.jai", "Start of the report:\n    ... one iteration! Incrementing!\n    ... one iteration! Incrementing!\n    ... one iteration! Incrementing!\n    ... one iteration! Incrementing!\n    ... one iteration! Incrementing!\nEnd of the report - count is: 5.\n");
} @TestProcedure

insert_code_output :: () {
    expect_program_output("examples/26/26.26_insert_code.jai", "x is 69105\nT is s64\nT is string\n");
} @TestProcedure

caller_code_argument_name_output :: () {
    expect_compile_output("examples/26/26.23_get_variable_name.jai", "a_constant\n");
} @TestProcedure

binary_swap_output :: () {
    expect_example_annotations("examples/28/28.13_binary_swap.jai");
} @TestProcedure

macro_swap_output :: () {
    expect_program_output("examples/26/26.28_swap_macro.jai", "Pre-swap:  a is 3, b is 5\nPost-swap: a is 5, b is 3\n");
} @TestProcedure

abstracting_loop_output :: () {
    expect_program_output("examples/26/26.34_abstracting_loop.jai", "Player no 0 is {\"Jane\", 82}\nPlayer no 1 is {\"John\", 75}\nPlayer is {\"Jane\", 82}\nPlayer is {\"John\", 75}\ninside macro! \nPlayer is {\"Jane\", 82}\ninside macro! \nPlayer is {\"John\", 75}\ninside macro player_loop! \nPlayer 0 is {\"Jane\", 82}\ninside macro player_loop! \nPlayer 1 is {\"John\", 75}\n");
} @TestProcedure

code_struct_member_output :: () {
    expect_program_output("examples/26/26.29_code_struct_member.jai", "The result of serializing is: '7-75-'.\n");
} @TestProcedure

insert_string_from_proc_output :: () {
    expect_program_output("examples/26/26.35_insert_string_from_proc.jai", "9\n27\n162\n");
} @TestProcedure

changing_ast_output :: () {
    expect_program_output("examples/26/26.36_changing_ast.jai", "314928\n");
} @TestProcedure

step_iterator_output :: () {
    expect_program_output("examples/26/26.40_step_iterator.jai", "0 - 2 - 4 - 6 - 8 - 10 - ");
} @TestProcedure

placeholder_fulfillment_output :: () {
    expect_example_annotations("examples/30/30.12_placeholder.jai");
} @TestProcedure

mutex_output :: () {
    expect_example_annotations("examples/31/31.6_mutex1.jai");
} @TestProcedure

hello_example_annotations_output :: () {
    expect_example_annotations("examples/hello.jai");
} @TestProcedure
