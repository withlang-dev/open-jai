print_expression_uses_mutated_code_tree :: () {
    expect_compile_output("test/examples/meta/print_expression_mutation_value.jai", "root: print(\"value: %\\n\", \"after\")\narg: \"after\"\n");
} @TestProcedure

nested_procedure_call_arguments_are_code_nodes :: () {
    expect_compile_output("test/examples/meta/nested_call_code_tree_value.jai", "expr count: 5\nnested: wrap(41 + 1)\nnested arg: 41 + 1\n");
} @TestProcedure
