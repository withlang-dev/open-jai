print_expression_uses_mutated_code_tree :: () {
    expect_compile_output("test/examples/meta/print_expression_mutation_value.jai", "root: print(\"value: %\\n\", \"after\")\narg: \"after\"\n");
} @TestProcedure
