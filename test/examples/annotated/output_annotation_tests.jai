// Behavioral tests for examples whose `// =>` annotations currently describe
// stable runtime output. Each procedure compiles and runs the example, then
// checks the annotated expectations in source order.

hello_sailor_output :: () {
    expect_example_annotations("examples/03/3.1_hello_sailor.jai");
} @TestProcedure

exit_example_output :: () {
    expect_example_annotations("examples/03/3.3_exit.jai");
} @TestProcedure

hello_sailor_chapter_04_output :: () {
    expect_program_output("examples/04/4.1_hello_sailor.jai", "Hello, Sailor from Jai!\nn is 42\n");
} @TestProcedure

intrinsics_chapter_04_output :: () {
    expect_program_output("examples/04/4.2_intrinsics.jai", "y is 42\n");
} @TestProcedure

literals_output :: () {
    expect_program_output("examples/05/5.1_literals.jai", "Hello, Sailor!\nI greet you: Hello, Sailor!\n42\nfalse\nchar literal: 49\nThe type of Hello, Sailor! is string\nThe type of 42 is s64\nThe type of false is bool\n");
} @TestProcedure

variable_declarations_2_output :: () {
    expect_example_annotations("examples/05/5.4_variable_declarations2.jai");
} @TestProcedure

swapping_output :: () {
    expect_program_output("examples/05/5.5_swapping.jai", "n is 3 and m is 2\nn2 is 3 and m2 is 2\n");
} @TestProcedure

write_helpers_output :: () {
    expect_program_output("examples/05/5.8_write.jai", "Hello, World!\nHello, World!\n-4242");
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

bools_output :: () {
    expect_program_output("examples/06/6.1_bools.jai", "b1 is true and of type bool\nAre 1 and 1.0 equal? true\nAre Jai and Java different? true\ntrue\n! changes to false\nb2 is false\nb1 and b2 is false\nb1 or b2 is true\n");
} @TestProcedure

numbers_output :: () {
    expect_program_output("examples/06/6.3_numbers.jai", "total_score is 55\n8 / 3 is 2\n8.0 / 3 is 2.666667\n8 % 3 is 2\nd is -5069095\ntotal_score has type s64\n74\na is -5069105 and b is 207\na is -5069104 and b is 208\ne is 3\ne is 1\ne is 0\nfalse\ntrue\n4\n4\n10\n");
} @TestProcedure

formatting_output :: () {
    expect_program_output("examples/06/6.5_formatting.jai", "108 6c i2 = ff\n07 2.252\n3.140\n3.14\nScientific-notation-formatted float: 1.234235e+10, Decimal value: 12342345234\n");
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

struct_declarations_output :: () {
    expect_program_output("examples/12/12.1_struct_declarations.jai", "{0, 0}\n0 0\n42 108\n1 4\n0 0\nVector2un\nRobert is aged 42 and is currently at location {64.139999, -21.92}\n{\"Robert\", 42, {64.139999, -21.92}}\n{2, 6.28}\nPerson\n32\nv3d = {\n    x = 1;\n    y = 2;\n    z = 3;\n}\n");
} @TestProcedure

struct_heap_output :: () {
    expect_program_output_contains("examples/12/12.2_struct_heap.jai", "*Person\n");
    expect_program_output_contains("examples/12/12.2_struct_heap.jai", "{\"Robert\", 42}\n");
    expect_program_output_contains("examples/12/12.2_struct_heap.jai", "{\"Jim\", 67}\n");
} @TestProcedure

linked_list_output :: () {
    expect_program_output_contains("examples/12/12.3_linked_list.jai", "Our list is: ");
    expect_program_output_contains("examples/12/12.3_linked_list.jai", "Our << list is: {0, ");
    expect_program_output_contains("examples/12/12.3_linked_list.jai", "List data is 0 -> 12 -> 24 -> 36\n");
} @TestProcedure

using_output :: () {
    expect_program_output("examples/12/12.4_using.jai", "Patient is: {{\"Johnson\"}, \"Bronchitis\"}\nPatient has name: Johnson\n");
} @TestProcedure

pointer_to_struct_output :: () {
    expect_program_output_contains("examples/12/12.5_pointer_to_struct.jai", "rob is ");
    expect_program_output_contains("examples/12/12.5_pointer_to_struct.jai", "The type of rob is *Person\n");
    expect_program_output_contains("examples/12/12.5_pointer_to_struct.jai", "The value rob points to is {\"Robert\", 42, {64.139999, -21.92}}\n");
    expect_program_output_contains("examples/12/12.5_pointer_to_struct.jai", "e's value is: {349825645}\n");
} @TestProcedure

as_using_output :: () {
    expect_program_output("examples/12/12.6_#as_using.jai", "{{\"Gates\"}, \"software engineer\"}\n{\"Gates\"}\nnum is {42, 3.1415}\ni is 42\n");
} @TestProcedure

struct_align_output :: () {
    expect_program_output("examples/12/12.7_struct_align.jai", "size = 16, value = 1010\n");
} @TestProcedure

inner_module_output :: () {
    expect_program_output("examples/12/12.8_inner_module_test.jai", "{42}");
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
