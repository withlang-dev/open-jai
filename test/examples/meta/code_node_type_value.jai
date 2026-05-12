#import "Basic";
#import "Compiler";

#run {
    code :: #code print("value: % % %\n", 41 + 1, 1 < 2, true && false);
    root, expressions := compiler_get_nodes(code);

    root_call := cast(*Code_Procedure_Call) root;
    format_arg := root_call.arguments_unsorted[0].expression;
    value_arg := root_call.arguments_unsorted[1].expression;
    comparison_arg := root_call.arguments_unsorted[2].expression;
    logical_arg := root_call.arguments_unsorted[3].expression;
    lhs := value_arg.subexpressions[0];
    rhs := value_arg.subexpressions[1];

    print("expression count: %\n", expressions.count);
    print("format type: %\n", type_to_string(format_arg.type));
    print("value type: %\n", type_to_string(value_arg.type));
    print("lhs type: %\n", type_to_string(lhs.type));
    print("rhs type: %\n", type_to_string(rhs.type));
    print("comparison type: %\n", type_to_string(comparison_arg.type));
    print("logical type: %\n", type_to_string(logical_arg.type));
}

main :: () {}
