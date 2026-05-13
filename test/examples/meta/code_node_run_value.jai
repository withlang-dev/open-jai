#import "Basic";
#import "Compiler";

first_root :: () -> *Code_Node {
    code :: #code answer: int = 42;
    root, expressions := compiler_get_nodes(code);
    return root;
}

ROOT :: #run first_root();

#run {
    print("root:% flags:% type:%\n", ROOT.kind, ROOT.node_flags, type_to_string(ROOT.type));
}

main :: () {}
