#import "Basic";
#import "Compiler";

code :: #code {
    x *= 3;
    y = wrap(41 + 1);
};

#run {
    root, expressions := compiler_get_nodes(code);
    print("root kind: %\n", root.kind);
    print("root subexpressions: %\n", root.subexpressions.count);
    first := root.subexpressions[0];
    second := root.subexpressions[3];
    print("first kind: %\n", first.kind);
    print("first subexpressions: %\n", first.subexpressions.count);
    print("second kind: %\n", second.kind);
    print("second subexpressions: %\n", second.subexpressions.count);
    print("flat count: %\n", expressions.count);
}

main :: () {}
