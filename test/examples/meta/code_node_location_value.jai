#import "Basic";
#import "Compiler";

captured_code :: #code reported: int = 42;

validate :: () -> int {
    root, expressions := compiler_get_nodes(captured_code);
    decl := cast(*Code_Declaration) expressions[expressions.count - 1];

    root_location := make_location(root);
    decl_location := make_location(decl);

    assert(contains(root_location.fully_pathed_filename, "code_node_location_value.jai"));
    assert(contains(decl_location.fully_pathed_filename, "code_node_location_value.jai"));
    assert(root_location.line_number == 4);
    assert(decl_location.line_number == 4);

    return root_location.line_number + decl_location.line_number;
}

RESULT :: #run validate();

main :: () {
    print("%\n", RESULT);
}
