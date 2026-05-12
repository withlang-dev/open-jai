#import "Basic";
#import "Compiler";

rewrite_string_literals :: (code: Code) -> Code {
    root, expressions := compiler_get_nodes(code);

    for expr : expressions {
        if expr.kind != .LITERAL continue;

        literal := cast(*Code_Literal) expr;
        if literal.value_type != .STRING continue;

        print("saw string literal: %\n", literal._string);
        if literal._string == "before" {
            literal._string = "after";
        }
    }

    return compiler_get_code(root);
}

rewrite_string_print :: (code: Code) #expand {
    new_code :: #run rewrite_string_literals(code);
    #insert new_code;
}

main :: () {
    rewrite_string_print(print("%\n", "before"));
}
