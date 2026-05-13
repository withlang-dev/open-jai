#import "Basic";
#import "Compiler";

#run {
    code :: #code value :: 42;
    root, expressions := compiler_get_nodes(code);
    print("compiler:% % %\n", root.kind, expressions.count, code_to_string(compiler_get_code(root)));
}

main :: () {}
