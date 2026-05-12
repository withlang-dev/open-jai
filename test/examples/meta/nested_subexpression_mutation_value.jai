#import "Basic";
#import "Compiler";
#import "Program_Print";

mutate_nested_binary :: (code: Code) -> Code {
    root, expressions := compiler_get_nodes(code);

    root_call := cast(*Code_Procedure_Call) root;
    nested_call := cast(*Code_Procedure_Call) root_call.arguments_unsorted[1].expression;
    binary := nested_call.arguments_unsorted[0].expression;

    print("expr count: %\n", expressions.count);
    print("binary kind: %\n", binary.kind);
    print("binary subexpressions: %\n", binary.subexpressions.count);

    lhs := cast(*Code_Literal) binary.subexpressions[0];
    rhs := cast(*Code_Literal) binary.subexpressions[1];
    print("before: % + %\n", lhs._s64, rhs._s64);

    lhs._s64 = 50;
    rhs._s64 = 8;

    builder: String_Builder;
    print_expression(*builder, root);
    print("root: %\n", builder_to_string(*builder));

    return compiler_get_code(root);
}

wrap :: (x: int) -> int {
    return x;
}

rewrite_nested_binary :: (code: Code) #expand {
    new_code :: #run mutate_nested_binary(code);
    #insert new_code;
}

main :: () {
    rewrite_nested_binary(print("%\n", wrap(41 + 1)));
}
