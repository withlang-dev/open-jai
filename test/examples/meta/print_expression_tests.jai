print_expression_uses_mutated_code_tree :: () {
    expect_compile_output("test/examples/meta/print_expression_mutation_value.jai", "root: print(\"value: %\\n\", \"after\")\narg: \"after\"\n");
} @TestProcedure

nested_procedure_call_arguments_are_code_nodes :: () {
    expect_compile_output("test/examples/meta/nested_call_code_tree_value.jai", "expr count: 5\nnested: wrap(41 + 1)\nnested arg: 41 + 1\n");
} @TestProcedure

nested_subexpression_literal_edits_round_trip :: () {
    expect_compile_output("test/examples/meta/nested_subexpression_mutation_value.jai", "expr count: 5\nbinary kind: BINARY_OPERATOR\nbinary subexpressions: 2\nbefore: 41 + 1\nroot: print(\"%\\n\", wrap(50 + 8))\n");
    expect_program_output("test/examples/meta/nested_subexpression_mutation_value.jai", "58\n");
} @TestProcedure

code_type_reflects_captured_expression_type :: () {
    expect_compile_output("test/examples/meta/code_type_value.jai", "integer code type: int\nstring code type: string\n");
    expect_program_output("test/examples/meta/code_type_value.jai", "caller type: float32\n");
} @TestProcedure

code_node_type_reflects_expression_types :: () {
    expect_compile_output("test/examples/meta/code_node_type_value.jai", "expression count: 10\nformat type: string\nvalue type: int\nlhs type: int\nrhs type: int\ncomparison type: bool\nlogical type: bool\n");
} @TestProcedure
