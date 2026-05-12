#import "Basic";
#import "Compiler";
#import "Program_Print";

#run {
    code :: #code print("outer %\n", wrap(41 + 1));

    root, expressions := compiler_get_nodes(code);
    print("expr count: %\n", expressions.count);

    root_call := cast(*Code_Procedure_Call) root;
    nested := cast(*Code_Procedure_Call) root_call.arguments_unsorted[1].expression;

    builder_nested: String_Builder;
    print_expression(*builder_nested, nested);
    print("nested: %\n", builder_to_string(*builder_nested));

    builder_arg: String_Builder;
    print_expression(*builder_arg, nested.arguments_unsorted[0].expression);
    print("nested arg: %\n", builder_to_string(*builder_arg));
}

main :: () {}
