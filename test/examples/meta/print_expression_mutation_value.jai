#import "Basic";
#import "Compiler";
#import "Program_Print";

#run {
    code :: #code print("value: %\n", "before");

    root, expressions := compiler_get_nodes(code);
    for expr : expressions {
        if expr.kind != .LITERAL continue;

        literal := cast(*Code_Literal) expr;
        if literal.value_type != .STRING continue;
        if literal._string == "before" {
            literal._string = "after";
        }
    }

    call := cast(*Code_Procedure_Call) root;
    builder: String_Builder;
    print_expression(*builder, root);
    rendered_root := builder_to_string(*builder);
    print("root: %\n", rendered_root);

    builder_arg: String_Builder;
    print_expression(*builder_arg, call.arguments_unsorted[1].expression);
    rendered_arg := builder_to_string(*builder_arg);
    print("arg: %\n", rendered_arg);
}

main :: () {}
