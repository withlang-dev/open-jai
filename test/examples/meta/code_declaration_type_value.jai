#import "Basic";
#import "Compiler";

#run {
    explicit_code :: #code answer: int = 42;
    explicit_root, explicit_expressions := compiler_get_nodes(explicit_code);
    explicit_decl := cast(*Code_Declaration) explicit_expressions[explicit_expressions.count - 1];

    inferred_code :: #code greeting := "hello";
    inferred_root, inferred_expressions := compiler_get_nodes(inferred_code);
    inferred_decl := cast(*Code_Declaration) inferred_expressions[inferred_expressions.count - 1];

    print("explicit root kind: %\n", explicit_root.kind);
    print("explicit decl name: %\n", explicit_decl.name);
    print("explicit decl type: %\n", type_to_string(explicit_decl.type));
    explicit_expr := cast(*Code_Literal) explicit_decl.expression;
    print("explicit expr kind: %\n", explicit_expr.kind);
    print("explicit expr value: %\n", explicit_expr._s64);
    print("inferred root kind: %\n", inferred_root.kind);
    print("inferred decl name: %\n", inferred_decl.name);
    print("inferred decl type: %\n", type_to_string(inferred_decl.type));
    inferred_expr := cast(*Code_Literal) inferred_decl.expression;
    print("inferred expr kind: %\n", inferred_expr.kind);
    print("inferred expr value: %\n", inferred_expr._string);
}

main :: () {}
