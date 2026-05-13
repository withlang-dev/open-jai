#import "Basic";
#import "Compiler";

node_type_string :: (node: *Code_Node) -> string {
    return type_to_string(node.type);
}

round_trip_node :: (node: *Code_Node) -> *Code_Node {
    return node;
}

#run {
    code :: #code print("value: % % %\n", 41 + 1, 1 < 2, true && false);
    root, expressions := compiler_get_nodes(code);
    root = round_trip_node(root);

    root_call := cast(*Code_Procedure_Call) root;
    format_arg := root_call.arguments_unsorted[0].expression;
    value_arg := root_call.arguments_unsorted[1].expression;
    comparison_arg := root_call.arguments_unsorted[2].expression;
    logical_arg := root_call.arguments_unsorted[3].expression;
    lhs := value_arg.subexpressions[0];
    rhs := value_arg.subexpressions[1];

    print("expression count: %\n", expressions.count);
    print("format type: %\n", node_type_string(format_arg));
    print("value type: %\n", node_type_string(value_arg));
    print("lhs type: %\n", node_type_string(lhs));
    print("rhs type: %\n", node_type_string(rhs));
    print("comparison type: %\n", node_type_string(comparison_arg));
    print("logical type: %\n", node_type_string(logical_arg));
}

main :: () {}
