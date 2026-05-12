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

code_declaration_nodes_expose_name_and_type :: () {
    expect_compile_output("test/examples/meta/code_declaration_type_value.jai", "explicit root kind: ROOT\nexplicit decl name: answer\nexplicit decl type: int\nexplicit expr kind: LITERAL\nexplicit expr value: 42\ninferred root kind: ROOT\ninferred decl name: greeting\ninferred decl type: string\ninferred expr kind: LITERAL\ninferred expr value: hello\n");
} @TestProcedure

code_block_nodes_expose_statement_subexpressions :: () {
    expect_compile_output("test/examples/meta/code_block_tree_value.jai", "root kind: BLOCK\nroot subexpressions: 9\nfirst kind: ASSIGNMENT\nfirst subexpressions: 2\nsecond kind: ASSIGNMENT\nsecond subexpressions: 5\nflat count: 9\n");
} @TestProcedure

code_block_nodes_expose_control_flow_subtrees :: () {
    expect_compile_output("test/examples/meta/code_control_tree_value.jai", "root kind: BLOCK\nroot subexpressions: 18\nkind: IF subexpressions: 6\nkind: IDENT subexpressions: 0\nkind: BLOCK subexpressions: 4\nkind: RETURN subexpressions: 3\nkind: BINARY_OPERATOR subexpressions: 2\nkind: LITERAL subexpressions: 0\nkind: LITERAL subexpressions: 0\nkind: WHILE subexpressions: 4\nkind: IDENT subexpressions: 0\nkind: BLOCK subexpressions: 2\nkind: STATEMENT subexpressions: 1\nkind: PROCEDURE_CALL subexpressions: 0\nkind: FOR subexpressions: 5\nkind: IDENT subexpressions: 0\nkind: BLOCK subexpressions: 3\nkind: ASSIGNMENT subexpressions: 2\nkind: IDENT subexpressions: 0\nkind: IDENT subexpressions: 0\n");
} @TestProcedure
